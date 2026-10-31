import CoreGraphics
import Testing
@testable import Clefwise

/// Builds bars by hand, as the importer would.
enum BarBuilder {
    static func note(_ letter: NoteLetter, _ octave: Int, _ accidental: Accidental = .natural, at offset: Double,
                     _ kind: NoteValue.Kind = .quarter, dots: Int = 0, staff: Int = 1, voice: Int = 1,
                     clef: Clef = .treble, sign: Accidental? = nil, shift: Int = 0, stemUp: Bool? = nil,
                     chord: Int? = nil, tie: Bool = false, tiedFrom: Bool = false) -> BarSymbol {
        let value = NoteValue(kind, dots: dots)
        return BarSymbol(pitch: Pitch(letter, octave + shift, accidental), clef: clef, staff: staff, voice: voice,
                         offset: offset, duration: value.quarters, value: value, octaveShift: shift, accidental: sign,
                         stemUp: stemUp, chord: chord ?? ownChord(offset, staff, voice, 1 + Pitch(letter, octave).diatonicIndex),
                         tiedToNext: tie, tiedFromPrevious: tiedFrom,
                         restPosition: nil, isWholeBarRest: false)
    }

    static func rest(at offset: Double, _ kind: NoteValue.Kind, staff: Int = 1, voice: Int = 1, clef: Clef = .treble,
                     wholeBar: Bool = false) -> BarSymbol {
        let value = NoteValue(kind)
        return BarSymbol(pitch: nil, clef: clef, staff: staff, voice: voice, offset: offset,
                         duration: wholeBar ? 4 : value.quarters, value: value, octaveShift: 0, accidental: nil,
                         stemUp: nil, chord: ownChord(offset, staff, voice, 0), tiedToNext: false, tiedFromPrevious: false,
                         restPosition: nil,
                         isWholeBarRest: wholeBar)
    }

    /// A chord id of a note's (or rest's) own.
    private static func ownChord(_ offset: Double, _ staff: Int, _ voice: Int, _ pitch: Int) -> Int {
        1_000_000 + Int(offset * 960) * 10_000 + pitch * 100 + staff * 10 + voice
    }

    /// One staff (treble) or a grand staff (treble and bass), sized for this bar's notes.
    static func bar(_ symbols: [BarSymbol], grand: Bool = false, fifths: Int = 0, length: Double = 4,
                    current: Int? = nil, last: Bool = false) -> BarDisplay {
        let sorted = symbols.sorted { ($0.offset, $0.staff, $0.voice) < ($1.offset, $1.staff, $1.voice) }
        let clefs: [Clef] = grand ? [.treble, .bass] : [.treble]
        let staves = clefs.enumerated().map { index, clef in
            let positions = sorted.filter { $0.staff == index + 1 }.compactMap(\.position)
            return BarDisplay.Staff(number: index + 1, clef: clef, keySignature: KeySignature(fifths: fifths),
                                    positions: min(0, positions.min() ?? 0)...max(8, positions.max() ?? 8))
        }
        let measure = ScoreMeasure(number: 1, start: 0, length: length,
                                   staves: staves.map { .init(clef: $0.clef, keySignature: $0.keySignature) },
                                   symbols: sorted)
        return BarDisplay(staves: staves, measure: measure, current: current, answered: [], isLastBar: last)
    }

    static let sizes = [CGSize(width: 904, height: 316), CGSize(width: 904, height: 420), CGSize(width: 724, height: 316)]
}

private func headX(_ layout: BarLayout, symbol: Int) -> CGFloat? {
    layout.chords.lazy.flatMap(\.heads).first { $0.symbol == symbol }?.center.x
}

@Suite struct BarLayoutSpacingTests {
    typealias B = BarBuilder

