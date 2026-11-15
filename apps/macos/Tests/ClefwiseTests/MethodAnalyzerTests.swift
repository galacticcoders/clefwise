import Foundation
import Testing
@testable import Clefwise

/// The analyzer's side of answer methods (`AnswerMethod`): the method filter, which applies
/// wherever the clef filter does; each day split by method; the window before by method; which
/// methods have answers at all; and each round's answers on a real piano.
@Suite struct MethodAnalyzerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()
    /// Sunday 15 November 2026, 16:00 in Stockholm. The week runs from Monday the 9th, the week
    /// before from Monday the 2nd.
    private let now = usageTestTime("2026-11-15T15:00:00.000Z")

    /// `daysAgo` local days before today, at a Stockholm wall-clock time.
    private func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
    }

    private func report(_ log: Log, _ range: ProgressFilter.Range = .week, clef: ProgressFilter.ClefFilter = .all,
                        method: AnswerMethod? = nil) -> ProgressReport {
        report(log.events, range, clef: clef, method: method)
    }

    private func report(_ events: [LoggedEvent], _ range: ProgressFilter.Range = .week,
                        clef: ProgressFilter.ClefFilter = .all, method: AnswerMethod? = nil) -> ProgressReport {
        ProgressAnalyzer.report(from: events, filter: ProgressFilter(range: range, clef: clef, method: method), now: now,
                                calendar: calendar)
    }

    /// This week: two days ago a round typed on the keyboard, then one on the piano setting with
    /// keys on screen and on a real piano; the guitar yesterday; the note buttons in the bass today.
    /// The week before: one round typed, one on a real piano.
    private func weekLog() -> (log: Log, keyboard: UUID, piano: UUID, guitar: UUID, buttons: UUID) {
        var log = Log()
        let oldTyped = log.round(at: at(9, 10)) { $0.answerInput = .keyboard }
        log.answer(oldTyped, at: at(9, 10, 0, 2), Pitch(.c, 5), ms: 2000, input: "keyboard", source: .typing)
        log.answer(oldTyped, at: at(9, 10, 0, 4), Pitch(.d, 5), correct: false, ms: 1800, input: "keyboard", source: .typing)
        log.end(oldTyped, at: at(9, 10, 0, 5), durationMs: 50_000, score: 1, attempts: 2)
        let oldMidi = log.round(at: at(8, 10)) { $0.answerInput = .piano }
        log.answer(oldMidi, at: at(8, 10, 0, 6), Pitch(.e, 5), ms: 6000, input: "piano", source: .midi)
        log.end(oldMidi, at: at(8, 10, 0, 7), durationMs: 40_000, score: 1, attempts: 1)

        let keyboard = log.round(at: at(2, 10)) { $0.answerInput = .keyboard }
        log.answer(keyboard, at: at(2, 10, 0, 1), Pitch(.e, 4), ms: 1000, input: "keyboard", source: .typing)
        log.answer(keyboard, at: at(2, 10, 0, 3), Pitch(.g, 4), ms: 1400, input: "keyboard", source: .typing)
        log.answer(keyboard, at: at(2, 10, 0, 4), Pitch(.b, 4), correct: false, ms: 800, input: "keyboard", source: .typing)
        log.end(keyboard, at: at(2, 10, 0, 5), durationMs: 60_000, score: 2, attempts: 3)
        let piano = log.round(at: at(2, 11)) { $0.answerInput = .piano }
        log.answer(piano, at: at(2, 11, 0, 3), Pitch(.e, 4), ms: 3000, input: "piano", source: .piano)
        log.answer(piano, at: at(2, 11, 0, 8), Pitch(.f, 4), ms: 5000, input: "piano", source: .midi)
        log.answer(piano, at: at(2, 11, 0, 12), Pitch(.a, 4), correct: false, ms: 4000, input: "piano", source: .midi)
        log.end(piano, at: at(2, 11, 0, 13), durationMs: 120_000, score: 2, attempts: 3)
        let guitar = log.round(at: at(1, 18)) { $0.answerInput = .guitar }
        log.answer(guitar, at: at(1, 18, 0, 16), Pitch(.e, 2), clef: .treble8vb, ms: 16_000, input: "guitar", source: .guitar)
        log.answer(guitar, at: at(1, 18, 0, 28), Pitch(.e, 3), clef: .treble8vb, ms: 12_000, input: "guitar", source: .guitar)
        log.end(guitar, at: at(1, 18, 0, 30), durationMs: 90_000, score: 2, attempts: 2)
        let buttons = log.round(at: at(0, 9)) { $0.clefChoice = .bass }
        log.answer(buttons, at: at(0, 9, 0, 2), Pitch(.g, 2), clef: .bass, ms: 1500)
        log.end(buttons, at: at(0, 9, 0, 3), durationMs: 30_000, score: 1, attempts: 1)
        return (log, keyboard, piano, guitar, buttons)
    }

    // MARK: - 1. An answer's method

    @Test func anAnswersMethodIsItsSettingOrARealPiano() {
        let week = report(weekLog().log)
        #expect(week.totals == ProgressTotals(answers: 9, correct: 7, rounds: 4, practiceSeconds: 300, daysPractised: 3,
                                              medianResponseMs: 3000))
        #expect(week.methodsPractised == Set(AnswerMethod.allCases))
        // Keys as before: the setting, `midi` for the real piano; most answers first, then by key.
        #expect(week.byInput == [
            BreakdownRow(key: "keyboard", answers: 3, correct: 2, medianResponseMs: 1200),
            BreakdownRow(key: "guitar", answers: 2, correct: 2, medianResponseMs: 14_000),
            BreakdownRow(key: "midi", answers: 2, correct: 1, medianResponseMs: 5000),
            BreakdownRow(key: "buttons", answers: 1, correct: 1, medianResponseMs: 1500),
            BreakdownRow(key: "piano", answers: 1, correct: 1, medianResponseMs: 3000),
        ])
    }

    @Test func anInputThisVersionDoesntKnowCountsOnlyWithEveryMethod() {
        var log = weekLog().log
        let harp = log.round(at: at(0, 12))
        log.answer(harp, at: at(0, 12, 0, 1), Pitch(.c, 5), ms: 900, input: "harp")
        log.end(harp, at: at(0, 12, 0, 2), durationMs: 10_000, score: 1, attempts: 1)

        let week = report(log)
        #expect(week.totals.answers == 10 && week.totals.rounds == 5)
        #expect(week.byInput.contains(BreakdownRow(key: "harp", answers: 1, correct: 1, medianResponseMs: 900)))
        // In the day, but in none of its methods.
        let today = week.days.last!
        #expect(today.answers == 2 && today.methods.map(\.method) == [.buttons] && today.methods[0].answers == 1)
        #expect(week.methodsPractised == Set(AnswerMethod.allCases))
        #expect(AnswerMethod.allCases.map { report(log, method: $0).totals.answers }.reduce(0, +) == 9)
        for method in AnswerMethod.allCases {
            let filtered = report(log, method: method)
            #expect(!filtered.byInput.contains { $0.key == "harp" })
            #expect(!filtered.recentRounds.contains { $0.id == harp })
        }
    }

    // MARK: - 2. The method filter

    @Test func theMethodFilterPicksAnswersEverywhere() {
        let (log, _, piano, _, _) = weekLog()
        let real = report(log, method: .realPiano)
        #expect(real.filter.method == .realPiano)
        #expect(real.totals == ProgressTotals(answers: 2, correct: 1, rounds: 1, practiceSeconds: 120, daysPractised: 1,
                                              medianResponseMs: 5000))
        #expect(real.previousTotals == ProgressTotals(answers: 1, correct: 1, rounds: 1, practiceSeconds: 40, daysPractised: 1,
                                                      medianResponseMs: 6000))
        // Days: only two days ago, and only its real piano part.
        #expect(real.days.count == 7)
        #expect(real.days.filter { $0.answers > 0 }.map(\.day) == [at(2, 0)])
        let day = real.days[4]
        #expect(day.answers == 2 && day.correct == 1 && day.practiceSeconds == 120 && day.medianResponseMs == 5000)
        #expect(day.methods == [MethodDay(method: .realPiano, answers: 2, correct: 1, medianResponseMs: 5000,
                                          lowerQuartileMs: 5000, upperQuartileMs: 5000, rightSingleNotes: 1)])
        // The note map and pitches: F4 and A4, not the E4 on the screen's keys or typed.
        #expect(real.positions.map(\.id) == ["treble1", "treble3"])
        #expect(real.positions.map(\.attempts) == [1, 1])
        #expect(real.pitches.map(\.id) == ["treble.F4", "treble.A4"])
        #expect(real.byInput == [BreakdownRow(key: "midi", answers: 2, correct: 1, medianResponseMs: 5000)])
        #expect(real.byNaming == [BreakdownRow(key: "letters", answers: 2, correct: 1, medianResponseMs: 5000)])
        #expect(real.recentRounds.map(\.id) == [piano])
        // Response times, now and the week before.
        #expect(real.responseTimes.current == TimeSpread(rightAnswers: 1, lowerQuartileMs: 5000, medianMs: 5000,
                                                         upperQuartileMs: 5000))
        #expect(real.responseTimes.previous == TimeSpread(rightAnswers: 1, lowerQuartileMs: 6000, medianMs: 6000,
                                                          upperQuartileMs: 6000))
        #expect(real.responseTimes.bySpeed.map(\.answers).reduce(0, +) == 2)
        #expect(real.responseTimes.histogram.reduce(0, +) == 1)
    }

    @Test func aRoundOfAnotherMethodIsLeftOutOfRounds() {
        let (log, keyboard, piano, guitar, buttons) = weekLog()
        let typed = report(log, method: .keyboard)
        #expect(typed.totals == ProgressTotals(answers: 3, correct: 2, rounds: 1, practiceSeconds: 60, daysPractised: 1,
                                               medianResponseMs: 1200))
        #expect(typed.previousTotals == ProgressTotals(answers: 2, correct: 1, rounds: 1, practiceSeconds: 50,
                                                       daysPractised: 1, medianResponseMs: 2000))
        #expect(typed.recentRounds.map(\.id) == [keyboard])
        // Its time, score and attempts stay the whole round's.
        #expect(typed.days[4].practiceSeconds == 60 && typed.days.map(\.practiceSeconds).reduce(0, +) == 60)
        // A round with keys on screen and on a real piano counts for both.
        #expect(report(log, method: .piano).recentRounds.map(\.id) == [piano])
        #expect(report(log, method: .piano).totals.rounds == 1 && report(log, method: .piano).totals.answers == 1)
        #expect(report(log, method: .guitar).recentRounds.map(\.id) == [guitar])
        #expect(report(log, method: .buttons).recentRounds.map(\.id) == [buttons])
        // Every answer has one method, so the methods' answers add up to every answer.
        #expect(AnswerMethod.allCases.map { report(log, method: $0).totals.answers }.reduce(0, +) == 9)
    }

    @Test func theMethodAndClefFiltersBothApply() {
        let log = weekLog().log
        let bassButtons = report(log, clef: .bass, method: .buttons)
        #expect(bassButtons.totals.answers == 1 && bassButtons.totals.rounds == 1 && bassButtons.totals.practiceSeconds == 30)
        let trebleButtons = report(log, clef: .treble, method: .buttons)
        #expect(trebleButtons.totals == ProgressTotals(answers: 0, correct: 0, rounds: 0, practiceSeconds: 0, daysPractised: 0))
        #expect(trebleButtons.recentRounds.isEmpty && trebleButtons.positions.isEmpty && trebleButtons.byInput.isEmpty)
        #expect(trebleButtons.days.allSatisfy { $0.methods.isEmpty })
        let guitar = report(log, clef: .treble8vb, method: .guitar)
        #expect(guitar.totals.answers == 2 && guitar.totals.rounds == 1)
        #expect(report(log, clef: .treble, method: .guitar).totals.rounds == 0)
        // The treble clef alone: every method's rounds with treble notes.
        #expect(report(log, clef: .treble).totals.rounds == 2)
    }

    @Test func piecesFollowTheMethodFilter() {
        var log = Log()
        let minuet = PieceContext(title: "Minuet in G", path: "/tmp/minuet.musicxml", part: "Piano", partIndex: 0,
                                  hand: "right", order: "inOrder", startBar: 1, oneNotePerChord: false, noteCount: 20,
                                  measureCount: 16)
        let played = log.round(at: at(1, 10), piece: minuet) { $0.answerInput = .piano }
        log.answer(played, at: at(1, 10, 0, 2), Pitch(.g, 4), ms: 2000, input: "piano", bar: 1, source: .midi)
        log.answer(played, at: at(1, 10, 0, 5), Pitch(.a, 4), correct: false, ms: 3000, input: "piano", bar: 2, source: .midi)
        log.answer(played, at: at(1, 10, 0, 8), Pitch(.b, 4), ms: 2500, input: "piano", bar: 2, source: .piano)
        log.end(played, at: at(1, 10, 0, 9), durationMs: 60_000, score: 2, attempts: 3, reason: .pieceComplete)
        let typed = log.round(at: at(0, 10)) { $0.answerInput = .keyboard }
        log.answer(typed, at: at(0, 10, 0, 1), Pitch(.c, 5), ms: 900, input: "keyboard", source: .typing)
        log.end(typed, at: at(0, 10, 0, 2), durationMs: 20_000, score: 1, attempts: 1)

        let real = report(log, method: .realPiano)
        #expect(real.pieces.count == 1)
        #expect(real.pieces.first.map { [$0.rounds, $0.answers, $0.correct] } == [1, 2, 1])
        #expect(real.pieces.first?.bars == [BarProgress(bar: 1, attempts: 1, correct: 1, medianResponseMs: 2000, rightSingleNotes: 1),
                                            BarProgress(bar: 2, attempts: 1, correct: 0)])
        let screen = report(log, method: .piano)
        #expect(screen.pieces.first?.bars == [BarProgress(bar: 2, attempts: 1, correct: 1, medianResponseMs: 2500, rightSingleNotes: 1)])
        #expect(report(log, method: .keyboard).pieces.isEmpty)
        #expect(report(log).pieces.first.map { [$0.rounds, $0.answers] } == [1, 3])
    }

    @Test func theSnapshotHasNoMethodSoCountsOnlyWithEveryMethod() {
        var log = Log()
        log.add(.statsSnapshot(StatsSnapshot(reason: "beforeUsageLog", noteStats: [
            "treble.F5": NoteStat(attempts: 10, correct: 7), "bass.G2": NoteStat(attempts: 6, correct: 6),
        ])), at: at(20, 9))
        let round = log.round(at: at(0, 10)) { $0.answerInput = .keyboard }
        log.answer(round, at: at(0, 10, 0, 1), Pitch(.f, 5), ms: 1000, input: "keyboard", source: .typing)
        log.end(round, at: at(0, 10, 0, 2), durationMs: 10_000, score: 1, attempts: 1)

        let every = report(log, .all)
        #expect(every.answersBeforeTracking == 16)
        #expect(every.positions.map(\.attempts) == [11, 6])
        // The clef filter alone keeps its clef's part, as before.
        #expect(report(log, .all, clef: .bass).answersBeforeTracking == 6)
        let typed = report(log, .all, method: .keyboard)
        #expect(typed.answersBeforeTracking == 0)
        #expect(typed.positions == [PositionProgress(clef: .treble, position: 8, natural: Pitch(.f, 5), attempts: 1, correct: 1,
                                                     medianResponseMs: 1000, attemptsBeforeTracking: 0,
                                                     recentMedianResponseMs: 1000, recentRightAnswers: 1)])
        #expect(typed.pitches.map(\.attempts) == [1])
        // Nothing of the guitar: empty, the snapshot not counted.
        #expect(report(log, .all, method: .guitar).isEmpty)
        // The clefs practised still count the snapshot's.
        #expect(typed.clefsPractised == [.treble, .bass])
    }

    // MARK: - 3. Methods practised

    @Test func methodsPractisedIgnoreTheWindowAndFilters() {
        var log = Log()
        let old = log.round(at: at(40, 10))
        log.answer(old, at: at(40, 10, 0, 1), Pitch(.e, 4), ms: 1000)
        let before = log.round(at: at(10, 10)) { $0.answerInput = .guitar }
        log.answer(before, at: at(10, 10, 0, 10), Pitch(.e, 2), clef: .treble8vb, ms: 10_000, input: "guitar", source: .guitar)
        let typed = log.round(at: at(1, 10)) { $0.answerInput = .keyboard }
        log.answer(typed, at: at(1, 10, 0, 1), Pitch(.f, 4), ms: 1000, input: "keyboard", source: .typing)
        log.answer(typed, at: at(1, 10, 0, 2), Pitch(.g, 4), ms: 1000, input: "harp", source: .click)
        let played = log.round(at: at(0, 10)) { $0.answerInput = .piano }
        log.answer(played, at: at(0, 10, 0, 4), Pitch(.a, 4), correct: false, ms: 4000, input: "piano", source: .midi)

        let practised: Set<AnswerMethod> = [.buttons, .guitar, .keyboard, .realPiano]
        #expect(report(log).methodsPractised == practised)
        #expect(report(log, .all).methodsPractised == practised)
        let narrow = report(log, clef: .bass, method: .piano)
        #expect(narrow.totals.answers == 0 && narrow.methodsPractised == practised)
        // So the filter offers them, and the one chosen.
        #expect(ProgressFilter.methodChoices(for: narrow, selected: .piano) == [.keyboard, .buttons, .realPiano, .piano, .guitar])
        #expect(report(Log()).methodsPractised.isEmpty)
    }

    // MARK: - 4. The window before, by method

    @Test func theWindowBeforeIsSplitByMethodToo() {
        let log = weekLog().log
        let week = report(log)
        #expect(week.previousByInput == [
            BreakdownRow(key: "keyboard", answers: 2, correct: 1, medianResponseMs: 2000),
            BreakdownRow(key: "midi", answers: 1, correct: 1, medianResponseMs: 6000),
        ])
        #expect(report(log, method: .realPiano).previousByInput == [BreakdownRow(key: "midi", answers: 1, correct: 1,
                                                                                 medianResponseMs: 6000)])
        #expect(report(log, method: .guitar).previousByInput == [])
        #expect(report(log, clef: .bass).previousByInput == [])
        // A month back takes the whole log in; the month before has nothing.
        #expect(report(log, .month).previousByInput == [])
        #expect(report(log, .all).previousByInput == nil)
        #expect(report(log, .all, method: .keyboard).previousByInput == nil)
    }

    @Test func theWindowBeforeSortsLikeTheWindow() {
        var log = Log()
        let round = log.round(at: at(10, 10))
        log.answer(round, at: at(10, 10, 0, 1), Pitch(.e, 4), ms: 1000, input: "piano", source: .piano)
        log.answer(round, at: at(10, 10, 0, 2), Pitch(.f, 4), ms: 1000, input: "keyboard", source: .typing)
        log.answer(round, at: at(10, 10, 0, 3), Pitch(.g, 4), ms: 1000, input: "guitar", source: .guitar)
        log.answer(round, at: at(10, 10, 0, 4), Pitch(.a, 4), ms: 1000, input: "guitar", source: .guitar)
        #expect(report(log).previousByInput?.map(\.key) == ["guitar", "keyboard", "piano"])
        #expect(report(log).byInput.isEmpty)
    }

    // MARK: - 5. Each day by method

    @Test func eachMethodsPartOfADayIsCountedAsTheDayIs() {
        var log = Log()
        let typed = log.round(at: at(2, 10)) { $0.answerInput = .keyboard }
        log.answer(typed, at: at(2, 10, 0, 1), Pitch(.e, 4), ms: 1000, input: "keyboard", source: .typing)
        log.answer(typed, at: at(2, 10, 0, 3), Pitch(.g, 4), ms: 1400, input: "keyboard", source: .typing)
        log.answer(typed, at: at(2, 10, 0, 4), Pitch(.b, 4), correct: false, ms: 800, input: "keyboard", source: .typing)
        // Named together: in the medians, not the quartiles.
        log.chord(typed, at: at(2, 10, 0, 6), [Pitch(.c, 5), Pitch(.e, 5)], ms: 2000, input: "keyboard", source: .typing)
        let played = log.round(at: at(2, 11)) { $0.answerInput = .piano }
        log.answer(played, at: at(2, 11, 0, 3), Pitch(.e, 4), ms: 3000, input: "piano", source: .piano)
        log.answer(played, at: at(2, 11, 0, 8), Pitch(.f, 4), ms: 5000, input: "piano", source: .midi)
        log.answer(played, at: at(2, 11, 0, 12), Pitch(.a, 4), correct: false, ms: 4000, input: "piano", source: .midi)
        log.answer(played, at: at(2, 11, 0, 17), Pitch(.d, 5), ms: 4600, input: "piano", source: .midi)
        log.answer(played, at: at(2, 11, 0, 18), Pitch(.c, 5), ms: 700, input: "harp")
        let guitar = log.round(at: at(1, 18)) { $0.answerInput = .guitar }
        log.answer(guitar, at: at(1, 18, 0, 16), Pitch(.e, 2), clef: .treble8vb, ms: 16_000, input: "guitar", source: .guitar)
        log.answer(guitar, at: at(1, 18, 0, 28), Pitch(.e, 3), clef: .treble8vb, correct: false, ms: 12_000, input: "guitar",
                   source: .guitar)

        let week = report(log)
        let day = week.days[4]
        #expect(day.day == at(2, 0) && day.answers == 10 && day.correct == 8)
        // In `AnswerMethod` order; the harp's answer in the day but in no method.
        #expect(day.methods == [
            MethodDay(method: .keyboard, answers: 5, correct: 4, medianResponseMs: 1700, lowerQuartileMs: 1100,
                      upperQuartileMs: 1300, rightSingleNotes: 2),
            MethodDay(method: .realPiano, answers: 3, correct: 2, medianResponseMs: 4800, lowerQuartileMs: 4700,
                      upperQuartileMs: 4900, rightSingleNotes: 2),
            MethodDay(method: .piano, answers: 1, correct: 1, medianResponseMs: 3000, lowerQuartileMs: 3000,
                      upperQuartileMs: 3000, rightSingleNotes: 1),
        ])
        #expect(day.methods.map(\.answers).reduce(0, +) == day.answers - 1)
        #expect(week.days[5].methods == [MethodDay(method: .guitar, answers: 2, correct: 1, medianResponseMs: 16_000,
                                                   lowerQuartileMs: 16_000, upperQuartileMs: 16_000, rightSingleNotes: 1)])
        // Days without answers have no methods.
        #expect([0, 1, 2, 3, 6].allSatisfy { week.days[$0].answers == 0 && week.days[$0].methods.isEmpty })

        // A method filter leaves only its part, which is then the day's.
        let typedOnly = report(log, method: .keyboard).days[4]
        #expect(typedOnly.answers == 5 && typedOnly.medianResponseMs == 1700)
        #expect(typedOnly.lowerQuartileMs == 1100 && typedOnly.upperQuartileMs == 1300)
        #expect(typedOnly.methods == [day.methods[0]])
        #expect(report(log, clef: .bass, method: .keyboard).days.allSatisfy { $0.methods.isEmpty })
        // The clef filter splits a method's part too.
        #expect(report(log, clef: .treble8vb).days[5].methods == week.days[5].methods)
        #expect(report(log, clef: .treble8vb).days[4].methods.isEmpty)
    }

    @Test func aDaysMethodsAddUpToItsAnswersInALongLog() {
        let events = SyntheticUsage.events(days: 90, seed: 3, now: now, calendar: calendar)
        let quarter = report(events, .quarter)
        #expect(quarter.totals.answers > 3000)
        for day in quarter.days {
            #expect(day.methods.map(\.answers).reduce(0, +) == day.answers)
            #expect(day.methods.map(\.correct).reduce(0, +) == day.correct)
            let order = day.methods.map { AnswerMethod.allCases.firstIndex(of: $0.method)! }
            #expect(order == order.sorted() && Set(order).count == order.count)
            #expect(day.methods.allSatisfy { $0.answers > 0 && $0.rightSingleNotes <= $0.correct })
        }
        // Each method's report is its part of every day, and the parts add up.
        var answers = 0
        for method in quarter.methodsPractised {
            let alone = report(events, .quarter, method: method)
            let parts = quarter.days.flatMap(\.methods).filter { $0.method == method }
            #expect(alone.totals.answers == parts.map(\.answers).reduce(0, +))
            #expect(alone.totals.correct == parts.map(\.correct).reduce(0, +))
            #expect(alone.days.flatMap(\.methods) == parts)
            #expect(alone.byInput.map(\.key) == [method.rawValue])
            #expect(alone.positions.map(\.attempts).reduce(0, +) == alone.totals.answers)
            #expect(alone.previousByInput.map { $0.allSatisfy { $0.key == method.rawValue } } == true)
            answers += alone.totals.answers
        }
        #expect(answers == quarter.totals.answers)
        #expect(quarter.methodsPractised == [.keyboard, .buttons, .piano])
    }

    // MARK: - 6. A round's answers on a real piano

    @Test func aRoundCountsItsRealPianoAnswers() {
        var log = Log()
        let typed = log.round(at: at(1, 10)) { $0.answerInput = .keyboard }
        log.answer(typed, at: at(1, 10, 0, 1), Pitch(.c, 5), ms: 900, input: "keyboard", source: .typing)
        log.end(typed, at: at(1, 10, 0, 2), durationMs: 20_000, score: 1, attempts: 1)
        let played = log.round(at: at(0, 10)) { $0.answerInput = .piano }
        log.answer(played, at: at(0, 10, 0, 2), Pitch(.e, 4), ms: 2000, input: "piano", source: .piano)
        log.answer(played, at: at(0, 10, 0, 5), Pitch(.f, 4), ms: 3000, input: "piano", source: .midi)
        log.answer(played, at: at(0, 10, 0, 9), Pitch(.g, 2), clef: .bass, correct: false, ms: 4000, input: "piano",
                   source: .midi)
        // Its question lost from the log: left out of the statistics, but still an answer of the round.
        log.answer(played, at: at(0, 10, 0, 12), Pitch(.a, 4), ms: 3000, input: "piano", logQuestion: false, source: .midi)
        log.answer(played, at: at(0, 10, 0, 14), Pitch(.b, 4), ms: 2000, input: "piano", source: .piano)
        log.end(played, at: at(0, 10, 0, 15), durationMs: 60_000, score: 4, attempts: 5)

        let week = report(log)
        #expect(week.recentRounds.map(\.id) == [played, typed])
        #expect(week.recentRounds.map(\.realPianoAnswers) == [3, 0])
        #expect(week.byInput.first { $0.key == "midi" }?.answers == 2)
        // Whatever the filter, every answer of the round counts.
        #expect(report(log, method: .piano).recentRounds.map(\.realPianoAnswers) == [3])
        #expect(report(log, clef: .treble, method: .realPiano).recentRounds.map(\.realPianoAnswers) == [3])
        #expect(report(log, clef: .bass).recentRounds.map(\.realPianoAnswers) == [3])
        #expect(report(log, method: .keyboard).recentRounds.map(\.realPianoAnswers) == [0])
    }
}

