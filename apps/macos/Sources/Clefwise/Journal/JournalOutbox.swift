import Foundation

// Finished records on their way from the device into the practice journal, and the ones waiting
// for it. See spec/practice-journal.md, "Writing a run": if the journal can't be found when a run
// ends, "the file waits on the device until it can be placed".

/// Hands finished records to the journal one at a time, on its own queue, and keeps the ones it
/// can't take yet in `pendingFolder`, laid out as in the journal (`runs/…`, `events/…`,
/// `pieces/…`). Those go in at the next chance: after the next record that does, when
/// `placePending()` is called (at launch, and once a journal is made or found). A record that
/// clashes with a different file already in the journal is moved to `keptFolder` and never
/// retried; the journal's copy stays.
final class JournalOutbox: @unchecked Sendable {
    let journal: JournalWriting
    /// Records waiting for the journal (Application Support/Clefwise/Pending in the app).
    let pendingFolder: URL
    /// This device's copy of any record that clashed with the journal's.
    var keptFolder: URL { pendingFolder.appendingPathComponent("kept", isDirectory: true) }

    /// Every disk change happens here, in the order handed over.
    private let queue = DispatchQueue(label: "Clefwise.JournalOutbox", qos: .utility)

    init(journal: JournalWriting, pendingFolder: URL) {
        self.journal = journal
        self.pendingFolder = pendingFolder
    }

    /// Places a finished run file in the journal (`JournalWriting.place`), or moves it to
    /// `pendingFolder` to wait. Returns at once.
    func place(runFile: URL, header: RunFileHeader, startedAt: Date) {
        queue.async { self.placeNow(runFile: runFile, header: header, startedAt: startedAt) }
    }

    /// Adds an event file to the journal (`JournalWriting.add`), or writes it and its score to
    /// `pendingFolder` to wait. Returns at once.
    func add(event: LoggedEvent, header: RunFileHeader, piece: JournalPieceFile?) {
        queue.async { self.addNow(event: event, header: header, piece: piece) }
    }

    /// Tries again with everything waiting in `pendingFolder`. Returns at once.
    func placePending() {
        queue.async { self.placePendingNow() }
    }

    /// Returns once everything handed over so far is in the journal or waiting (tests).
    func waitUntilDone() {
        queue.sync {}
    }

    /// Like `waitUntilDone()`, giving up after `timeout` (quitting: what's left is placed at the
    /// next launch). Returns whether it finished.
    @discardableResult
    func waitUntilDone(timeout: TimeInterval) -> Bool {
        let done = DispatchSemaphore(value: 0)
        queue.async { done.signal() }
        return done.wait(timeout: .now() + timeout) == .success
    }

    // MARK: - On the queue

    private func placeNow(runFile: URL, header: RunFileHeader, startedAt: Date) {
        guard let run = header.run else { return }
        let path = JournalLayout.runPath(startedAt: startedAt, run: run)
        do {
            try journal.place(runFile: runFile, header: header, startedAt: startedAt)
            placePendingIfAny()
        } catch JournalError.clash {
            keepAside(runFile, as: path)
        } catch {
            wait(runFile, as: path)
        }
    }

    private func addNow(event: LoggedEvent, header: RunFileHeader, piece: JournalPieceFile?) {
        do {
            try journal.add(event: event, header: header, piece: piece)
            placePendingIfAny()
        } catch JournalError.clash, JournalError.damagedScore {
            try? write(event: event, header: header, piece: piece, in: keptFolder)
        } catch {
            try? write(event: event, header: header, piece: piece, in: pendingFolder)
        }
    }

    /// Scores first go in with the events that bring them, then the runs, oldest first. Stops at
    /// the first record the journal can't take for want of a journal; a record that clashes is
    /// moved aside and the rest carry on.
    private func placePendingNow() {
        let manager = FileManager.default
        guard let paths = manager.subpaths(atPath: pendingFolder.path) else { return }
        var scores: [String: (url: URL, fileExtension: String)] = [:]
        var events: [String] = []
        var runs: [(path: String, startedAt: Date)] = []
        for path in paths.sorted() {
            switch JournalLayout.file(at: path) {
            case .piece(let hash, let fileExtension): scores[hash] = (pendingFolder.appendingPathComponent(path), fileExtension)
            case .event: events.append(path)
            case .run(let startedAt, _): runs.append((path, startedAt))
            default: break
            }
        }
        var allEventsIn = true
        for path in events {
            let url = pendingFolder.appendingPathComponent(path)
            let read = RunFile.read(url)
            guard let header = read.header, read.events.count == 1, let event = read.events.first else {
                allEventsIn = false
                continue
            }
            let piece = event.event.scoreHash.flatMap { hash in
                scores[hash].flatMap { score in
                    (try? Data(contentsOf: score.url)).map {
                        JournalPieceFile(data: $0, hash: hash, fileExtension: score.fileExtension)
                    }
                }
            }
            do {
                try journal.add(event: event, header: header, piece: piece)
                try? manager.removeItem(at: url)
            } catch JournalError.clash, JournalError.damagedScore {
                keepAside(url, as: path)
            } catch {
                return
            }
        }
        // Scores wait only for their events.
        if allEventsIn {
            for score in scores.values { try? manager.removeItem(at: score.url) }
        }
        for run in runs {
            let url = pendingFolder.appendingPathComponent(run.path)
            guard let header = RunFile.read(url).header else { continue }
            do {
                try journal.place(runFile: url, header: header, startedAt: run.startedAt)
            } catch JournalError.clash {
                keepAside(url, as: run.path)
            } catch {
                return
            }
        }
        removeEmptyFolders()
    }

