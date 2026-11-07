import Foundation
import Testing
@testable import Clefwise

/// A usage log written by hand, in one session: rounds, and answers with their questions. The
/// journal's dashboard tests write its rounds into journals too.
struct Log {
    private(set) var events: [LoggedEvent] = []
    private let session = UUID()

    mutating func add(_ event: UsageEvent, at time: Date) {
        events.append(LoggedEvent(event, session: session, sequence: events.count, time: time))
    }

    /// A round on the default settings as changed by `change`.
    @discardableResult
    mutating func round(at time: Date, keyFifths: Int = 0, piece: PieceContext? = nil,
                        _ change: (inout Game.Settings) -> Void = { _ in }) -> UUID {
        var settings = Game.Settings()
        change(&settings)
        let id = UUID()
        add(.roundStarted(RoundStarted(round: id, via: .button, settings: JSONValue(encoding: settings),
                                       keyFifths: keyFifths, piece: piece)), at: time)
        return id
    }

    /// A question on `written` shown `ms` before `time` (unless `logQuestion` is false, as when the
    /// log lost it), and its answer at `time`.
    mutating func answer(_ round: UUID, at time: Date, _ written: Pitch, clef: Clef = .treble, correct: Bool = true,
                         ms: Int = 1000, octaveShift: Int = 0, input: String = "buttons", naming: String = "letters",
                         bar: Int? = nil, logQuestion: Bool = true) {
        let question = UUID()
        if logQuestion {
            let played = Pitch(written.letter, written.octave + octaveShift, written.accidental)
            add(.questionShown(QuestionShown(
                round: round, question: question, index: 0, clef: clef.rawValue, pitch: LoggedPitch(played),
                written: LoggedPitch(written), position: clef.position(of: written), keyFifths: 0, printedAccidental: nil,
                octaveShift: octaveShift, pieceNote: bar.map { PieceNoteRef(measure: $0, staff: 1, onset: 0, chord: 0) },
                pickChance: nil, naming: naming, input: input, hintsVisible: false, keyNamesVisible: false)),
                at: time.addingTimeInterval(-Double(ms) / 1000))
        }
        add(.answerGiven(AnswerGiven(round: round, question: question, responseMs: ms, source: .click,
                                     letter: written.letter.name, accidental: 0, name: written.letter.name, pitch: nil,
                                     correct: correct, wrongOctave: nil, keystrokes: [], scoreAfter: 0, streakAfter: 0)),
            at: time)
    }

    mutating func end(_ round: UUID, at time: Date, durationMs: Int, score: Int, attempts: Int,
                      reason: RoundEndReason = .stopped) {
        add(.roundEnded(RoundEnded(round: round, reason: reason, durationMs: durationMs, score: score, attempts: attempts,
                                   bestStreak: 0, averageResponseMs: nil, bestScore: nil, isNewBest: false,
                                   notesToReview: [])), at: time)
    }
}

