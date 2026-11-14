import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import Clefwise

// The guitar answer's views: the neck's geometry, the names and marks on it, the tuning menu's
// choices, its colours, and the guitar clef on the staff.

@Suite struct NeckLayoutTests {
    private let guitarStep = pow(2, -1.0 / 12)

    @Test func fretsNarrowUpTheNeckAsOnAGuitar() throws {
        let widths = NeckLayout.fretWidths(count: 12, filling: 900, narrowest: NeckLayout.narrowestFret)
        #expect(widths.count == 12)
        #expect(abs(widths.reduce(0, +) - 900) < 0.001)
        for (wider, narrower) in zip(widths, widths.dropFirst()) {
            #expect(abs(Double(narrower / wider) - guitarStep) < 1e-9)
        }
        // The 12th fret is half as wide as the 1st, as on a real neck... give or take the step.
        #expect(abs(Double(widths[11] / widths[0]) - pow(2, -11.0 / 12)) < 1e-9)
    }

    @Test func aLongNeckInANarrowWindowFlattensItsCurveButKeepsEveryFretWideEnough() throws {
        // 24 frets in the smallest window: 820 less the window's padding, the open strings and the nut.
        let room: CGFloat = 820 - 48 - NeckLayout.openWidth - NeckLayout.nutWidth
        let widths = NeckLayout.fretWidths(count: 24, filling: room, narrowest: NeckLayout.narrowestFret)
        #expect(abs(widths.reduce(0, +) - room) < 0.001)
        #expect(try #require(widths.min()) >= NeckLayout.narrowestFret - 0.01)
        let steps = zip(widths, widths.dropFirst()).map { Double($1 / $0) }
        // Still narrowing, evenly, but less steeply than a real neck.
        #expect(steps.allSatisfy { $0 < 1 && $0 > guitarStep })
        #expect(steps.allSatisfy { abs($0 - steps[0]) < 1e-9 })
    }

    @Test func withNoRoomForTheCurveEveryFretIsAsWide() {
        let widths = NeckLayout.fretWidths(count: 24, filling: 400, narrowest: NeckLayout.narrowestFret)
        #expect(widths.allSatisfy { abs($0 - 400.0 / 24) < 0.001 })
        #expect(NeckLayout.fretWidths(count: 12, filling: 0, narrowest: 22).isEmpty)
    }

    @Test func placesTileTheNeckStringOneOnTop() {
        for frets in [12, 19, 24] {
            let size = CGSize(width: 952, height: 122)
            let layout = NeckLayout(frets: frets, size: size)
            #expect(layout.boardHeight == 122 - NeckLayout.numbersHeight)
            #expect(layout.wires.count == frets)
            #expect(layout.left >= 0 && layout.right <= size.width + 0.001)
            for string in 1...6 {
                let row = (0...frets).map { layout.target(GuitarPosition(string: string, fret: $0)) }
                // Open strings on the left of the nut, which they take too; then fret after fret.
                #expect(row[0].minX == layout.left && row[0].maxX == layout.nutRight)
                for (left, right) in zip(row, row.dropFirst()) {
                    #expect(abs(left.maxX - right.minX) < 0.001)
                }
                #expect(abs(row[frets].maxX - layout.right) < 0.001)
                #expect(row.allSatisfy { abs($0.minY - layout.rowHeight * CGFloat(string - 1)) < 0.001 })
                #expect(abs(layout.stringY(string) - row[0].midY) < 0.001)
            }
            #expect(layout.target(GuitarPosition(string: 1, fret: 5)).minY == 0)
            #expect(abs(layout.target(GuitarPosition(string: 6, fret: 5)).maxY - layout.boardHeight) < 0.001)
            // A mark is centred in the open strings' column, not over the nut, and fits its place.
            #expect(layout.markWidth(GuitarPosition(string: 3, fret: 0)) == NeckLayout.openWidth)
            for position in Fretboard(frets: frets).positions {
                let dot = layout.dot(position)
                #expect(dot > 0 && dot <= layout.rowHeight && dot <= layout.markWidth(position))
            }
        }
    }

    @Test func aVeryWideWindowDoesNotStretchTheNeckOutOfShape() {
        let layout = NeckLayout(frets: 12, size: CGSize(width: 2400, height: 122))
        let first = layout.fretSpan(1)
        #expect(abs(first.upperBound - first.lowerBound - NeckLayout.widestFret) < 0.001)
        // Centred.
        #expect(abs(layout.left - (2400 - layout.right)) < 0.001)
    }
}

