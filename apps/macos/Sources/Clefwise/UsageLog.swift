import Foundation

/// Gets a copy of every line the usage log writes: the run-file writer tees a practice run's lines
/// into its own file through it (`UsageLog.lineSink`).
protocol RunLineSink: AnyObject, Sendable {
    /// Called on the log's queue, one line at a time in the order written. `line` is exactly the
    /// bytes meant for the day file, its line feed included, and `event` what they encode. It's
    /// called whether or not the day file took the line (a full disk, a missing folder). It must
    /// not call back into the log: `flush()` would deadlock.
    func lineLogged(_ line: Data, _ event: LoggedEvent)
}

/// The usage log on disk: one JSON Lines file per local day in Application Support, only ever
/// appended to, so a crash can at worst cut off the line being written.
final class UsageLog: UsageRecorder, @unchecked Sendable {
    static let shared = UsageLog(folder: defaultFolder)

    /// ~/Library/Application Support/Clefwise/Usage
    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clefwise/Usage", isDirectory: true)
    }

    let folder: URL
    /// One per launch, stamped on every event.
    let session = UUID()

    private let clock: () -> Date
    /// Files go by local day, so an evening's practice isn't split at UTC midnight.
    private let calendar: Calendar

    /// Guards `nextSequence`, and queues lines in sequence order when several threads record.
    private let lock = NSLock()
    private var nextSequence = 0

    /// Disk work happens here, never on the caller's thread. `file`, `fileName` and `sink` belong
    /// to it.
    private let queue = DispatchQueue(label: "Clefwise.UsageLog", qos: .utility)
    private var file: FileHandle?
    private var fileName: String?
    private var sink: RunLineSink?

    /// `clock` and `timeZone` are for tests.
    init(folder: URL, clock: @escaping () -> Date = { Date() }, timeZone: TimeZone = .autoupdatingCurrent) {
        self.folder = folder
        self.clock = clock
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// Also gets every line written, after the day file (nil, the default, for none). It's kept
    /// strongly, and only lines written after it's set reach it: set it once at startup, before
    /// the first event is recorded. Setting it waits for the lines already queued; never set it
    /// from the sink itself.
    var lineSink: RunLineSink? {
        get { queue.sync { sink } }
        set { queue.sync { sink = newValue } }
    }

    /// Stamps the event now and leaves the writing to the log's queue.
    func record(_ event: UsageEvent) {
        record(event, at: clock())
    }

    /// Stamps the event with `time` and leaves the writing to the log's queue. It's numbered in the
    /// order recorded, and goes in the file of the local day `time` falls on.
    func record(_ event: UsageEvent, at time: Date) {
        lock.withLock {
            let logged = LoggedEvent(event, session: session, sequence: nextSequence, time: time)
            nextSequence += 1
            queue.async { self.write(logged) }
        }
    }

    /// Hands out the next sequence number without writing anything: for an event of this session
    /// kept only in the practice journal (the piece library's changes), so it still has its place
    /// in the session's order. The log then has a gap there.
    func takeSequence() -> Int {
        lock.withLock {
            defer { nextSequence += 1 }
            return nextSequence
        }
    }

    /// Returns once everything recorded so far is written and synced (before quitting or exporting).
    func flush() {
        queue.sync { try? file?.synchronize() }
    }

    // MARK: - Writing (on `queue`)

    /// Writes the line to its day file, then hands the same bytes to the sink.
    private func write(_ logged: LoggedEvent) {
        guard let line = try? logged.encodedLine() else { return }
        writeToDayFile(line, time: logged.time)
        sink?.lineLogged(line, logged)
    }

    /// Drops the line on any I/O problem (disk full, folder gone…) and reopens on the next write:
    /// losing an event beats crashing or stalling the app.
    private func writeToDayFile(_ line: Data, time: Date) {
        let name = Self.fileName(for: time, in: calendar)
        // A file deleted while open would swallow writes without an error.
        if name != fileName || !FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            closeFile()
            file = openFile(named: name)
            fileName = file == nil ? nil : name
        }
        guard let file else { return }
        do {
            try file.write(contentsOf: line)
        } catch {
            closeFile()
        }
    }

    private func openFile(named name: String) -> FileHandle? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.appendingPathComponent(name).path, O_RDWR | O_CREAT | O_APPEND | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        // A line cut off by a crash would swallow the next one: end it first.
        let size = lseek(descriptor, 0, SEEK_END)
        var last: UInt8 = 0
        if size > 0, pread(descriptor, &last, 1, size - 1) == 1, last != 0x0A {
            try? handle.write(contentsOf: Data([0x0A]))
        }
        return handle
    }

    private func closeFile() {
        try? file?.synchronize()
        try? file?.close()
        file = nil
        fileName = nil
    }

    /// "usage-2026-10-30.jsonl", for the local day `time` falls on.
    private static func fileName(for time: Date, in calendar: Calendar) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: time)
        return String(format: "usage-%04d-%02d-%02d.jsonl", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    // MARK: - Reading

    /// The day files in `folder`, oldest first.
    static func eventFiles(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .filter { $0.hasPrefix("usage-") && $0.hasSuffix(".jsonl") }
            .sorted()
            .map { folder.appendingPathComponent($0) }
    }

    /// Every event in `folder`, in time order. Lines that can't be read (cut off by a crash,
    /// written by a newer version, edited by hand) are skipped and counted.
    static func readEvents(in folder: URL) -> (events: [LoggedEvent], unreadableLines: Int) {
        var events: [LoggedEvent] = []
        let unreadable = forEachEvent(in: eventFiles(in: folder)) { events.append($0) }
        // Already in order unless the clock went back; ties keep the order they were written in.
        let sorted = events.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
        return (sorted, unreadable)
    }

    /// Calls `body` with each readable event in `files`, in the order written, holding one file
    /// in memory at a time. Returns how many lines couldn't be read.
    @discardableResult
    static func forEachEvent(in files: [URL], _ body: (LoggedEvent) throws -> Void) rethrows -> Int {
        var unreadable = 0
        for url in files {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            try forEachLine(in: data) { line in
                if let event = Self.event(in: line) {
                    try body(event)
                } else {
                    unreadable += 1
                }
            }
        }
        return unreadable
    }

    /// Calls `body` with each line of JSON Lines `data`, in order, without its line feed. Empty
    /// lines are skipped; a last line with no line feed (cut off) is passed on like the others.
    static func forEachLine(in data: Data, _ body: (Data) throws -> Void) rethrows {
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[start..<end]
            start = end + 1
            guard !line.isEmpty else { continue }
            try body(line)
        }
    }

    /// The event in one log line, or nil when it can't be read (cut off, from a newer version…).
    static func event(in line: Data) -> LoggedEvent? {
        try? LoggedEvent.decoder.decode(LoggedEvent.self, from: line)
    }
}
