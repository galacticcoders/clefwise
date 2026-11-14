import Foundation
import Testing
@testable import Clefwise

/// The guitar's contract: tunings, places on the neck, its reach, the guitar clef, and settings.
@Suite struct GuitarTests {
    // MARK: Tunings

    @Test func standardTuningIsNumberedAsGuitaristsDo() {
        let tuning = GuitarTuning.standard
        #expect(tuning.strings.map(\.name) == ["E2", "A2", "D3", "G3", "B3", "E4"])
        #expect(tuning.openPitch(of: 1) == Pitch(.e, 4))
        #expect(tuning.openPitch(of: 6) == Pitch(.e, 2))
        #expect(tuning.name == "Standard")
        #expect(tuning.stringNames(in: .letters) == "E A D G B E")
        #expect(tuning.stringNames(in: .solfege) == "Mi La Re Sol Si Mi")
    }

    @Test func dropDLowersOnlyTheSixthString() {
        #expect(GuitarTuning.dropD.strings.map(\.name) == ["D2", "A2", "D3", "G3", "B3", "E4"])
        #expect(GuitarTuning.dropD.name == "Drop D")
        #expect(GuitarTuning.presets.first == .standard)
        #expect(Set(GuitarTuning.presets.map(\.key)).count == GuitarTuning.presets.count)
    }

    @Test func tuningsAreSavedAsOneString() throws {
        let data = try JSONEncoder().encode([GuitarTuning.dropD])
        #expect(String(decoding: data, as: UTF8.self) == #"["dropD"]"#)
        #expect(try JSONDecoder().decode([GuitarTuning].self, from: data) == [.dropD])
        for preset in GuitarTuning.presets {
            #expect(GuitarTuning(key: preset.key) == preset)
            #expect(preset.isPreset)
        }
    }

    @Test func aTuningThatIsNoPresetIsSavedByItsOpenStrings() throws {
        let openC = GuitarTuning(strings: [Pitch(.c, 2), Pitch(.g, 2), Pitch(.c, 3), Pitch(.g, 3), Pitch(.c, 4), Pitch(.e, 4)])
        #expect(!openC.isPreset)
        #expect(openC.key == "C2 G2 C3 G3 C4 E4")
        #expect(openC.name == "C G C G C E")
        #expect(GuitarTuning(key: openC.key) == openC)
        let data = try JSONEncoder().encode(openC)
        #expect(try JSONDecoder().decode(GuitarTuning.self, from: data) == openC)
    }

    @Test func keysThatAreNoTuningAreRefused() {
        #expect(GuitarTuning(key: "") == nil)
        #expect(GuitarTuning(key: "sitar") == nil)
        #expect(GuitarTuning(key: "E2 A2 D3 G3 B3") == nil)
        #expect(GuitarTuning(key: "E2 A2 D3 G3 B3 E4 A4") == nil)
        #expect(GuitarTuning(key: "E2 A2 D3 G3 B3 X4") == nil)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(GuitarTuning.self, from: Data(#""sitar""#.utf8)) }
    }

    // MARK: The neck

    @Test func placesSoundTheirOpenStringPlusTheFret() {
        let board = Fretboard()
        #expect(board.frets == 12)
        #expect(board.pitch(at: GuitarPosition(string: 6, fret: 0)) == Pitch(.e, 2))
        #expect(board.pitch(at: GuitarPosition(string: 4, fret: 2)) == Pitch(.e, 3))
        #expect(board.pitch(at: GuitarPosition(string: 1, fret: 1)) == Pitch(.f, 4))
        // Between the naturals, sharps, as on the piano.
        #expect(board.pitch(at: GuitarPosition(string: 6, fret: 2)) == Pitch(.f, 2, .sharp))
        #expect(board.midiNumber(at: GuitarPosition(string: 1, fret: 12)) == 76)
        #expect(board.positions.count == 6 * 13)
    }