    @Test func notesStruckTogetherLineUpAcrossStaves() throws {
        var symbols: [BarSymbol] = []
        for step in 0..<8 {
            symbols.append(B.note(.e, 2, at: Double(step) * 0.5, .eighth, staff: 2, clef: .bass))
        }
        symbols += [B.note(.e, 5, at: 0), B.note(.g, 5, at: 1, dots: 1), B.note(.f, 5, .sharp, at: 2.5, .eighth),
                    B.note(.b, 4, at: 3)]
        let bar = B.bar(symbols, grand: true)
        for size in B.sizes {
            let layout = BarLayout(bar: bar, size: size)
            for (index, symbol) in bar.measure.symbols.enumerated() where symbol.staff == 1 {
                let partner = try #require(bar.measure.symbols.indices.first {
                    bar.measure.symbols[$0].staff == 2 && bar.measure.symbols[$0].offset == symbol.offset
                })
                let upper = try #require(headX(layout, symbol: index))
                let lower = try #require(headX(layout, symbol: partner))
                #expect(abs(upper - lower) < 0.001)
            }
        }
    }

    @Test func xGrowsWithOffsetAndLongerNotesGetMoreRoom() throws {
        // Half, quarter, eighth, eighth.
        let bar = B.bar([B.note(.g, 4, at: 0, .half), B.note(.a, 4, at: 2), B.note(.b, 4, at: 3, .eighth),
                         B.note(.c, 5, at: 3.5, .eighth)])
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 316))
        let xs = layout.columns.map(\.x)
        #expect(xs.count == 4)
        #expect(zip(xs, xs.dropFirst()).allSatisfy { $0 < $1 })
        let afterHalf = xs[1] - xs[0], afterQuarter = xs[2] - xs[1], afterEighth = xs[3] - xs[2]
        #expect(afterHalf > afterQuarter)
        #expect(afterQuarter > afterEighth)
        // Engraver's spacing, not proportional: a half gets less than twice a quarter's room.
        #expect(afterHalf < 2 * afterQuarter)
    }

    @Test func theBarFillsTheWidth() {
        let bar = B.bar([B.note(.g, 4, at: 0), B.note(.a, 4, at: 1), B.note(.b, 4, at: 2, .half)])
        for size in B.sizes {
            let layout = BarLayout(bar: bar, size: size)
            #expect(layout.columns.first!.x > layout.barStart)
            #expect(layout.columns.last!.x < layout.notesEnd)
            // The last note's room by time reaches the end of the bar: a half note's worth.
            let last = layout.notesEnd - layout.columns.last!.x
            let quarter = layout.columns[1].x - layout.columns[0].x
            #expect(last > quarter * 1.2)
            #expect(abs(layout.staffRight - (size.width - layout.space * 0.5)) < 0.001)
        }
    }

    @Test func stretchMeetsMinimumsAndFillsTheWidth() {
        let widths = BarLayout.stretch([(min: 10, ideal: 1), (min: 50, ideal: 1), (min: 5, ideal: 2)], toFill: 200)
        #expect(abs(widths.reduce(0, +) - 200) < 0.01)
        #expect(widths[1] >= 50)
        #expect(abs(widths[2] - 2 * widths[0]) < 0.01)
        // Not enough room: every segment's minimum.
        #expect(BarLayout.stretch([(min: 10, ideal: 1), (min: 20, ideal: 1)], toFill: 25) == [10, 20])
    }

    @Test func aDenseBarShrinksTheStaffInsteadOfOverlapping() throws {
        var symbols: [BarSymbol] = []
        let letters: [NoteLetter] = [.c, .d, .e, .f, .g, .a, .b, .c]
        for step in 0..<16 {
            let sign: Accidental? = step % 3 == 0 ? .sharp : step % 3 == 1 ? .flat : nil
            let accidental: Accidental = sign ?? .natural
            symbols.append(B.note(letters[step % 8], 5, accidental, at: Double(step) * 0.25, .sixteenth, sign: sign))
            symbols.append(B.note(letters[(step + 3) % 8], 3, accidental, at: Double(step) * 0.25, .sixteenth, staff: 2,
                                  clef: .bass, sign: sign))
        }
        let bar = B.bar(symbols, grand: true)
        let size = CGSize(width: 724, height: 316)
        let layout = BarLayout(bar: bar, size: size)
        let sparse = BarLayout(bar: B.bar([B.note(.c, 5, at: 0), B.note(.c, 3, at: 0, staff: 2, clef: .bass)], grand: true),
                               size: size)
        #expect(layout.space < sparse.space)
        // No two columns' ink overlaps on a staff: heads, signs, dots and flags.
        for staff in 0..<2 {
            let boxes = layout.chords.filter { $0.staff == staff }.map { chord -> (column: Int, rect: CGRect) in
                var rect = chord.heads.map { headBox($0, layout.space) }.reduce(CGRect.null) { $0.union($1) }
                for head in chord.heads { if let frame = head.accidentalFrame { rect = rect.union(frame) } }
                return (chord.column, rect)
            }
            for a in boxes {
                for b in boxes where b.column == a.column + 1 {
                    #expect(a.rect.maxX < b.rect.minX)
                }
            }
        }
    }

    @Test func aSingleStaffIsSizedAndPlacedLikeStaffView() {
        let positions = [0...8, -4...12, -9...16, 2...20]
        for size in BarBuilder.sizes {
            for range in positions {
                let staff = BarDisplay.Staff(number: 1, clef: .treble, keySignature: .cMajor, positions: range)
                let measure = ScoreMeasure(number: 1, start: 0, length: 4, staves: [.init(clef: .treble, keySignature: .cMajor)],
                                           symbols: [B.note(.g, 4, at: 0, .whole)])
                let bar = BarDisplay(staves: [staff], measure: measure, current: 0, answered: [], isLastBar: false)
                let layout = BarLayout(bar: bar, size: size)
                let staffView = StaffGeometry(size: size, fitting: range)
                #expect(abs(layout.space - staffView.space) < 0.0001)
                #expect(abs(layout.staves[0].geometry.bottomLineY - staffView.bottomLineY) < 0.0001)
            }
        }
    }

    @Test func aGrandStaffLeavesRoomForLedgerNotesBetweenTheStaves() {
        let close = BarLayout.grandStaffReach(upper: 0...8, lower: 0...8)
        let far = BarLayout.grandStaffReach(upper: -6...8, lower: 0...14)
        #expect(far.upper > close.upper && far.lower > close.lower)
        // C4 two ledger lines below the treble, with a sharp hanging under it.
        #expect(BarLayout.grandStaffReach(upper: -4...8, lower: 0...8).upper == 2 + 1.25)

        let bar = B.bar([B.note(.a, 3, at: 0, sign: .sharp), B.note(.e, 4, at: 0, staff: 2, clef: .bass)], grand: true)
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 316))
        let upper = layout.staves[0], lower = layout.staves[1]
        #expect(upper.geometry.y(0) < lower.geometry.y(8))
        #expect(upper.band.upperBound == lower.band.lowerBound)
        // Each staff's ink stays in its own strip.
        for box in layout.inkBoxes {
            let band = layout.staves[box.staff].band
            #expect(box.rect.minY >= band.lowerBound - 0.5 && box.rect.maxY <= band.upperBound + 0.5)
        }
    }
}