@Suite struct FretNameTests {
    /// With the octave as it sounds: the open 6th string is E2, the 1st E4.
    @Test func naturalsHaveOneNameWithTheirOctave() {
        // Where it's narrow, the octave under the name.
        #expect(GuitarNeck.names(of: Pitch(.e, 2), in: .solfege, prefersFlats: false) == [["Mi2"], ["Mi", "2"]])
        #expect(GuitarNeck.names(of: Pitch(.b, 3), in: .letters, prefersFlats: true) == [["B3"], ["B", "3"]])
        #expect(GuitarNeck.names(of: Pitch(.g, 3), in: .sargam, prefersFlats: false) == [["Pa3"], ["Pa", "3"]])
        #expect(GuitarNeck.names(of: Pitch(.c, 6), in: .letters, prefersFlats: false) == [["C6"], ["C", "6"]])
        let board = Fretboard()
        #expect((1...6).map { GuitarNeck.names(of: board.pitch(at: GuitarPosition(string: $0, fret: 0)), in: .letters, prefersFlats: false)[0] }
                == [["E4"], ["B3"], ["G3"], ["D3"], ["A2"], ["E2"]])
    }

    @Test func notesBetweenAreCalledBothWaysWhereThereIsRoom() {
        // Then the sharp, or in a flat key the flat; both in the same octave.
        #expect(GuitarNeck.names(of: Pitch(.f, 3, .sharp), in: .solfege, prefersFlats: false) == [["Fa♯3/Sol♭3"], ["Fa♯3"], ["Fa♯", "3"]])
        #expect(GuitarNeck.names(of: Pitch(.f, 3, .sharp), in: .solfege, prefersFlats: true) == [["Fa♯3/Sol♭3"], ["Sol♭3"], ["Sol♭", "3"]])
        #expect(GuitarNeck.names(of: Pitch(.a, 2, .sharp), in: .letters, prefersFlats: false) == [["A♯2/B♭2"], ["A♯2"], ["A♯", "2"]])
        #expect(GuitarNeck.names(of: Pitch(.c, 4, .sharp), in: .letters, prefersFlats: true) == [["C♯4/D♭4"], ["D♭4"], ["D♭", "4"]])
    }

    @Test func sargamHasOneNameOnTwoLinesWhereNarrow() {
        #expect(GuitarNeck.names(of: Pitch(.c, 4, .sharp), in: .sargam, prefersFlats: false) == [["komal Re4"], ["komal", "Re4"]])
        #expect(GuitarNeck.names(of: Pitch(.f, 3, .sharp), in: .sargam, prefersFlats: true) == [["tivra Ma3"], ["tivra", "Ma3"]])
    }

    @Test func everyPlaceOnTheBoardHasAName() {
        for tuning in GuitarTuning.presets {
            let board = Fretboard(tuning: tuning, frets: 24)
            for position in board.positions {
                for naming in NamingSystem.allCases {
                    let names = GuitarNeck.names(of: board.pitch(at: position), in: naming, prefersFlats: false)
                    #expect(!names.isEmpty && names.allSatisfy { !$0.isEmpty && $0.allSatisfy { !$0.isEmpty } })
                }
            }
        }
    }
}

@Suite struct GuitarMarksTests {
    private let board = Fretboard()
    /// Every place that sounds E3, the guitar clef's bottom line.
    private let e3Places: Set = [GuitarPosition(string: 4, fret: 2), GuitarPosition(string: 5, fret: 7),
                                 GuitarPosition(string: 6, fret: 12)]

    private func marked(_ marks: GuitarMarks) -> [GuitarPosition: KeyHighlight] {
        Dictionary(uniqueKeysWithValues: board.positions.compactMap { position in
            let highlight = marks.highlight(at: position)
            return highlight == .none ? nil : (position, highlight)
        })
    }

    private func question(_ pitch: Pitch) -> Question {
        Question(clef: .treble8vb, pitch: pitch)
    }