    /// The bottom line of the guitar clef (E3, as it sounds) is on three strings within 12 frets.
    @Test func everyPlaceANoteCanBePlayedIsFound() {
        let board = Fretboard()
        #expect(board.positions(sounding: Pitch(.e, 3).midiNumber)
                == [GuitarPosition(string: 4, fret: 2), GuitarPosition(string: 5, fret: 7), GuitarPosition(string: 6, fret: 12)])
        #expect(board.positions(sounding: Pitch(.e, 2).midiNumber) == [GuitarPosition(string: 6, fret: 0)])
        #expect(board.positions(sounding: Pitch(.d, 2).midiNumber).isEmpty)
        #expect(Fretboard(tuning: .dropD).positions(sounding: Pitch(.d, 2).midiNumber) == [GuitarPosition(string: 6, fret: 0)])
        // Past the frets shown there's no place, even on a real neck.
        #expect(board.positions(sounding: Pitch(.b, 5).midiNumber).isEmpty)
        #expect(Fretboard(frets: 19).positions(sounding: Pitch(.b, 5).midiNumber) == [GuitarPosition(string: 1, fret: 19)])
    }

    @Test func theBoardShowsBetweenTwelveAndTwentyFourFrets() {
        #expect(Fretboard(frets: 3).frets == 12)
        #expect(Fretboard(frets: 30).frets == 24)
        #expect(Fretboard(frets: 17).frets == 17)
    }

    @Test func reachRunsFromTheLowestOpenStringToTheTopFret() {
        #expect(Fretboard.reach(of: .standard) == 40...88)
        #expect(Fretboard.reach(of: .dropD) == 38...88)
        #expect(Fretboard.canPlay(Pitch(.e, 2).midiNumber, in: .standard))
        #expect(!Fretboard.canPlay(Pitch(.d, 2).midiNumber, in: .standard))
        #expect(Fretboard.canPlay(Pitch(.d, 2).midiNumber, in: .dropD))
        #expect(!Fretboard.canPlay(Pitch(.f, 6).midiNumber, in: .standard))
    }

    @Test func theBoardGrowsOnlyForNotesThatNeedIt() {
        let staff = (0...8).map { Clef.treble8vb.pitch(atPosition: $0).midiNumber }
        #expect(Fretboard.fretsNeeded(for: staff, in: .standard) == 12)
        // Five ledger lines above the guitar clef: B5 as it sounds, the 1st string's 19th fret.
        #expect(Fretboard.fretsNeeded(for: staff + [Pitch(.b, 5).midiNumber], in: .standard) == 19)
        // Notes out of reach don't count, and the board stops at 24.
        #expect(Fretboard.fretsNeeded(for: [Pitch(.b, 1).midiNumber, Pitch(.c, 7).midiNumber], in: .standard) == 12)
        #expect(Fretboard.fretsNeeded(for: [Pitch(.e, 6).midiNumber], in: .standard) == 24)
        #expect(Fretboard.fretsNeeded(for: [Int](), in: .standard) == 12)
    }

    // MARK: Pitches

    @Test func midiNumbersAreSpelledLikeThePianoKeys() {
        #expect(Pitch(midiNumber: 60) == Pitch(.c, 4))
        #expect(Pitch(midiNumber: 61) == Pitch(.c, 4, .sharp))
        #expect(Pitch(midiNumber: 40) == Pitch(.e, 2))
        #expect(Pitch(midiNumber: 0) == Pitch(.c, -1))
        for midi in 0...127 { #expect(Pitch(midiNumber: midi).midiNumber == midi) }
    }

    @Test func pitchNamesReadBack() {
        for name in ["F♯4", "E♭2", "C4", "B-1", "A#3", "Bb3"] {
            #expect(Pitch(name: name) != nil, "\(name)")
        }
        #expect(Pitch(name: "A#3") == Pitch(.a, 3, .sharp))
        #expect(Pitch(name: "Bb3") == Pitch(.b, 3, .flat))
        for pitch in [Pitch(.f, 4, .sharp), Pitch(.e, 2, .flat), Pitch(.c, -1)] {
            #expect(Pitch(name: pitch.name) == pitch)
        }
        for name in ["", "H4", "c4", "C", "C♯", "C4x"] {
            #expect(Pitch(name: name) == nil, "\(name)")
        }
    }

    // MARK: The guitar clef

    @Test func theGuitarClefIsTheTrebleClefAnOctaveDown() {
        let guitar = Clef.treble8vb
        #expect(guitar.rawValue == "treble8vb")
        #expect(guitar.name == "Guitar")
        #expect(guitar.bottomLine == Pitch(.e, 3))
        #expect(guitar.position(of: Pitch(.e, 3)) == 0)
        for position in -10...18 {
            let treble = Clef.treble.pitch(atPosition: position)
            #expect(guitar.pitch(atPosition: position) == Pitch(treble.letter, treble.octave - 1))
        }
        #expect(guitar.lineLetters == Clef.treble.lineLetters)
        #expect(guitar.spaceLetters == Clef.treble.spaceLetters)
        #expect(guitar.lineMnemonic == Clef.treble.lineMnemonic)
        #expect(guitar.spaceMnemonic == Clef.treble.spaceMnemonic)
        #expect(guitar.readsAs == .treble && Clef.bass.readsAs == .bass)
        // Treble and bass keep their places.
        #expect(Clef.allCases == [.treble, .bass, .treble8vb])
    }

    @Test func keySignaturesSitWhereTheTrebleClefsDo() {
        for key in KeySignature.all {
            #expect(key.staffPositions(for: .treble8vb) == key.staffPositions(for: .treble))
        }
        #expect(KeySignature(fifths: 1).staffPositions(for: .bass) == [6])
    }

    @Test func theGuitarClefIsDrawnWithItsOwnGlyphOnTheGLine() {
        #expect(SMuFL.Glyph.clef(.treble8vb) == .gClef8vb)
        #expect(SMuFL.Glyph.clef(.treble8vb, change: true) == .gClef8vb)
        #expect(SMuFL.Glyph.clef(.treble) == .gClef)
        #expect(StaffMetrics.clefPosition(.treble8vb) == 2)
        #expect(StaffMetrics.clefPosition(.treble) == 2)
        #expect(StaffMetrics.clefPosition(.bass) == 6)
    }

    /// The guitar clef's questions sound as the clef says: the bottom line is the D string's 2nd fret.
    @Test func aGuitarClefQuestionIsPlayedWhereItSounds() {
        let question = Question(clef: .treble8vb, pitch: Clef.treble8vb.pitch(atPosition: 0))
        #expect(question.position == 0)
        #expect(question.writtenPitch == Pitch(.e, 3))
        #expect(Fretboard().positions(sounding: question.pitch.midiNumber).first == GuitarPosition(string: 4, fret: 2))
    }

    // MARK: Settings

    @Test func theGuitarIsAnAnswerInputThatAnswersByPitch() {
        #expect(Game.AnswerInput.guitar.rawValue == "guitar")
        #expect(Game.AnswerInput.allCases == [.buttons, .piano, .keyboard, .guitar])
        #expect(Game.AnswerInput.guitar.answersPitch && Game.AnswerInput.piano.answersPitch)
        #expect(!Game.AnswerInput.buttons.answersPitch && !Game.AnswerInput.keyboard.answersPitch)
        #expect(AnswerSource.guitar.rawValue == "guitar")
    }

    @Test func settingsFromBeforeTheGuitarLoadInStandardTuning() throws {
        let saved = Data(#"{"answerInput":"piano","piece":{"hand":"left"}}"#.utf8)
        let settings = try JSONDecoder().decode(Game.Settings.self, from: saved)
        #expect(settings.guitarTuning == .standard)
        #expect(settings.piece.guitarTuning == nil)
        #expect(settings.answerInput == .piano && settings.piece.hand == .left)
    }

    @Test func aTuningThatDoesNotReadLosesOnlyTheTuning() throws {
        let saved = Data(#"{"answerInput":"guitar","guitarTuning":"sitar","piece":{"guitarTuning":7,"hand":"left"}}"#.utf8)
        let settings = try JSONDecoder().decode(Game.Settings.self, from: saved)
        #expect(settings.guitarTuning == .standard && settings.answerInput == .guitar)
        #expect(settings.piece.guitarTuning == nil && settings.piece.hand == .left)
    }

    @Test func tuningsAreSavedWithTheSettings() throws {
        var settings = Game.Settings()
        settings.guitarTuning = .dropD
        settings.piece.guitarTuning = .dadgad
        let data = try JSONEncoder().encode(settings)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""guitarTuning":"dropD""#) && json.contains(#""guitarTuning":"dadgad""#))
        let read = try JSONDecoder().decode(Game.Settings.self, from: data)
        #expect(read.guitarTuning == .dropD && read.piece.guitarTuning == .dadgad)
    }
}

/// The game's side of the guitar contract that's settled without a piece.
@MainActor
@Suite final class GuitarGameContractTests: GameTestBench {
    @Test func answeringOnTheGuitarAsksInTheGuitarClef() {
        game.settings.clefChoice = .both
        #expect(game.randomClefs == [.treble, .bass])
        game.settings.answerInput = .guitar
        #expect(game.randomClefs == [.treble8vb])
        // The toolbar's choice is kept for the other inputs.
        #expect(game.settings.clefChoice == .both)
    }

    @Test func withNoPieceTheTuningIsTheGlobalOne() {
        #expect(game.guitarTuning == .standard)
        game.guitarTuning = .dropD
        #expect(game.settings.guitarTuning == .dropD)
        #expect(game.fretboard.tuning == .dropD)
        #expect(game.settings.piece.guitarTuning == nil)
    }
}
