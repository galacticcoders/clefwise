import Foundation
import Testing
@testable import Clefwise

// The dashboard read from the practice journal (spec/practice-journal.md, "Reading" and "Bringing
// in the old usage log"): the same report as from the usage log for the same runs, pieces by their
// journal id, staves for old runs from this Mac's log, several devices' opening balances added up,
// and the store reading the journal.

/// A journal in a test's own folder, written straight from events: each round's events as its run
/// file, and each opening balance and library event as an event file. Events a journal doesn't
/// keep (`pieceOpened` and the like between rounds) are left out.
struct TestJournal {
    let folder: URL

    /// Writes `events` as `device` would have: each round's from its first event on, as its run file
    /// named by that event's time; each `statsSnapshot`, `pieceAdded`, `pieceRevised` and
    /// `pieceRemoved` as its event file.
    func write(_ events: [LoggedEvent], device: UUID = JournalFixture.device) throws {
        var runs: [UUID: [LoggedEvent]] = [:]
        var order: [UUID] = []
        for logged in events {
            if let round = Self.round(of: logged.event) {
                if runs[round] == nil { order.append(round) }
                runs[round, default: []].append(logged)
                continue
            }
            switch logged.event {
            case .statsSnapshot, .pieceAdded, .pieceRevised, .pieceRemoved:
                let header = RunFileHeader(event: logged.id, device: device, launch: JournalFixture.launch)
                try put(try header.encodedLine() + logged.encodedLine(),
                        at: JournalLayout.eventPath(at: logged.time, event: logged.id))
            default:
                continue
            }
        }
        for round in order {
            let events = runs[round] ?? []
            var data = try RunFileHeader(run: round, device: device, launch: JournalFixture.launch).encodedLine()
            for logged in events { data += try logged.encodedLine() }
            try put(data, at: JournalLayout.runPath(startedAt: events[0].time, run: round))
        }
    }

    private func put(_ data: Data, at path: String) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// The round an event is about, for the events of a round.
    private static func round(of event: UsageEvent) -> UUID? {
        switch event {
        case .roundStarted(let started): started.round
        case .questionShown(let question): question.round
        case .answerGiven(let answer): answer.round
        case .roundPaused(let pause): pause.round
        case .roundResumed(let resume): resume.round
        case .roundRestored(let restore): restore.round
        case .roundEnded(let end): end.round
        default: nil
        }
    }
}

@Suite struct DashboardJournalTests {
    private let temporary = UsageTestFolder()
    private var journalFolder: URL { temporary.url.appendingPathComponent("Journal", isDirectory: true) }
    private var usageFolder: URL { temporary.url.appendingPathComponent("Usage", isDirectory: true) }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()
    /// Friday 30 October 2026, 16:00 in Stockholm, as in `ProgressAnalyzerTests`.
    private let now = usageTestTime("2026-10-30T15:00:00.000Z")

