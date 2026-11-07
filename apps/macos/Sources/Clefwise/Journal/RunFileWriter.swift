import Foundation

// The device's side of a practice run: its working file while it goes on, handed to the journal
// when it ends, and found again at the next launch if the app stopped first. See
// spec/practice-journal.md, "Writing a run" and "After a crash".

/// Tees each practice run's lines from the usage log into a working file of its own in
/// `currentFolder`, and hands the finished file to the journal through `outbox` (which keeps it in
/// `Pending` while the journal can't be reached). See `RunFileWriting`. The app has one for each
/// journal, in its state folder (`JournalState.folder(for:in:)`), and the usage log's lines reach
/// the one in use through a `JournalRunRouter`.
final class RunFileWriter: RunFileWriting, @unchecked Sendable {
    /// ~/Library/Application Support/Clefwise, where build 1 kept its one journal's `Current` and
    /// `Pending` (`BuildOneFolders`). Build 2 keeps them per journal.
    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clefwise", isDirectory: true)
    }

    let folder: URL
    /// This installation and the app as it launched, for each run file's header.
    let device: UUID
    let launch: AppLaunched
    /// Where finished runs go: into the journal, or to wait in `folder/Pending`.
    let outbox: JournalOutbox

    /// Where the working file is, named by its round (`<lowercase round id>.jsonl`).
    var currentFolder: URL { folder.appendingPathComponent("Current", isDirectory: true) }

    /// Guards `working`: lines come on the usage log's queue, the launch's look on the main thread.
    private let lock = NSLock()
    /// The run being written, from its `roundStarted` to its `roundEnded`.
    private var working: WorkingFile?

    /// A run's working file, open for appending.
    private struct WorkingFile {
        let round: UUID
        let url: URL
        let handle: FileHandle
        let header: RunFileHeader
        /// Its `roundStarted`'s `time`, which names it in the journal.
        let startedAt: Date
        /// It has an `answerGiven`, so it's worth a file in the journal.
        var isAnswered: Bool
    }

    /// `folder` holds `Current` and `Pending`; `journal` is where finished runs go; `device` and
    /// `launch` go in each run file's header.
    init(folder: URL, journal: JournalWriting, device: UUID, launch: AppLaunched) {
        self.folder = folder
        self.device = device
        self.launch = launch
        outbox = JournalOutbox(journal: journal, pendingFolder: folder.appendingPathComponent("Pending", isDirectory: true))
    }

    // MARK: - Lines from the usage log (on its queue)

    func lineLogged(_ line: Data, _ event: LoggedEvent) {
        lock.withLock {
            if case .roundStarted(let started) = event.event {
                // Never two at once: one still open (which shouldn't happen) stays where it is.
                if let working { close(working) }
                working = start(started.round, at: event.time)
            }
            guard var run = working else { return }
            // Should a write fail (a full disk), the usage log still has the line.
            try? run.handle.write(contentsOf: line)
            switch event.event {
            case .answerGiven(let answer) where answer.round == run.round:
                run.isAnswered = true
                working = run
            case .roundEnded(let ended) where ended.round == run.round:
                working = nil
                finish(run)
            default:
                break
            }
        }
    }

    /// Makes the round's working file and writes its header; nil when it can't.
    private func start(_ round: UUID, at time: Date) -> WorkingFile? {
        let url = currentFolder.appendingPathComponent("\(round.uuidString.lowercased()).jsonl")
        let header = RunFileHeader(run: round, device: device, launch: launch)
        try? FileManager.default.createDirectory(at: currentFolder, withIntermediateDirectories: true)
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: header.encodedLine())
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return WorkingFile(round: round, url: url, handle: handle, header: header, startedAt: time, isAnswered: false)
    }

    /// Syncs and closes the file, leaving it where it is.
    private func close(_ file: WorkingFile) {
        try? file.handle.synchronize()
        try? file.handle.close()
    }

    /// The run ended: a run with no answers gets no file; any other goes to the journal, off the
    /// log's queue.
    private func finish(_ file: WorkingFile) {
        close(file)
        if file.isAnswered {
            outbox.place(runFile: file.url, header: file.header, startedAt: file.startedAt)
        } else {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    // MARK: - At launch

    func inspectAtLaunch() -> PendingRun? {
        outbox.placePending()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: currentFolder.path)) ?? []
        var unfinished: [(round: UUID, url: URL, header: RunFileHeader, startedAt: Date, events: [LoggedEvent])] = []
        for name in names.sorted() where name.hasSuffix(".jsonl") {
            let url = currentFolder.appendingPathComponent(name)
            let read = RunFile.read(url)
            guard let header = read.header, let round = header.run else {
                // Cut off in its header, before it had anything to keep.
                if read.events.isEmpty { try? FileManager.default.removeItem(at: url) }
                continue
            }
            let isAnswered = read.events.contains {
                if case .answerGiven(let answer) = $0.event { answer.round == round } else { false }
            }
            guard isAnswered else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            let started = read.events.first {
                if case .roundStarted(let started) = $0.event { started.round == round } else { false }
            }
            let startedAt = (started ?? read.events[0]).time
            if case .roundEnded(let ended) = read.events.last?.event, ended.round == round {
                // The app stopped after the run ended, before the file went into the journal.
                outbox.place(runFile: url, header: header, startedAt: startedAt)
            } else {
                unfinished.append((round, url, header, startedAt, read.events))
            }
        }
        // A device runs one round at a time; should there be more, the others stay as they are.
        guard let newest = unfinished.max(by: { $0.startedAt < $1.startedAt }),
              let handle = Self.reopen(newest.url) else { return nil }
        lock.withLock {
            working = WorkingFile(round: newest.round, url: newest.url, handle: handle, header: newest.header,
                                  startedAt: newest.startedAt, isAnswered: true)
        }
        return PendingRun(round: newest.round, file: newest.url, events: newest.events)
    }

    /// Opens a working file for appending, ending a line cut off by the crash first so it can't
    /// swallow the next one (as the usage log does).
    private static func reopen(_ url: URL) -> FileHandle? {
        let descriptor = Darwin.open(url.path, O_RDWR | O_APPEND | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let size = lseek(descriptor, 0, SEEK_END)
        var last: UInt8 = 0
        if size > 0, pread(descriptor, &last, 1, size - 1) == 1, last != 0x0A {
            try? handle.write(contentsOf: Data([0x0A]))
        }
        return handle
    }
}
