import Testing
@testable import Clefwise

@Suite struct NoteValueTests {
    @Test func lengthsCountDots() {
        #expect(NoteValue(.quarter).quarters == 1)
        #expect(NoteValue(.half, dots: 1).quarters == 3)
        #expect(NoteValue(.quarter, dots: 2).quarters == 1.75)
        #expect(NoteValue(.whole).quarters == 4)
        #expect(NoteValue(.sixteenth).quarters == 0.25)
    }

    @Test func shapes() {
        #expect(NoteValue(.whole).isHollow && !NoteValue(.whole).hasStem)
        #expect(NoteValue(.half).isHollow && NoteValue(.half).hasStem)
        #expect(!NoteValue(.quarter).isHollow)
        #expect(NoteValue.Kind.allCases.map { NoteValue($0).flags } == [0, 0, 0, 1, 2, 3, 4])
        #expect(NoteValue.Kind.whole > .half && NoteValue.Kind.eighth < .quarter)
    }

    @Test func musicXMLTypes() {
        #expect(NoteValue.Kind(musicXMLType: "16th") == .sixteenth)
        #expect(NoteValue.Kind(musicXMLType: "breve") == .whole)
        #expect(NoteValue.Kind(musicXMLType: "128th") == .sixtyFourth)
        #expect(NoteValue.Kind(musicXMLType: "crotchet") == nil)
    }

    @Test func nearestValueForALength() {
        #expect(NoteValue.nearest(toQuarters: 1) == NoteValue(.quarter))
        #expect(NoteValue.nearest(toQuarters: 3) == NoteValue(.half, dots: 1))
        #expect(NoteValue.nearest(toQuarters: 3.5) == NoteValue(.half, dots: 2))
        #expect(NoteValue.nearest(toQuarters: 6) == NoteValue(.whole, dots: 1))
        // Five quarters isn't one value: the longest that fits.
        #expect(NoteValue.nearest(toQuarters: 5) == NoteValue(.whole))
        #expect(NoteValue.nearest(toQuarters: 1.0 / 3) == NoteValue(.sixteenth))
        #expect(NoteValue.nearest(toQuarters: 0.01) == NoteValue(.sixtyFourth))
    }
}

@Suite struct BarSymbolTests {
    private func symbol(_ pitch: Pitch?, clef: Clef = .treble, shift: Int = 0) -> BarSymbol {
        BarSymbol(pitch: pitch, clef: clef, staff: 1, voice: 1, offset: 0, duration: 1, value: NoteValue(.quarter),
                  octaveShift: shift, accidental: nil, stemUp: nil, chord: 1, tiedToNext: false,
                  tiedFromPrevious: false, restPosition: nil, isWholeBarRest: false)
    }

    @Test func positionIsWhereTheNoteIsWritten() {
        #expect(symbol(Pitch(.e, 4)).position == 0)
        #expect(symbol(Pitch(.g, 2), clef: .bass).position == 0)
        // Under 8va, E6 is written as E5, on the top space.
        #expect(symbol(Pitch(.e, 6), shift: 1).position == 7)
        #expect(symbol(Pitch(.e, 6), shift: 1).writtenPitch == Pitch(.e, 5))
        #expect(symbol(nil).position == nil && symbol(nil).isRest)
    }

    @Test func partFindsANotesSymbol() {
        let measure = ScoreMeasure(number: 2, start: 4, length: 4,
                                   staves: [.init(clef: .treble, keySignature: .cMajor)],
                                   symbols: [symbol(nil), symbol(Pitch(.g, 4))])
        let note = ScoreNote(pitch: Pitch(.g, 4), clef: .treble, keySignature: .cMajor, printedAccidental: nil,
                             octaveShift: 0, staff: 1, measure: 2, onset: 4, chord: 1, symbolIndex: 1)
        let empty = ScoreMeasure(number: 1, start: 0, length: 4,
                                 staves: [.init(clef: .treble, keySignature: .cMajor)], symbols: [])
        let part = ScorePart(name: "Flute", notes: [note], measures: [empty, measure], measureCount: 2,
                             staffCount: 1, skippedNoteCount: 0)
        #expect(part.symbol(for: note)?.index == 1)
        #expect(part.symbol(for: note)?.measure.number == 2)

        let withoutLayout = ScorePart(name: "Flute", notes: [note], measureCount: 2, staffCount: 1, skippedNoteCount: 0)
        #expect(withoutLayout.symbol(for: note) == nil)
    }
}
