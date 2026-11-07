import Foundation

// Bringing a device's existing usage log and piece library into its practice journal, once, when
// the journal is made. See spec/practice-journal.md, "Bringing in the old usage log".

/// Copies what a device already has into its journal: each practice run in its usage log as a run
/// file, its opening balance (`statsSnapshot`) as an event file, and each piece in its library as
/// its score and a `pieceAdded`. The log and the library are only read.
///
/// Bringing them in again adds nothing that's already there: a run file is named by its round, the
/// snapshot's event file by the snapshot's own id, a library entry's `pieceAdded` by the entry's id,
/// and a score by its bytes. A record whose file is already in the journal is skipped.
enum LogImport {
    /// What bringing the log in did.
    struct Summary: Equatable, Sendable {
        /// Run files placed in the journal, `runsInterrupted` of them given an `interrupted` end.
        var runsWritten = 0
        var runsInterrupted = 0
        /// Runs with no `answerGiven`, which get no file.
        var runsWithoutAnswers = 0
        /// Runs whose file was already in the journal.
        var runsAlreadyPresent = 0
        /// Runs left open in their session but brought back in a later one (`roundRestored`): the
        /// run-file writer has them.
        var runsRestoredLater = 0
        /// Event files written for the opening balance (`statsSnapshot`), and ones already there.
        var eventsWritten = 0
        var eventsAlreadyPresent = 0
        /// Library pieces brought in (their score and `pieceAdded`), already there, or left out
        /// because their copy in the library can't be read.
        var piecesWritten = 0
        var piecesAlreadyPresent = 0
        var piecesUnreadable = 0
        /// Log lines that didn't parse (cut off by a crash, from a newer version…), and how many of
        /// them fell within a run and went into its file.
        var unreadableLines = 0
        var unreadableLinesInRuns = 0
    }

    enum Failure: Error, Equatable {
        /// The journal has no folder (none made yet, or out of reach).
        case noJournal
    }

    /// Brings in the usage log in `usageLog` and the piece library in `pieceLibrary`, off the main
    /// thread. See `bringInNow`.
    static func bringIn(usageLog: URL, pieceLibrary: URL, device: UUID, launch: AppLaunched,
                        into journal: JournalWriting, skippingSession: UUID? = nil,
                        now: @escaping @Sendable () -> Date = { Date() }) async throws -> Summary {
        try await Task.detached(priority: .utility) {
            try bringInNow(usageLog: usageLog, pieceLibrary: pieceLibrary, device: device, launch: launch,
                           into: journal, skippingSession: skippingSession, now: now)
        }.value
    }

    /// Brings in the usage log in `usageLog` (its day files) and the piece library in
    /// `pieceLibrary` (its `index.json` and copies), on the calling thread:
    /// - **Runs:** within each session, every line from a `roundStarted` to the `roundEnded` of the
    ///   same round, both included, whatever else the session logged between, copied byte for byte.
    ///   Line 1 is a header from the session's `appLaunched` (failing that, the last one logged
    ///   before the run, or `launch`). A run with no answers gets no file; one its session never
    ///   ended (the app crashed) gets an `interrupted` end, timed at its last event and
    ///   `recordedAt` `now()`.
    /// - **Opening balance:** each `statsSnapshot` becomes an event file.
    /// - **Library:** each entry becomes its score in `pieces/` and a `pieceAdded` with the entry's
    ///   id, timed when it was added, its header from `launch`.
    ///
    /// `device` goes in every header. `skippingSession` is the running app's own session, if its
    /// log is already being written: the run-file writer takes its runs, so its lines are left
    /// alone. Throws `Failure.noJournal` when the journal has no folder, or what the journal threw;
    /// what was written by then stays, and bringing the log in again carries on from there.
    static func bringInNow(usageLog: URL, pieceLibrary: URL, device: UUID, launch: AppLaunched,
                           into journal: JournalWriting, skippingSession: UUID? = nil,
                           now: () -> Date = { Date() }) throws -> Summary {
        guard let folder = journal.folder else { throw Failure.noJournal }
        var summary = Summary()
        // The events this bringing-in makes (interrupted ends, `pieceAdded`) form a session of
        // their own, numbered in the order made.
        let session = UUID()
        var sequence = 0
        func envelope(_ event: UsageEvent, id: UUID = UUID(), at time: Date) -> LoggedEvent {
            defer { sequence += 1 }
            return LoggedEvent(event, id: id, session: session, sequence: sequence, time: time)
        }
        func isInJournal(_ path: String) -> Bool {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path)
        }

        var splitter = RunSplitter<Data>(skipping: skippingSession)
        var snapshots: [LoggedEvent] = []