    @Test func thePlaceClickedIsMarkedRightOrWrong() {
        let right = Game.Flash(letter: .e, accidental: .natural, pitch: Pitch(.e, 3), isCorrect: true,
                               position: GuitarPosition(string: 5, fret: 7))
        #expect(marked(GuitarMarks(board: board, flash: right, question: question(Pitch(.f, 3))))
                == [GuitarPosition(string: 5, fret: 7): .correct])
        let wrong = Game.Flash(letter: .f, accidental: .natural, pitch: Pitch(.f, 3), isCorrect: false,
                               position: GuitarPosition(string: 4, fret: 3))
        #expect(marked(GuitarMarks(board: board, flash: wrong, question: question(Pitch(.e, 3))))
                == [GuitarPosition(string: 4, fret: 3): .wrong])
    }

    @Test func aMissRevealsEveryPlaceTheNoteIsPlayed() {
        let wrong = Game.Flash(letter: .f, accidental: .natural, pitch: Pitch(.f, 3), isCorrect: false,
                               position: GuitarPosition(string: 4, fret: 3))
        let marks = marked(GuitarMarks(board: board, flash: wrong, question: question(Pitch(.e, 3)), isShowingMiss: true))
        #expect(Set(marks.filter { $0.value == .reveal }.keys) == e3Places)
        #expect(marks[GuitarPosition(string: 4, fret: 3)] == .wrong)
        #expect(marks.count == 4)
    }

    @Test func notesAreMatchedBySoundNotSpelling() {
        // D♭4 is played where the board's C♯4 is: B string 2nd fret, G string 6th, D string 11th.
        let marks = marked(GuitarMarks(board: board, question: question(Pitch(.d, 4, .flat)), isShowingMiss: true))
        #expect(Set(marks.keys) == [GuitarPosition(string: 2, fret: 2), GuitarPosition(string: 3, fret: 6),
                                    GuitarPosition(string: 4, fret: 11)])
    }

    @Test func nothingIsRevealedBeforeAMiss() {
        #expect(marked(GuitarMarks(board: board, question: question(Pitch(.e, 3)))).isEmpty)
    }

    @Test func notesNamedTogetherAreChosenThenJudgedAndTheMissedOnesRevealed() {
        let questions = [question(Pitch(.e, 3)), question(Pitch(.g, 3))]
        let entries = [Game.GroupEntry(letter: .e, accidental: .natural, pitch: Pitch(.e, 3), position: GuitarPosition(string: 4, fret: 2)),
                       Game.GroupEntry(letter: .a, accidental: .natural, pitch: Pitch(.a, 3), position: GuitarPosition(string: 3, fret: 2))]
        let chosen = GuitarMarks(board: board, group: .init(questions: questions, entries: entries, result: nil))
        #expect(marked(chosen) == [GuitarPosition(string: 4, fret: 2): .armed, GuitarPosition(string: 3, fret: 2): .armed])

        let result = Game.GroupResult(isRight: [true, false], entryIndices: [0, 1], entryIsRight: [true, false])
        let judged = GuitarMarks(board: board, group: .init(questions: questions, entries: entries, result: result))
        #expect(marked(judged) == [GuitarPosition(string: 4, fret: 2): .correct, GuitarPosition(string: 3, fret: 2): .wrong])

        // During the pause after the mistake, G3 shows wherever it's played.
        let missed = GuitarMarks(board: board, isShowingMiss: true,
                                 group: .init(questions: questions, entries: entries, result: result))
        let g3Places = Set(board.positions(sounding: Pitch(.g, 3).midiNumber))
        let marks = marked(missed)
        #expect(Set(marks.filter { $0.value == .reveal }.keys) == g3Places)
        #expect(marks.count == 2 + g3Places.count)
    }
}

@Suite struct GuitarTuningMenuTests {
    @Test func thePresetsComeFirstThenTheScoresOwnTuning() throws {
        #expect(GuitarTuningMenu.choices(scoreTuning: nil, inUse: .standard) == GuitarTuning.presets)
        // A preset the score asks for isn't listed twice.
        #expect(GuitarTuningMenu.choices(scoreTuning: .dropD, inUse: .dropD) == GuitarTuning.presets)
        let openC = try #require(GuitarTuning(key: "C2 G2 C3 G3 C4 E4"))
        #expect(GuitarTuningMenu.choices(scoreTuning: openC, inUse: .standard) == GuitarTuning.presets + [openC])
        // A tuning saved with a piece stays on the menu while it's in use.
        #expect(GuitarTuningMenu.choices(scoreTuning: nil, inUse: openC) == GuitarTuning.presets + [openC])
    }
}

@Suite struct GuitarColourTests {
    /// WCAG contrast between two sRGB colours given as 0xRRGGBB.
    private func contrast(_ a: Int, _ b: Int) -> Double {
        func luminance(_ hex: Int) -> Double {
            let channels = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { value -> Double in
                let c = Double(value) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let (lighter, darker) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (lighter + 0.05) / (darker + 0.05)
    }

    @Test func namesOnTheNeckReadInBothAppearances() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            #expect(contrast(Theme.fretLabel.hex(in: appearance), Theme.fretboard.hex(in: appearance)) >= 7)
            // The strings show on the wood, and the inlays only just do.
            #expect(contrast(Theme.guitarString.hex(in: appearance), Theme.fretboard.hex(in: appearance)) >= 3)
            #expect(contrast(Theme.fretInlay.hex(in: appearance), Theme.fretboard.hex(in: appearance)) < 2)
        }
        // A maple neck in light, a rosewood one in dark.
        #expect(Theme.fretboard.hex(in: .aqua) == 0xE8D8BA)
        #expect(Theme.fretboard.hex(in: .darkAqua) == 0x3B2F28)
    }
}

