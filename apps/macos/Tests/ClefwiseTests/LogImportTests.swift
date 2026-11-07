import Foundation
import Testing
@testable import Clefwise

// Bringing the old usage log and piece library into a journal (spec/practice-journal.md, "Bringing
// in the old usage log").

/// A journal in a folder, as the spec has it: run files moved to their place, event files written
/// whole, scores written once. It never overwrites, so writing anything twice fails the test.
final class FolderJournal: JournalWriting, @unchecked Sendable {
    let folder: URL?

    init(folder: URL?) { self.folder = folder }

    struct NoJournal: Error {}

    func place(runFile: URL, header: RunFileHeader, startedAt: Date) throws {
        guard let folder, let run = header.run else { throw NoJournal() }
        let target = folder.appendingPathComponent(JournalLayout.runPath(startedAt: startedAt, run: run))
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: runFile, to: target)
    }

    func add(event: LoggedEvent, header: RunFileHeader, piece: JournalPieceFile?) throws {
        guard let folder else { throw NoJournal() }
        if let piece {
            let url = folder.appendingPathComponent(JournalLayout.piecePath(hash: piece.hash, fileExtension: piece.fileExtension))
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try piece.data.write(to: url, options: .withoutOverwriting)
            }
        }
        var header = header
        header.event = event.id
        let url = folder.appendingPathComponent(JournalLayout.eventPath(at: event.time, event: event.id))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (header.encodedLine() + event.encodedLine()).write(to: url, options: .withoutOverwriting)
    }

    /// Every file in the journal by its relative path, with its bytes.
    func contents() -> [String: Data] {
        guard let folder, let paths = FileManager.default.enumerator(atPath: folder.path) else { return [:] }
        var files: [String: Data] = [:]
        for case let path as String in paths {
            var isFolder: ObjCBool = false
            let url = folder.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue {
                files[path] = try? Data(contentsOf: url)
            }
        }
        return files
    }
}

/// The lines of `data`, without their line feeds.
func journalLines(_ data: Data) -> [Data] {
    var lines: [Data] = []
    UsageLog.forEachLine(in: data) { lines.append(Data($0)) }
    return lines
}

private let device = UUID(uuidString: "D0D0D0D0-1111-4222-8333-444455556666")!
private let importedAt = usageTestTime("2026-11-06T12:00:00.000Z")

private func launched(_ version: String, timeZone: String = "Europe/Bucharest") -> AppLaunched {
    AppLaunched(appVersion: version, build: "1", osVersion: "26.1.0", model: "Mac15,12", locale: "en_GB",
                timeZone: timeZone, screen: nil, systemAppearance: "light")
}

/// Writes a usage log by hand: each session's lines numbered in order, the times given in seconds
/// after `start`.
private struct LogWriter {
    let start: Date
    private(set) var lines: [Data] = []
    private var sequences: [UUID: Int] = [:]

    init(start: Date) { self.start = start }

    /// Appends `event` as `session` logged it, `at` seconds in; returns it as read back from its
    /// line (its time to the millisecond).
    @discardableResult
    mutating func log(_ event: UsageEvent, _ session: UUID, at seconds: Double) throws -> LoggedEvent {
        let logged = LoggedEvent(event, session: session, sequence: sequences[session, default: 0],
                                 time: start.addingTimeInterval(seconds))
        sequences[session, default: 0] += 1
        let line = Data(try logged.encodedLine().dropLast())
        lines.append(line)
        return try LoggedEvent.decoder.decode(LoggedEvent.self, from: line)
    }

    /// Appends a line as it is.
    mutating func raw(_ text: String, counting session: UUID? = nil) {
        lines.append(Data(text.utf8))
        if let session { sequences[session, default: 0] += 1 }
    }

    /// The lines as a day file. A line cut off by a crash ends with a line feed too: the next launch
    /// adds one before going on.
    func data() -> Data {
        lines.reduce(into: Data()) { $0 += $1 + Data([0x0A]) }
    }
}

/// A round's start as versions until 2026-11-07 logged it, with `mode` in its settings: `practice`,
/// or `sprint` for a 60-second sprint.
private func roundStarted(_ round: UUID, mode: String = "practice") -> UsageEvent {
    var settings: [String: JSONValue] = [:]
    if case .object(let saved) = JSONValue(encoding: Game.Settings()) { settings = saved }
    settings["mode"] = .string(mode)
    return .roundStarted(RoundStarted(round: round, via: .button, settings: .object(settings), keyFifths: 0, piece: nil))
}