        func write(_ run: RunSplitter<Data>.Run) throws {
            guard run.events.contains(where: \.isAnswer) else {
                summary.runsWithoutAnswers += 1
                return
            }
            guard !isInJournal(JournalLayout.runPath(startedAt: run.startedAt, run: run.round)) else {
                summary.runsAlreadyPresent += 1
                return
            }
            let header = RunFileHeader(run: run.round, device: device,
                                       launch: splitter.launches[run.session] ?? run.launch ?? launch)
            var contents = try header.encodedLine()
            for line in run.lines {
                contents.append(line)
                contents.append(0x0A)
            }
            if !run.ended, let last = run.events.last {
                let end = interruptedEnd(of: run.events, round: run.round, recordedAt: now())
                contents.append(try envelope(.roundEnded(end), at: last.time).encodedLine())
            }
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("clefwise-import-\(UUID().uuidString).jsonl")
            try contents.write(to: file)
            do {
                try journal.place(runFile: file, header: header, startedAt: run.startedAt)
            } catch {
                try? FileManager.default.removeItem(at: file)
                throw error
            }
            summary.runsWritten += 1
            if !run.ended { summary.runsInterrupted += 1 }
            summary.unreadableLinesInRuns += run.unreadableLines
        }

        // Runs, in the order the log has them.
        for url in UsageLog.eventFiles(in: usageLog) {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            try UsageLog.forEachLine(in: data) { line in
                let event = UsageLog.event(in: line)
                if let event {
                    if case .statsSnapshot = event.event, event.session != skippingSession { snapshots.append(event) }
                } else {
                    summary.unreadableLines += 1
                }
                if let run = splitter.take(Data(line), event) { try write(run) }
            }
        }
        for run in splitter.finish() {
            if splitter.restoredRounds.contains(run.round) {
                summary.runsRestoredLater += 1
            } else {
                try write(run)
            }
        }

        // The opening balance.
        for snapshot in snapshots {
            guard !isInJournal(JournalLayout.eventPath(at: snapshot.time, event: snapshot.id)) else {
                summary.eventsAlreadyPresent += 1
                continue
            }
            let header = RunFileHeader(event: snapshot.id, device: device,
                                       launch: splitter.launches[snapshot.session] ?? launch)
            try journal.add(event: snapshot, header: header, piece: nil)
            summary.eventsWritten += 1
        }

