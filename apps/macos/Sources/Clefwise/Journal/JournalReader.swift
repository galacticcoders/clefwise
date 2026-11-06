import Foundation

// Reading a practice journal's records: its runs and its event files, each file read once and kept,
// since files in a journal never change. Everything the app shows from the journal starts here.
// See spec/practice-journal.md, "Folder sync" and "Reading".

/// Reads the runs and event files of the journal in `folder`, and keeps what it has read: files in a
/// journal never change, so each is read once, and a later `read()` only reads the names it hasn't
/// seen yet. A file that can't be used yet (still arriving through a sync service, or from a newer
/// app) is left out and tried again at the next `read()`.
///
/// Safe to use from any thread: `read()` takes a lock for its whole run, so two calls at once read
/// each new file once between them. It reads files, so call it off the main thread.
final class JournalReader: @unchecked Sendable {
    /// One complete practice run, as its file in `runs/` tells it.
    struct Run: Sendable {
        /// The file's path in the journal, `runs/YYYY/MM/<UTC start>-<run id>.jsonl`.
        var path: String
        /// The run's id, from the file's name: the `round` in its events.
        var id: UUID
        /// When it started: its `roundStarted`'s `time`, to the millisecond; failing that, the time
        /// in its name, to the second.
        var startedAt: Date
        /// The file's first line: where the run comes from.
        var header: RunFileHeader
        /// Every later line that parses, in the order written: from its `roundStarted` to its
        /// `roundEnded`, which is always last.
        var events: [LoggedEvent]
    }

    /// What the journal holds, as of one `read()`.
    struct Contents: Sendable {
        /// Complete runs, by `startedAt`, then by id (compared in lowercase).
        var runs: [Run] = []
        /// The opening balances: the one event of each `statsSnapshot` event file, by `time`, then
        /// by id (compared in lowercase).
        var snapshots: [LoggedEvent] = []
        /// The piece library's changes: the one event of each `pieceAdded`, `pieceRevised` and
        /// `pieceRemoved` event file, ordered like `snapshots`. When they disagree, the latest wins.
        var pieceEvents: [LoggedEvent] = []
        /// Files in `runs/` and `events/` whose names fit the layout but that were left out this
        /// time, to be tried again at the next `read()`: one that couldn't be read (not downloaded
        /// yet, or gone while being read), whose first line isn't a header, whose header is in a
        /// format newer than `RunFileHeader.currentFormat`, a run whose last event isn't its
        /// `roundEnded` (still arriving), or an event file whose event line doesn't parse (cut off,
        /// or a type this version doesn't know). Names that don't fit aren't counted.
        var skippedFiles = 0
        /// Lines that didn't parse in the files read and kept, and so left out of their events. Lines
        /// in skipped files aren't counted.
        var unreadableLines = 0
    }

    /// The journal's folder.
    let folder: URL

    /// Guards `cache` and `ignoredNames`, and serialises reading.
    private let lock = NSLock()
    /// Files read whole and kept, by their path in the journal. Their bytes never change.
    private var cache: [String: Record] = [:]
    /// Paths last found that don't fit the layout, so they aren't checked again while they're there.
    private var ignoredNames: Set<String> = []

    /// A file read whole: what it holds, and how many of its lines didn't parse.
    private enum Record {
        case run(Run, unreadableLines: Int)
        /// An event file's one event, whatever its type.
        case event(LoggedEvent, unreadableLines: Int)
    }

    /// Reads nothing yet: the first `read()` reads every file.
    init(folder: URL) {
        self.folder = folder
    }

    /// What the journal holds now. Lists `runs/` and `events/` (all the way down), keeps only the
    /// paths `JournalLayout.file(at:)` takes for a run or an event (so `.DS_Store`, temporary names
    /// and sync services' conflicted copies are ignored), reads each one not read before with
    /// `RunFile.read`, and keeps it unless it's skipped (see `Contents.skippedFiles`). A file that
    /// has gone from the folder is gone from the result, and forgotten.
    func read() -> Contents {
        lock.withLock {
            let listed = [JournalLayout.runsFolder, JournalLayout.eventsFolder].flatMap { Self.paths(in: $0, of: folder) }
            let present = Set(listed)
            cache = cache.filter { present.contains($0.key) }
            ignoredNames.formIntersection(present)

            var contents = Contents()
            for path in listed where cache[path] == nil && !ignoredNames.contains(path) {
                guard let file = JournalLayout.file(at: path) else {
                    ignoredNames.insert(path)
                    continue
                }
                if let record = Self.record(at: path, file: file, in: folder) {
                    cache[path] = record
                } else {
                    contents.skippedFiles += 1
                }
            }
            for record in cache.values {
                switch record {
                case .run(let run, let unreadable):
                    contents.runs.append(run)
                    contents.unreadableLines += unreadable
                case .event(let event, let unreadable):
                    contents.unreadableLines += unreadable
                    switch event.event {
                    case .statsSnapshot: contents.snapshots.append(event)
                    case .pieceAdded, .pieceRevised, .pieceRemoved: contents.pieceEvents.append(event)
                    default: break
                    }
                }
            }
            contents.runs.sort { Self.isOrdered(($0.startedAt, $0.id), before: ($1.startedAt, $1.id)) }
            contents.snapshots.sort { Self.isOrdered(($0.time, $0.id), before: ($1.time, $1.id)) }
            contents.pieceEvents.sort { Self.isOrdered(($0.time, $0.id), before: ($1.time, $1.id)) }
            return contents
        }
    }

    // MARK: - Reading a file

    /// The file at `path`, read whole, or nil when it's to be skipped this time (see
    /// `Contents.skippedFiles`). Paths outside `runs/` and `events/` have nothing to read here.
    private static func record(at path: String, file: JournalLayout.File, in folder: URL) -> Record? {
        let read = RunFile.read(folder.appendingPathComponent(path))
        guard let header = read.header, header.format <= RunFileHeader.currentFormat else { return nil }
        switch file {
        case .run(let named, let id):
            guard case .roundEnded = read.events.last?.event else { return nil }
            let started = read.events.first { if case .roundStarted = $0.event { true } else { false } }
            let run = Run(path: path, id: id, startedAt: started?.time ?? named, header: header, events: read.events)
            return .run(run, unreadableLines: read.unreadableLines)
        case .event:
            guard let event = read.events.first else { return nil }
            return .event(event, unreadableLines: read.unreadableLines)
        default:
            return nil
        }
    }

    /// The relative paths ("runs/2026/11/…") of everything under `subfolder` of `journal`, folders
    /// and hidden files included; none when it isn't there.
    private static func paths(in subfolder: String, of journal: URL) -> [String] {
        let root = journal.appendingPathComponent(subfolder, isDirectory: true)
        guard let items = FileManager.default.enumerator(atPath: root.path) else { return [] }
        return items.compactMap { ($0 as? String).map { "\(subfolder)/\($0)" } }
    }

    /// By time, then by id in lowercase (the ids' text is only made for a tie).
    private static func isOrdered(_ a: (time: Date, id: UUID), before b: (time: Date, id: UUID)) -> Bool {
        if a.time != b.time { return a.time < b.time }
        return a.id.uuidString.lowercased() < b.id.uuidString.lowercased()
    }
}
