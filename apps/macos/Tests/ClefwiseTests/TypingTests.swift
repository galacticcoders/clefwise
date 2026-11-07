import Foundation
import Testing
@testable import Clefwise

// Typing one note's name in a key with sharps: no Return. A right name goes in the moment it's
// typed, a wrong one is judged at once, and only the right letter without its sign waits for it.

/// G major, in order: G4, F♯4, G4.
private let gMajorTune = Score(title: "Typing tune", parts: [ScorePart(name: "Flute", notes: [
    ScoreNote(pitch: Pitch(.g, 4), clef: .treble, keySignature: KeySignature(fifths: 1), printedAccidental: nil,
              octaveShift: 0, staff: 1, measure: 1, onset: 0, chord: 1),
    ScoreNote(pitch: Pitch(.f, 4, .sharp), clef: .treble, keySignature: KeySignature(fifths: 1), printedAccidental: nil,
              octaveShift: 0, staff: 1, measure: 1, onset: 1, chord: 2),
    ScoreNote(pitch: Pitch(.g, 4), clef: .treble, keySignature: KeySignature(fifths: 1), printedAccidental: nil,
              octaveShift: 0, staff: 1, measure: 1, onset: 2, chord: 3),
], measureCount: 1, staffCount: 1, skippedNoteCount: 0)])

private let gMajorTuneURL = URL(fileURLWithPath: "/tmp/clefwise-typing-tests/tune.musicxml")

@MainActor
@Suite final class TypingTests: GameTestBench {
    private var answers: [AnswerGiven] {
        recorder.events.compactMap { $0.event.payload as? AnswerGiven }
    }

    private func type(_ text: String) {
        for character in text { game.handleKey(characters: String(character), keyCode: 0) }
    }

    private func pressReturn() {
        game.handleKey(characters: "\r", keyCode: 36)
    }

    /// The G major tune in solfège (or `naming`), typed, its first note (G4) up.
    private func startTune(naming: NamingSystem = .solfege) throws {
        game.settings.answerInput = .keyboard
        game.settings.naming = naming
        game.open(gMajorTune, from: gMajorTuneURL)
        game.start()
        #expect(game.accidentalsPossible)
        #expect(try #require(game.question).pitch == Pitch(.g, 4))
    }

    @Test func aRightNameGoesInAtOnceThoughASignCouldFollow() throws {
        try startTune()
        type("sol")
        #expect(answers.count == 1 && answers[0].correct && answers[0].name == "Sol")
        #expect(answers[0].keystrokes.map(\.result) == [.typed, .typed, .submitted])
        #expect(game.score == 1 && game.typedText.isEmpty)
        #expect(game.question?.pitch == Pitch(.f, 4, .sharp))
    }

    @Test func theRightLetterWithoutItsSignWaitsForTheSign() throws {
        try startTune()
        type("sol")
        type("fa")
        #expect(answers.count == 1 && game.typedText == "fa")
        // Return would answer plain Fa, a miss, so the box doesn't ask for it.
        #expect(!game.typingNeedsReturn)
        type("#")
        #expect(answers.count == 2 && answers[1].correct && answers[1].name == "Fa♯")
        #expect(game.score == 2 && game.streak == 2)
    }

    @Test func returnAnswersTheRightLetterWithoutItsSignAsTyped() throws {
        try startTune()
        type("sol")
        type("fa")
        pressReturn()
        #expect(answers.count == 2 && !answers[1].correct && answers[1].name == "Fa")
        #expect(answers[1].keystrokes.map(\.key) == ["f", "a", "Return"])
        #expect(game.isShowingMiss && game.streak == 0)
    }

    @Test func aWrongNameIsJudgedAtOnce() async throws {
        try startTune()
        type("fa") // G4: no sign makes Fa right
        #expect(answers.count == 1 && !answers[0].correct && answers[0].name == "Fa")
        #expect(game.isShowingMiss && game.typedText.isEmpty)
        try await waitUntil { !game.isShowingMiss }
        #expect(game.question?.pitch == Pitch(.f, 4, .sharp))
        type("mi") // F♯4: Mi♯ isn't Fa♯
        #expect(answers.count == 2 && !answers[1].correct && answers[1].name == "Mi")
    }

    @Test func aWrongNameCantBeTakenBackAndRetyped() throws {
        try startTune()
        type("si") // judged at once, so there's nothing left to delete
        game.handleKey(characters: "\u{7f}", keyCode: 51)
        type("sol")
        #expect(answers.count == 1 && !answers[0].correct)
        #expect(game.score == 0)
    }

    @Test func aFlatAfterTheRightLetterIsJudged() throws {
        try startTune(naming: .letters)
        type("g") // G4, right at once
        type("f") // F♯4: waits for the sign
        #expect(answers.count == 1 && game.typedText == "f")
        type("b") // after a whole name, "b" is a flat: F♭, wrong
        #expect(answers.count == 2 && !answers[1].correct && answers[1].name == "F♭")
    }

    @Test func sargamWaitsForTivraMa() throws {
        try startTune(naming: .sargam)
        type("pa") // G4 is Pa
        type("ma")
        #expect(answers.count == 1 && game.typedText == "ma")
        type("#")
        #expect(answers.count == 2 && answers[1].correct)
    }

    @Test func withoutSignsEveryNameStillGoesInAtOnce() throws {
        game.settings.answerInput = .keyboard
        game.settings.naming = .solfege
        game.start()
        #expect(!game.accidentalsPossible)
        let question = try #require(game.question)
        type(NamingSystem.solfege.name(of: question.pitch.letter).lowercased())
        #expect(answers.count == 1 && answers[0].correct)
    }
}