        // The library.
        for entry in libraryEntries(in: pieceLibrary) {
            guard !isInJournal(JournalLayout.eventPath(at: entry.addedAt, event: entry.id)) else {
                summary.piecesAlreadyPresent += 1
                continue
            }
            guard let data = try? Data(contentsOf: pieceLibrary.appendingPathComponent(entry.fileName)) else {
                summary.piecesUnreadable += 1
                continue
            }
            // The bytes' own hash, which names the file, even if the index's is out of date.
            let score = JournalPieceFile(data: data, fileExtension: scoreExtension(of: entry))
            let added = PieceAdded(piece: score.hash, title: entry.title,
                                   fileName: (entry.originalPath as NSString).lastPathComponent,
                                   libraryID: entry.id, originalPath: entry.originalPath)
            try journal.add(event: envelope(.pieceAdded(added), id: entry.id, at: entry.addedAt),
                            header: RunFileHeader(event: entry.id, device: device, launch: launch), piece: score)
            summary.piecesWritten += 1
        }
        return summary
    }

    /// The runs in `events` (one session or several, in the order logged), each as its events from
    /// `roundStarted` to `roundEnded`, in the order they started. Runs left open come last in their
    /// session, without an end. Splits as `bringInNow` does, for folding events without files.
    static func runs(in events: [LoggedEvent]) -> [[LoggedEvent]] {
        var splitter = RunSplitter<LoggedEvent>(skipping: nil)
        var runs: [RunSplitter<LoggedEvent>.Run] = []
        for event in events {
            if let run = splitter.take(event, event) { runs.append(run) }
        }
        runs += splitter.finish()
        return runs.sorted { $0.order < $1.order }.map(\.lines)
    }

    // MARK: - An interrupted end

    /// The `roundEnded` for a run its session never ended (`events`, the run's events in order): reason
    /// `interrupted`, and its round time, pauses, score, attempts, best streak, average response time,
    /// notes to review and the question left on screen, counted from the events up to the last one.
    /// The caller times it at the last event.
    static func interruptedEnd(of events: [LoggedEvent], round: UUID, recordedAt: Date) -> RoundEnded {
        var clock = RoundClock()
        var shown: [UUID: QuestionShown] = [:]
        var onScreen: (question: QuestionShown, activeMs: Int, pausedMs: Int)?
        var score = 0, attempts = 0, bestStreak = 0
        var responseTimes: [Int] = []
        var groupsAllRight: [UUID: (responseMs: Int, allRight: Bool)] = [:]
        var groupOrder: [UUID] = []
        var misses: [String: (count: Int, pitch: LoggedPitch)] = [:]

        for logged in events {
            let time = logged.time
            switch logged.event {
            case .roundStarted(let started) where started.round == round:
                clock.start(at: time)
            case .roundPaused(let paused) where paused.round == round:
                clock.pause(at: time, activeMs: paused.activeMs)
            case .roundResumed(let resumed) where resumed.round == round:
                clock.resume(at: time, pausedMs: resumed.pausedMs)
            case .roundRestored(let restored) where restored.round == round:
                clock.restore(at: time, activeMs: restored.activeMs)
            case .questionShown(let question) where question.round == round:
                shown[question.question] = question
                // Notes asked together are on screen as their first.
                if onScreen == nil || question.group == nil || onScreen?.question.group != question.group {
                    onScreen = (question, clock.active(at: time), clock.paused(at: time))
                }
            case .answerGiven(let answer) where answer.round == round:
                onScreen = nil
                attempts += 1
                if answer.correct { score += 1 }
                bestStreak = max(bestStreak, answer.streakAfter)
                if let group = answer.group {
                    if groupsAllRight[group] == nil { groupOrder.append(group) }
                    groupsAllRight[group] = (answer.responseMs, (groupsAllRight[group]?.allRight ?? true) && answer.correct)
                } else if answer.correct {
                    responseTimes.append(answer.responseMs)
                }
                if !answer.correct, let question = shown[answer.question] {
                    let key = JournalProjection.statKey(clef: question.clef, pitch: question.pitch.name)
                    misses[key, default: (0, question.pitch)].count += 1
                }
            default:
                break
            }
        }
        // One time per question, as `Game` keeps them: notes asked together count once, when all
        // were right.
        responseTimes += groupOrder.compactMap { groupsAllRight[$0].flatMap { $0.allRight ? $0.responseMs : nil } }
        let last = events.last?.time ?? recordedAt
        let pausedMs = clock.paused(at: last)
        // As `Game` lists them: most missed first, then lowest.
        let review = misses.sorted {
            $0.value.count != $1.value.count ? $0.value.count > $1.value.count
                : ($0.value.pitch.diatonicIndex, $0.value.pitch.midi, $0.key) < ($1.value.pitch.diatonicIndex, $1.value.pitch.midi, $1.key)
        }
        let unanswered = onScreen.map { left in
            let paused = pausedMs - left.pausedMs
            return UnansweredQuestion(question: left.question.question, shownMs: clock.active(at: last) - left.activeMs,
                                      keystrokes: [], pausedMs: paused > 0 ? paused : nil, group: left.question.group)
        }
        return RoundEnded(
            round: round, reason: .interrupted, durationMs: clock.active(at: last),
            pausedMs: clock.everPaused ? pausedMs : nil, score: score, attempts: attempts, bestStreak: bestStreak,
            averageResponseMs: responseTimes.isEmpty
                ? nil : Int((Double(responseTimes.reduce(0, +)) / Double(responseTimes.count)).rounded()),
            notesToReview: review.prefix(4).map(\.key),
            unansweredQuestion: unanswered, recordedAt: recordedAt)
    }

    /// A round's time from its events' times: running from `roundStarted`, stopped from each
    /// `roundPaused` (to the time it logs) to its `roundResumed`, and after a `roundRestored` paused
    /// from its time on, with the time it logs.
    private struct RoundClock {
        private var activeMs = 0
        private var pausedMs = 0
        private var runningSince: Date?
        private var pausedSince: Date?
        private(set) var everPaused = false

        mutating func start(at time: Date) {
            runningSince = time
        }

        mutating func pause(at time: Date, activeMs logged: Int) {
            activeMs = logged
            runningSince = nil
            pausedSince = time
            everPaused = true
        }

        mutating func resume(at time: Date, pausedMs logged: Int) {
            if pausedSince != nil { pausedMs += logged }
            pausedSince = nil
            runningSince = time
        }

        mutating func restore(at time: Date, activeMs logged: Int) {
            activeMs = logged
            runningSince = nil
            pausedSince = time
            everPaused = true
        }

        func active(at time: Date) -> Int {
            activeMs + (runningSince.map { Self.milliseconds(from: $0, to: time) } ?? 0)
        }

        func paused(at time: Date) -> Int {
            pausedMs + (pausedSince.map { Self.milliseconds(from: $0, to: time) } ?? 0)
        }

        private static func milliseconds(from start: Date, to end: Date) -> Int {
            max(0, Int((end.timeIntervalSince(start) * 1000).rounded()))
        }
    }

    // MARK: - The library

    /// What's read of an entry in the piece library's `index.json` (`PieceLibrary.Entry`).
    private struct LibraryEntry: Decodable {
        let id: UUID
        let title: String
        let originalPath: String
        let fileName: String
        let addedAt: Date
    }

    /// The library's entries, oldest first; none when its index is missing or doesn't read.
    private static func libraryEntries(in folder: URL) -> [LibraryEntry] {
        guard let data = try? Data(contentsOf: PieceLibrary.indexURL(in: folder)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = (try? decoder.decode([LibraryEntry].self, from: data)) ?? []
        return entries.sorted { ($0.addedAt, $0.id.uuidString) < ($1.addedAt, $1.id.uuidString) }
    }

    /// The copy's extension, or failing that the original's, if the journal takes it; `musicxml`
    /// otherwise.
    private static func scoreExtension(of entry: LibraryEntry) -> String {
        for name in [entry.fileName, entry.originalPath] {
            let fileExtension = (name as NSString).pathExtension.lowercased()
            if JournalLayout.pieceExtensions.contains(fileExtension) { return fileExtension }
        }
        return "musicxml"
    }
}

