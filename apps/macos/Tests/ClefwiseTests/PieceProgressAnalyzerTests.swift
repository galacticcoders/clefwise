import Foundation
import Testing
@testable import Clefwise

/// A piece's own progress worked out from the log (2026-11-15): each bar's time, and day by day the
/// start of a bar (the first note on arriving in it, in a round going in order) against the rest.
@Suite struct PieceProgressAnalyzerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()
    /// Sunday 15 November 2026, 16:00 in Stockholm.
    private let now = usageTestTime("2026-11-15T15:00:00.000Z")
    private let path = "/tmp/comptine.mxl"

    private func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
    }

    private func day(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
    }

    private func comptine(_ order: Game.PieceSettings.Order = .inOrder) -> PieceContext {
        PieceContext(title: "Comptine", path: path, part: "Piano", partIndex: 0, hand: "right", order: order.rawValue,
                     startBar: 1, oneNotePerChord: false, noteCount: 40, measureCount: 16)
    }

    private func report(_ log: Log, range: ProgressFilter.Range = .week, clef: ProgressFilter.ClefFilter = .all,
                        method: AnswerMethod? = nil, practice: PracticeFilter? = nil) -> ProgressReport {
        var filter = ProgressFilter(range: range, clef: clef)
        filter.method = method
        filter.practice = practice
        return ProgressAnalyzer.report(from: log.events, filter: filter, now: now, calendar: calendar)
    }

    /// The piece's days in `report` (none when the piece isn't there).
    private func days(_ report: ProgressReport) -> [PieceDay] {
        report.pieces.first { $0.id == path }?.days ?? []
    }

    // MARK: - Bars

    @Test func aBarsTimeIsTheMedianOfItsRightSingleNotesInAnyOrder() throws {
        var log = Log()
        let inOrder = log.round(at: at(1, 9), piece: comptine())
        log.notes(inOrder, from: at(1, 9), [(bar: 2, ms: 800), (bar: 2, ms: 1200)])
        log.answer(inOrder, at: at(1, 9, 1), Pitch(.c, 5), correct: false, ms: 5000, bar: 2)
        log.answer(inOrder, at: at(1, 9, 2), Pitch(.c, 5), correct: false, ms: 900, bar: 3)
        // Notes named together share one time: counted in the bar, not in its time.
        log.together(inOrder, at: at(1, 9, 3), [Pitch(.c, 5), Pitch(.e, 5)], bar: 2, ms: 3000)
        let shuffled = log.round(at: at(1, 10), piece: comptine(.shuffled))
        log.answer(shuffled, at: at(1, 10, 1), Pitch(.c, 5), ms: 1000, bar: 2)

        let piece = try #require(report(log).pieces.first)
        #expect(piece.bars == [
            BarProgress(bar: 2, attempts: 6, correct: 5, medianResponseMs: 1000, rightSingleNotes: 3),
            BarProgress(bar: 3, attempts: 1, correct: 0, medianResponseMs: nil, rightSingleNotes: 0),
        ])
    }

    // MARK: - The start of a bar and the rest

    @Test func theStartOfABarIsToldFromTheRestLeavingTheFirstQuestionOut() {
        var log = Log()
        let round = log.round(at: at(0, 9), piece: comptine())
        // The first question takes getting ready: it's in neither.
        log.notes(round, from: at(0, 9), [(bar: 1, ms: 6000), (bar: 1, ms: 900), (bar: 1, ms: 700),
                                          (bar: 2, ms: 4000), (bar: 2, ms: 800), (bar: 3, ms: 3000), (bar: 3, ms: 600)])

        #expect(days(report(log)) == [PieceDay(day: day(0), answers: 7, correct: 7, barStartMs: 3500, barStarts: 2,
                                               restOfBarMs: 750, restOfBar: 4, methods: [.keyboard])])
        // Each bar's time takes in every right single note, the first question too.
        #expect(report(log).pieces.first?.bars.first?.medianResponseMs == 900)
    }

    @Test func wrongAnswersAreInNeitherTime() {
        var log = Log()
        let round = log.round(at: at(0, 9), piece: comptine())
        log.notes(round, from: at(0, 9), [(bar: 1, ms: 2000), (bar: 2, ms: 5000), (bar: 2, ms: 800), (bar: 2, ms: 2000),
                                          (bar: 3, ms: 2500)],
                  wrong: [1, 3])

        // Bar 2 started with a wrong answer: its next note is still the rest of the bar.
        #expect(days(report(log)) == [PieceDay(day: day(0), answers: 5, correct: 3, barStartMs: 2500, barStarts: 1,
                                               restOfBarMs: 800, restOfBar: 1, methods: [.keyboard])])
    }

    @Test func aShuffledRoundCountsOnlyInAnswersAndCorrect() {
        var log = Log()
        let round = log.round(at: at(0, 9), piece: comptine(.shuffled))
        log.notes(round, from: at(0, 9), [(bar: 3, ms: 2000), (bar: 1, ms: 3000), (bar: 3, ms: 900), (bar: 2, ms: 2500)],
                  wrong: [3])
        // Random notes aren't the piece's at all.
        let random = log.round(at: at(0, 10))
        log.answer(random, at: at(0, 10, 1), Pitch(.c, 5), ms: 1000, input: "keyboard", source: .typing)

        let report = report(log)
        #expect(report.pieces.count == 1)
        #expect(days(report) == [PieceDay(day: day(0), answers: 4, correct: 3, barStartMs: nil, barStarts: 0,
                                          restOfBarMs: nil, restOfBar: 0, methods: [.keyboard])])
    }

    @Test func notesNamedTogetherStartABarOnce() {
        var log = Log()
        let round = log.round(at: at(0, 9), piece: comptine())
        // The round's first question is a group: neither.
        log.together(round, at: at(0, 9, 0, 10), [Pitch(.a, 4), Pitch(.c, 5)], bar: 1, ms: 5000)
        log.answer(round, at: at(0, 9, 0, 20), Pitch(.e, 5), ms: 700, input: "keyboard", bar: 1, source: .typing)
        // Into bar 2: the group's first question starts it, with the group's time; its other notes
        // are in neither.
        log.together(round, at: at(0, 9, 0, 30), [Pitch(.b, 4), Pitch(.d, 5), Pitch(.g, 5)], bar: 2, ms: 2400)
        log.answer(round, at: at(0, 9, 0, 40), Pitch(.e, 5), ms: 900, input: "keyboard", bar: 2, source: .typing)
        // A group within the bar is in neither.
        log.together(round, at: at(0, 9, 0, 50), [Pitch(.a, 4), Pitch(.c, 5)], bar: 2, ms: 1800)

        #expect(days(report(log)) == [PieceDay(day: day(0), answers: 9, correct: 9, barStartMs: 2400, barStarts: 1,
                                               restOfBarMs: 800, restOfBar: 2, methods: [.keyboard])])
        // A bar's time is its single notes'.
        #expect(report(log).pieces.first?.bars.map(\.rightSingleNotes) == [1, 1])
    }

    @Test func aGroupNamedWrongFirstDoesntStartTheBar() {
        var log = Log()
        let round = log.round(at: at(0, 9), piece: comptine())
        log.notes(round, from: at(0, 9), [(bar: 1, ms: 3000)])
        log.together(round, at: at(0, 9, 1), [Pitch(.b, 4), Pitch(.d, 5)], bar: 2, ms: 2400, wrong: [0])
        log.together(round, at: at(0, 9, 2), [Pitch(.c, 5), Pitch(.e, 5)], bar: 3, ms: 2000, wrong: [1])

        // The group's time is its first note's answer: counted when that one is right.
        #expect(days(report(log)) == [PieceDay(day: day(0), answers: 5, correct: 3, barStartMs: 2000, barStarts: 1,
                                               restOfBarMs: nil, restOfBar: 0, methods: [.keyboard])])
    }

    @Test func aRestoredRoundStartsAfresh() {
        var log = Log()
        let round = log.round(at: at(0, 9), piece: comptine())
        log.notes(round, from: at(0, 9), [(bar: 1, ms: 3000), (bar: 1, ms: 700)])
        // The app crashed with bar 2's first note on screen; back, it's asked again as a new
        // question. Finding the place again is getting ready: the next question is in neither.
        let lost = log.shown(round, at: at(0, 9, 1), Pitch(.d, 5), bar: 2)
        log.add(.roundRestored(RoundRestored(round: round, activeMs: 20_000, unansweredQuestion: lost)), at: at(0, 9, 5))
        log.notes(round, from: at(0, 9, 6), [(bar: 2, ms: 3500), (bar: 2, ms: 800), (bar: 3, ms: 2500)])

        #expect(days(report(log)) == [PieceDay(day: day(0), answers: 5, correct: 5, barStartMs: 2500, barStarts: 1,
                                               restOfBarMs: 750, restOfBar: 2, methods: [.keyboard])])
    }

    // MARK: - Days

    @Test func daysComeOldestFirstWithTheirMethods() {
        var log = Log()
        let typed = log.round(at: at(2, 20), piece: comptine())
        log.notes(typed, from: at(2, 20), [(bar: 1, ms: 5000), (bar: 1, ms: 1300), (bar: 2, ms: 4300), (bar: 2, ms: 1100)])
        let played = log.round(at: at(0, 9), piece: comptine())
        log.notes(played, from: at(0, 9), [(bar: 1, ms: 9000), (bar: 2, ms: 7600), (bar: 2, ms: 1000)],
                  input: "piano", source: .midi)
        let clicked = log.round(at: at(0, 10), piece: comptine())
        log.notes(clicked, from: at(0, 10), [(bar: 5, ms: 4000)], input: "buttons", source: .click)

        #expect(days(report(log)) == [
            PieceDay(day: day(2), answers: 4, correct: 4, barStartMs: 4300, barStarts: 1, restOfBarMs: 1200, restOfBar: 2,
                     methods: [.keyboard]),
            PieceDay(day: day(0), answers: 4, correct: 4, barStartMs: 7600, barStarts: 1, restOfBarMs: 1000, restOfBar: 1,
                     methods: [.buttons, .realPiano]),
        ])
    }

    @Test func aDayGoesByLocalTime() {
        var log = Log()
        let round = log.round(at: at(1, 23, 59), piece: comptine())
        // 23:59:10 yesterday and 00:00:10 today, Stockholm time.
        log.answer(round, at: at(1, 23, 59, 10), Pitch(.c, 5), ms: 3000, input: "keyboard", bar: 1, source: .typing)
        log.answer(round, at: at(0, 0, 0, 10), Pitch(.c, 5), ms: 4000, input: "keyboard", bar: 2, source: .typing)

        #expect(days(report(log)).map(\.day) == [day(1), day(0)])
        #expect(days(report(log)).map(\.barStarts) == [0, 1])
    }

    // MARK: - Filters

    /// On the piano: keys on a real piano and on the one on screen in one round, a bass note, and a
    /// round ten days ago.
    private func filterLog() -> Log {
        var log = Log()
        let old = log.round(at: at(10, 9), piece: comptine())
        log.notes(old, from: at(10, 9), [(bar: 1, ms: 4000), (bar: 2, ms: 4300)], input: "piano", source: .midi)
        let round = log.round(at: at(0, 9), piece: comptine())
        log.answer(round, at: at(0, 9, 0, 10), Pitch(.c, 5), ms: 5000, input: "piano", bar: 1, source: .midi)
        // Into bar 2 on the screen's piano, then on with the real one.
        log.answer(round, at: at(0, 9, 0, 20), Pitch(.d, 5), ms: 2000, input: "piano", bar: 2, source: .piano)
        log.answer(round, at: at(0, 9, 0, 30), Pitch(.e, 5), ms: 800, input: "piano", bar: 2, source: .midi)
        // Bar 3 starts with a bass note.
        log.answer(round, at: at(0, 9, 0, 40), Pitch(.c, 3), clef: .bass, ms: 3000, input: "piano", bar: 3, source: .midi)
        log.answer(round, at: at(0, 9, 0, 50), Pitch(.g, 4), ms: 600, input: "piano", bar: 3, source: .midi)
        return log
    }

    @Test func theMethodFilterLeavesAnswersOutButNotTheQuestionBefore() {
        let log = filterLog()
        #expect(days(report(log)) == [PieceDay(day: day(0), answers: 5, correct: 5, barStartMs: 2500, barStarts: 2,
                                               restOfBarMs: 700, restOfBar: 2, methods: [.realPiano, .piano])])
        // Bar 2's first note was on the screen's piano: with the real piano alone, bar 2 has no start,
        // and its next note is still the rest of the bar.
        #expect(days(report(log, method: .realPiano)) == [
            PieceDay(day: day(0), answers: 4, correct: 4, barStartMs: 3000, barStarts: 1, restOfBarMs: 700, restOfBar: 2,
                     methods: [.realPiano]),
        ])
        #expect(days(report(log, method: .piano)) == [
            PieceDay(day: day(0), answers: 1, correct: 1, barStartMs: 2000, barStarts: 1, restOfBarMs: nil, restOfBar: 0,
                     methods: [.piano]),
        ])
        #expect(days(report(log, method: .keyboard)).isEmpty)
    }

    @Test func theClefFilterLeavesAnswersOut() {
        // Bar 3 started with the bass note: in treble its next note is still the rest of the bar.
        #expect(days(report(filterLog(), clef: .treble)) == [
            PieceDay(day: day(0), answers: 4, correct: 4, barStartMs: 2000, barStarts: 1, restOfBarMs: 700, restOfBar: 2,
                     methods: [.realPiano, .piano]),
        ])
        #expect(days(report(filterLog(), clef: .bass)) == [
            PieceDay(day: day(0), answers: 1, correct: 1, barStartMs: 3000, barStarts: 1, restOfBarMs: nil, restOfBar: 0,
                     methods: [.realPiano]),
        ])
    }

    @Test func thePracticeFilterKeepsThePieceOrNot() {
        let log = filterLog()
        let all = days(report(log))
        #expect(days(report(log, practice: .pieces)) == all)
        #expect(days(report(log, practice: .piece(path))) == all)
        #expect(days(report(log, practice: .piece("/tmp/elsewhere.mxl"))).isEmpty)
        #expect(days(report(log, practice: .random)).isEmpty)
    }

    @Test func daysAreTheWindowsOnly() {
        let log = filterLog()
        #expect(days(report(log)).map(\.day) == [day(0)])
        let month = days(report(log, range: .month))
        #expect(month.map(\.day) == [day(10), day(0)])
        #expect(month.first == PieceDay(day: day(10), answers: 2, correct: 2, barStartMs: 4300, barStarts: 1,
                                        restOfBarMs: nil, restOfBar: 0, methods: [.realPiano]))
        #expect(days(report(log, range: .all)) == month)
    }
}

