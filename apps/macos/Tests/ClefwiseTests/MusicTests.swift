import Testing
@testable import Clefwise

@Suite struct KeySignatureTests {
    @Test func gMajorSharpensOnlyF() {
        let g = KeySignature(fifths: 1)
        #expect(g.accidental(for: .f) == .sharp)
        #expect(g.accidental(for: .c) == .natural)
    }

    @Test func sharpAndFlatOrder() {
        #expect(KeySignature(fifths: 5).alteredLetters == [.f, .c, .g, .d, .a])
        #expect(KeySignature(fifths: -2).alteredLetters == [.b, .e])
    }

    @Test func signsSitOnTheirLetters() {
        // F♯ on the top line in treble, the fourth line in bass; the first flat on the B line.
        #expect(KeySignature(fifths: 1).staffPositions(for: .treble) == [8])
        #expect(KeySignature(fifths: 1).staffPositions(for: .bass) == [6])
        #expect(Clef.treble.pitch(atPosition: 8) == Pitch(.f, 5))
        #expect(Clef.bass.pitch(atPosition: 6) == Pitch(.f, 3))
        #expect(Clef.treble.pitch(atPosition: KeySignature(fifths: -1).staffPositions(for: .treble)[0]) == Pitch(.b, 4))
    }

    @Test func namesCoverSevenSharpsAndFlats() {
        #expect(KeySignature(fifths: 1).majorKey == "G")
        #expect(KeySignature(fifths: 1).minorKey == "E")
        #expect(KeySignature(fifths: -7).majorKey == "C♭")
        #expect(KeySignature(fifths: 7).minorKey == "A♯")
    }
}

@Suite struct PitchTests {
    @Test func enharmonicsShareASoundButNotAPosition() {
        #expect(Pitch(.f, 4, .sharp).midiNumber == 66)
        #expect(Pitch(.g, 4, .flat).midiNumber == 66)
        #expect(Pitch(.f, 4, .sharp).diatonicIndex == Pitch(.f, 4).diatonicIndex)
    }

    @Test func names() {
        #expect(Pitch(.f, 4, .sharp).name == "F♯4")
        #expect(Pitch(.c, 4).name == "C4")
    }

    @Test func eightVaIsWrittenAnOctaveLower() {
        let question = Question(clef: .treble, pitch: Pitch(.e, 6), octaveShift: 1)
        #expect(question.writtenPitch == Pitch(.e, 5))
        #expect(question.position == 7)
    }
}

@Suite struct NamingTests {
    @Test func sharpAndFlatNames() {
        #expect(NamingSystem.solfege.name(of: Pitch(.b, 3, .flat)) == "Si♭")
        #expect(NamingSystem.sargam.name(of: Pitch(.f, 4, .sharp)) == "tivra Ma")
        #expect(NamingSystem.sargam.name(of: Pitch(.d, 4, .flat)) == "komal Re")
    }

    @Test func lettersGoBySpellingSargamBySwara() {
        #expect(NamingSystem.letters.accepts(.f, .sharp, for: Pitch(.f, 5, .sharp)))
        #expect(!NamingSystem.letters.accepts(.g, .flat, for: Pitch(.f, 5, .sharp)))
        #expect(NamingSystem.sargam.accepts(.g, .flat, for: Pitch(.f, 5, .sharp)))
    }

    @Test func sargamOnlyNamesItsTwelveSwaras() {
        #expect(NamingSystem.sargam.hasName(.d, .flat))
        #expect(NamingSystem.sargam.hasName(.f, .sharp))
        #expect(!NamingSystem.sargam.hasName(.c, .flat))
        #expect(NamingSystem.letters.hasName(.c, .flat))
    }
}
