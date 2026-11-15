import Foundation
import Testing
@testable import Clefwise

/// Random notes apart from pieces in Progress: the practice filter, the "Random notes / Pieces"
/// breakdown, the pieces offered, and the note when a range mixes them (2026-11-15).
@Suite struct PracticeFilterTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()
    private let now = usageTestTime("2026-11-15T15:00:00.000Z")

    private func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
    }

    private func piece(_ title: String, path: String) -> PieceContext {
        PieceContext(title: title, path: path, part: "Piano", partIndex: 0, hand: "right", order: "inOrder", startBar: 1,
                     oneNotePerChord: false, noteCount: 20, measureCount: 16)
    }

    private func report(_ log: Log, _ practice: PracticeFilter? = nil, range: ProgressFilter.Range = .week,
                        method: AnswerMethod? = nil) -> ProgressReport {
        var filter = ProgressFilter(range: range, clef: .all)
        filter.practice = practice
        filter.method = method
        return ProgressAnalyzer.report(from: log.events, filter: filter, now: now, calendar: calendar)
    }

    /// On the real piano: random notes read cold, slowly; the Comptine quickly; a minuet once, long ago.
    private func pianoLog() -> Log {
        var log = Log()
        let random = log.round(at: at(1, 10)) { $0.answerInput = .piano }
        log.answer(random, at: at(1, 10, 1), Pitch(.e, 4), ms: 3400, input: "piano", source: .midi)
        log.answer(random, at: at(1, 10, 2), Pitch(.g, 4), ms: 3600, input: "piano", source: .midi)
        log.answer(random, at: at(1, 10, 3), Pitch(.b, 4), correct: false, ms: 5000, input: "piano", source: .midi)
        log.end(random, at: at(1, 10, 4), durationMs: 60_000, score: 2, attempts: 3)
        let comptine = log.round(at: at(0, 9), piece: piece("Comptine", path: "/tmp/comptine.mxl")) { $0.answerInput = .piano }
        for second in 1...4 {
            log.answer(comptine, at: at(0, 9, 0, second), Pitch(.b, 4), ms: 600, input: "piano", bar: 1, source: .midi)
        }
        log.end(comptine, at: at(0, 9, 1), durationMs: 30_000, score: 4, attempts: 4)
        let minuet = log.round(at: at(40, 9), piece: piece("Minuet in G", path: "/tmp/minuet.mxl")) { $0.answerInput = .piano }
        log.answer(minuet, at: at(40, 9, 0, 1), Pitch(.d, 5), ms: 900, input: "piano", bar: 1)
        log.end(minuet, at: at(40, 9, 1), durationMs: 20_000, score: 1, attempts: 1)
        return log
    }

    @Test func randomNotesAndPiecesAreToldApart() {
        let week = report(pianoLog())
        #expect(week.totals.answers == 7)
        let kinds = Dictionary(uniqueKeysWithValues: week.byPractice.map { ($0.key, $0) })
        #expect(kinds[PracticeFilter.randomKey]?.answers == 3 && kinds[PracticeFilter.randomKey]?.medianResponseMs == 3500)
        #expect(kinds[PracticeFilter.piecesKey]?.answers == 4 && kinds[PracticeFilter.piecesKey]?.medianResponseMs == 600)
    }

    @Test func theFilterKeepsOnlyThatPractice() {
        let log = pianoLog()
        let random = report(log, .random)
        #expect(random.totals.answers == 3 && random.totals.rounds == 1 && random.totals.medianResponseMs == 3500)
        #expect(random.pieces.isEmpty)
        #expect(random.days.flatMap(\.methods).map(\.answers).reduce(0, +) == 3)

        let pieces = report(log, .pieces)
        #expect(pieces.totals.answers == 4 && pieces.totals.rounds == 1 && pieces.totals.medianResponseMs == 600)
        #expect(pieces.pieces.map(\.title) == ["Comptine"])

        // One piece, by its key (here its path: no journal id).
        let comptine = report(log, .piece("/tmp/comptine.mxl"), range: .all)
        #expect(comptine.totals.answers == 4)
        let minuet = report(log, .piece("/tmp/minuet.mxl"), range: .all)
        #expect(minuet.totals.answers == 1 && minuet.totals.rounds == 1)
        #expect(report(log, .piece("/tmp/elsewhere.mxl"), range: .all).totals.answers == 0)

        // With a method filter too.
        #expect(report(log, .random, method: .piano).totals.answers == 0)
        #expect(report(log, .pieces, method: .realPiano).totals.answers == 4)
    }

    @Test func piecesPractisedAreOfferedWhateverTheFilter() {
        let filtered = report(pianoLog(), .random)
        // Most recently practised first, the minuet's 40 days ago outside the week too.
        #expect(filtered.piecesPractised.map(\.title) == ["Comptine", "Minuet in G"])
        #expect(filtered.piecesPractised.map(\.id) == ["/tmp/comptine.mxl", "/tmp/minuet.mxl"])
        #expect(filtered.hasRandomPractice)
        #expect(PracticeFilter.piece("/tmp/minuet.mxl").label(in: filtered) == "Minuet in G")
        #expect(PracticeFilter.piece("/tmp/gone.mxl").label(in: filtered) == "A piece")
        #expect(PracticeFilter.random.label(in: filtered) == "Random notes")

        var log = Log()
        let only = log.round(at: at(0, 9), piece: piece("Comptine", path: "/tmp/comptine.mxl"))
        log.answer(only, at: at(0, 9, 0, 1), Pitch(.b, 4), ms: 600, bar: 1)
        #expect(!report(log).hasRandomPractice)
    }

    @Test func theSnapshotCountsOnlyWithAllPractice() {
        var log = pianoLog()
        log.add(.statsSnapshot(StatsSnapshot(reason: "beforeUsageLog", noteStats: ["treble.E4": NoteStat(attempts: 10, correct: 9)])),
                at: at(60, 8))
        #expect(report(log, range: .all).answersBeforeTracking == 10)
        #expect(report(log, .random, range: .all).answersBeforeTracking == 0)
    }

    @Test func theFilterReadsOldAndNewSaves() throws {
        let decode = { (json: String) in try JSONDecoder().decode(ProgressFilter.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"range":"week","clef":"all","method":"midi"}"#).practice == nil)
        #expect(try decode(#"{"range":"week","clef":"all","practice":{"someday":{}}}"#).practice == nil)
        for practice in [PracticeFilter.random, .pieces, .piece("ab12")] {
            var filter = ProgressFilter(range: .month, clef: .treble)
            filter.practice = practice
            #expect(try decode(String(decoding: JSONEncoder().encode(filter), as: UTF8.self)) == filter)
        }
    }

    @Test func theNoteSaysWhenPracticeIsMixed() {
        let mixed = report(pianoLog())
        #expect(MixedMethodsNote.mixesPractice(in: mixed))
        #expect(!MixedMethodsNote.mixesPractice(in: report(pianoLog(), .random)))
        // Only the real piano in the week: the methods aren't mixed, the practice is.
        #expect(MixedMethodsNote.methods(in: mixed) == nil)
        #expect(MixedMethodsNote(methods: [], mixesPractice: true).text.hasPrefix("This range has random notes and pieces."))
        #expect(MixedMethodsNote(methods: [.keyboard, .realPiano], mixesPractice: true).text
            .hasPrefix("This range has answers from Keyboard and Real piano, from random notes and from pieces"))
    }
}