    /// After a record went in: the journal is there, so anything waiting can follow it.
    private func placePendingIfAny() {
        let manager = FileManager.default
        let waiting = [JournalLayout.runsFolder, JournalLayout.eventsFolder].contains {
            manager.fileExists(atPath: pendingFolder.appendingPathComponent($0).path)
        }
        if waiting { placePendingNow() }
    }

    /// Moves a run file into `pendingFolder` at its place in the journal's layout, unless it's
    /// already there. Should the move fail, it stays where it is (a working file is then placed
    /// at the next launch).
    private func wait(_ file: URL, as path: String) {
        let destination = pendingFolder.appendingPathComponent(path)
        guard file.standardizedFileURL.path != destination.standardizedFileURL.path else { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            keepAside(file, as: path)
            return
        }
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: file, to: destination)
    }

    /// Moves a record that clashed into `keptFolder`, with a number added should the name be taken.
    private func keepAside(_ file: URL, as path: String) {
        let manager = FileManager.default
        var destination = keptFolder.appendingPathComponent(path)
        let stem = destination.deletingPathExtension().lastPathComponent, fileExtension = destination.pathExtension
        var number = 2
        while manager.fileExists(atPath: destination.path) {
            destination = destination.deletingLastPathComponent().appendingPathComponent("\(stem) \(number).\(fileExtension)")
            number += 1
        }
        try? manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.moveItem(at: file, to: destination)
    }

    /// Writes an event file (and its score, unless already there) under `root`, laid out as in the
    /// journal, each to a temporary name first.
    private func write(event: LoggedEvent, header: RunFileHeader, piece: JournalPieceFile?, in root: URL) throws {
        var header = header
        header.event = event.id
        if let piece {
            let url = root.appendingPathComponent(JournalLayout.piecePath(hash: piece.hash, fileExtension: piece.fileExtension))
            if (try? Data(contentsOf: url)) != piece.data { try writeReplacing(piece.data, to: url) }
        }
        let url = root.appendingPathComponent(JournalLayout.eventPath(at: event.time, event: event.id))
        try writeReplacing(header.encodedLine() + event.encodedLine(), to: url)
    }

    private func writeReplacing(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".clefwise-\(UUID().uuidString).tmp")
        try PracticeJournal.writeSynced(data, to: temporary)
        guard rename(temporary.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// Takes away the folders left empty in `pendingFolder` (not `kept/`).
    private func removeEmptyFolders() {
        for top in [JournalLayout.runsFolder, JournalLayout.eventsFolder, JournalLayout.piecesFolder] {
            let root = pendingFolder.appendingPathComponent(top)
            let inside = (FileManager.default.subpaths(atPath: root.path) ?? []).map { root.appendingPathComponent($0).path }
            // Deepest first; rmdir leaves any folder that isn't empty.
            for path in inside.sorted(by: { $0.count > $1.count }) + [root.path] { rmdir(path) }
        }
    }
}

private extension UsageEvent {
    /// The hash of the score a library event brings into the journal's `pieces/`.
    var scoreHash: String? {
        switch self {
        case .pieceAdded(let added): added.piece
        case .pieceRevised(let revised): revised.file
        default: nil
        }
    }
}

// MARK: - Events kept only in the journal

/// Where the piece library's changes go: `pieceAdded`, `pieceRevised` and `pieceRemoved`, kept only
/// in the journal, never in the usage log.
protocol JournalEventRecording: AnyObject, Sendable {
    /// Stamps `event` as happening now, in the usage log's session and order, and adds it to the
    /// journal as an event file, `piece` going into `pieces/` first. Returns at once: the disk work
    /// happens elsewhere, and while the journal can't be reached the event waits on the device.
    func recordInJournal(_ event: UsageEvent, piece: JournalPieceFile?)
}

/// Stamps events like the usage log does (its session, its next sequence number), heads each with
/// an event file's header (this device, the app as it launched) and hands it to the outbox.
final class JournalEventRecorder: JournalEventRecording, @unchecked Sendable {
    let outbox: JournalOutbox
    let device: UUID
    let launch: AppLaunched
    /// Whose session and sequence numbers the events share.
    let log: UsageLog
    private let clock: () -> Date

    /// `clock` is for tests.
    init(outbox: JournalOutbox, device: UUID, launch: AppLaunched, log: UsageLog, clock: @escaping () -> Date = { Date() }) {
        self.outbox = outbox
        self.device = device
        self.launch = launch
        self.log = log
        self.clock = clock
    }

    func recordInJournal(_ event: UsageEvent, piece: JournalPieceFile?) {
        let logged = LoggedEvent(event, session: log.session, sequence: log.takeSequence(), time: clock())
        outbox.add(event: logged, header: RunFileHeader(event: logged.id, device: device, launch: launch), piece: piece)
    }
}
