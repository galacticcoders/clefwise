import Foundation
import Testing
@testable import Clefwise

/// `Game.bestScoreKey(for:)`, which projections use without a game, must be the key the game saves
/// best scores under.
@MainActor
@Suite final class BestScoreKeyTests: GameTestBench {
    @Test func theStaticKeyIsTheOneBestScoresAreSavedUnder() {
        var setups: [Game.Settings] = []
        var settings = Game.Settings()
        setups.append(settings)
        settings.clefChoice = .bass
        settings.range = NoteRange(below: true, onStaff: true, above: false, ledgerLines: 2)
        settings.answerInput = .piano
        setups.append(settings)
        settings.clefChoice = .both
        settings.answerInput = .keyboard
        settings.key = .fixed(KeySignature(fifths: -2))
        settings.addsAccidentals = true
        setups.append(settings)
        settings.key = .random
        setups.append(settings)

        var keys: Set<String> = []
        for setup in setups {
            var playing = setup
            playing.isMuted = true
            playing.mode = .sprint
            game.settings = playing
            game.start()
            answerRight()
            game.stop()
            let key = Game.bestScoreKey(for: game.settings)
            keys.insert(key)
            #expect(storedBestScores()?[key] == 1, "\(key)")
            #expect(Set(storedBestScores()?.keys.map { $0 } ?? []) == keys, "saved under no other key")
            #expect(game.bestScore == 1)
        }
        #expect(keys == ["treble.staff", "bass.below2+staff.piano", "both.below2+staff.keyboard.key-2.acc",
                         "both.below2+staff.keyboard.keyRandom.acc"])
    }
}