/// Splits usage-log lines into practice runs as they're read: within each session, every line from
/// a `roundStarted` to the `roundEnded` of the same round, both included, whatever else the session
/// logged between. `Line` is what's kept of each line: its bytes when bringing the log in, or the
/// event itself.
struct RunSplitter<Line> {
    struct Run {
        var round: UUID
        var session: UUID
        /// The `roundStarted`'s time.
        var startedAt: Date
        /// Which run this was to start, from 0.
        var order: Int
        var lines: [Line] = []
        /// The lines that parsed, in order.
        var events: [LoggedEvent] = []
        /// Lines carried along that didn't parse.
        var unreadableLines = 0
        /// Its `roundEnded` came; false for a run its session left open (the app crashed).
        var ended = false
        /// The session's `appLaunched` as known when the run started, or failing that the last one
        /// logged before it.
        var launch: AppLaunched?
    }

    /// A session whose lines are left out (the running app's).
    let skippedSession: UUID?
    /// Each session's `appLaunched`.
    private(set) var launches: [UUID: AppLaunched] = [:]
    /// Rounds brought back after a crash, in any session (`roundRestored`).
    private(set) var restoredRounds: Set<UUID> = []
    private var lastLaunch: AppLaunched?
    /// By session.
    private var open: [UUID: Run] = [:]
    /// The session of the last line that parsed: a line that doesn't goes in its run, if one's open.
    private var lastSession: UUID?
    private var runsStarted = 0

    init(skipping session: UUID?) {
        skippedSession = session
    }

    /// Takes the next line in the order logged, with its event (nil when it doesn't parse). Returns
    /// the run it finished, if any: its own when it's the `roundEnded`, or the session's open one
    /// when a new `roundStarted` comes before that run ended.
    mutating func take(_ line: Line, _ event: LoggedEvent?) -> Run? {
        guard let event else {
            if let session = lastSession, var run = open[session] {
                run.lines.append(line)
                run.unreadableLines += 1
                open[session] = run
            }
            return nil
        }
        lastSession = event.session
        if case .roundRestored(let restored) = event.event { restoredRounds.insert(restored.round) }
        guard event.session != skippedSession else { return nil }
        if case .appLaunched(let launch) = event.event {
            launches[event.session] = launch
            lastLaunch = launch
        }
        var finished: Run?
        if case .roundStarted(let started) = event.event {
            finished = open.removeValue(forKey: event.session)
            open[event.session] = Run(round: started.round, session: event.session, startedAt: event.time,
                                      order: runsStarted, launch: launches[event.session] ?? lastLaunch)
            runsStarted += 1
        }
        guard var run = open[event.session] else { return finished }
        run.lines.append(line)
        run.events.append(event)
        if case .roundEnded(let ended) = event.event, ended.round == run.round {
            run.ended = true
            open[event.session] = nil
            return run
        }
        open[event.session] = run
        return finished
    }

    /// The runs still open once every line is taken, in the order they started: their sessions
    /// stopped without ending them.
    mutating func finish() -> [Run] {
        defer { open = [:] }
        return open.values.sorted { $0.order < $1.order }
    }
}

private extension LoggedEvent {
    /// An event with an id of its own choosing, so bringing the log in again names it the same.
    init(_ event: UsageEvent, id: UUID, session: UUID, sequence: Int, time: Date) {
        schema = Self.schemaVersion
        self.id = id
        self.time = time
        self.session = session
        self.sequence = sequence
        self.event = event
    }

    var isAnswer: Bool {
        if case .answerGiven = event { return true }
        return false
    }
}

private extension LoggedPitch {
    /// Steps from C0, letters only: what orders notes on the staff.
    var diatonicIndex: Int {
        octave * 7 + (["C", "D", "E", "F", "G", "A", "B"].firstIndex(of: letter) ?? 0)
    }
}