@Suite struct ProgressAnalyzerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()
    /// Friday 30 October 2026, 16:00 in Stockholm. The week back to Saturday the 24th takes in
    /// the end of summer time on Sunday the 25th, a 25-hour day.
    private let now = usageTestTime("2026-10-30T15:00:00.000Z")

    /// `daysAgo` local days before today, at a Stockholm wall-clock time.
    private func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
    }

    private func report(_ log: Log, _ range: ProgressFilter.Range = .week,
                        clef: ProgressFilter.ClefFilter = .all) -> ProgressReport {
        ProgressAnalyzer.report(from: log.events, filter: ProgressFilter(range: range, clef: clef), now: now, calendar: calendar)
    }

    /// Current and longest.
    private func streaks(_ report: ProgressReport) -> [Int] { [report.currentStreakDays, report.longestStreakDays] }

    private func piece(_ title: String, path: String, hand: String = "right", measures: Int = 32) -> PieceContext {
        PieceContext(title: title, path: path, part: "Piano", partIndex: 0, hand: hand, order: "inOrder", startBar: 1,
                     oneNotePerChord: false, noteCount: 20, measureCount: measures)
    }

    // MARK: - Window, totals, days

    @Test func emptyLogGivesEmptyDays() {
        let week = report(Log())
        #expect(week.isEmpty)
        #expect(week.days.count == 7)
        #expect(week.days.allSatisfy { $0.answers == 0 && $0.practiceSeconds == 0 && $0.medianResponseMs == nil })
        #expect(week.totals == ProgressTotals())
        #expect(week.previousTotals == ProgressTotals())
        #expect(streaks(week) == [0, 0])
        #expect(week.positions.isEmpty && week.pitches.isEmpty && week.pieces.isEmpty && week.recentRounds.isEmpty)
        let allTime = report(Log(), .all)
        #expect(allTime.days.isEmpty)
        #expect(allTime.periodStart == nil && allTime.previousTotals == nil)
    }

    /// Rounds A–G around the week from Saturday 24 October: G is after `now`, D runs over midnight
    /// into the window, C is before the previous week.
    private func windowLog() -> (log: Log, e: UUID, f: UUID) {
        var log = Log()
        let c = log.round(at: at(14, 23, 30))
        log.answer(c, at: at(14, 23, 31), Pitch(.c, 5), ms: 700)
        log.end(c, at: at(14, 23, 32), durationMs: 60_000, score: 1, attempts: 1)
        let b = log.round(at: at(13, 9))
        log.answer(b, at: at(13, 9, 1), Pitch(.d, 5), ms: 2000)
        log.end(b, at: at(13, 9, 2), durationMs: 60_000, score: 1, attempts: 1)
        let a = log.round(at: at(10, 18))
        log.answer(a, at: at(10, 18, 1), Pitch(.e, 5), ms: 1200)
        log.answer(a, at: at(10, 18, 2), Pitch(.f, 5), correct: false, ms: 800)
        log.answer(a, at: at(10, 18, 3), Pitch(.g, 5), ms: 1400)
        log.end(a, at: at(10, 18, 5), durationMs: 300_000, score: 2, attempts: 3)
        let d = log.round(at: at(7, 23, 50))
        log.answer(d, at: at(7, 23, 59, 59), Pitch(.a, 4), ms: 900)
        log.answer(d, at: at(6, 0), Pitch(.b, 4), ms: 1100) // exactly at the window's start
        log.end(d, at: at(6, 0, 10), durationMs: 1_200_000, score: 2, attempts: 2)
        let e = log.round(at: at(6, 9))
        log.answer(e, at: at(6, 9, 1), Pitch(.c, 5), ms: 600)
        log.end(e, at: at(6, 9, 2), durationMs: 90_000, score: 1, attempts: 1)
        let f = log.round(at: at(0, 15, 50)) // still going at `now`
        log.answer(f, at: at(0, 15, 51), Pitch(.d, 5), ms: 1000)
        log.answer(f, at: at(0, 15, 52), Pitch(.e, 5), correct: false, ms: 500)
        log.answer(f, at: now, Pitch(.f, 5), ms: 3000)
        let g = log.round(at: at(0, 16, 30))
        log.answer(g, at: at(0, 16, 31), Pitch(.g, 5), ms: 800)
        log.end(g, at: at(0, 16, 32), durationMs: 120_000, score: 1, attempts: 1)
        return (log, e, f)
    }

    @Test func weekCountsFromItsFirstDayThroughNow() {
        let (log, e, f) = windowLog()
        let week = report(log)
        #expect(week.generatedAt == now)
        #expect(week.filter == ProgressFilter(range: .week, clef: .all))
        #expect(week.periodStart == usageTestTime("2026-10-23T22:00:00.000Z"))
        #expect(week.totals == ProgressTotals(answers: 5, correct: 4, rounds: 2, practiceSeconds: 690, daysPractised: 2,
                                              medianResponseMs: 1050))
        #expect(week.previousTotals == ProgressTotals(answers: 5, correct: 4, rounds: 3, practiceSeconds: 1560,
                                                      daysPractised: 3, medianResponseMs: 1300))
        #expect(week.days.map(\.day) == (0..<7).reversed().map { at($0, 0) })
        #expect(week.days.first == DayProgress(day: at(6, 0), answers: 2, correct: 2, practiceSeconds: 90, medianResponseMs: 850,
                                               lowerQuartileMs: 725, upperQuartileMs: 975))
        #expect(week.days.last == DayProgress(day: at(0, 0), answers: 3, correct: 2, practiceSeconds: 600, medianResponseMs: 2000,
                                              lowerQuartileMs: 1500, upperQuartileMs: 2500))
        #expect(week.days.dropFirst().dropLast().allSatisfy { $0.answers == 0 && $0.practiceSeconds == 0 && $0.medianResponseMs == nil })
        #expect(week.recentRounds == [
            RecentRound(id: f, started: at(0, 15, 50), durationMs: 600_000, mode: "sprint", input: "buttons", naming: "letters",
                        description: "Treble · On the staff · C major", score: 2, attempts: 3, endReason: nil),
            RecentRound(id: e, started: at(6, 9), durationMs: 90_000, mode: "sprint", input: "buttons", naming: "letters",
                        description: "Treble · On the staff · C major", score: 1, attempts: 1, endReason: .stopped),
        ])
        #expect(streaks(week) == [1, 2])
        #expect(week.unreadableLines == 0)
        #expect(ProgressAnalyzer.report(from: log.events, filter: ProgressFilter(range: .week), unreadableLines: 3,
                                        now: now, calendar: calendar).unreadableLines == 3)
    }

    @Test func allTimeTakesEverythingFromTheFirstDay() {
        let allTime = report(windowLog().log, .all)
        #expect(allTime.periodStart == nil && allTime.previousTotals == nil)
        #expect(allTime.totals == ProgressTotals(answers: 12, correct: 10, rounds: 7, practiceSeconds: 2430, daysPractised: 6,
                                                 medianResponseMs: 1050))
        #expect(allTime.days.count == 15)
        #expect(allTime.days.first?.day == at(14, 0) && allTime.days.last?.day == at(0, 0))
        #expect(allTime.days.map(\.answers).reduce(0, +) == 12)
        #expect(allTime.recentRounds.count == 7)
    }

    @Test func longerWindowsStartOnLocalMidnight() {
        let month = report(windowLog().log, .month), quarter = report(windowLog().log, .quarter)
        #expect(month.periodStart == usageTestTime("2026-09-30T22:00:00.000Z"))
        #expect(month.days.count == 30)
        #expect(month.totals.answers == 11 && month.previousTotals == ProgressTotals())
        #expect(quarter.periodStart == usageTestTime("2026-08-01T22:00:00.000Z"))
        #expect(quarter.days.count == 90)
    }

    @Test func daysFollowLocalTimeAcrossTheEndOfSummerTime() {
        var log = Log()
        let saturday = log.round(at: at(6, 12))
        log.answer(saturday, at: at(6, 12, 1), Pitch(.g, 4), ms: 1500)
        log.end(saturday, at: at(6, 12, 2), durationMs: 60_000, score: 1, attempts: 1)
        let late = log.round(at: at(5, 23, 59)) // Sunday the 25th, the 25-hour day
        log.answer(late, at: at(5, 23, 59, 30), Pitch(.e, 4), ms: 1000)
        log.answer(late, at: at(4, 0, 0, 30), Pitch(.f, 4), ms: 2000)
        log.end(late, at: at(4, 0, 1), durationMs: 120_000, score: 2, attempts: 2)
        let week = report(log)
        #expect(week.days.map(\.day) == ["2026-10-23T22:00:00.000Z", "2026-10-24T22:00:00.000Z", "2026-10-25T23:00:00.000Z",
                                         "2026-10-26T23:00:00.000Z", "2026-10-27T23:00:00.000Z", "2026-10-28T23:00:00.000Z",
                                         "2026-10-29T23:00:00.000Z"].map(usageTestTime))
        #expect(week.days[1] == DayProgress(day: at(5, 0), answers: 1, correct: 1, practiceSeconds: 120, medianResponseMs: 1000,
                                            lowerQuartileMs: 1000, upperQuartileMs: 1000))
        #expect(week.days[2] == DayProgress(day: at(4, 0), answers: 1, correct: 1, practiceSeconds: 0, medianResponseMs: 2000,
                                            lowerQuartileMs: 2000, upperQuartileMs: 2000))
        #expect(week.days[0].answers == 1)
        // Saturday, Sunday and Monday in a row, the 25-hour Sunday included.
        #expect(week.longestStreakDays == 3 && week.currentStreakDays == 0)
    }

    // MARK: - Clef filter

    @Test func clefFilterPicksAnswersAndTheRoundsWithThem() {
        var log = Log()
        let treble = log.round(at: at(1, 18))
        log.answer(treble, at: at(1, 18, 1), Pitch(.e, 4), ms: 1000)
        log.answer(treble, at: at(1, 18, 2), Pitch(.f, 4), correct: false, ms: 1500)
        log.end(treble, at: at(1, 18, 3), durationMs: 60_000, score: 1, attempts: 2)
        let bass = log.round(at: at(1, 19)) { $0.clefChoice = .bass }
        log.answer(bass, at: at(1, 19, 1), Pitch(.g, 2), clef: .bass, ms: 2000)
        log.end(bass, at: at(1, 19, 2), durationMs: 30_000, score: 1, attempts: 1)
        let both = log.round(at: at(0, 10)) { $0.clefChoice = .both }
        log.answer(both, at: at(0, 10, 1), Pitch(.g, 4), ms: 700)
        log.answer(both, at: at(0, 10, 2), Pitch(.a, 2), clef: .bass, correct: false, ms: 900)
        log.answer(both, at: at(0, 10, 3), Pitch(.b, 2), clef: .bass, ms: 1300)
        log.end(both, at: at(0, 10, 4), durationMs: 45_000, score: 2, attempts: 3)
        let empty = log.round(at: at(0, 11))
        log.end(empty, at: at(0, 11, 1), durationMs: 5000, score: 0, attempts: 0)

        let all = report(log), trebleOnly = report(log, clef: .treble), bassOnly = report(log, clef: .bass)
        #expect(all.totals == ProgressTotals(answers: 6, correct: 4, rounds: 4, practiceSeconds: 140, daysPractised: 2,
                                             medianResponseMs: 1150))
        #expect(trebleOnly.totals == ProgressTotals(answers: 3, correct: 2, rounds: 2, practiceSeconds: 105, daysPractised: 2,
                                                    medianResponseMs: 850))
        #expect(bassOnly.totals == ProgressTotals(answers: 3, correct: 2, rounds: 2, practiceSeconds: 75, daysPractised: 2,
                                                  medianResponseMs: 1650))
        #expect(all.recentRounds.map(\.id) == [empty, both, bass, treble])
        #expect(trebleOnly.recentRounds.map(\.id) == [both, treble])
        #expect(bassOnly.recentRounds.map(\.id) == [both, bass])
        // A round's score is the whole round's.
        #expect(trebleOnly.recentRounds.first.map { [$0.score, $0.attempts] } == [2, 3])
        #expect(trebleOnly.days.suffix(2).map(\.practiceSeconds) == [60, 45])
        #expect(Set(trebleOnly.positions.map(\.clef)) == [.treble] && Set(bassOnly.pitches.map(\.clef)) == [.bass])
        #expect(trebleOnly.byInput == [BreakdownRow(key: "buttons", answers: 3, correct: 2, medianResponseMs: 850)])
    }

    // MARK: - Streaks and medians

    @Test func streaksCountYesterdayAndIgnoreTheFilter() {
        var log = Log()
        // Days 10, 8–5 and 3–1 ago, nothing today; bass on some, and most before the week.
        for daysAgo in [10, 8, 7, 6, 5, 3, 2, 1] {
            let round = log.round(at: at(daysAgo, 18))
            log.answer(round, at: at(daysAgo, 18, 1), Pitch(.c, 3), clef: daysAgo.isMultiple(of: 2) ? .bass : .treble)
        }
        let week = report(log, clef: .treble)
        #expect(streaks(week) == [3, 4])

        let today = log.round(at: at(0, 9))
        log.answer(today, at: at(0, 9, 1), Pitch(.c, 3), clef: .bass)
        #expect(streaks(report(log, clef: .treble)) == [4, 4])

        var lapsed = Log()
        for daysAgo in [4, 3, 2] {
            let round = lapsed.round(at: at(daysAgo, 18))
            lapsed.answer(round, at: at(daysAgo, 18, 1), Pitch(.c, 5))
        }
        #expect(streaks(report(lapsed)) == [0, 3])
    }

    @Test func mediansAreOfCorrectAnswersOnly() {
        var log = Log()
        let round = log.round(at: at(0, 9))
        for (ms, correct) in [(3000, true), (100, false), (1000, true), (9000, false), (2000, true)] {
            log.answer(round, at: at(0, 9, 1), Pitch(.c, 5), correct: correct, ms: ms)
        }
        let week = report(log)
        #expect(week.totals.medianResponseMs == 2000)
        #expect(week.days.last?.medianResponseMs == 2000)
        #expect(week.positions.map(\.medianResponseMs) == [2000])
        #expect(ProgressAnalyzer.median([]) == nil && ProgressAnalyzer.median([5, 1]) == 3 && ProgressAnalyzer.median([4, 1]) == 3)
    }

    // MARK: - Notes

    @Test func positionsShareSharpsWhilePitchesKeepThemApart() {
        var log = Log()
        let round = log.round(at: at(0, 9)) { $0.clefChoice = .both }
        log.answer(round, at: at(0, 9, 1), Pitch(.f, 5), ms: 1000)
        log.answer(round, at: at(0, 9, 2), Pitch(.f, 5, .sharp), ms: 2000)
        log.answer(round, at: at(0, 9, 3), Pitch(.f, 5, .sharp), correct: false, ms: 500)
        log.answer(round, at: at(0, 9, 4), Pitch(.f, 5), ms: 3000)
        log.answer(round, at: at(0, 9, 5), Pitch(.g, 5), ms: 1500, octaveShift: 1) // sounds G6, written G5
        log.answer(round, at: at(0, 9, 6), Pitch(.b, 4, .flat), ms: 1200)
        log.answer(round, at: at(0, 9, 7), Pitch(.e, 4), ms: 900)
        log.answer(round, at: at(0, 9, 8), Pitch(.g, 2), clef: .bass, correct: false, ms: 800)
        let week = report(log)
        #expect(week.positions == [
            PositionProgress(clef: .treble, position: 0, natural: Pitch(.e, 4), attempts: 1, correct: 1, medianResponseMs: 900,
                             attemptsBeforeTracking: 0, recentMedianResponseMs: 900, recentRightAnswers: 1),
            PositionProgress(clef: .treble, position: 4, natural: Pitch(.b, 4), attempts: 1, correct: 1, medianResponseMs: 1200,
                             attemptsBeforeTracking: 0, recentMedianResponseMs: 1200, recentRightAnswers: 1),
            PositionProgress(clef: .treble, position: 8, natural: Pitch(.f, 5), attempts: 4, correct: 3, medianResponseMs: 2000,
                             attemptsBeforeTracking: 0, recentMedianResponseMs: 2000, recentRightAnswers: 3),
            PositionProgress(clef: .treble, position: 9, natural: Pitch(.g, 5), attempts: 1, correct: 1, medianResponseMs: 1500,
                             attemptsBeforeTracking: 0, recentMedianResponseMs: 1500, recentRightAnswers: 1),
            PositionProgress(clef: .bass, position: 0, natural: Pitch(.g, 2), attempts: 1, correct: 0, medianResponseMs: nil,
                             attemptsBeforeTracking: 0),
        ])
        #expect(week.pitches == [
            PitchProgress(clef: .treble, pitch: Pitch(.e, 4), attempts: 1, correct: 1, medianResponseMs: 900),
            PitchProgress(clef: .treble, pitch: Pitch(.b, 4, .flat), attempts: 1, correct: 1, medianResponseMs: 1200),
            PitchProgress(clef: .treble, pitch: Pitch(.f, 5), attempts: 2, correct: 2, medianResponseMs: 2000),
            PitchProgress(clef: .treble, pitch: Pitch(.f, 5, .sharp), attempts: 2, correct: 1, medianResponseMs: 2000),
            PitchProgress(clef: .treble, pitch: Pitch(.g, 5), attempts: 1, correct: 1, medianResponseMs: 1500),
            PitchProgress(clef: .bass, pitch: Pitch(.g, 2), attempts: 1, correct: 0, medianResponseMs: nil),
        ])
    }

    @Test func snapshotCountsInAllTimeOnly() {
        var log = Log()
        log.add(.statsSnapshot(StatsSnapshot(reason: "beforeUsageLog", noteStats: [
            "treble.F5": NoteStat(attempts: 10, correct: 7), "treble.F♯5": NoteStat(attempts: 4, correct: 1),
            "bass.G2": NoteStat(attempts: 6, correct: 6), "treble.E4": NoteStat(),
            "treble.H9": NoteStat(attempts: 5, correct: 5), "alto.C4": NoteStat(attempts: 3, correct: 3),
            "treble.C": NoteStat(attempts: 2, correct: 2), "trebleF5": NoteStat(attempts: 1, correct: 1),
        ], bestScores: [:])), at: at(20, 9))
        let round = log.round(at: at(0, 10))
        log.answer(round, at: at(0, 10, 1), Pitch(.f, 5), ms: 1000)

        let month = report(log, .month)
        #expect(month.answersBeforeTracking == 0)
        #expect(month.positions == [PositionProgress(clef: .treble, position: 8, natural: Pitch(.f, 5), attempts: 1, correct: 1,
                                                     medianResponseMs: 1000, attemptsBeforeTracking: 0,
                                                     recentMedianResponseMs: 1000, recentRightAnswers: 1)])
        let allTime = report(log, .all)
        #expect(allTime.answersBeforeTracking == 20)
        #expect(allTime.totals.answers == 1)
        #expect(allTime.positions == [
            PositionProgress(clef: .treble, position: 8, natural: Pitch(.f, 5), attempts: 15, correct: 9, medianResponseMs: 1000,
                             attemptsBeforeTracking: 14, recentMedianResponseMs: 1000, recentRightAnswers: 1),
            PositionProgress(clef: .bass, position: 0, natural: Pitch(.g, 2), attempts: 6, correct: 6, medianResponseMs: nil,
                             attemptsBeforeTracking: 6),
        ])
        #expect(allTime.pitches == [
            PitchProgress(clef: .treble, pitch: Pitch(.f, 5), attempts: 11, correct: 8, medianResponseMs: 1000),
            PitchProgress(clef: .treble, pitch: Pitch(.f, 5, .sharp), attempts: 4, correct: 1, medianResponseMs: nil),
            PitchProgress(clef: .bass, pitch: Pitch(.g, 2), attempts: 6, correct: 6, medianResponseMs: nil),
        ])
        let bass = report(log, .all, clef: .bass)
        #expect(bass.answersBeforeTracking == 6 && bass.totals.answers == 0 && !bass.isEmpty)
        #expect(bass.positions.map(\.attemptsBeforeTracking) == [6])

        #expect(ProgressAnalyzer.parseStatKey("bass.B♭-1").map { [$0.clef.rawValue, $0.pitch.name] } == ["bass", "B♭-1"])
        #expect(ProgressAnalyzer.parseStatKey("treble.F♯") == nil && ProgressAnalyzer.parseStatKey("treble.F#5") == nil)
    }

    // MARK: - Breakdowns, pieces, rounds

    @Test func breakdownsGoByInputAndNaming() {
        var log = Log()
        let round = log.round(at: at(0, 9))
        let answers: [(String, String, Int, Bool)] = [
            ("buttons", "letters", 1000, true), ("buttons", "letters", 1200, true), ("buttons", "letters", 300, false),
            ("piano", "solfege", 2000, true), ("keyboard", "letters", 1500, true), ("keyboard", "letters", 700, false),
            ("keyboard", "sargam", 2500, true),
        ]
        for (input, naming, ms, correct) in answers {
            log.answer(round, at: at(0, 9, 1), Pitch(.c, 5), correct: correct, ms: ms, input: input, naming: naming)
        }
        let week = report(log)
        #expect(week.byInput == [BreakdownRow(key: "buttons", answers: 3, correct: 2, medianResponseMs: 1100),
                                 BreakdownRow(key: "keyboard", answers: 3, correct: 2, medianResponseMs: 2000),
                                 BreakdownRow(key: "piano", answers: 1, correct: 1, medianResponseMs: 2000)])
        #expect(week.byNaming == [BreakdownRow(key: "letters", answers: 5, correct: 3, medianResponseMs: 1200),
                                  BreakdownRow(key: "sargam", answers: 1, correct: 1, medianResponseMs: 2500),
                                  BreakdownRow(key: "solfege", answers: 1, correct: 1, medianResponseMs: 2000)])
    }

    @Test func piecesGoByPathWithTheirBars() {
        var log = Log()
        let old = log.round(at: at(10, 18), piece: piece("Old Tune", path: "/old.musicxml"))
        log.answer(old, at: at(10, 18, 1), Pitch(.c, 5), bar: 1)
        let first = log.round(at: at(2, 18), piece: piece("Minuet", path: "/minuet.musicxml"))
        log.answer(first, at: at(2, 18, 1), Pitch(.d, 5), bar: 1)
        log.answer(first, at: at(2, 18, 2), Pitch(.d, 5), correct: false, bar: 1)
        log.answer(first, at: at(2, 18, 3), Pitch(.b, 4), bar: 3)
        log.end(first, at: at(2, 18, 4), durationMs: 240_000, score: 2, attempts: 3)
        // The file was edited since: the latest round has the title and bars.
        let second = log.round(at: at(1, 18), piece: piece("Minuet in G", path: "/minuet.musicxml", measures: 34))
        log.answer(second, at: at(1, 18, 1), Pitch(.g, 4), bar: 2)
        log.end(second, at: at(1, 18, 2), durationMs: 60_000, score: 1, attempts: 1, reason: .pieceComplete)
        let random = log.round(at: at(1, 19))
        log.answer(random, at: at(1, 19, 1), Pitch(.g, 4))
        let gavotte = log.round(at: at(0, 9), piece: piece("Gavotte", path: "/gavotte.musicxml", measures: 20))
        log.end(gavotte, at: at(0, 9, 1), durationMs: 20_000, score: 0, attempts: 0, reason: .abandoned)

        let week = report(log)
        #expect(week.pieces == [
            PieceProgressSummary(title: "Gavotte", path: "/gavotte.musicxml", lastPractised: at(0, 9), rounds: 1, answers: 0,
                                 correct: 0, measureCount: 20, bars: []),
            PieceProgressSummary(title: "Minuet in G", path: "/minuet.musicxml", lastPractised: at(1, 18, 1), rounds: 2,
                                 answers: 4, correct: 3, measureCount: 34,
                                 bars: [BarProgress(bar: 1, attempts: 2, correct: 1), BarProgress(bar: 2, attempts: 1, correct: 1),
                                        BarProgress(bar: 3, attempts: 1, correct: 1)]),
        ])
        // Neither has a bass answer.
        #expect(report(log, clef: .bass).pieces.isEmpty)
        #expect(report(log, .all).pieces.map(\.title) == ["Gavotte", "Minuet in G", "Old Tune"])
    }

    @Test func recentRoundsDescribeWhatWasPractised() {
        var log = Log()
        let gMajor = log.round(at: at(3, 10), keyFifths: 1) { $0.key = .fixed(KeySignature(fifths: 1)) }
        log.end(gMajor, at: at(3, 10, 1), durationMs: 60_000, score: 20, attempts: 22, reason: .timeUp)
        let random = log.round(at: at(3, 11), keyFifths: -3) {
            $0.clefChoice = .bass
            $0.range = .oneLedgerLine
            $0.key = .random
            $0.mode = .practice
            $0.answerInput = .piano
            $0.naming = .solfege
        }
        log.end(random, at: at(3, 11, 2), durationMs: 120_000, score: 8, attempts: 10)
        let crashed = log.round(at: at(2, 10)) {
            $0.clefChoice = .both
            $0.range = .threeLedgerLines
            $0.answerInput = .keyboard
            $0.naming = .sargam
        }
        log.answer(crashed, at: at(2, 10, 1), Pitch(.c, 5))
        log.answer(crashed, at: at(2, 10, 3), Pitch(.d, 5), correct: false)
        let minuet = log.round(at: at(1, 10), piece: piece("Minuet in G", path: "/minuet.musicxml", hand: "left"))
        log.end(minuet, at: at(1, 10, 5), durationMs: 300_000, score: 18, attempts: 20, reason: .pieceComplete)
        log.add(.pieceOpened(PieceOpened(path: "/clarinet.musicxml", title: "Clarinet Tune", via: .drop,
                                         parts: [PartInfo(name: "Clarinet", notes: 40, measures: 16, staves: 1, skipped: 0)])),
                at: at(1, 10, 59))
        let clarinet = log.round(at: at(1, 11), piece: piece("Clarinet Tune", path: "/clarinet.musicxml"))
        log.end(clarinet, at: at(1, 11, 1), durationMs: 45_000, score: 9, attempts: 9, reason: .stopped)
        // Settings from an older version, with only some keys.
        let older = UUID()
        log.add(.roundStarted(RoundStarted(round: older, via: .key, settings: .object(["mode": .string("practice")]),
                                           keyFifths: 0, piece: nil)), at: at(0, 9))
        log.end(older, at: at(0, 9, 1), durationMs: 30_000, score: 3, attempts: 4, reason: .appQuit)
        let unanswered = log.round(at: at(0, 10))

        let rounds = report(log).recentRounds
        #expect(rounds == [
            RecentRound(id: unanswered, started: at(0, 10), durationMs: nil, mode: "sprint", input: "buttons",
                        naming: "letters", description: "Treble · On the staff · C major", score: 0, attempts: 0, endReason: nil),
            RecentRound(id: older, started: at(0, 9), durationMs: 30_000, mode: "practice", input: "buttons", naming: "letters",
                        description: "Treble · On the staff · C major", score: 3, attempts: 4, endReason: .appQuit),
            RecentRound(id: clarinet, started: at(1, 11), durationMs: 45_000, mode: "sprint", input: "buttons", naming: "letters",
                        description: "Clarinet Tune", score: 9, attempts: 9, endReason: .stopped),
            RecentRound(id: minuet, started: at(1, 10), durationMs: 300_000, mode: "sprint", input: "buttons", naming: "letters",
                        description: "Minuet in G · Left hand", score: 18, attempts: 20, endReason: .pieceComplete),
            RecentRound(id: crashed, started: at(2, 10), durationMs: 180_000, mode: "sprint", input: "keyboard", naming: "sargam",
                        description: "Both · +3 ledger lines · C major", score: 1, attempts: 2, endReason: nil),
            RecentRound(id: random, started: at(3, 11), durationMs: 120_000, mode: "practice", input: "piano", naming: "solfege",
                        description: "Bass · +1 ledger line · Random key (E♭ major)", score: 8, attempts: 10, endReason: .stopped),
            RecentRound(id: gMajor, started: at(3, 10), durationMs: 60_000, mode: "sprint", input: "buttons", naming: "letters",
                        description: "Treble · On the staff · G major", score: 20, attempts: 22, endReason: .timeUp),
        ])
        // The crashed round counts up to its last answer; the one with no answers, not at all.
        #expect(report(log).totals.practiceSeconds == 60 + 120 + 180 + 300 + 45 + 30)
    }

    @Test func recentRoundsKeepTheLatestFifty() {
        var log = Log()
        let ids = (0..<60).map { index in log.round(at: at(5, 8).addingTimeInterval(Double(index) * 300)) }
        let rounds = report(log).recentRounds
        #expect(rounds.map(\.id) == Array(ids.reversed().prefix(50)))
        #expect(report(log).totals.rounds == 60)
    }

    @Test func answersToQuestionsMissingFromTheLogAreSkipped() {
        var log = Log()
        let lost = log.round(at: at(1, 10))
        log.answer(lost, at: at(1, 10, 1), Pitch(.c, 5), ms: 500, logQuestion: false)
        let today = log.round(at: at(0, 10))
        log.answer(today, at: at(0, 10, 1), Pitch(.c, 5), ms: 500, logQuestion: false)
        log.answer(today, at: at(0, 10, 2), Pitch(.d, 5), correct: false, ms: 900)
        let week = report(log)
        #expect(week.totals == ProgressTotals(answers: 1, correct: 0, rounds: 2, practiceSeconds: 180, daysPractised: 1,
                                              medianResponseMs: nil))
        #expect(week.days.suffix(2).map(\.answers) == [0, 1])
        #expect(week.positions.map(\.attempts) == [1] && week.byInput.map(\.answers) == [1])
        #expect(streaks(week) == [1, 1])
        // A round's own score still counts every answer it logged.
        #expect(week.recentRounds.map { [$0.score, $0.attempts] } == [[1, 2], [1, 1]])
    }

    // MARK: - A synthetic log

    @Test func syntheticLogHasEverythingTheDashboardShows() {
        let events = SyntheticUsage.events(days: 90, seed: 1, now: now, calendar: calendar)
        #expect(events.first?.event.type == "appLaunched")
        #expect(events.dropFirst().first?.event == .statsSnapshot(SyntheticUsage.snapshot))
        #expect(zip(events, events.dropFirst()).allSatisfy { $0.time <= $1.time })
        #expect(events.last.map { $0.time <= now } == true)
        var types: [String: Int] = [:]
        var questions: [QuestionShown] = []
        var started: Set<UUID> = [], ended: Set<UUID> = [], pieceRounds = 0
        for logged in events {
            types[logged.event.type, default: 0] += 1
            switch logged.event {
            case .questionShown(let question): questions.append(question)
            case .roundStarted(let start):
                started.insert(start.round)
                if start.piece != nil { pieceRounds += 1 }
            case .roundEnded(let end): ended.insert(end.round)
            default: break
            }
        }
        #expect(types["statsSnapshot"] == 1)
        #expect(types["appLaunched"]! > types["appTerminated"]!, "a crash leaves a session without a quit")
        #expect(!started.subtracting(ended).isEmpty, "a round without an end")
        #expect(pieceRounds > 0 && types["pieceOpened"]! > 0)
        #expect(Set(questions.map(\.clef)) == ["treble", "bass"])
        #expect(Set(questions.map(\.input)) == ["buttons", "piano", "keyboard"])
        #expect(Set(questions.map(\.naming)) == ["letters", "solfege", "sargam"])
        #expect(questions.contains { $0.keyFifths == 1 } && questions.contains { $0.written.accidental == 1 })
        #expect(questions.contains { $0.printedAccidental == 1 })
        #expect(questions.contains { $0.octaveShift == 1 && $0.pieceNote != nil })
        let days = Set(events.map { calendar.startOfDay(for: $0.time) })
        #expect(days.count > 45 && days.count < 85, "most days, not all")
    }

    @Test func syntheticReportAddsUp() {
        let events = SyntheticUsage.events(days: 90, seed: 1, now: now, calendar: calendar)
        let quarter = ProgressAnalyzer.report(from: events, filter: ProgressFilter(range: .quarter), now: now, calendar: calendar)
        let totals = quarter.totals
        #expect(quarter.days.count == 90)
        #expect(totals.answers > 3000)
        #expect(quarter.days.map(\.answers).reduce(0, +) == totals.answers)
        #expect(quarter.days.map(\.correct).reduce(0, +) == totals.correct)
        #expect(abs(quarter.days.map(\.practiceSeconds).reduce(0, +) - totals.practiceSeconds) < 0.001)
        #expect(quarter.days.filter { $0.answers > 0 }.count == totals.daysPractised)
        #expect(totals.accuracy.map { $0 > 0.6 && $0 < 0.95 } == true)
        #expect(totals.medianResponseMs.map { $0 > 500 && $0 < 3000 } == true)
        #expect(totals.practiceSeconds > Double(totals.answers) && totals.practiceSeconds < Double(totals.answers) * 5)
        #expect(quarter.positions.map(\.attempts).reduce(0, +) == totals.answers)
        #expect(quarter.pitches.map(\.attempts).reduce(0, +) == totals.answers)
        #expect(quarter.byInput.map(\.answers).reduce(0, +) == totals.answers && quarter.byInput.count == 3)
        #expect(quarter.byNaming.map(\.answers).reduce(0, +) == totals.answers && quarter.byNaming.count == 3)
        #expect(quarter.longestStreakDays >= max(quarter.currentStreakDays, 3))
        #expect(quarter.recentRounds.count == 50)
        #expect(zip(quarter.recentRounds, quarter.recentRounds.dropFirst()).allSatisfy { $0.started > $1.started })
        let minuet = quarter.pieces.first
        #expect(quarter.pieces.count == 1 && minuet?.title == SyntheticUsage.pieceTitle && minuet?.measureCount == 32)
        #expect(minuet.map { $0.bars.map(\.bar) == $0.bars.map(\.bar).sorted() && $0.bars.count == 32 } == true)
        #expect(quarter.answersBeforeTracking == 0)

        let allTime = ProgressAnalyzer.report(from: events, filter: ProgressFilter(range: .all), now: now, calendar: calendar)
        #expect(allTime.totals == totals)
        #expect(allTime.answersBeforeTracking == 138)
        #expect(allTime.positions.map(\.attemptsBeforeTracking).reduce(0, +) == 138)
        #expect(allTime.positions.map(\.attempts).reduce(0, +) == totals.answers + 138)

        let treble = ProgressAnalyzer.report(from: events, filter: ProgressFilter(range: .quarter, clef: .treble),
                                             now: now, calendar: calendar)
        let bass = ProgressAnalyzer.report(from: events, filter: ProgressFilter(range: .quarter, clef: .bass),
                                           now: now, calendar: calendar)
        #expect(treble.totals.answers + bass.totals.answers == totals.answers)
        // Every synthetic round has answers; rounds on both clefs count in both.
        #expect(treble.totals.rounds < totals.rounds && bass.totals.rounds < totals.rounds)
        #expect(treble.totals.rounds + bass.totals.rounds > totals.rounds)
    }

    @Test func syntheticPracticeImproves() {
        let events = SyntheticUsage.events(days: 90, seed: 2, now: now, calendar: calendar)
        let days = ProgressAnalyzer.report(from: events, filter: ProgressFilter(range: .quarter), now: now, calendar: calendar)
            .days.filter { $0.answers > 0 }
        let early = days.prefix(days.count / 3), late = days.suffix(days.count / 3)
        func accuracy(_ days: ArraySlice<DayProgress>) -> Double {
            Double(days.map(\.correct).reduce(0, +)) / Double(days.map(\.answers).reduce(0, +))
        }
        func typicalMs(_ days: ArraySlice<DayProgress>) -> Double {
            Double(days.compactMap(\.medianResponseMs).reduce(0, +)) / Double(days.count)
        }
        #expect(accuracy(late) > accuracy(early) + 0.15)
        #expect(typicalMs(late) < typicalMs(early) * 0.7)
    }

    @Test func syntheticLogIsTheSameForASeed() {
        let first = SyntheticUsage.events(days: 30, seed: 5, now: now, calendar: calendar)
        let second = SyntheticUsage.events(days: 30, seed: 5, now: now, calendar: calendar)
        // Event ids are random; everything else is the seed's.
        #expect(first.map(\.event) == second.map(\.event))
        #expect(first.map(\.time) == second.map(\.time) && first.map(\.session) == second.map(\.session))
        #expect(first.map(\.event) != SyntheticUsage.events(days: 30, seed: 6, now: now, calendar: calendar).map(\.event))
        let filter = ProgressFilter(range: .month)
        #expect(ProgressAnalyzer.report(from: first, filter: filter, now: now, calendar: calendar)
                    == ProgressAnalyzer.report(from: second, filter: filter, now: now, calendar: calendar))
    }

    @Test func yearsOfLogAreQuick() {
        let events = SyntheticUsage.events(days: 4 * 365, seed: 3, now: now, calendar: calendar)
        #expect(events.count >= 200_000)
        let clock = ContinuousClock()
        var report: ProgressReport?
        let elapsed = clock.measure {
            report = ProgressAnalyzer.report(from: events, filter: ProgressFilter(range: .all), now: now, calendar: calendar)
        }
        // Debug builds are many times slower than release, where this takes well under a second.
        #expect(elapsed < .seconds(15), "\(events.count) events took \(elapsed)")
        #expect(report?.days.count ?? 0 > 4 * 360)
        print("Analysed \(events.count) events in \(elapsed)")
    }
}