    /// `daysAgo` local days before today, at a Stockholm wall-clock time.
    private func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
    }

    private func piece(_ title: String, path: String, libraryID: UUID? = nil, id: String? = nil,
                       staves: Int? = nil) -> PieceContext {
        PieceContext(title: title, path: path, part: "Piano", partIndex: 0, hand: "right", order: "inOrder", startBar: 1,
                     oneNotePerChord: false, noteCount: 20, measureCount: 32, libraryID: libraryID, id: id, file: id,
                     staves: staves)
    }

    private func report(_ contents: JournalReader.Contents, pieceOpenings: [LoggedEvent] = [],
                        _ filter: ProgressFilter = ProgressFilter(range: .week)) -> ProgressReport {
        ProgressAnalyzer.report(from: contents, pieceOpenings: pieceOpenings, filter: filter, now: now, calendar: calendar)
    }

    /// `events` as one day file in the usage folder.
    private func writeLog(_ events: [LoggedEvent], name: String = "usage-2026-10-30.jsonl") throws {
        try FileManager.default.createDirectory(at: usageFolder, withIntermediateDirectories: true)
        try events.reduce(into: Data()) { $0 += try $1.encodedLine() }.write(to: usageFolder.appendingPathComponent(name))
    }

    // MARK: - The same as from the log

    @Test func theJournalGivesTheSameReportAsTheLogForTheSameRuns() throws {
        // Months of practice, with an opening balance, a piece, and a crash or two.
        try writeLog(SyntheticUsage.events(days: 90, seed: 1, now: now, calendar: calendar))
        let summary = try LogImport.bringInNow(usageLog: usageFolder, pieceLibrary: temporary.url.appendingPathComponent("Pieces"),
                                               device: JournalFixture.device, launch: JournalFixture.launch,
                                               into: FolderJournal(folder: journalFolder))
        #expect(summary.runsInterrupted > 0 && summary.runsWithoutAnswers == 0 && summary.eventsWritten == 1)
        let contents = JournalReader(folder: journalFolder).read()
        #expect(contents.runs.count == summary.runsWritten && contents.snapshots.count == 1)
        let openings = LoggedPieceOpenings.read(in: usageFolder)
        #expect(!openings.isEmpty)
        let log = UsageLog.readEvents(in: usageFolder)

        let filters = [ProgressFilter(range: .week), ProgressFilter(range: .month, clef: .treble),
                       ProgressFilter(range: .quarter), ProgressFilter(range: .all), ProgressFilter(range: .all, clef: .bass)]
        for filter in filters {
            let fromJournal = report(contents, pieceOpenings: openings, filter)
            var fromLog = ProgressAnalyzer.report(from: log.events, filter: filter, unreadableLines: log.unreadableLines,
                                                  now: now, calendar: calendar)
            // The log never ended the rounds the app crashed in; bringing it in ended them as
            // interrupted, timed and scored as the log had them.
            for index in fromLog.recentRounds.indices where fromLog.recentRounds[index].endReason == nil {
                fromLog.recentRounds[index].endReason = .interrupted
            }
            #expect(fromJournal == fromLog, "\(filter)")
        }
        let allTime = report(contents, pieceOpenings: openings, ProgressFilter(range: .all))
        #expect(allTime.pieces.map(\.id) == [SyntheticUsage.piecePath] && allTime.answersBeforeTracking == 138)
    }

    // MARK: - Data from versions with the sprint

    /// Four rounds and an opening balance, logged by a version until 2026-11-07 (`old`), with
    /// sprints and best scores, or as the same rounds are logged now: a sprint, a sprint on a piece,
    /// a timed practice round, and a sprint whose settings kept a limit it didn't have.
    private func practice(old: Bool) -> Log {
        var log = Log()
        log.add(.statsSnapshot(StatsSnapshot(reason: "beforeUsageLog", noteStats: ["treble.F5": NoteStat(attempts: 10, correct: 7)],
                                             bestScores: old ? ["treble.staff": 12] : nil)), at: at(30, 9))
        func start(_ time: Date, _ mode: String, piece: PieceContext? = nil,
                   _ change: (inout Game.Settings) -> Void = { _ in }) -> UUID {
            old ? log.oldRound(at: time, mode: mode, piece: piece, change) : log.round(at: time, piece: piece, change)
        }
        func end(_ round: UUID, at time: Date, durationMs: Int, score: Int, attempts: Int, reason: RoundEndReason,
                 best: Int? = nil) {
            var ended = RoundEnded(round: round, reason: reason, durationMs: durationMs, score: score, attempts: attempts,
                                   bestStreak: score, averageResponseMs: nil, notesToReview: [])
            if old {
                ended.bestScore = best
                ended.isNewBest = best == score
            }
            log.add(.roundEnded(ended), at: time)
        }
        let sprint = start(at(2, 10), "sprint")
        log.answer(sprint, at: at(2, 10, 0, 2), Pitch(.f, 5), ms: 1500)
        log.answer(sprint, at: at(2, 10, 0, 4), Pitch(.g, 4), correct: false, ms: 1800)
        end(sprint, at: at(2, 10, 1), durationMs: 60_000, score: 1, attempts: 2, reason: .timeUp, best: 12)
        let onPiece = start(at(1, 10), "sprint", piece: piece("Minuet in G", path: "/minuet.musicxml", staves: 1))
        log.answer(onPiece, at: at(1, 10, 0, 2), Pitch(.c, 5), bar: 1)
        log.answer(onPiece, at: at(1, 10, 0, 4), Pitch(.d, 5), bar: 2)
        end(onPiece, at: at(1, 10, 1), durationMs: 60_000, score: 2, attempts: 2, reason: .timeUp)
        let timed = start(at(0, 9), "practice") {
            $0.practiceLimit = .time
            $0.practiceMinutes = 5
        }
        log.answer(timed, at: at(0, 9, 0, 2), Pitch(.e, 4))
        end(timed, at: at(0, 9, 0, 30), durationMs: 30_000, score: 1, attempts: 1, reason: .stopped)
        let withLimit = start(at(0, 11), "sprint") { $0.practiceLimit = .notes }
        log.answer(withLimit, at: at(0, 11, 0, 2), Pitch(.b, 4))
        end(withLimit, at: at(0, 11, 1), durationMs: 60_000, score: 1, attempts: 1, reason: .timeUp, best: 12)
        return log
    }

    @Test func sprintsFromBeforeItWentCountAsTheyAlwaysDid() throws {
        let then = temporary.url.appendingPathComponent("Then", isDirectory: true)
        let since = temporary.url.appendingPathComponent("Since", isDirectory: true)
        try TestJournal(folder: then).write(practice(old: true).events)
        try TestJournal(folder: since).write(practice(old: false).events)
        let old = JournalReader(folder: then).read(), new = JournalReader(folder: since).read()
        #expect(old.runs.count == 4 && old.snapshots.count == 1 && old.unreadableLines == 0)

        // The same note stats, the opening balance's included…
        let stats = JournalProjection(contents: old).noteStats
        #expect(stats == JournalProjection(contents: new).noteStats)
        #expect(stats["treble.F5"] == NoteStat(attempts: 11, correct: 8, recent: [true]))
        #expect(stats["treble.G4"] == NoteStat(attempts: 1, correct: 0, recent: [false]))

        // …and the same dashboard, every number of it.
        let week = report(old)
        #expect(week.totals.rounds == 4 && week.totals.answers == 6 && week.totals.correct == 5)
        #expect(week.totals.practiceSeconds == 210)
        // Only Recent Rounds tells them apart: the sprints keep their name, and had no limit.
        #expect(week.recentRounds.map(\.modeLabel) == ["60s Sprint", "Practice · 5 min", "60s Sprint", "60s Sprint"])
        #expect(report(new).recentRounds.map(\.modeLabel) == ["Practice · 100 notes", "Practice · 5 min", "Practice", "Practice"])
        let filters = [ProgressFilter(range: .week), ProgressFilter(range: .all), ProgressFilter(range: .all, clef: .treble)]
        for filter in filters {
            var fromOld = report(old, filter)
            let fromNew = report(new, filter)
            try #require(fromOld.recentRounds.count == fromNew.recentRounds.count)
            for index in fromOld.recentRounds.indices {
                fromOld.recentRounds[index].id = fromNew.recentRounds[index].id
                fromOld.recentRounds[index].wasSprint = false
                fromOld.recentRounds[index].practiceLength = fromNew.recentRounds[index].practiceLength
            }
            #expect(fromOld == fromNew, "\(filter)")
        }
    }

    // MARK: - Staves

    @Test func runsBroughtInFromTheLogTakeTheirStavesFromThisMacsLog() throws {
        var log = Log()
        let opened = PieceOpened(path: "/clarinet.musicxml", title: "Clarinet Tune", via: .drop,
                                 parts: [PartInfo(name: "Clarinet", notes: 40, measures: 16, staves: 1, skipped: 0)])
        log.add(.pieceOpened(opened), at: at(2, 9))
        let old = log.round(at: at(2, 10), piece: piece("Clarinet Tune", path: "/clarinet.musicxml"))
        log.answer(old, at: at(2, 10, 1), Pitch(.c, 5))
        log.end(old, at: at(2, 10, 2), durationMs: 2000, score: 1, attempts: 1)
        // Since the journal, rounds say themselves, whatever the log says.
        var grand = opened
        grand.parts[0].staves = 2
        log.add(.pieceOpened(grand), at: at(1, 9))
        let new = log.round(at: at(1, 10), piece: piece("Clarinet Tune", path: "/clarinet.musicxml", staves: 1))
        log.answer(new, at: at(1, 10, 1), Pitch(.d, 5))
        log.end(new, at: at(1, 10, 2), durationMs: 2000, score: 1, attempts: 1)
        let duet = log.round(at: at(0, 10), piece: piece("Duet", path: "/duet.musicxml", staves: 2))
        log.answer(duet, at: at(0, 10, 1), Pitch(.e, 5))
        log.end(duet, at: at(0, 10, 2), durationMs: 2000, score: 1, attempts: 1)
        try TestJournal(folder: journalFolder).write(log.events)
        try writeLog(log.events)
        let contents = JournalReader(folder: journalFolder).read()
        #expect(contents.runs.count == 3)

        let openings = LoggedPieceOpenings.read(in: usageFolder)
        #expect(openings.map(\.event) == [.pieceOpened(opened), .pieceOpened(grand)])
        let withLog = report(contents, pieceOpenings: openings)
        #expect(withLog.recentRounds.map(\.description) == ["Duet · Right hand", "Clarinet Tune", "Clarinet Tune"])
        // Without the log, the old run can't tell, so it names its hand.
        #expect(report(contents).recentRounds.map(\.description) == ["Duet · Right hand", "Clarinet Tune",
                                                                     "Clarinet Tune · Right hand"])
        // An opening counts from its time on: one after the round says nothing about it.
        #expect(report(contents, pieceOpenings: [openings[1]]).recentRounds.last?.description == "Clarinet Tune · Right hand")
        // And the log's other events count for nothing.
        #expect(report(contents, pieceOpenings: log.events) == withLog)
    }

    // MARK: - Pieces

    @Test func aPieceIsOneWhateverMacOrPathItWasPractisedFrom() throws {
        let minuet = String(repeating: "0a", count: 32)
        let entry = UUID(), otherMac = UUID()
        var log = Log()
        // Before the library: known by the path it was first opened from.
        let beforeLibrary = log.round(at: at(3, 9), piece: piece("Minuet", path: "/Users/a/Minuet.musicxml"))
        log.answer(beforeLibrary, at: at(3, 9, 1), Pitch(.d, 5), bar: 1)
        log.end(beforeLibrary, at: at(3, 9, 2), durationMs: 60_000, score: 1, attempts: 1)
        // In the library, before the journal: by its entry.
        let inLibrary = log.round(at: at(2, 9), piece: piece("Minuet", path: "/Users/a/Old/Minuet.musicxml", libraryID: entry))
        log.answer(inLibrary, at: at(2, 9, 1), Pitch(.g, 4), correct: false, bar: 2)
        log.end(inLibrary, at: at(2, 9, 2), durationMs: 60_000, score: 0, attempts: 1)
        // Since the journal, on this Mac and on another, from another path.
        let here = log.round(at: at(1, 9), piece: piece("Minuet", path: "/Users/a/Minuet.musicxml", libraryID: entry,
                                                        id: minuet, staves: 2))
        log.answer(here, at: at(1, 9, 1), Pitch(.a, 4), bar: 2)
        log.end(here, at: at(1, 9, 2), durationMs: 60_000, score: 1, attempts: 1)
        let there = log.round(at: at(0, 9), piece: piece("Minuet in G", path: "/Users/b/Music/Minuet.musicxml",
                                                         libraryID: otherMac, id: minuet.uppercased(), staves: 2))
        log.answer(there, at: at(0, 9, 1), Pitch(.b, 4), bar: 3)
        log.end(there, at: at(0, 9, 2), durationMs: 60_000, score: 1, attempts: 1)
        // A piece the journal doesn't know.
        let gavotte = log.round(at: at(0, 8), piece: piece("Gavotte", path: "/gavotte.musicxml"))
        log.answer(gavotte, at: at(0, 8, 1), Pitch(.c, 5), bar: 1)
        log.end(gavotte, at: at(0, 8, 2), durationMs: 30_000, score: 1, attempts: 1)
        // Brought into the journal from the library afterwards.
        log.add(.pieceAdded(PieceAdded(piece: minuet, title: "Minuet", fileName: "Minuet.musicxml", libraryID: entry,
                                       originalPath: "/Users/a/Minuet.musicxml")), at: at(0, 12))
        try TestJournal(folder: journalFolder).write(log.events)

        let pieces = report(JournalReader(folder: journalFolder).read()).pieces
        #expect(pieces == [
            PieceProgressSummary(title: "Minuet in G", path: "/Users/b/Music/Minuet.musicxml", lastPractised: at(0, 9, 1),
                                 rounds: 4, answers: 4, correct: 3, measureCount: 32,
                                 bars: [BarProgress(bar: 1, attempts: 1, correct: 1), BarProgress(bar: 2, attempts: 2, correct: 1),
                                        BarProgress(bar: 3, attempts: 1, correct: 1)],
                                 pieceID: minuet),
            PieceProgressSummary(title: "Gavotte", path: "/gavotte.musicxml", lastPractised: at(0, 8, 1), rounds: 1,
                                 answers: 1, correct: 1, measureCount: 32, bars: [BarProgress(bar: 1, attempts: 1, correct: 1)]),
        ])
        #expect(pieces.map(\.id) == [minuet, "/gavotte.musicxml"])

        // The usage log has no `pieceAdded`: its old rounds go by path, its new ones by id.
        let fromLog = ProgressAnalyzer.report(from: log.events, filter: ProgressFilter(range: .week), now: now, calendar: calendar)
        #expect(fromLog.pieces.map(\.id) == [minuet, "/gavotte.musicxml", "/Users/a/Old/Minuet.musicxml",
                                             "/Users/a/Minuet.musicxml"])
    }

    // MARK: - Opening balances

    @Test func eachDevicesOpeningBalanceAddsUp() throws {
        let first = StatsSnapshot(reason: "beforeUsageLog", noteStats: [
            "treble.F5": NoteStat(attempts: 10, correct: 7), "bass.G2": NoteStat(attempts: 6, correct: 6),
        ], bestScores: ["treble.staff": 12])
        let second = StatsSnapshot(reason: "beforeUsageLog", noteStats: [
            "treble.F5": NoteStat(attempts: 5, correct: 5), "treble.E4": NoteStat(attempts: 3, correct: 1),
        ], bestScores: ["treble.staff": 20])
        var log = Log()
        log.add(.statsSnapshot(first), at: at(30, 9))
        log.add(.statsSnapshot(second), at: at(20, 9))
        let round = log.round(at: at(0, 10))
        log.answer(round, at: at(0, 10, 1), Pitch(.f, 5), ms: 1000)
        log.end(round, at: at(0, 10, 2), durationMs: 2000, score: 1, attempts: 1)
        try TestJournal(folder: journalFolder).write(log.events)
        let contents = JournalReader(folder: journalFolder).read()
        #expect(contents.snapshots.count == 2)

        let allTime = report(contents, ProgressFilter(range: .all))
        #expect(allTime.answersBeforeTracking == 24)
        #expect(allTime.positions == [
            PositionProgress(clef: .treble, position: 0, natural: Pitch(.e, 4), attempts: 3, correct: 1, medianResponseMs: nil,
                             attemptsBeforeTracking: 3),
            PositionProgress(clef: .treble, position: 8, natural: Pitch(.f, 5), attempts: 16, correct: 13, medianResponseMs: 1000,
                             attemptsBeforeTracking: 15, recentMedianResponseMs: 1000, recentRightAnswers: 1),
            PositionProgress(clef: .bass, position: 0, natural: Pitch(.g, 2), attempts: 6, correct: 6, medianResponseMs: nil,
                             attemptsBeforeTracking: 6),
        ])
        // The same from the log, and only in all time.
        let fromLog = ProgressAnalyzer.report(from: log.events, filter: ProgressFilter(range: .all), now: now, calendar: calendar)
        #expect(fromLog == allTime)
        #expect(report(contents, ProgressFilter(range: .quarter)).answersBeforeTracking == 0)
    }

    // MARK: - This Mac's log

    @Test func onlyTheLogsPieceOpeningsAreReadAndThenKept() throws {
        let session = UUID()
        let opened = { (path: String) in
            UsageEvent.pieceOpened(PieceOpened(path: path, title: "Tune", via: .menu,
                                               parts: [PartInfo(name: "Piano", notes: 1, measures: 1, staves: 2, skipped: 0)]))
        }
        let later = LoggedEvent(opened("/later.musicxml"), session: session, sequence: 3, time: at(0, 9))
        // A title that mentions the type doesn't make its line one, nor does a line cut off.
        let mention = LoggedEvent(.uiAction(UIAction(name: "openPiece", detail: #""type":"pieceOpened""#)), session: session,
                                  sequence: 4, time: at(0, 9, 1))
        var day = try [LoggedEvent(.appLaunched(JournalFixture.launch), session: session, sequence: 0, time: at(0, 8)), later,
                       mention].reduce(into: Data()) { $0 += try $1.encodedLine() }
        day += Data(#"{"schema":1,"type":"pieceOpened","id":"#.utf8) + Data([0x0A])
        try FileManager.default.createDirectory(at: usageFolder, withIntermediateDirectories: true)
        try day.write(to: usageFolder.appendingPathComponent("usage-2026-10-30.jsonl"))
        // Out of order in another day's file: the clock went back.
        let earlier = LoggedEvent(opened("/earlier.musicxml"), session: session, sequence: 1, time: at(1, 9))
        try writeLog([earlier], name: "usage-2026-10-31.jsonl")
        try "not a log".write(to: usageFolder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let openings = LoggedPieceOpenings(log: usageFolder)
        #expect(openings.events == [earlier, later])
        try writeLog([LoggedEvent(opened("/newest.musicxml"), session: session, sequence: 5, time: at(0, 10))],
                     name: "usage-2026-11-01.jsonl")
        // Read once, then kept.
        #expect(openings.events == [earlier, later])
        #expect(LoggedPieceOpenings.read(in: usageFolder).count == 3)
        #expect(LoggedPieceOpenings.read(in: temporary.url.appendingPathComponent("Nowhere")).isEmpty)
    }
}

// MARK: - The store

@MainActor
@Suite final class ProgressStoreJournalTests {
    private let temporary = UsageTestFolder()
    private var journalFolder: URL { temporary.url.appendingPathComponent("Journal", isDirectory: true) }
    private var usageFolder: URL { temporary.url.appendingPathComponent("Usage", isDirectory: true) }

    private func waitUntilLoaded(_ store: ProgressStore) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !(store.hasLoaded && !store.isLoading), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.hasLoaded && !store.isLoading)
    }

    /// A round answered `answers` times, an hour or so ago.
    private func round(answers: Int, minutesAgo: Double) -> [LoggedEvent] {
        var log = Log()
        let start = Date(timeIntervalSinceNow: -minutesAgo * 60)
        let round = log.round(at: start)
        for index in 0..<answers { log.answer(round, at: start.addingTimeInterval(Double(index + 1)), Pitch(.g, 4)) }
        log.end(round, at: start.addingTimeInterval(30), durationMs: 30_000, score: answers, attempts: answers)
        return log.events
    }

    @Test func itReadsTheJournalAndOnlyItsNewFilesOnReload() async throws {
        try TestJournal(folder: journalFolder).write(round(answers: 3, minutesAgo: 90))
        let store = ProgressStore(reader: JournalReader(folder: journalFolder), defaults: InMemoryDefaults(),
                                  log: UsageLog(folder: usageFolder))
        store.filter = ProgressFilter(range: .all)
        store.reload()
        try await waitUntilLoaded(store)
        #expect(store.report.totals.answers == 3 && store.report.totals.rounds == 1)
        let expected = ProgressAnalyzer.report(from: JournalReader(folder: journalFolder).read(), filter: store.filter,
                                               now: store.report.generatedAt)
        #expect(store.report == expected)

        try TestJournal(folder: journalFolder).write(round(answers: 2, minutesAgo: 30))
        store.reload()
        try await waitUntilLoaded(store)
        #expect(store.report.totals.answers == 5 && store.report.totals.rounds == 2)
    }

    @Test func withoutAJournalItsReportsAreEmpty() async throws {
        let store = ProgressStore(reader: nil, defaults: InMemoryDefaults(), log: UsageLog(folder: usageFolder))
        store.reload()
        try await waitUntilLoaded(store)
        #expect(store.report.isEmpty && store.report.filter == store.filter)
    }
}
