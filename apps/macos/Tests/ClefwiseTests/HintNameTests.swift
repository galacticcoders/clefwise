import Testing
@testable import Clefwise

/// The names the hints write on the staff's lines and spaces.
@Suite struct HintNameTests {
    @Test func linesAndSpacesAreNamedWithTheirOctave() {
        #expect(StaffDrawing.hintNames(for: 0...8, clef: .treble, keySignature: .cMajor, naming: .letters)
                == ["E4", "F4", "G4", "A4", "B4", "C5", "D5", "E5", "F5"])
        #expect(StaffDrawing.hintNames(for: 0...8, clef: .bass, keySignature: .cMajor, naming: .solfege)
                == ["Sol2", "La2", "Si2", "Do3", "Re3", "Mi3", "Fa3", "Sol3", "La3"])
        // Ledger lines too: middle C below the treble staff, the open low E below the guitar's.
        #expect(StaffDrawing.hintNames(for: -2...(-2), clef: .treble, keySignature: .cMajor, naming: .letters) == ["C4"])
        #expect(StaffDrawing.hintNames(for: -7...(-7), clef: .treble8vb, keySignature: .cMajor, naming: .letters) == ["E2"])
    }

    @Test func theKeySignaturesSignsAreKept() {
        // G major: the top line is F♯5; B♭ major: the middle line is B♭4.
        #expect(StaffDrawing.hintNames(for: 8...8, clef: .treble, keySignature: KeySignature(fifths: 1), naming: .letters) == ["F♯5"])
        #expect(StaffDrawing.hintNames(for: 4...4, clef: .treble, keySignature: KeySignature(fifths: -2), naming: .solfege) == ["Si♭4"])
        #expect(StaffDrawing.hintNames(for: 8...8, clef: .treble, keySignature: KeySignature(fifths: 1), naming: .sargam) == ["tivra Ma5"])
    }

    /// The guitar clef sounds an octave below the treble clef, and its hints say so, as the frets do.
    @Test func theGuitarClefIsNamedAsItSounds() {
        let treble = StaffDrawing.hintNames(for: -10...18, clef: .treble, keySignature: .cMajor, naming: .letters)
        let guitar = StaffDrawing.hintNames(for: -10...18, clef: .treble8vb, keySignature: .cMajor, naming: .letters)
        for (high, low) in zip(treble, guitar) {
            #expect(high.dropLast() == low.dropLast() && Int(String(high.last!))! == Int(String(low.last!))! + 1)
        }
        let bottomLine = Clef.treble8vb.pitch(atPosition: 0)
        #expect(guitar[10] == GuitarNeck.names(of: bottomLine, in: .letters, prefersFlats: false)[0][0])
    }
}
