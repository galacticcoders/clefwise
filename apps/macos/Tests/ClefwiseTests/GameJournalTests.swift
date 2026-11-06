import Foundation
import Testing
@testable import Clefwise

// `Game` with several journals on one Mac: each journal's values under its own keys in the
// defaults, and the note stats and best scores taken from the journal (spec/practice-journal.md,
// "Several journals").

@MainActor
@Suite final class GameJournalTests: GameTestBench {
    private let namespace = "journal.6f9619ff-8b86-4011-b42d-00c04fc964ff."

    private func stored<T: Decodable>(_ type: T.Type, _ name: String, in namespace: String = "") -> T? {
        defaults.data(forKey: Game.key(name, in: namespace)).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    /// A sprint on random notes with `right` notes named right, ended by running out of time.
    private func sprint(_ right: Int, on game: Game) {
        game.start()
        for _ in 0..<right {
            guard let question = game.question else { break }
            game.answer(question.pitch)
        }
        game.tick(at: .now + .seconds(61))
    }

    @Test func keysAreTheNamespaceThenTheName() {
        #expect(Game.key(Game.Keys.settings, in: "") == "settings")
        #expect(Game.key(Game.Keys.noteStats, in: "") == "noteStats")
        #expect(Game.key(Game.Keys.bestScores, in: namespace) == namespace + "bestScores")
        #expect(game.namespace == "")
    }

    @Test func aJournalsValuesAreKeptApartFromTheOldOnes() throws {
        // The keys the app has always used, from playing before.
        game.settings.naming = .solfege
        sprint(3, on: game)
        let legacy = (settings: defaults.data(forKey: "settings"), noteStats: defaults.data(forKey: "noteStats"),
                      bestScores: defaults.data(forKey: "bestScores"))
        #expect(legacy.settings != nil && legacy.noteStats != nil && legacy.bestScores != nil)
        let bestBefore = try #require(game.bestScore)

        // A journal of its own starts with the default settings and nothing kept.
        let log = MemoryUsageRecorder()
        let journal = Game(defaults: defaults, namespace: namespace, recorder: log, library: library)
        journal.settings.isMuted = true
        #expect(journal.namespace == namespace)
        #expect(journal.settings.naming == .letters)
        #expect(journal.bestScore == nil)
        // There's nothing from before the log to record for it.
        #expect(!log.events.contains { $0.event.type == "statsSnapshot" })
        #expect(defaults.object(forKey: namespace + "usageLogStarted") == nil)

        journal.settings.clefChoice = .bass
        sprint(2, on: journal)
        #expect(stored(Game.Settings.self, Game.Keys.settings, in: namespace)?.clefChoice == .bass)
        #expect(stored([String: Int].self, Game.Keys.bestScores, in: namespace)?.values.max() == 2)
        #expect(stored([String: NoteStat].self, Game.Keys.noteStats, in: namespace)?.values.map(\.attempts).reduce(0, +) == 2)

        // The old keys are as they were…
        #expect(defaults.data(forKey: "settings") == legacy.settings)
        #expect(defaults.data(forKey: "noteStats") == legacy.noteStats)
        #expect(defaults.data(forKey: "bestScores") == legacy.bestScores)
        let again = relaunch()
        #expect(again.settings.naming == .solfege && again.settings.clefChoice == .treble)
        #expect(again.bestScore == bestBefore)

        // …and so are another journal's.
        let other = Game(defaults: defaults, namespace: "journal.other.", recorder: MemoryUsageRecorder(), library: library)
        #expect(other.settings.clefChoice == .treble)
        #expect(Game(defaults: defaults, namespace: namespace, recorder: MemoryUsageRecorder(), library: library)
            .settings.clefChoice == .bass)
    }

    @Test func theProjectionReplacesTheStatsAndIsSaved() {
        sprint(4, on: game)
        let setup = Game.bestScoreKey(for: game.settings)
        #expect(game.bestScore == 4)

        let stats = ["treble.E4": NoteStat(attempts: 7, correct: 6, recent: [true, true, false, true])]
        game.apply(projection: JournalProjection(noteStats: stats, bestScores: [setup: 11, "bass.staff": 3]))
        #expect(game.bestScore == 11)
        #expect(stored([String: NoteStat].self, Game.Keys.noteStats) == stats)
        #expect(stored([String: Int].self, Game.Keys.bestScores) == [setup: 11, "bass.staff": 3])
        #expect(relaunch().bestScore == 11)

        // Nothing kept that the projection doesn't have.
        game.apply(projection: JournalProjection())
        #expect(game.bestScore == nil)
        #expect(stored([String: NoteStat].self, Game.Keys.noteStats) == [:])
        #expect(stored([String: Int].self, Game.Keys.bestScores) == [:])
    }

    @Test func theProjectionIsSavedInTheJournalsNamespace() {
        let journal = Game(defaults: defaults, namespace: namespace, recorder: MemoryUsageRecorder(), library: library)
        let setup = Game.bestScoreKey(for: journal.settings)
        journal.apply(projection: JournalProjection(noteStats: ["treble.G4": NoteStat(attempts: 1, correct: 1, recent: [true])],
                                                    bestScores: [setup: 9]))
        #expect(stored([String: Int].self, Game.Keys.bestScores, in: namespace) == [setup: 9])
        #expect(stored([String: Int].self, Game.Keys.bestScores) == nil)
        #expect(game.bestScore == nil)
    }

    @Test func aRoundInProgressCarriesOn() throws {
        game.start()
        for _ in 0..<3 { _ = answerRight() }
        let question = try #require(game.question)
        game.apply(projection: JournalProjection(noteStats: [:], bestScores: [Game.bestScoreKey(for: game.settings): 2]))
        #expect(game.phase == .playing && game.score == 3 && game.attempts == 3)
        #expect(game.question == question)
        // Its answers from now on count on top of the new stats, and its score against the new best.
        _ = answerRight()
        #expect(stored([String: NoteStat].self, Game.Keys.noteStats)?.values.map(\.attempts).reduce(0, +) == 1)
        game.tick(at: .now + .seconds(61))
        #expect(game.summary?.isNewBest == true)
        #expect(game.bestScore == 4)
    }
}