@Suite struct BarLayoutNoteTests {
    typealias B = BarBuilder

    @Test func stemDirections() {
        #expect(BarLayout.stemDirection(positions: [3], voice: 1, multiVoice: false))
        #expect(!BarLayout.stemDirection(positions: [4], voice: 1, multiVoice: false))
        #expect(!BarLayout.stemDirection(positions: [6], voice: 1, multiVoice: false))
        // A chord goes by the note furthest from the middle line; even, down.
        #expect(!BarLayout.stemDirection(positions: [0, 9], voice: 1, multiVoice: false))
        #expect(BarLayout.stemDirection(positions: [-3, 6], voice: 1, multiVoice: false))
        #expect(!BarLayout.stemDirection(positions: [2, 6], voice: 1, multiVoice: false))
        // Two voices on a staff: odd voices up, even down, wherever the notes are.
        #expect(BarLayout.stemDirection(positions: [-2], voice: 1, multiVoice: true) == true)
        #expect(BarLayout.stemDirection(positions: [10], voice: 2, multiVoice: true) == false)
    }

    @Test func theScoresStemDirectionWins() throws {
        let bar = B.bar([B.note(.g, 4, at: 0, stemUp: false), B.note(.a, 5, at: 1, stemUp: true), B.note(.c, 4, at: 2)])
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 316))
        let stems = layout.chords.sorted { $0.column < $1.column }.map(\.stemUp)
        #expect(stems == [false, true, true])
        // Up from the right of the head, down from the left; at least to the middle line on one voice.
        let c4 = try #require(layout.chords.first { $0.column == 2 })
        let stem = try #require(c4.stem)
        #expect(stem.midX > c4.heads[0].center.x)
        #expect(stem.minY <= layout.staves[0].geometry.y(4) + 0.001)
        let g4 = try #require(layout.chords.first { $0.column == 0 })
        #expect(try #require(g4.stem).midX < g4.heads[0].center.x)
    }

    @Test func secondsGoOnTheOtherSideOfTheStem() {
        // Stem up: the upper note of a second goes right; stem down: the lower one goes left.
        #expect(BarLayout.flippedHeads(positions: [1, 2], stemUp: true) == [false, true])
        #expect(BarLayout.flippedHeads(positions: [5, 6, 8], stemUp: false) == [true, false, false])
        // A cluster alternates.
        #expect(BarLayout.flippedHeads(positions: [0, 1, 2], stemUp: true) == [false, true, false])
        #expect(BarLayout.flippedHeads(positions: [0, 2, 4], stemUp: true) == [false, false, false])

        let bar = B.bar([B.note(.c, 5, .sharp, at: 0, .half, sign: .sharp, chord: 1), B.note(.d, 5, at: 0, .half, chord: 1),
                         B.note(.f, 5, .sharp, at: 0, .half, sign: .sharp, chord: 1)])
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 316))
        let chord = layout.chords[0]
        #expect(!chord.stemUp)
        let stem = chord.stem!
        #expect(chord.heads[0].isFlipped && chord.heads[0].center.x < stem.minX)
        #expect(chord.heads[1].center.x > stem.maxX && chord.heads[2].center.x > stem.maxX)
    }

    @Test func stackedAccidentalsNeverCollide() {
        let bar = B.bar([B.note(.c, 5, .sharp, at: 0, .half, sign: .sharp, chord: 1), B.note(.d, 5, at: 0, .half, chord: 1),
                         B.note(.f, 5, .sharp, at: 0, .half, sign: .sharp, chord: 1),
                         B.note(.e, 4, .flat, at: 2, sign: .flat, chord: 2), B.note(.g, 4, .flat, at: 2, sign: .flat, chord: 2),
                         B.note(.b, 4, .flat, at: 2, sign: .flat, chord: 2),
                         B.note(.f, 4, at: 3, .eighth, sign: .natural, chord: 3), B.note(.g, 4, .sharp, at: 3, .eighth, sign: .sharp, chord: 3)])
        for size in B.sizes {
            let layout = BarLayout(bar: bar, size: size)
            for chord in layout.chords {
                let frames = chord.heads.compactMap(\.accidentalFrame)
                let heads = chord.heads.map { headBox($0, layout.space) }
                for (i, a) in frames.enumerated() {
                    for b in frames[(i + 1)...] { #expect(!a.intersects(b)) }
                    for head in heads { #expect(!a.intersects(head)) }
                }
            }
            // Three flats a third apart take three columns, the highest nearest the notes.
            let flats = layout.chords.first { $0.column == 1 }!.heads
            #expect(flats.map { $0.accidentalColumn! } == [2, 1, 0])
        }
        #expect(BarLayout.accidentalColumns([(.sharp, 8), (.sharp, 1)]) == [0, 0])
        #expect(BarLayout.accidentalColumns([(.sharp, 8), (.sharp, 3)]) == [0, 1])
    }

    @Test func dotsSitInSpaces() {
        let bar = B.bar([B.note(.f, 4, at: 0, .quarter, dots: 1, chord: 1), B.note(.g, 4, at: 0, .quarter, dots: 1, chord: 1),
                         B.note(.b, 4, at: 1.5, .half, dots: 1)])
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 316))
        let staff = layout.staves[0].geometry
        let dotYs = layout.chords.flatMap(\.heads).flatMap(\.dots).map(\.y)
        #expect(dotYs.count == 3)
        // F4 (a space) keeps its own; G4 and B4 (lines) move up to the space above.
        #expect(Set(dotYs.map { Int(((staff.bottomLineY - $0) / (staff.space / 2)).rounded()) }) == [1, 3, 5])
    }

    @Test func tiesJoinNotesAndRunToTheBarLines() throws {
        let bar = B.bar([B.note(.g, 4, at: 0, .half, tiedFrom: true), B.note(.b, 4, at: 2, tie: true),
                         B.note(.b, 4, at: 3, tie: true)])
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 316))
        #expect(layout.ties.count == 3)
        let incoming = try #require(layout.ties.first { $0.symbol == 0 })
        #expect(incoming.start.x < layout.columns[0].x && incoming.start.x >= layout.barStart)
        let between = try #require(layout.ties.first { $0.symbol == 1 })
        #expect(between.start.x > layout.columns[1].x && between.end.x < layout.columns[2].x)
        // Stems down from the middle line, so the ties bow up.
        #expect(between.up)
        let outgoing = try #require(layout.ties.first { $0.symbol == 2 })
        #expect(outgoing.end.x > layout.columns[2].x && outgoing.end.x <= layout.staffRight)
    }

    @Test func restsSitInTheirUsualPlacesAndMakeWayForAnotherVoice() {
        let usual = BarBuilder.rest(at: 0, .whole)
        #expect(BarLayout.restPosition(usual, kind: .whole, multiVoice: false) == 6)
        #expect(BarLayout.restPosition(BarBuilder.rest(at: 0, .quarter), kind: .quarter, multiVoice: false) == 4)
        #expect(BarLayout.restPosition(BarBuilder.rest(at: 0, .quarter, voice: 1), kind: .quarter, multiVoice: true) == 8)
        #expect(BarLayout.restPosition(BarBuilder.rest(at: 0, .half, voice: 2), kind: .half, multiVoice: true) == 0)

        // A lower-voice rest under an upper-voice note on the bottom line moves clear of it.
        let bar = B.bar([B.note(.g, 4, at: 0, voice: 1), B.rest(at: 0, .quarter, voice: 2),
                         B.rest(at: 0, .whole, staff: 2, clef: .bass, wholeBar: true)], grand: true)
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 420))
        let head = headBox(layout.chords[0].heads[0], layout.space)
        let rest = layout.rests.first { $0.staff == 0 }!
        #expect(rest.frame.minY > head.maxY)
        // The whole-bar rest is centred in the bar.
        let whole = layout.rests.first { $0.staff == 1 }!
        #expect(abs(whole.origin.x - (layout.barStart + layout.notesEnd) / 2) < 0.001)
    }

    @Test func aClefChangeGetsASmallClefBeforeItsNote() throws {
        let bar = B.bar([B.note(.c, 3, at: 0, staff: 2, clef: .bass), B.note(.g, 4, at: 1, staff: 2, clef: .treble),
                         B.note(.c, 5, at: 0), B.note(.d, 5, at: 1)], grand: true)
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 316))
        let change = try #require(layout.clefChanges.first)
        #expect(layout.clefChanges.count == 1)
        #expect(change.clef == .treble && change.staff == 1 && change.column == 1)
        #expect(change.left > layout.columns[0].x && change.left < layout.columns[1].x)
        #expect(layout.staves[1].endClef == .treble)
    }

    @Test func anOctaveMarkSpansItsRunAboveTheNotes() throws {
        let bar = B.bar([B.note(.e, 5, at: 0, shift: 1), B.note(.g, 5, at: 1, shift: 1), B.note(.a, 5, at: 2, shift: 1),
                         B.note(.b, 4, at: 3)])
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 316))
        #expect(layout.octaveMarks.count == 1)
        let mark = try #require(layout.octaveMarks.first)
        #expect(mark.symbols.count == 3)
        #expect(mark.hookX > layout.columns[2].x && mark.hookX < layout.columns[3].x)
        let notes = layout.inkBoxes.filter { $0.symbol != nil }.map(\.rect)
        #expect(notes.allSatisfy { $0.minY > mark.lineY + mark.halfDigit })
        #expect(mark.lineY - mark.halfDigit > 0)
    }
}

