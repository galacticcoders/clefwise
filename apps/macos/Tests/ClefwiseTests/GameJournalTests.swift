import Foundation
import Testing
@testable import Clefwise

// `Game` with several journals on one Mac: each journal's values under its own keys in the
// defaults, and the note stats taken from the journal (spec/practice-journal.md, "Several
// journals").

@MainActor
@Suite final class GameJournalTests: GameTestBench {
    private let namespace = "journal.6f9619ff-8b86-4011-b42d-00c04fc964ff."

    private func stored<T: Decodable>(_ type: T.Type, _ name: String, in namespace: String = "") -> T? {
        defaults.data(forKey: Game.key(name, in: namespace)).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    /// A round of random notes with `right` notes named right, then stopped.
    private func round(_ right: Int, on game: Game) {
        game.start()
        for _ in 0..<right {
            guard let question = game.question else { break }
            game.answer(question.pitch)
        }
        game.stop()
    }

    private func answersInStats(in namespace: String = "") -> Int? {
        stored([String: NoteStat].self, Game.Keys.noteStats, in: namespace)?.values.map(\.attempts).reduce(0, +)
    }

    @Test func keysAreTheNamespaceThenTheName() {
        #expect(Game.key(Game.Keys.settings, in: "") == "settings")
        #expect(Game.key(Game.Keys.noteStats, in: "") == "noteStats")
        #expect(Game.key(Game.Keys.noteStats, in: namespace) == namespace + "noteStats")
        #expect(game.namespace == "")
    }

    @Test func aJournalsValuesAreKeptApartFromTheOldOnes() throws {
        // The keys the app has always used, from playing before.
        game.settings.naming = .solfege
        round(3, on: game)
        let legacy = (settings: defaults.data(forKey: "settings"), noteStats: defaults.data(forKey: "noteStats"))
        #expect(legacy.settings != nil && legacy.noteStats != nil)

        // A journal of its own starts with the default settings and nothing kept.
        let log = MemoryUsageRecorder()
        let journal = Game(defaults: defaults, namespace: namespace, recorder: log, library: library)
        journal.settings.isMuted = true
        #expect(journal.namespace == namespace)
        #expect(journal.settings.naming == .letters)
        #expect(answersInStats(in: namespace) == nil)
        // There's nothing from before the log to record for it.
        #expect(!log.events.contains { $0.event.type == "statsSnapshot" })
        #expect(defaults.object(forKey: namespace + "usageLogStarted") == nil)

        journal.settings.clefChoice = .bass
        round(2, on: journal)
        #expect(stored(Game.Settings.self, Game.Keys.settings, in: namespace)?.clefChoice == .bass)
        #expect(answersInStats(in: namespace) == 2)

        // The old keys are as they were…
        #expect(defaults.data(forKey: "settings") == legacy.settings)
        #expect(defaults.data(forKey: "noteStats") == legacy.noteStats)
        let again = relaunch()
        #expect(again.settings.naming == .solfege && again.settings.clefChoice == .treble)

        // …and so are another journal's.
        let other = Game(defaults: defaults, namespace: "journal.other.", recorder: MemoryUsageRecorder(), library: library)
        #expect(other.settings.clefChoice == .treble)
        #expect(Game(defaults: defaults, namespace: namespace, recorder: MemoryUsageRecorder(), library: library)
            .settings.clefChoice == .bass)
    }

    @Test func theProjectionReplacesTheStatsAndIsSaved() {
        round(4, on: game)
        #expect(answersInStats() == 4)

        let stats = ["treble.E4": NoteStat(attempts: 7, correct: 6, recent: [true, true, false, true])]
        game.apply(projection: JournalProjection(noteStats: stats))
        #expect(stored([String: NoteStat].self, Game.Keys.noteStats) == stats)

        // Nothing kept that the projection doesn't have.
        game.apply(projection: JournalProjection())
        #expect(stored([String: NoteStat].self, Game.Keys.noteStats) == [:])
        // Nor anything under the key best sprint scores were kept under until 2026-11-07.
        #expect(defaults.object(forKey: "bestScores") == nil)
    }

    @Test func theProjectionIsSavedInTheJournalsNamespace() {
        let journal = Game(defaults: defaults, namespace: namespace, recorder: MemoryUsageRecorder(), library: library)
        let stats = ["treble.G4": NoteStat(attempts: 1, correct: 1, recent: [true])]
        journal.apply(projection: JournalProjection(noteStats: stats))
        #expect(stored([String: NoteStat].self, Game.Keys.noteStats, in: namespace) == stats)
        #expect(stored([String: NoteStat].self, Game.Keys.noteStats) == nil)
    }

    @Test func aRoundInProgressCarriesOn() throws {
        game.start()
        for _ in 0..<3 { _ = answerRight() }
        let question = try #require(game.question)
        game.apply(projection: JournalProjection(noteStats: [:]))
        #expect(game.phase == .playing && game.score == 3 && game.attempts == 3)
        #expect(game.question == question)
        // Its answers from now on count on top of the new stats.
        _ = answerRight()
        #expect(answersInStats() == 1)
        game.stop()
        #expect(game.summary?.score == 4 && game.summary?.attempts == 4)
    }
}
