import Foundation
import Testing
@testable import Clefwise

// `Game.refreshStats(from:)`: the note stats and best scores taken from the journal, read off the
// main thread, never mid-round and never behind the rounds the game has ended, the latest refresh
// winning (spec/practice-journal.md, "What stays on each device": the projections are a cache of
// the files).

@MainActor
@Suite final class GameStatsRefreshTests: GameTestBench {
    private let temporary = UsageTestFolder()

    private func folder(scoring score: Int) -> URL {
        temporary.url.appendingPathComponent("Journal \(score)", isDirectory: true)
    }

    /// A journal of its own: an opening balance, then a minute's sprint on the default settings in
    /// which `score` notes were named right. Returns its reader and what it folds to.
    private func journal(scoring score: Int) throws -> (reader: JournalReader, projection: JournalProjection) {
        let start = Date(timeIntervalSinceNow: -3600)
        var log = Log()
        log.add(.statsSnapshot(StatsSnapshot(reason: "beforeUsageLog", noteStats: ["bass.G2": NoteStat(attempts: 4, correct: 3)],
                                             bestScores: [:])), at: start)
        let round = log.round(at: start)
        for index in 0..<score { log.answer(round, at: start.addingTimeInterval(Double(index + 1)), Pitch(.e, 4)) }
        log.end(round, at: start.addingTimeInterval(60), durationMs: 60_000, score: score, attempts: score, reason: .timeUp)
        try TestJournal(folder: folder(scoring: score)).write(log.events)
        let projection = JournalProjection.read(journal: folder(scoring: score))
        #expect(projection.bestScores == [Game.bestScoreKey(for: Game.Settings()): score])
        return (JournalReader(folder: folder(scoring: score)), projection)
    }

    private func storedNoteStats() -> [String: NoteStat]? {
        defaults.data(forKey: Game.Keys.noteStats).flatMap { try? JSONDecoder().decode([String: NoteStat].self, from: $0) }
    }

    private func answersInStats() -> Int? {
        storedNoteStats()?.values.map(\.attempts).reduce(0, +)
    }

    /// Answers `count` notes right in a sprint, then stops it.
    private func playSprint(answering count: Int) {
        game.start()
        for _ in 0..<count { answerRight() }
        game.stop()
    }

    @Test func betweenRoundsTheJournalsStatsAreTakenAtOnce() async throws {
        let (reader, projection) = try journal(scoring: 7)
        game.refreshStats(from: reader)
        #expect(game.isRefreshingStats)
        try await waitUntil { !game.isRefreshingStats }
        #expect(game.bestScore == 7 && !game.hasStatsWaitingForRoundEnd)
        #expect(storedNoteStats() == projection.noteStats)

        // With a round's summary up, the round is over too; one without an answer has no run to wait
        // for.
        game.apply(projection: JournalProjection())
        playSprint(answering: 0)
        #expect(game.phase == .finished && game.summary != nil)
        game.refreshStats(from: reader)
        try await waitUntil { !game.isRefreshingStats }
        #expect(storedNoteStats() == projection.noteStats && game.bestScore == 7)
    }