@Suite struct BarLayoutCanvasTests {
    typealias B = BarBuilder

    /// Bars that push at the edges: ledger notes, two voices, octave marks, ties, rests, dense rhythm.
    static let bars: [BarDisplay] = {
        var dense: [BarSymbol] = []
        for step in 0..<16 {
            dense.append(B.note(.a, 5, .sharp, at: Double(step) * 0.25, .sixteenth, sign: .sharp))
            dense.append(B.note(.c, 2, at: Double(step) * 0.25, .sixteenth, staff: 2, clef: .bass))
        }
        return [
            B.bar([B.note(.c, 4, at: 0, .eighth, dots: 1), B.note(.a, 5, at: 1.5, .half, tie: true), B.rest(at: 3.5, .eighth)],
                  fifths: 7, current: 1),
            B.bar([B.note(.e, 5, at: 0, voice: 1, shift: 1), B.note(.g, 5, at: 1, .eighth, voice: 1, shift: 1),
                   B.note(.c, 5, at: 0, .half, voice: 2), B.rest(at: 2, .quarter, voice: 2), B.note(.c, 4, at: 3, .thirtySecond, voice: 2),
                   B.rest(at: 0, .whole, staff: 2, clef: .bass, wholeBar: true)], grand: true, current: 0, last: true),
            B.bar(dense, grand: true, current: 3),
            B.bar([B.note(.c, 2, at: 0, .sixtyFourth, staff: 2, voice: 2, clef: .bass), B.note(.c, 4, at: 0, .whole, staff: 2, clef: .bass),
                   B.note(.c, 6, at: 0, .sixtyFourth, shift: -1, stemUp: false)], grand: true, current: 1),
        ]
    }()

