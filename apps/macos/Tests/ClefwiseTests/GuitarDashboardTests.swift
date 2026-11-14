import Foundation
import Testing
@testable import Clefwise

/// The dashboard with answers in the guitar clef (`Clef.treble8vb`, "Guitar"): its own note map
/// column and clef filter, but only once there are answers in it; without any, everything is as
/// before.
@Suite struct GuitarDashboardTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()
    private let now = usageTestTime("2026-11-14T15:00:00.000Z")

    private func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
    }

    private func report(_ log: Log, _ range: ProgressFilter.Range = .week, clef: ProgressFilter.ClefFilter = .all) -> ProgressReport {
        ProgressAnalyzer.report(from: log.events, filter: ProgressFilter(range: range, clef: clef), now: now, calendar: calendar)
    }

    /// A round of treble notes on the note buttons, then one answered on the guitar in the guitar
    /// clef: the open low E (E2, below the third ledger line) twice, and the bottom line (E3).
    private func mixedLog() -> Log {
        var log = Log()
        let treble = log.round(at: at(2, 10))
        log.answer(treble, at: at(2, 10, 1), Pitch(.e, 4), ms: 900)
        log.answer(treble, at: at(2, 10, 2), Pitch(.c, 5), correct: false, ms: 1500)
        log.end(treble, at: at(2, 10, 3), durationMs: 60_000, score: 1, attempts: 2)
        let guitar = log.round(at: at(1, 18)) { $0.answerInput = .guitar }
        log.answer(guitar, at: at(1, 18, 1), Pitch(.e, 2), clef: .treble8vb, ms: 2000, input: "guitar")
        log.answer(guitar, at: at(1, 18, 2), Pitch(.e, 2), clef: .treble8vb, correct: false, ms: 2500, input: "guitar")
        log.answer(guitar, at: at(1, 18, 3), Pitch(.e, 3), clef: .treble8vb, ms: 1200, input: "guitar")
        log.end(guitar, at: at(1, 18, 4), durationMs: 90_000, score: 2, attempts: 3)
        return log
    }

    private func trebleOnlyLog() -> Log {
        var log = Log()
        let round = log.round(at: at(1, 9))
        log.answer(round, at: at(1, 9, 1), Pitch(.g, 4), ms: 800)
        log.answer(round, at: at(1, 9, 2), Pitch(.a, 4), ms: 700)
        log.end(round, at: at(1, 9, 3), durationMs: 30_000, score: 2, attempts: 2)
        return log
    }

    // MARK: With guitar answers

    @Test func guitarAnswersCountLikeAnyOther() {
        let week = report(mixedLog())
        #expect(week.totals.answers == 5 && week.totals.correct == 3 && week.totals.rounds == 2)
        // Places by the written position: treble first, then the guitar clef after bass.
        #expect(week.positions.map(\.id) == ["treble0", "treble5", "treble8vb-7", "treble8vb0"])
        let lowE = week.positions[2]
        #expect(lowE.clef == .treble8vb && lowE.position == -7 && lowE.natural == Pitch(.e, 2))
        #expect(lowE.attempts == 2 && lowE.correct == 1)
        #expect(week.pitches.map(\.id) == ["treble.E4", "treble.C5", "treble8vb.E2", "treble8vb.E3"])
        #expect(week.clefsPractised == [.treble, .treble8vb])
    }

    @Test func theGuitarIsAnAnswerMethodOfItsOwn() {
        let week = report(mixedLog())
        #expect(week.byInput.map(\.key) == ["guitar", "buttons"])
        #expect(week.byInput.map { Game.AnswerInput(rawValue: $0.key)?.label } == ["Guitar", "Note buttons"])
        #expect(week.byInput[0].answers == 3 && week.byInput[0].correct == 2)
        // Random notes answered on the guitar are guitar music, whatever the toolbar's clef says.
        #expect(week.recentRounds.map(\.input) == ["guitar", "buttons"])
        #expect(week.recentRounds.map(\.description) == ["Guitar · On the staff · C major", "Treble · On the staff · C major"])
    }

    @Test func theGuitarFilterCountsOnlyTheGuitarClef() {
        let guitar = report(mixedLog(), clef: .treble8vb)
        #expect(guitar.totals.answers == 3 && guitar.totals.rounds == 1)
        #expect(Set(guitar.positions.map(\.clef)) == [.treble8vb])
        #expect(NoteMapSection.clefs(for: guitar) == [.treble8vb])
        let treble = report(mixedLog(), clef: .treble)
        #expect(treble.totals.answers == 2 && Set(treble.positions.map(\.clef)) == [.treble])
        #expect(NoteMapSection.clefs(for: treble) == [.treble])
        // The journal has guitar answers whatever the filter shows, so Guitar stays on offer.
        #expect(treble.clefsPractised.contains(.treble8vb))
        #expect(ProgressFilter.ClefFilter.choices(for: treble, selected: .treble) == [.all, .treble, .bass, .treble8vb])
    }

    @Test func theNoteMapsShowTheGuitarClefBesideTrebleAndBass() {
        let week = report(mixedLog())
        #expect(NoteMapSection.clefs(for: week) == [.treble, .bass, .treble8vb])
        #expect(ProgressFilter.ClefFilter.choices(for: week, selected: .all) == [.all, .treble, .bass, .treble8vb])
        #expect(ProgressFilter.ClefFilter.treble8vb.label == "Guitar")
        // A window without guitar answers has no guitar column, though Guitar stays a filter.
        var log = mixedLog()
        let later = log.round(at: at(0, 9))
        log.answer(later, at: at(0, 9, 1), Pitch(.g, 2), clef: .bass)
        log.end(later, at: at(0, 9, 2), durationMs: 10_000, score: 1, attempts: 1)
        let today = ProgressAnalyzer.report(from: log.events, filter: ProgressFilter(range: .week, clef: .all),
                                            now: now.addingTimeInterval(6 * 86_400), calendar: calendar)
        #expect(today.positions.map(\.clef) == [.bass])
        #expect(NoteMapSection.clefs(for: today) == [.treble, .bass])
        #expect(ProgressFilter.ClefFilter.choices(for: today, selected: .all).contains(.treble8vb))
    }

    // MARK: Without guitar answers

    @Test func withoutGuitarAnswersEverythingIsAsBefore() {
        for range in ProgressFilter.Range.allCases {
            let report = report(trebleOnlyLog(), range)
            #expect(NoteMapSection.clefs(for: report) == [.treble, .bass])
            #expect(ProgressFilter.ClefFilter.choices(for: report, selected: .all) == [.all, .treble, .bass])
            #expect(report.clefsPractised == [.treble])
        }
        let empty = report(Log())
        #expect(NoteMapSection.clefs(for: empty) == [.treble, .bass])
        #expect(ProgressFilter.ClefFilter.choices(for: empty, selected: .bass) == [.all, .treble, .bass])
        #expect(ProgressFilter.ClefFilter.choices(for: .empty(ProgressFilter()), selected: .all) == [.all, .treble, .bass])
    }

    @Test func theSampleReportIsAsBefore() {
        let sample = ProgressReport.sample(now: now, calendar: calendar)
        #expect(Set(sample.positions.map(\.clef)) == [.treble, .bass])
        #expect(sample.clefsPractised.isEmpty)
        #expect(NoteMapSection.clefs(for: sample) == [.treble, .bass])
        #expect(ProgressFilter.ClefFilter.choices(for: sample, selected: .all) == [.all, .treble, .bass])
        #expect(sample == ProgressReport.sample(now: now, calendar: calendar))
    }

    /// Picked before, it stays on offer even while the report has nothing in it.
    @Test func theSavedGuitarFilterIsAlwaysOffered() {
        let report = report(trebleOnlyLog(), clef: .treble8vb)
        #expect(report.isEmpty)
        #expect(ProgressFilter.ClefFilter.choices(for: report, selected: .treble8vb) == [.all, .treble, .bass, .treble8vb])
        #expect(NoteMapSection.clefs(for: report) == [.treble8vb])
    }

    /// Opening balances in the guitar clef (none exist yet, but they'd key notes the same way).
    @Test func openingBalancesCountTowardsTheClefsPractised() {
        var log = Log()
        log.add(.statsSnapshot(StatsSnapshot(reason: "beforeUsageLog", noteStats: ["treble8vb.E2": NoteStat(attempts: 3, correct: 2)])), at: at(3, 9))
        #expect(report(log).clefsPractised == [.treble8vb])
        #expect(report(log, .all).positions.map(\.id) == ["treble8vb-7"])
    }

    // MARK: The saved filter

    @Test func savedFiltersDecodeTolerantly() throws {
        func decode(_ json: String) throws -> ProgressFilter {
            try JSONDecoder().decode(ProgressFilter.self, from: Data(json.utf8))
        }
        #expect(try decode(#"{"range":"week","clef":"bass"}"#) == ProgressFilter(range: .week, clef: .bass))
        #expect(try decode(#"{"range":"quarter","clef":"treble8vb"}"#) == ProgressFilter(range: .quarter, clef: .treble8vb))
        // A clef or range this version doesn't know loses only itself.
        #expect(try decode(#"{"range":"week","clef":"alto"}"#) == ProgressFilter(range: .week, clef: .all))
        #expect(try decode(#"{"range":"decade","clef":"bass"}"#) == ProgressFilter(range: .month, clef: .bass))
        #expect(try decode("{}") == ProgressFilter())
        let saved = ProgressFilter(range: .all, clef: .treble8vb)
        #expect(try JSONDecoder().decode(ProgressFilter.self, from: JSONEncoder().encode(saved)) == saved)
        #expect(String(decoding: try JSONEncoder().encode(ProgressFilter(range: .week, clef: .treble)), as: UTF8.self)
                .contains(#""clef":"treble""#))
    }
}