@Suite struct GuitarClefDrawingTests {
    @Test func onlyAChangeToTheGuitarClefIsScaled() {
        for clef in [Clef.treble, .bass] {
            #expect(StaffMetrics.clefScale(clef) == 1 && StaffMetrics.clefScale(clef, change: true) == 1)
        }
        #expect(StaffMetrics.clefScale(.treble8vb) == 1)
        let scale = StaffMetrics.clefScale(.treble8vb, change: true)
        #expect(scale > 0.6 && scale < 0.7)
        // As big as the treble clef's change glyph, with the 8 below it.
        let treble = StaffMetrics.clefExtent(.treble, change: true)
        let guitar = StaffMetrics.clefExtent(.treble8vb, change: true)
        #expect(abs(guitar.top - treble.top) < 0.15)
        #expect(guitar.bottom < treble.bottom - 0.3)
        #expect(abs(StaffMetrics.clefWidth(.treble8vb, change: true) - StaffMetrics.clefWidth(.treble, change: true)) < 0.15)
    }

    @Test func theEightFitsUnderEveryStaff() {
        // About two and a half spaces below the bottom line, where the treble clef's tail ends at 1.6.
        let eight = -StaffMetrics.clefExtent(.treble8vb).bottom
        #expect(eight > 2.3 && eight < 2.7)
        // A staff always has three spaces below its bottom line, however lopsided the notes it fits.
        for positions in [nil, 0...8, 0...18, -2...18, -10...8] as [ClosedRange<Int>?] {
            #expect(StaffGeometry.room(fitting: positions).below - 2 > eight)
        }
    }

    private func note(_ letter: NoteLetter, _ octave: Int, at offset: Double, staff: Int = 1, clef: Clef) -> BarSymbol {
        BarBuilder.note(letter, octave, at: offset, staff: staff, clef: clef)
    }

    private func bar(_ symbols: [BarSymbol], clefs: [Clef]) -> BarDisplay {
        let staves = clefs.enumerated().map { index, clef in
            let positions = symbols.filter { $0.staff == index + 1 }.compactMap(\.position)
            return BarDisplay.Staff(number: index + 1, clef: clef, keySignature: .cMajor,
                                    positions: min(0, positions.min() ?? 0)...max(8, positions.max() ?? 8))
        }
        let measure = ScoreMeasure(number: 1, start: 0, length: 4, staves: staves.map { .init(clef: $0.clef, keySignature: $0.keySignature) },
                                   symbols: symbols.sorted { ($0.offset, $0.staff) < ($1.offset, $1.staff) })
        return BarDisplay(staves: staves, measure: measure, current: nil, answered: [], isLastBar: false)
    }

    @Test func onAGrandStaffTheEightKeepsToTheUpperStaffsSideOfTheGap() throws {
        // High notes on the lower staff reach up into the gap as far as they can without signs.
        let symbols = [note(.e, 3, at: 0, clef: .treble8vb), note(.g, 3, at: 1, clef: .treble8vb),
                       note(.e, 4, at: 0, staff: 2, clef: .bass), note(.c, 4, at: 2, staff: 2, clef: .bass)]
        for size in BarBuilder.sizes {
            let layout = BarLayout(bar: bar(symbols, clefs: [.treble8vb, .bass]), size: size)
            let upper = layout.staves[0], lower = layout.staves[1]
            let eightBottom = upper.geometry.bottomLineY - StaffMetrics.clefExtent(.treble8vb).bottom * layout.space
            #expect(eightBottom <= upper.band.upperBound)
            #expect(eightBottom < lower.geometry.y(8) - layout.space)
            let start = try #require(layout.inkBoxes.first { $0.staff == 0 && $0.kind == .start })
            #expect(start.rect.maxY <= upper.band.upperBound + 0.001)
        }
    }

    @Test func aChangeToTheGuitarClefIsDrawnAtTheChangeSize() throws {
        let symbols = [note(.e, 4, at: 0, clef: .treble), note(.g, 4, at: 1, clef: .treble),
                       note(.c, 4, at: 2, clef: .treble8vb), note(.a, 3, at: 3, clef: .treble8vb)]
        let layout = BarLayout(bar: bar(symbols, clefs: [.treble]), size: CGSize(width: 904, height: 316))
        let change = try #require(layout.clefChanges.first)
        #expect(change.clef == .treble8vb)
        let drawn = BarLayout.clefChangePath(change, layout.staves[0].geometry).boundingRect
        let (bottom, top) = StaffMetrics.clefExtent(.treble8vb, change: true)
        #expect(abs(drawn.height - (top - bottom) * layout.space) < 0.5)
        #expect(abs(drawn.width - StaffMetrics.clefWidth(.treble8vb, change: true) * layout.space) < 0.5)
        // Its left edge where the layout put it, clear of the note after it.
        #expect(abs(drawn.minX - change.left) < 0.5)
        let head = try #require(layout.chords.flatMap(\.heads).first { $0.symbol == 2 })
        #expect(drawn.maxX < head.center.x - NoteShapes.headWidth / 2 * layout.space)
    }
}