    @Test(arguments: bars.indices) func everythingStaysOnTheCanvas(_ index: Int) {
        for size in B.sizes {
            var text = BarTextMetrics()
            text.labelSize = CGSize(width: 2.4, height: 1.2)
            text.hintWidth = 1.2
            let layout = BarLayout(bar: Self.bars[index], size: size, text: text)
            let canvas = CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5)
            for box in layout.inkBoxes { #expect(canvas.contains(box.rect), "\(box) at \(size)") }
            if let label = layout.label {
                #expect(canvas.contains(label))
                let current = Self.bars[index].current!
                let head = layout.chords.flatMap(\.heads).first { $0.symbol == current }!
                #expect(!label.intersects(headBox(head, layout.space)))
            }
        }
    }

    @Test func thePillGoesOutsideTheStaffByTheNote() throws {
        var text = BarTextMetrics()
        text.labelSize = CGSize(width: 2, height: 1.1)
        let single = BarLayout(bar: B.bar([B.note(.g, 4, at: 0), B.note(.f, 5, .sharp, at: 1)], fifths: 1, current: 1),
                               size: CGSize(width: 904, height: 316), text: text)
        let label = try #require(single.label)
        #expect(label.maxY < single.staves[0].geometry.y(8))
        #expect(abs(label.midX - single.columns[1].x) < 1)

        let grand = BarLayout(bar: B.bar([B.note(.g, 4, at: 0), B.note(.c, 3, at: 0, staff: 2, clef: .bass)], grand: true,
                                         current: 1), size: CGSize(width: 904, height: 420), text: text)
        let lower = try #require(grand.label)
        #expect(lower.minY > grand.staves[1].geometry.y(0))
    }
}

private func headBox(_ head: BarLayout.Head, _ space: CGFloat) -> CGRect {
    let box = NoteShapes.head(head.kind).cgPath.boundingBoxOfPath
    return CGRect(x: head.center.x + box.minX * space, y: head.center.y + box.minY * space,
                  width: box.width * space, height: box.height * space)
}