private extension Log {
    /// Single notes answered one after another, ten seconds apart from `start`, each `ms` after it
    /// was shown; the answers at the offsets in `wrong` named wrong.
    mutating func notes(_ round: UUID, from start: Date, _ notes: [(bar: Int, ms: Int)], wrong: Set<Int> = [],
                        input: String = "keyboard", source: AnswerSource = .typing) {
        for (offset, note) in notes.enumerated() {
            answer(round, at: start.addingTimeInterval(Double(offset + 1) * 10), Pitch(.c, 5), correct: !wrong.contains(offset),
                   ms: note.ms, input: input, bar: note.bar, source: source)
        }
    }

    /// Notes in `bar` asked together and named at once, `ms` after they were shown; the notes at
    /// the offsets in `wrong` named wrong.
    mutating func together(_ round: UUID, at time: Date, _ notes: [Pitch], bar: Int, ms: Int, wrong: Set<Int> = [],
                           input: String = "keyboard", source: AnswerSource = .typing) {
        let group = UUID()
        let questions = notes.map { _ in UUID() }
        for (offset, (note, question)) in zip(notes, questions).enumerated() {
            add(.questionShown(QuestionShown(
                round: round, question: question, index: 0, clef: Clef.treble.rawValue, pitch: LoggedPitch(note),
                written: LoggedPitch(note), position: Clef.treble.position(of: note), keyFifths: 0, printedAccidental: nil,
                octaveShift: 0, pieceNote: PieceNoteRef(measure: bar, staff: 1, onset: 0, chord: offset), pickChance: nil,
                naming: "letters", input: input, hintsVisible: false, keyNamesVisible: false, group: group,
                groupSize: notes.count)),
                at: time.addingTimeInterval(-Double(ms) / 1000))
        }
        for (offset, (note, question)) in zip(notes, questions).enumerated() {
            add(.answerGiven(AnswerGiven(round: round, question: question, responseMs: ms, source: source,
                                         letter: note.letter.name, accidental: 0, name: note.letter.name, pitch: nil,
                                         correct: !wrong.contains(offset), wrongOctave: nil, keystrokes: [], scoreAfter: 0,
                                         streakAfter: 0, group: group, groupSize: notes.count)),
                at: time)
        }
    }

    /// A single note shown in `bar` at `time` and never answered; its question's id.
    mutating func shown(_ round: UUID, at time: Date, _ note: Pitch, bar: Int) -> UUID {
        let question = UUID()
        add(.questionShown(QuestionShown(
            round: round, question: question, index: 0, clef: Clef.treble.rawValue, pitch: LoggedPitch(note),
            written: LoggedPitch(note), position: Clef.treble.position(of: note), keyFifths: 0, printedAccidental: nil,
            octaveShift: 0, pieceNote: PieceNoteRef(measure: bar, staff: 1, onset: 0, chord: 0), pickChance: nil,
            naming: "letters", input: "keyboard", hintsVisible: false, keyNamesVisible: false)),
            at: time)
        return question
    }
}