private extension Log {
    /// Notes asked together as one chord and named at once, `ms` after they were shown.
    mutating func chord(_ round: UUID, at time: Date, _ notes: [Pitch], clef: Clef = .treble, correct: Bool = true,
                        ms: Int, input: String, source: AnswerSource) {
        let group = UUID()
        let questions = notes.map { _ in UUID() }
        for (note, question) in zip(notes, questions) {
            add(.questionShown(QuestionShown(
                round: round, question: question, index: 0, clef: clef.rawValue, pitch: LoggedPitch(note),
                written: LoggedPitch(note), position: clef.position(of: note), keyFifths: 0, printedAccidental: nil,
                octaveShift: 0, pieceNote: nil, pickChance: nil, naming: "letters", input: input, hintsVisible: false,
                keyNamesVisible: false, group: group, groupSize: notes.count)),
                at: time.addingTimeInterval(-Double(ms) / 1000))
        }
        for (note, question) in zip(notes, questions) {
            add(.answerGiven(AnswerGiven(round: round, question: question, responseMs: ms, source: source,
                                         letter: note.letter.name, accidental: 0, name: note.letter.name, pitch: nil,
                                         correct: correct, wrongOctave: nil, keystrokes: [], scoreAfter: 0, streakAfter: 0,
                                         group: group, groupSize: notes.count)),
                at: time)
        }
    }
}