private func question(_ round: UUID, _ id: UUID, _ pitch: Pitch, index: Int = 0) -> UsageEvent {
    .questionShown(QuestionShown(round: round, question: id, index: index, clef: "treble", pitch: LoggedPitch(pitch),
                                 written: LoggedPitch(pitch), position: 0, keyFifths: 0, printedAccidental: nil,
                                 octaveShift: 0, pieceNote: nil, pickChance: nil, naming: "letters", input: "buttons",
                                 hintsVisible: false, keyNamesVisible: false))
}

private func answer(_ round: UUID, _ id: UUID, correct: Bool, responseMs: Int = 1500, score: Int, streak: Int) -> UsageEvent {
    .answerGiven(AnswerGiven(round: round, question: id, responseMs: responseMs, source: .click, letter: "E",
                             accidental: 0, name: "E", pitch: nil, correct: correct, wrongOctave: nil, keystrokes: [],
                             scoreAfter: score, streakAfter: streak))
}

private func ended(_ round: UUID, _ reason: RoundEndReason = .stopped, score: Int, attempts: Int) -> UsageEvent {
    .roundEnded(RoundEnded(round: round, reason: reason, durationMs: 4000, score: score, attempts: attempts, bestStreak: score,
                           averageResponseMs: nil, notesToReview: []))
}

@MainActor
@Suite struct LogImportTests {
    private let temporary = UsageTestFolder()
    private var usage: URL { temporary.url.appendingPathComponent("Usage", isDirectory: true) }
    private var libraryFolder: URL { temporary.url.appendingPathComponent("Pieces", isDirectory: true) }
    private var journal: FolderJournal { FolderJournal(folder: temporary.url.appendingPathComponent("Journal", isDirectory: true)) }

    private let s1 = UUID(), s2 = UUID(), s3 = UUID(), s4 = UUID()
    private let r1 = UUID(), r2 = UUID(), r3 = UUID(), r4 = UUID(), r5 = UUID()
    private let q1 = UUID(), q2 = UUID(), q3 = UUID(), q4 = UUID(), q5 = UUID(), q6 = UUID()

    private func writeDay(_ name: String, _ data: Data) throws {
        try FileManager.default.createDirectory(at: usage, withIntermediateDirectories: true)
        try data.write(to: usage.appendingPathComponent(name))
    }

    private func bringIn(skipping session: UUID? = nil) throws -> LogImport.Summary {
        try LogImport.bringInNow(usageLog: usage, pieceLibrary: libraryFolder, device: device, launch: launched("9.9.9"),
                                 into: journal, skippingSession: session, now: { importedAt })
    }

    private func runFile(_ round: UUID, startedAt: Date) -> (header: RunFileHeader?, lines: [Data])? {
        let url = journal.folder!.appendingPathComponent(JournalLayout.runPath(startedAt: startedAt, run: round))
        guard let data = try? Data(contentsOf: url) else { return nil }
        let lines = journalLines(data)
        return (lines.first.flatMap(RunFileHeader.init(line:)), Array(lines.dropFirst()))
    }