    @Test func statsReadBeforeAFinishedRoundsRunArrivedAreDropped() async throws {
        let (reader, projection) = try journal(scoring: 7)
        game.refreshStats(from: reader)
        try await waitUntil { !game.isRefreshingStats }
        #expect(game.bestScore == 7)

        // A new best, whose run hasn't reached the journal yet.
        playSprint(answering: 8)
        let start = try #require(recorder.events.lastIndex { $0.event.type == "roundStarted" })
        #expect(game.summary?.isNewBest == true && game.bestScore == 8)
        #expect(answersInStats() == 4 + 7 + 8)
        game.refreshStats(from: reader)
        try await waitUntil { !game.isRefreshingStats }
        // No dip back to the journal's: nothing changed.
        #expect(game.bestScore == 8 && answersInStats() == 4 + 7 + 8)
        #expect(!game.hasStatsWaitingForRoundEnd)

        // Once the run is in, the next refresh is taken, with another Mac's practice that came too.
        try TestJournal(folder: folder(scoring: 7)).write(Array(recorder.events[start...]))
        var otherMac = Log()
        let round = otherMac.round(at: Date(timeIntervalSinceNow: -60)) { $0.clefChoice = .bass }
        otherMac.answer(round, at: Date(timeIntervalSinceNow: -59), Pitch(.g, 2), clef: .bass, correct: false)
        otherMac.end(round, at: Date(timeIntervalSinceNow: -58), durationMs: 2000, score: 0, attempts: 1)
        try TestJournal(folder: folder(scoring: 7)).write(otherMac.events, device: UUID())
        game.refreshStats(from: reader)
        try await waitUntil { !game.isRefreshingStats }
        let caughtUp = JournalProjection.read(journal: folder(scoring: 7))
        #expect(caughtUp.noteStats != projection.noteStats && caughtUp.runsRead == 3)
        #expect(storedNoteStats() == caughtUp.noteStats)
        #expect(game.bestScore == 8 && answersInStats() == 4 + 7 + 8 + 1)
    }

    @Test func midRoundTheyWaitForItsEndAndOnlyARoundWithoutAnAnswerLetsThemIn() async throws {
        let (first, _) = try journal(scoring: 7)
        let (second, projection) = try journal(scoring: 9)
        game.start()
        game.refreshStats(from: first)
        try await waitUntil { !game.isRefreshingStats }
        #expect(game.hasStatsWaitingForRoundEnd && game.bestScore == nil)

        // Paused, the round is still going; and a newer result replaces the one waiting.
        game.pause()
        game.refreshStats(from: second)
        try await waitUntil { !game.isRefreshingStats }
        try await Task.sleep(for: .milliseconds(50))
        #expect(game.hasStatsWaitingForRoundEnd && game.bestScore == nil)
        game.resume()

        // Ended without an answer, the round has no run, so the stats waiting are up to date.
        game.stop()
        try await waitUntil { !game.hasStatsWaitingForRoundEnd }
        #expect(game.bestScore == 9 && storedNoteStats() == projection.noteStats)

        // After a round with answers, the stats waiting are out of date: dropped, not taken.
        game.start()
        for _ in 0..<2 { answerRight() }
        game.refreshStats(from: second)
        try await waitUntil { !game.isRefreshingStats }
        #expect(game.hasStatsWaitingForRoundEnd)
        game.stop()
        try await waitUntil { !game.hasStatsWaitingForRoundEnd }
        try await Task.sleep(for: .milliseconds(50))
        #expect(game.bestScore == 9 && answersInStats() == 4 + 9 + 2)
    }

    @Test func startingOverKeepsThemWaitingForTheNewRoundsEnd() async throws {
        // Starting over drops the round, but another is playing at once: the stats wait for its end.
        let (reader, projection) = try journal(scoring: 5)
        game.start()
        game.refreshStats(from: reader)
        try await waitUntil { !game.isRefreshingStats }
        game.start()
        try await Task.sleep(for: .milliseconds(50))
        #expect(game.hasStatsWaitingForRoundEnd && game.bestScore == nil)
        game.appWillTerminate()
        try await waitUntil { !game.hasStatsWaitingForRoundEnd }
        #expect(game.phase == .idle && game.bestScore == 5)
        #expect(storedNoteStats() == projection.noteStats)
    }

    @Test func overlappingRefreshesKeepTheLatest() async throws {
        let journals = try [3, 5, 9].map { try journal(scoring: $0) }
        for journal in journals { game.refreshStats(from: journal.reader) }
        try await waitUntil { !game.isRefreshingStats }
        #expect(game.bestScore == 9)
        #expect(storedNoteStats() == journals[2].projection.noteStats)
    }
}
