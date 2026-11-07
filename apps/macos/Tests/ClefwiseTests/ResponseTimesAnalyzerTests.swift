import Foundation
import Testing
@testable import Clefwise

/// A usage log written by hand for the response-time statistics: questions are numbered in their
/// round as the game numbers them, and notes can be asked together as a chord.
private struct TimesLog {
    private(set) var events: [LoggedEvent] = []
    private let session = UUID()
    /// Questions shown so far in each round.
    private var shown: [UUID: Int] = [:]

    mutating func add(_ event: UsageEvent, at time: Date) {
        events.append(LoggedEvent(event, session: session, sequence: events.count, time: time))
    }

    mutating func round(at time: Date) -> UUID {
        let id = UUID()
        add(.roundStarted(RoundStarted(round: id, via: .button, settings: JSONValue(encoding: Game.Settings()),
                                       keyFifths: 0, piece: nil)), at: time)
        return id
    }

    /// A single note on `written` shown `ms` before `time` (unless `logQuestion` is false, as when
    /// the log lost it, though it still takes its place in the round), and its answer at `time`.
    mutating func answer(_ round: UUID, at time: Date, _ written: Pitch, clef: Clef = .treble, correct: Bool = true,
                         ms: Int = 1000, staff: Int? = nil, logQuestion: Bool = true) {
        let question = UUID()
        let shownAt = time.addingTimeInterval(-Double(ms) / 1000)
        if logQuestion {
            add(.questionShown(shownQuestion(round, question, written, clef: clef, staff: staff, group: nil)), at: shownAt)
        } else {
            shown[round, default: 0] += 1
        }
        add(.answerGiven(answerGiven(round, question, written, correct: correct, ms: ms, group: nil)), at: time)
    }

    /// Notes asked together as one chord, each named right or wrong as `correct` says.
    mutating func chord(_ round: UUID, at time: Date, _ notes: [(Pitch, Bool)], clef: Clef = .treble, ms: Int = 1000) {
        let group = (id: UUID(), size: notes.count)
        let questions = notes.map { _ in UUID() }
        for (note, question) in zip(notes, questions) {
            add(.questionShown(shownQuestion(round, question, note.0, clef: clef, staff: nil, group: group)),
                at: time.addingTimeInterval(-Double(ms) / 1000))
        }
        for (note, question) in zip(notes, questions) {
            add(.answerGiven(answerGiven(round, question, note.0, correct: note.1, ms: ms, group: group)), at: time)
        }
    }

    private mutating func shownQuestion(_ round: UUID, _ question: UUID, _ written: Pitch, clef: Clef, staff: Int?,
                                        group: (id: UUID, size: Int)?) -> QuestionShown {
        let index = shown[round, default: 0]
        shown[round] = index + 1
        return QuestionShown(
            round: round, question: question, index: index, clef: clef.rawValue, pitch: LoggedPitch(written),
            written: LoggedPitch(written), position: clef.position(of: written), keyFifths: 0, printedAccidental: nil,
            octaveShift: 0, pieceNote: staff.map { PieceNoteRef(measure: 1, staff: $0, onset: 0, chord: 0) },
            pickChance: nil, naming: "letters", input: "buttons", hintsVisible: false, keyNamesVisible: false,
            group: group?.id, groupSize: group?.size)
    }

    private func answerGiven(_ round: UUID, _ question: UUID, _ written: Pitch, correct: Bool, ms: Int,
                             group: (id: UUID, size: Int)?) -> AnswerGiven {
        AnswerGiven(round: round, question: question, responseMs: ms, source: .click, letter: written.letter.name,
                    accidental: 0, name: written.letter.name, pitch: nil, correct: correct, wrongOctave: nil,
                    keystrokes: [], scoreAfter: 0, streakAfter: 0, group: group?.id, groupSize: group?.size)
    }
}

@Suite struct ResponseTimesAnalyzerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()
    /// Friday 30 October 2026, 16:00 in Stockholm.
    private let now = usageTestTime("2026-10-30T15:00:00.000Z")

    /// `daysAgo` local days before today, at a Stockholm wall-clock time.
    private func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
    }

    private func report(_ log: TimesLog, _ range: ProgressFilter.Range = .week,
                        clef: ProgressFilter.ClefFilter = .all) -> ProgressReport {
        ProgressAnalyzer.report(from: log.events, filter: ProgressFilter(range: range, clef: clef), now: now, calendar: calendar)
    }

    /// A histogram with `counts` in the given bins and zeros elsewhere.
    private func histogram(_ counts: [Int: Int]) -> [Int] {
        (0...ResponseTimes.histogramBins).map { counts[$0] ?? 0 }
    }

    // MARK: - Spread and shape

    @Test func quartilesAndHistogramOfRightAnswers() {
        var log = TimesLog()
        let round = log.round(at: at(0, 9))
        for (second, ms) in [249, 250, 500, 1000, 5999, 6000, 7500].enumerated() {
            log.answer(round, at: at(0, 9, 1, second * 8), Pitch(.e, 4), ms: ms)
        }
        log.answer(round, at: at(0, 9, 2), Pitch(.f, 4), correct: false, ms: 300) // wrong: not in the shape
        let times = report(log).responseTimes
        // Sorted 249 250 500 1000 5999 6000 7500: the quartiles sit at ranks 1.5, 3 and 4.5.
        #expect(times.current == TimeSpread(rightAnswers: 7, lowerQuartileMs: 375, medianMs: 1000, upperQuartileMs: 6000))
        #expect(times.current.spreadMs == 5625)
        // 249 ms is in the first bin, 250 starts the second, 5999 is the last full bin, 6 s and more overflow.
        #expect(times.histogram == histogram([0: 1, 1: 1, 2: 1, 4: 1, 23: 1, 24: 2]))
        #expect(times.histogram.count == ResponseTimes.histogramBins + 1)
    }

    @Test func thePreviousWindowAndAllTime() {
        var log = TimesLog()
        let before = log.round(at: at(9, 10)) // the week before
        log.answer(before, at: at(9, 10, 1), Pitch(.g, 4), ms: 2000)
        log.answer(before, at: at(9, 10, 2), Pitch(.a, 4), ms: 3000)
        log.answer(before, at: at(9, 10, 3), Pitch(.b, 4), correct: false, ms: 900)
        let older = log.round(at: at(20, 10)) // before both weeks
        log.answer(older, at: at(20, 10, 1), Pitch(.c, 5), ms: 4000)
        let recent = log.round(at: at(1, 10))
        log.answer(recent, at: at(1, 10, 1), Pitch(.d, 5), ms: 800)
        log.answer(recent, at: at(1, 10, 2), Pitch(.e, 5), ms: 1200)

        let week = report(log).responseTimes
        #expect(week.current == TimeSpread(rightAnswers: 2, lowerQuartileMs: 900, medianMs: 1000, upperQuartileMs: 1100))
        #expect(week.previous == TimeSpread(rightAnswers: 2, lowerQuartileMs: 2250, medianMs: 2500, upperQuartileMs: 2750))
        #expect(week.histogram == histogram([3: 1, 4: 1]))
        #expect(week.previousHistogram == histogram([8: 1, 12: 1]))
        // The week before's wrong answer is in neither window's speeds.
        #expect(week.bySpeed.map(\.answers).reduce(0, +) == 2)

        let allTime = report(log, .all).responseTimes
        #expect(allTime.previous == nil && allTime.previousHistogram == nil)
        #expect(allTime.current == TimeSpread(rightAnswers: 5, lowerQuartileMs: 1200, medianMs: 2000, upperQuartileMs: 3000))
        #expect(allTime.histogram == histogram([3: 1, 4: 1, 8: 1, 12: 1, 16: 1]))
        #expect(allTime.bySpeed.map(\.answers).reduce(0, +) == 6)
    }

    @Test func chordsNamedTogetherAreLeftOut() throws {
        var log = TimesLog()
        let round = log.round(at: at(0, 9))
        log.answer(round, at: at(0, 9, 1), Pitch(.e, 4), ms: 1000)
        log.chord(round, at: at(0, 9, 5), [(Pitch(.c, 4), true), (Pitch(.e, 4), true), (Pitch(.g, 4), false)], ms: 3000)
        log.answer(round, at: at(0, 9, 6), Pitch(.e, 4), ms: 2000)
        let week = report(log)
        let times = week.responseTimes
        #expect(times.current == TimeSpread(rightAnswers: 2, lowerQuartileMs: 1250, medianMs: 1500, upperQuartileMs: 1750))
        #expect(times.histogram == histogram([4: 1, 8: 1]))
        #expect(times.bySpeed.map(\.answers) == [0, 0, 1, 0, 1, 0, 0])
        #expect(times.bySpeed.map(\.wrong).allSatisfy { $0 == 0 })
        #expect(times.byPreviousNote.map(\.answers).allSatisfy { $0 == 0 })
        // The rest of the dashboard still counts the chord.
        #expect(week.totals.answers == 5 && week.totals.correct == 4)
        let today = try #require(week.days.last)
        #expect(today.medianResponseMs == 2500) // 1000, 3000, 3000, 2000
        #expect(today.lowerQuartileMs == 1250 && today.upperQuartileMs == 1750)
        let e4 = try #require(week.positions.first { $0.clef == .treble && $0.position == 0 })
        #expect(e4.attempts == 3 && e4.medianResponseMs == 2000)
        #expect(e4.recentMedianResponseMs == 1500 && e4.recentRightAnswers == 2)
        let c4 = try #require(week.positions.first { $0.clef == .treble && $0.position == -2 })
        #expect(c4.recentMedianResponseMs == nil && c4.recentRightAnswers == 0)
    }

    // MARK: - Mistakes by speed

    @Test func everyAnswerCountsBySpeed() {
        var log = TimesLog()
        let round = log.round(at: at(0, 9))
        let answers: [(ms: Int, correct: Bool)] = [
            (0, true), (749, false), (750, true), (999, false), (1000, true), (1499, true), (1500, false),
            (2000, true), (2999, false), (3000, true), (4999, false), (5000, false), (60_000, true),
        ]
        for (index, answer) in answers.enumerated() {
            log.answer(round, at: at(0, 9, 1 + index), Pitch(.e, 4), correct: answer.correct, ms: answer.ms)
        }
        let times = report(log).responseTimes
        #expect(times.bySpeed == [
            SpeedBin(lowerMs: 0, upperMs: 750, answers: 2, wrong: 1),
            SpeedBin(lowerMs: 750, upperMs: 1000, answers: 2, wrong: 1),
            SpeedBin(lowerMs: 1000, upperMs: 1500, answers: 2, wrong: 0),
            SpeedBin(lowerMs: 1500, upperMs: 2000, answers: 1, wrong: 1),
            SpeedBin(lowerMs: 2000, upperMs: 3000, answers: 2, wrong: 1),
            SpeedBin(lowerMs: 3000, upperMs: 5000, answers: 2, wrong: 1),
            SpeedBin(lowerMs: 5000, upperMs: nil, answers: 2, wrong: 1),
        ])
        #expect(times.bySpeed[5].mistakeRate == 0.5)
        // Wrong answers stay out of the right answers' shape.
        #expect(times.current.rightAnswers == 7 && times.histogram.reduce(0, +) == 7)
    }

    @Test func anEmptyWindowHasEveryRowAndBin() {
        for range in ProgressFilter.Range.allCases {
            let times = report(TimesLog(), range).responseTimes
            #expect(times.current == TimeSpread())
            #expect(times.histogram == histogram([:]))
            #expect(times.bySpeed.map(\.lowerMs) == [0] + ResponseTimes.speedEdgesMs)
            #expect(times.bySpeed.map(\.upperMs) == ResponseTimes.speedEdgesMs + [nil])
            #expect(times.bySpeed.allSatisfy { $0.answers == 0 && $0.wrong == 0 })
            #expect(times.byPreviousNote == PreviousNoteDistance.allCases.map {
                PreviousNoteRow(distance: $0, answers: 0, correct: 0, medianMs: nil)
            })
            #expect((times.previous == nil) == (range == .all))
            #expect((times.previousHistogram == nil) == (range == .all))
        }
    }

    // MARK: - The clef filter

    @Test func theClefFilterPicksTheNotes() {
        var log = TimesLog()
        let round = log.round(at: at(0, 9))
        log.answer(round, at: at(0, 9, 1), Pitch(.e, 4), ms: 800)
        log.answer(round, at: at(0, 9, 2), Pitch(.f, 4), ms: 900)
        log.answer(round, at: at(0, 9, 3), Pitch(.g, 2), clef: .bass, ms: 2000)
        log.answer(round, at: at(0, 9, 4), Pitch(.a, 2), clef: .bass, correct: false, ms: 2500)
        log.answer(round, at: at(0, 9, 5), Pitch(.c, 3), clef: .bass, ms: 4000)
        let previousWeek = log.round(at: at(8, 9))
        log.answer(previousWeek, at: at(8, 9, 1), Pitch(.g, 4), ms: 1200)
        log.answer(previousWeek, at: at(8, 9, 2), Pitch(.c, 3), clef: .bass, ms: 3200)

        let bass = report(log, clef: .bass)
        #expect(bass.responseTimes.current == TimeSpread(rightAnswers: 2, lowerQuartileMs: 2500, medianMs: 3000, upperQuartileMs: 3500))
        #expect(bass.responseTimes.previous == TimeSpread(rightAnswers: 1, lowerQuartileMs: 3200, medianMs: 3200, upperQuartileMs: 3200))
        #expect(bass.responseTimes.histogram == histogram([8: 1, 16: 1]))
        #expect(bass.responseTimes.previousHistogram == histogram([12: 1]))
        #expect(bass.responseTimes.bySpeed.map(\.answers) == [0, 0, 0, 0, 2, 1, 0])
        #expect(bass.responseTimes.byPreviousNote.map(\.answers) == [0, 1, 1, 0]) // A2 after G2, C3 after A2
        #expect(bass.days.last?.lowerQuartileMs == 2500 && bass.days.last?.upperQuartileMs == 3500)
        #expect(bass.positions.map(\.recentRightAnswers) == [1, 0, 1])

        let treble = report(log, clef: .treble)
        #expect(treble.responseTimes.current == TimeSpread(rightAnswers: 2, lowerQuartileMs: 825, medianMs: 850, upperQuartileMs: 875))
        #expect(treble.responseTimes.previous?.medianMs == 1200)
        #expect(treble.responseTimes.byPreviousNote.map(\.answers) == [0, 1, 0, 0]) // F4 after E4

        let both = report(log)
        #expect(both.responseTimes.current.rightAnswers == 4)
        #expect(both.responseTimes.byPreviousNote.map(\.answers) == [0, 2, 1, 0]) // G2 after F4 is on the other staff
    }

    // MARK: - The previous note

    @Test func distancesFromTheNoteBeforeInTheSameRound() {
        var log = TimesLog()
        let round = log.round(at: at(0, 9))
        var second = 0
        func next() -> Date { second += 5; return at(0, 9, second / 60, second % 60) }
        log.answer(round, at: next(), Pitch(.e, 4), ms: 9000)                // first of the round: left out
        log.answer(round, at: next(), Pitch(.f, 4), ms: 1000)                // +1: one step
        log.answer(round, at: next(), Pitch(.c, 5), ms: 1600)                // +4: four or more
        log.answer(round, at: next(), Pitch(.a, 4), ms: 1200)                // −2: two or three
        log.answer(round, at: next(), Pitch(.a, 4, .sharp), ms: 1400)        // 0: same place
        log.answer(round, at: next(), Pitch(.g, 4), correct: false, ms: 700) // −1, wrong
        log.answer(round, at: next(), Pitch(.f, 4), ms: 1100)                // −1
        log.answer(round, at: next(), Pitch(.g, 2), clef: .bass, ms: 9000)   // after the other clef: left out
        log.answer(round, at: next(), Pitch(.g, 4), ms: 9000)                // after the other clef: left out
        log.chord(round, at: next(), [(Pitch(.c, 4), true), (Pitch(.e, 4), true)], ms: 9000) // a chord: left out
        log.answer(round, at: next(), Pitch(.f, 4), ms: 9000)                // after a chord: left out
        log.answer(round, at: next(), Pitch(.d, 5), ms: 1800)                // +5: four or more
        log.answer(round, at: next(), Pitch(.e, 5), ms: 9000, logQuestion: false) // lost from the log: skipped
        log.answer(round, at: next(), Pitch(.f, 5), ms: 9000)                // its question before is lost: left out
        let other = log.round(at: next())
        log.answer(other, at: next(), Pitch(.g, 5), ms: 9000)                // a new round's first: left out
        log.answer(other, at: next(), Pitch(.c, 6), ms: 3000)                // +3: two or three

        let rows = report(log).responseTimes.byPreviousNote
        #expect(rows == [
            PreviousNoteRow(distance: .samePlace, answers: 1, correct: 1, medianMs: 1400),
            PreviousNoteRow(distance: .oneStep, answers: 3, correct: 2, medianMs: 1050),
            PreviousNoteRow(distance: .twoOrThreeSteps, answers: 2, correct: 2, medianMs: 2100),
            PreviousNoteRow(distance: .fourOrMoreSteps, answers: 2, correct: 2, medianMs: 1700),
        ])
        #expect(rows[1].accuracy == 2.0 / 3)
    }

    @Test func aPieceStaffIsItsOwnEvenInTheSameClef() {
        var log = TimesLog()
        let round = log.round(at: at(0, 9))
        log.answer(round, at: at(0, 9, 1), Pitch(.e, 4), ms: 1000, staff: 1)
        log.answer(round, at: at(0, 9, 2), Pitch(.f, 4), ms: 1000, staff: 2) // another treble staff: left out
        log.answer(round, at: at(0, 9, 3), Pitch(.g, 4), ms: 1000, staff: 2) // one step on the same staff
        #expect(report(log).responseTimes.byPreviousNote.map(\.answers) == [0, 1, 0, 0])
    }

    @Test func thePreviousNoteCountsOnlyAnswersInTheWindow() {
        var log = TimesLog()
        // A round over midnight into the week: the note before may be outside it.
        let round = log.round(at: at(7, 23, 59))
        log.answer(round, at: at(7, 23, 59, 30), Pitch(.e, 4), ms: 1000)
        log.answer(round, at: at(7, 23, 59, 50), Pitch(.f, 4), ms: 1000) // the week before
        log.answer(round, at: at(6, 0, 0, 10), Pitch(.c, 5), ms: 1000)   // in the week, from F4
        let rows = report(log).responseTimes.byPreviousNote
        #expect(rows.map(\.answers) == [0, 0, 0, 1])
    }

    // MARK: - Days and places

    @Test func eachDayHasItsQuartiles() {
        var log = TimesLog()
        let monday = log.round(at: at(4, 9))
        for (index, ms) in [400, 1000, 600, 800, 1200].enumerated() {
            log.answer(monday, at: at(4, 9, 1, index), Pitch(.e, 4), ms: ms)
        }
        log.answer(monday, at: at(4, 9, 2), Pitch(.e, 4), correct: false, ms: 5000)
        let wednesday = log.round(at: at(2, 9))
        log.answer(wednesday, at: at(2, 9, 1), Pitch(.e, 4), correct: false, ms: 700)
        log.chord(wednesday, at: at(2, 9, 2), [(Pitch(.c, 4), true), (Pitch(.e, 4), true)], ms: 1500)
        let today = log.round(at: at(0, 9))
        log.answer(today, at: at(0, 9, 1), Pitch(.e, 4), ms: 1300)

        let days = report(log).days
        #expect(days.map(\.lowerQuartileMs) == [nil, nil, 600, nil, nil, nil, 1300])
        #expect(days.map(\.upperQuartileMs) == [nil, nil, 1000, nil, nil, nil, 1300])
        #expect(days.map(\.spreadMs) == [nil, nil, 400, nil, nil, nil, 0])
        // Wednesday's only right answers are a chord's: a median, but no quartiles.
        #expect(days[4].medianResponseMs == 1500 && days[4].lowerQuartileMs == nil)
    }

    @Test func aPlaceIsNamedNowAsFastAsItsLastTwentyRightAnswers() throws {
        var log = TimesLog()
        log.add(.statsSnapshot(StatsSnapshot(reason: "beforeUsageLog", noteStats: [
            "treble.E4": NoteStat(attempts: 50, correct: 50), "treble.D4": NoteStat(attempts: 5, correct: 4),
        ])), at: at(10, 8))
        let before = log.round(at: at(10, 9)) // before the week: not in its "now"
        log.answer(before, at: at(10, 9, 1), Pitch(.e, 4), ms: 100)
        let round = log.round(at: at(0, 9))
        // 25 right answers to E4 and its flat (the same line), slowest first, with mistakes between.
        for index in 0..<25 {
            let pitch = index.isMultiple(of: 2) ? Pitch(.e, 4) : Pitch(.e, 4, .flat)
            log.answer(round, at: at(0, 9, 1, index * 2), pitch, ms: 2500 - index * 100)
            log.answer(round, at: at(0, 9, 1, index * 2 + 1), Pitch(.e, 4), correct: false, ms: 300)
        }
        log.chord(round, at: at(0, 9, 2), [(Pitch(.e, 4), true), (Pitch(.g, 4), true)], ms: 50)
        log.answer(round, at: at(0, 9, 3), Pitch(.f, 4), ms: 1200)
        log.answer(round, at: at(0, 9, 4), Pitch(.f, 4), ms: 1400)
        log.answer(round, at: at(0, 9, 5), Pitch(.a, 4), correct: false, ms: 900)

        let week = report(log)
        func place(_ position: Int, in report: ProgressReport) -> PositionProgress? {
            report.positions.first { $0.clef == .treble && $0.position == position }
        }
        // The last 20 are 2000 ms down to 100 ms: their median is 1050.
        let e4 = try #require(place(0, in: week))
        #expect(e4.recentRightAnswers == 20 && e4.recentMedianResponseMs == 1050)
        #expect(e4.medianResponseMs == 1250) // all 25, and the chord's 50 ms: 26 values
        let f4 = try #require(place(1, in: week))
        #expect(f4.recentRightAnswers == 2 && f4.recentMedianResponseMs == 1300)
        let a4 = try #require(place(3, in: week))
        #expect(a4.recentRightAnswers == 0 && a4.recentMedianResponseMs == nil)

        // All time takes the earlier 100 ms too, but it's not among the last 20; the snapshot has no times.
        let allTime = report(log, .all)
        let e4AllTime = try #require(place(0, in: allTime))
        #expect(e4AllTime.recentRightAnswers == 20 && e4AllTime.recentMedianResponseMs == 1050)
        #expect(e4AllTime.attemptsBeforeTracking == 50)
        let d4 = try #require(place(-1, in: allTime))
        #expect(d4.attemptsBeforeTracking == 5 && d4.recentRightAnswers == 0 && d4.recentMedianResponseMs == nil)
    }
}