    /// Two days of log: four sessions, five rounds, a snapshot, events between rounds, a line cut
    /// off by a crash and one that isn't JSON at all. Returns what the tests check against.
    private func writeLog() throws -> (day1: LogWriter, day2: LogWriter, snapshot: LoggedEvent, starts: [UUID: Date]) {
        var starts: [UUID: Date] = [:]
        var day1 = LogWriter(start: usageTestTime("2026-11-01T09:00:00.000Z"))
        try day1.log(.appLaunched(launched("0.1.0")), s1, at: 0)
        let snapshot = try day1.log(.statsSnapshot(StatsSnapshot(
            reason: "beforeUsageLog", noteStats: ["treble.E4": NoteStat(attempts: 3, correct: 2, recent: [true, false, true])],
            bestScores: ["treble.staff": 12])), s1, at: 0.1)
        try day1.log(.settingChanged(SettingChanged(setting: "mode", from: .string("sprint"), to: .string("practice"))), s1, at: 1)
        // R1: answered, with an app switch inside it and an answer an older version wrote with its
        // keys in another order and a field this one doesn't know.
        starts[r1] = try day1.log(roundStarted(r1), s1, at: 2).time
        try day1.log(question(r1, q1, Pitch(.e, 4)), s1, at: 2.1)
        day1.raw(#"{"type":"answerGiven","schema":1,"id":"\#(UUID().uuidString)","time":"2026-11-01T09:00:03.000Z","session":"\#(s1.uuidString)","sequence":5,"round":"\#(r1.uuidString)","question":"\#(q1.uuidString)","responseMs":900,"source":"click","letter":"E","accidental":0,"name":"E","correct":true,"keystrokes":[],"scoreAfter":1,"streakAfter":1,"legacyField":true}"#,
                 counting: s1)
        try day1.log(.appActivity(AppActivity(active: false)), s1, at: 3.5)
        try day1.log(.appActivity(AppActivity(active: true)), s1, at: 4)
        try day1.log(question(r1, q2, Pitch(.f, 4), index: 1), s1, at: 4.1)
        try day1.log(answer(r1, q2, correct: false, score: 1, streak: 0), s1, at: 5)
        try day1.log(ended(r1, score: 1, attempts: 2), s1, at: 6)
        // Between rounds: not part of any run.
        try day1.log(.uiAction(UIAction(name: "showDashboard", detail: nil)), s1, at: 7)
        day1.raw("not a usage line")
        // R2: started and stopped with no answer.
        starts[r2] = try day1.log(roundStarted(r2), s1, at: 8).time
        try day1.log(question(r2, q3, Pitch(.g, 4)), s1, at: 8.1)
        try day1.log(ended(r2, score: 0, attempts: 0), s1, at: 9)
        try day1.log(.appTerminated(AppTerminated(sessionSeconds: 10)), s1, at: 10)

        var day2 = LogWriter(start: usageTestTime("2026-11-02T18:00:00.000Z"))
        try day2.log(.appLaunched(launched("0.1.0")), s2, at: 0)
        // R3: the app crashed mid-round, cutting off the line it was writing.
        starts[r3] = try day2.log(roundStarted(r3), s2, at: 1).time
        try day2.log(question(r3, q4, Pitch(.a, 4)), s2, at: 1.5)
        try day2.log(answer(r3, q4, correct: true, responseMs: 1200, score: 1, streak: 1), s2, at: 2.7)
        try day2.log(question(r3, q5, Pitch(.b, 4), index: 1), s2, at: 2.75)
        day2.raw(#"{"schema":1,"type":"keyPress","id":"#)
        // The next launch, a newer version, ends R4 normally after a pause.
        try day2.log(.appLaunched(launched("0.2.0", timeZone: "Europe/Stockholm")), s3, at: 600)
        starts[r4] = try day2.log(roundStarted(r4, mode: "sprint"), s3, at: 601).time
        try day2.log(question(r4, q6, Pitch(.c, 5)), s3, at: 601.2)
        try day2.log(.roundPaused(RoundPaused(round: r4, question: q6, via: .key, activeMs: 300)), s3, at: 601.5)
        try day2.log(.roundResumed(RoundResumed(round: r4, question: q6, via: .key, pausedMs: 2000)), s3, at: 603.5)
        try day2.log(answer(r4, q6, correct: true, score: 1, streak: 1), s3, at: 604)
        try day2.log(ended(r4, .timeUp, score: 1, attempts: 1), s3, at: 661)
        // A session with no `appLaunched` (its line lost): its header falls back to the last one.
        let q7 = UUID()
        starts[r5] = try day2.log(roundStarted(r5), s4, at: 700).time
        try day2.log(question(r5, q7, Pitch(.d, 5)), s4, at: 700.5)
        try day2.log(answer(r5, q7, correct: true, score: 1, streak: 1), s4, at: 701)
        try day2.log(ended(r5, score: 1, attempts: 1), s4, at: 702)

        try writeDay("usage-2026-11-01.jsonl", day1.data())
        try writeDay("usage-2026-11-02.jsonl", day2.data())
        return (day1, day2, snapshot, starts)
    }

    /// The library: two pieces, the first opened again later, its index as `PieceLibrary` writes it.
    private func writeLibrary() throws -> [PieceLibrary.Entry] {
        let originals = temporary.url.appendingPathComponent("Originals", isDirectory: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let minuet = originals.appendingPathComponent("Minuet.musicxml")
        let prelude = originals.appendingPathComponent("Prelude.XML")
        try Data("<score-partwise>minuet</score-partwise>".utf8).write(to: minuet)
        try Data("<score-partwise>prelude</score-partwise>".utf8).write(to: prelude)
        let library = PieceLibrary(folder: libraryFolder)
        let first = try library.add(minuet, title: "Minuet in G", now: usageTestTime("2026-10-20T10:00:00.000Z"))
        let second = try library.add(prelude, title: "Prelude", now: usageTestTime("2026-10-25T11:30:00.000Z"))
        try library.add(minuet, title: "Minuet in G", now: usageTestTime("2026-11-01T08:00:00.000Z"))
        return [first, second]
    }

    @Test func runsEventsAndPiecesGoWhereTheSpecSays() throws {
        let (day1, day2, snapshot, starts) = try writeLog()
        let entries = try writeLibrary()

        let summary = try bringIn()
        #expect(summary == LogImport.Summary(
            runsWritten: 4, runsInterrupted: 1, runsWithoutAnswers: 1, runsAlreadyPresent: 0, runsRestoredLater: 0,
            eventsWritten: 1, eventsAlreadyPresent: 0, piecesWritten: 2, piecesAlreadyPresent: 0, piecesUnreadable: 0,
            unreadableLines: 2, unreadableLinesInRuns: 1))

        // Every file has a name that fits, and nothing else was written.
        let files = journal.contents()
        #expect(files.keys.allSatisfy(JournalLayout.fits))
        #expect(files.keys.filter { $0.hasPrefix("runs/") }.count == 4)
        #expect(files.keys.filter { $0.hasPrefix("events/") }.count == 3)
        #expect(files.keys.filter { $0.hasPrefix("pieces/") }.count == 2)

        // R1: its header from its session's launch, then the log's lines from its start to its end,
        // byte for byte, the app switch and the older line among them.
        let run1 = try #require(runFile(r1, startedAt: starts[r1]!))
        #expect(run1.header == RunFileHeader(run: r1, device: device, launch: launched("0.1.0")))
        #expect(run1.lines == Array(day1.lines[3...10]))
        #expect(String(decoding: run1.lines[2], as: UTF8.self).contains("legacyField"))

        // R2 had no answers: no file.
        #expect(runFile(r2, startedAt: starts[r2]!) == nil)

        // R3 never ended: its lines, the cut-off one too, then an interrupted end counted from them.
        let run3 = try #require(runFile(r3, startedAt: starts[r3]!))
        #expect(run3.header?.run == r3 && run3.header?.appVersion == "0.1.0")
        #expect(Array(run3.lines.dropLast()) == Array(day2.lines[1...5]))
        let lastLine = try #require(run3.lines.last)
        let end = try #require(UsageLog.event(in: lastLine))
        #expect(end.time == starts[r3]!.addingTimeInterval(1.75))
        #expect(end.event == .roundEnded(RoundEnded(
            round: r3, reason: .interrupted, durationMs: 1750, pausedMs: nil, score: 1, attempts: 1, bestStreak: 1,
            averageResponseMs: 1200, notesToReview: [],
            unansweredQuestion: UnansweredQuestion(question: q5, shownMs: 0, keystrokes: []), recordedAt: importedAt)))

        // R4 in the next session, with that session's launch.
        let run4 = try #require(runFile(r4, startedAt: starts[r4]!))
        #expect(run4.header == RunFileHeader(run: r4, device: device, launch: launched("0.2.0", timeZone: "Europe/Stockholm")))
        #expect(run4.lines == Array(day2.lines[7...12]))

        // R5's session has no launch: the last one logged before it stands in.
        let run5 = try #require(runFile(r5, startedAt: starts[r5]!))
        #expect(run5.header?.appVersion == "0.2.0" && run5.header?.timeZone == "Europe/Stockholm")
        #expect(run5.lines == Array(day2.lines[13...16]))

        // Every run file reads back whole, ending with its `roundEnded`.
        for (round, start) in starts where round != r2 {
            let read = RunFile.read(journal.folder!.appendingPathComponent(JournalLayout.runPath(startedAt: start, run: round)))
            #expect(read.header?.run == round)
            #expect(read.unreadableLines == (round == r3 ? 1 : 0))
            guard case .roundEnded(let ended) = read.events.last?.event else {
                Issue.record("\(round) doesn't end with roundEnded")
                continue
            }
            #expect(ended.round == round)
        }

        // The opening balance, under the snapshot's own id and time.
        let snapshotFile = RunFile.read(journal.folder!.appendingPathComponent(
            JournalLayout.eventPath(at: snapshot.time, event: snapshot.id)))
        #expect(snapshotFile.header == RunFileHeader(event: snapshot.id, device: device, launch: launched("0.1.0")))
        #expect(snapshotFile.events == [snapshot])

        // Each piece: its score named by its hash, and a `pieceAdded` under the entry's id, timed when added.
        for (entry, original) in zip(entries, ["Minuet.musicxml", "Prelude.XML"]) {
            let bytes = try Data(contentsOf: libraryFolder.appendingPathComponent(entry.fileName))
            #expect(JournalPieceFile.sha256(of: bytes) == entry.contentHash)
            let fileExtension = original == "Prelude.XML" ? "xml" : "musicxml"
            #expect(files[JournalLayout.piecePath(hash: entry.contentHash, fileExtension: fileExtension)] == bytes)

            let added = RunFile.read(journal.folder!.appendingPathComponent(JournalLayout.eventPath(at: entry.addedAt, event: entry.id)))
            #expect(added.header == RunFileHeader(event: entry.id, device: device, launch: launched("9.9.9")))
            let event = try #require(added.events.first)
            #expect(added.events.count == 1 && event.id == entry.id && event.time == entry.addedAt)
            #expect(event.event == .pieceAdded(PieceAdded(piece: entry.contentHash, title: entry.title, fileName: original,
                                                          libraryID: entry.id, originalPath: entry.originalPath)))
        }
    }

    @Test func bringingItInAgainAddsNothing() async throws {
        _ = try writeLog()
        _ = try writeLibrary()
        let first = try await LogImport.bringIn(usageLog: usage, pieceLibrary: libraryFolder, device: device,
                                                launch: launched("9.9.9"), into: journal, now: { importedAt })
        #expect(first.runsWritten == 4 && first.eventsWritten == 1 && first.piecesWritten == 2)
        let files = journal.contents()

        let again = try bringIn()
        #expect(again == LogImport.Summary(
            runsWritten: 0, runsInterrupted: 0, runsWithoutAnswers: 1, runsAlreadyPresent: 4, runsRestoredLater: 0,
            eventsWritten: 0, eventsAlreadyPresent: 1, piecesWritten: 0, piecesAlreadyPresent: 2, piecesUnreadable: 0,
            unreadableLines: 2, unreadableLinesInRuns: 0))
        #expect(journal.contents() == files)
    }

    @Test func theRunningSessionAndRoundsBroughtBackLaterAreLeftToTheWriter() throws {
        var day = LogWriter(start: usageTestTime("2026-11-03T08:00:00.000Z"))
        // S1 crashed mid-round; S2 brought the round back (and its file is the writer's to place).
        try day.log(.appLaunched(launched("0.3.0")), s1, at: 0)
        try day.log(roundStarted(r1), s1, at: 1)
        try day.log(question(r1, q1, Pitch(.e, 4)), s1, at: 1.5)
        try day.log(answer(r1, q1, correct: true, score: 1, streak: 1), s1, at: 2)
        try day.log(.appLaunched(launched("0.3.0")), s2, at: 100)
        try day.log(.roundRestored(RoundRestored(round: r1, activeMs: 1000, unansweredQuestion: nil)), s2, at: 100.5)
        try day.log(ended(r1, .stopped, score: 1, attempts: 1), s2, at: 101)
        // S3 is the app running now, mid-round.
        try day.log(.appLaunched(launched("0.3.0")), s3, at: 200)
        try day.log(roundStarted(r2), s3, at: 201)
        try day.log(question(r2, q2, Pitch(.f, 4)), s3, at: 201.5)
        try day.log(answer(r2, q2, correct: true, score: 1, streak: 1), s3, at: 202)
        try writeDay("usage-2026-11-03.jsonl", day.data())

        let summary = try bringIn(skipping: s3)
        #expect(summary.runsWritten == 0 && summary.runsRestoredLater == 1)
        #expect(journal.contents().isEmpty)
    }

    @Test func aJournalWithNoFolderIsRefused() throws {
        #expect(throws: LogImport.Failure.noJournal) {
            try LogImport.bringInNow(usageLog: usage, pieceLibrary: libraryFolder, device: device,
                                     launch: launched("9.9.9"), into: FolderJournal(folder: nil))
        }
    }

    @Test func anInterruptedEndLeavesPausesOutAndCountsGroupsOnce() {
        let round = UUID(), group = UUID(), a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let session = UUID(), start = usageTestTime("2026-11-04T10:00:00.000Z")
        var sequence = 0
        func at(_ seconds: Double, _ event: UsageEvent) -> LoggedEvent {
            defer { sequence += 1 }
            return LoggedEvent(event, session: session, sequence: sequence, time: start.addingTimeInterval(seconds))
        }
        func grouped(_ event: UsageEvent) -> UsageEvent {
            switch event {
            case .questionShown(var shown):
                shown.group = group
                shown.groupSize = 2
                return .questionShown(shown)
            case .answerGiven(var given):
                given.group = group
                given.groupSize = 2
                return .answerGiven(given)
            default: return event
            }
        }
        let events = [
            at(0, roundStarted(round)),
            at(0.5, grouped(question(round, a, Pitch(.e, 4)))),
            at(0.5, grouped(question(round, b, Pitch(.g, 4), index: 1))),
            at(2, grouped(answer(round, a, correct: true, responseMs: 1500, score: 2, streak: 2))),
            at(2, grouped(answer(round, b, correct: true, responseMs: 1500, score: 2, streak: 2))),
            at(2.1, question(round, c, Pitch(.f, 4), index: 2)),
            at(3, answer(round, c, correct: false, responseMs: 900, score: 2, streak: 0)),
            at(4, question(round, d, Pitch(.a, 4), index: 3)),
            at(5, .roundPaused(RoundPaused(round: round, question: d, via: .button, activeMs: 5000))),
            at(15, .roundResumed(RoundResumed(round: round, question: d, via: .button, pausedMs: 10_000))),
            at(17, .roundPaused(RoundPaused(round: round, question: d, via: .appSwitch, activeMs: 7000))),
            at(20, .appActivity(AppActivity(active: false))),
        ]
        let end = LogImport.interruptedEnd(of: events, round: round, recordedAt: importedAt)
        #expect(end == RoundEnded(
            round: round, reason: .interrupted, durationMs: 7000, pausedMs: 13_000, score: 2, attempts: 3, bestStreak: 2,
            averageResponseMs: 1500, notesToReview: ["treble.F4"],
            unansweredQuestion: UnansweredQuestion(question: d, shownMs: 3000, keystrokes: [], pausedMs: 13_000),
            recordedAt: importedAt))
    }

    @Test func splittingEventsKeepsEachSessionsRunsApart() throws {
        var day = LogWriter(start: usageTestTime("2026-11-05T08:00:00.000Z"))
        // Two copies of the app at once (a development build beside the installed one).
        try day.log(.appLaunched(launched("1")), s1, at: 0)
        try day.log(.appLaunched(launched("2")), s2, at: 0.5)
        try day.log(roundStarted(r1), s1, at: 1)
        try day.log(roundStarted(r2), s2, at: 2)
        try day.log(question(r1, q1, Pitch(.e, 4)), s1, at: 3)
        try day.log(question(r2, q2, Pitch(.f, 4)), s2, at: 4)
        try day.log(ended(r2, score: 0, attempts: 0), s2, at: 5)
        try day.log(answer(r1, q1, correct: true, score: 1, streak: 1), s1, at: 6)
        let events = day.lines.compactMap(UsageLog.event(in:))

        let runs = LogImport.runs(in: events)
        #expect(runs.map { $0.map(\.sequence) } == [[1, 2, 3], [1, 2, 3]])
        #expect(runs.map { $0.map(\.session) } == [[s1, s1, s1], [s2, s2, s2]])
    }
}
