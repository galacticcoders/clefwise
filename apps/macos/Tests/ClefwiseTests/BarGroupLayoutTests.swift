import CoreGraphics
import Testing
@testable import Clefwise

/// Notes asked together: the band behind them, how each note is inked, and the wrong marks' pills.
private typealias B = BarBuilder

private extension BarDisplay {
    /// The note named `name` (e.g. "G5", "F♯4") at `offset` on `staff`.
    func note(_ name: String, at offset: Double, staff: Int = 1) -> Int {
        measure.symbols.indices.first {
            measure.symbols[$0].pitch?.name == name && measure.symbols[$0].offset == offset && measure.symbols[$0].staff == staff
        }!
    }

    /// These notes asked together, the first as `current`.
    func asking(_ notes: [Int], answered: Set<Int> = []) -> BarDisplay {
        var bar = BarDisplay(staves: staves, measure: measure, current: notes.first, answered: answered, isLastBar: isLastBar)
        bar.together = Set(notes.dropFirst())
        return bar
    }

    func marking(_ marks: [Int: NoteMark]) -> BarDisplay {
        var bar = self
        bar.marks = marks
        return bar
    }

    func wrong(_ notes: [Int]) -> [Int: NoteMark] {
        Dictionary(uniqueKeysWithValues: notes.map { ($0, NoteMark.wrong(name: NamingSystem.solfege.name(of: measure.symbols[$0].pitch!))) })
    }
}

/// The user's bar: B4 and G5 struck together as a dotted quarter, twice.
private let screenshot = B.bar([B.note(.b, 4, at: 0, dots: 1, chord: 1), B.note(.g, 5, at: 0, dots: 1, chord: 1),
                                B.note(.e, 5, at: 1.5, .eighth), B.note(.b, 4, at: 2, dots: 1, chord: 2),
                                B.note(.g, 5, at: 2, dots: 1, chord: 2), B.note(.e, 5, at: 3.5, .eighth)])

/// A three-note chord with a quarter before it and beamed eighths after it.
private let triad = B.bar([B.note(.g, 4, at: 0), B.note(.c, 5, at: 1, chord: 7), B.note(.e, 5, at: 1, chord: 7),
                           B.note(.g, 5, at: 1, chord: 7)] + B.beamed([(.a, 4), (.b, 4)], from: 2, .eighth) + [B.note(.c, 5, at: 3)])

/// Both hands: three-note chords in each, then two-note chords, on a grand staff.
private let hands = B.bar([B.note(.e, 5, at: 0, .half, chord: 1), B.note(.g, 5, at: 0, .half, chord: 1), B.note(.c, 6, at: 0, .half, chord: 1),
                           B.note(.a, 2, at: 0, .half, staff: 2, clef: .bass, chord: 2), B.note(.e, 3, at: 0, .half, staff: 2, clef: .bass, chord: 2),
                           B.note(.c, 4, at: 0, .half, staff: 2, clef: .bass, chord: 2),
                           B.note(.d, 5, at: 2, .half, chord: 3), B.note(.f, 5, at: 2, .half, chord: 3),
                           B.note(.g, 2, at: 2, .half, staff: 2, clef: .bass, chord: 4), B.note(.d, 3, at: 2, .half, staff: 2, clef: .bass, chord: 4)],
                          grand: true)
private let handsFirst = [hands.note("E5", at: 0), hands.note("G5", at: 0), hands.note("C6", at: 0),
                          hands.note("A2", at: 0, staff: 2), hands.note("E3", at: 0, staff: 2), hands.note("C4", at: 0, staff: 2)]

/// Sixteenths in both hands with chords inside the beams and a sharp: the space beside a group is tight.
private let dense: BarDisplay = {
    var symbols: [BarSymbol] = []
    let upper: [[(NoteLetter, Int, Accidental?)]] = [[(.e, 5, nil)], [(.g, 4, .sharp), (.d, 5, nil)], [(.e, 5, nil)], [(.b, 4, nil)],
                                                     [(.c, 5, nil), (.e, 5, nil), (.a, 5, nil)], [(.b, 4, nil)], [(.c, 5, nil)], [(.a, 4, nil)]]
    let lower: [[(NoteLetter, Int)]] = [[(.a, 2)], [(.e, 3)], [(.a, 3)], [(.e, 3)], [(.a, 2), (.e, 3)], [(.c, 4)], [(.e, 3)], [(.c, 3)]]
    for step in 0..<8 {
        let part: BeamPart = step % 4 == 0 ? .begin : step % 4 == 3 ? .end : .continue
        for (letter, octave, sign) in upper[step] {
            symbols.append(B.note(letter, octave, sign ?? .natural, at: Double(step) * 0.25, .sixteenth, sign: sign, chord: 100 + step,
                                  beams: [part, part]))
        }
        for (letter, octave) in lower[step] {
            symbols.append(B.note(letter, octave, at: Double(step) * 0.25, .sixteenth, staff: 2, clef: .bass, chord: 200 + step,
                                  beams: [part, part]))
        }
    }
    symbols += [B.note(.e, 5, at: 2, .half, chord: 300), B.note(.g, 5, .sharp, at: 2, .half, sign: .sharp, chord: 300),
                B.note(.e, 2, at: 2, .half, staff: 2, clef: .bass)]
    return B.bar(symbols, grand: true, length: 3, time: TimeSignature(beats: 3, beatType: 4))
}()
private let denseFirst = [dense.note("G♯4", at: 0.25), dense.note("D5", at: 0.25), dense.note("E3", at: 0.25, staff: 2)]
private let denseSecond = [dense.note("C5", at: 1), dense.note("E5", at: 1), dense.note("A5", at: 1),
                           dense.note("A2", at: 1, staff: 2), dense.note("E3", at: 1, staff: 2)]

private func heads(_ layout: BarLayout) -> [BarLayout.InkBox] { layout.inkBoxes.filter { $0.kind == .head } }

private func head(_ layout: BarLayout, _ symbol: Int) -> BarLayout.Head {
    layout.chords.flatMap(\.heads).first { $0.symbol == symbol }!
}

@Suite struct BarGroupHighlightTests {
    @Test func oneBandCoversEveryNoteAskedOnItsStaff() throws {
        let b4 = screenshot.note("B4", at: 2), g5 = screenshot.note("G5", at: 2)
        let bar = screenshot.asking([b4, g5], answered: [0, 1, 2])
        for size in B.sizes {
            let layout = BarLayout(bar: bar, size: size)
            #expect(layout.highlights.count == 1)
            let band = try #require(layout.highlights.first)
            for box in heads(layout) where [b4, g5].contains(box.symbol!) { #expect(band.contains(box.rect)) }
            // The other notes stay outside it.
            for box in heads(layout) where ![b4, g5].contains(box.symbol!) { #expect(!band.intersects(box.rect)) }
            let staff = layout.staves[0].geometry
            #expect(band.minY <= staff.y(8) - 0.8 * layout.space && band.maxY >= staff.y(0) + 0.8 * layout.space - 0.001)
        }
    }

    @Test func aBandTakesInSigns() throws {
        let bar = B.bar([B.note(.g, 4, at: 0), B.note(.f, 4, .sharp, at: 1, sign: .sharp, chord: 5), B.note(.d, 5, at: 1, chord: 5)])
        let asked = bar.asking([1, 2])
        let layout = BarLayout(bar: asked, size: CGSize(width: 904, height: 316))
        let band = try #require(layout.highlights.first)
        let sign = try #require(head(layout, 1).accidentalFrame)
        #expect(band.minX < sign.minX && band.maxX > sign.maxX)
    }

    @Test func aGroupOnOneStaffOfAGrandStaffKeepsToIt() throws {
        let rightHand = Array(handsFirst.prefix(3))
        for size in B.sizes {
            let layout = BarLayout(bar: hands.asking(rightHand), size: size)
            let band = try #require(layout.highlights.first)
            #expect(layout.highlights.count == 1)
            #expect(band.maxY < layout.staves[1].geometry.y(8))
            for symbol in rightHand { #expect(band.contains(heads(layout).first { $0.symbol == symbol }!.rect)) }
        }
    }

    @Test func bothHandsGetOneBandThroughBothStaves() throws {
        for size in B.sizes {
            let layout = BarLayout(bar: hands.asking(handsFirst), size: size)
            #expect(layout.highlights.count == 1)
            let band = try #require(layout.highlights.first)
            #expect(band.minY < layout.staves[0].geometry.y(8) && band.maxY > layout.staves[1].geometry.y(0))
            for symbol in handsFirst { #expect(band.contains(heads(layout).first { $0.symbol == symbol }!.rect)) }
            #expect(band.minY >= 0 && band.maxY <= size.height)
        }
    }

    @Test func oneNoteAskedKeepsItsBand() throws {
        // As it was before notes could be asked together: the staff's height, the head and its sign, and 0.4 spaces either side.
        let bar = B.bar([B.note(.g, 4, at: 0), B.note(.f, 5, .sharp, at: 1, sign: .sharp), B.note(.a, 4, at: 2, .half)], current: 1)
        for size in B.sizes {
            let layout = BarLayout(bar: bar, size: size)
            let s = layout.space
            let note = head(layout, 1)
            let staff = layout.staves[0].geometry
            let halfWidth = NoteShapes.headInkWidth(note.kind) / 2 * s
            let left = min(note.center.x - halfWidth, note.accidentalFrame!.minX) - 0.4 * s
            let top = min(staff.y(8) - 0.8 * s, note.center.y - 1.1 * s), bottom = max(staff.y(0) + 0.8 * s, note.center.y + 1.1 * s)
            let expected = CGRect(x: left, y: top, width: note.center.x + halfWidth + 0.4 * s - left, height: bottom - top)
            let band = try #require(layout.highlights.first)
            #expect(abs(band.minX - expected.minX) < 0.001 && abs(band.maxX - expected.maxX) < 0.001)
            #expect(abs(band.minY - expected.minY) < 0.001 && abs(band.maxY - expected.maxY) < 0.001)
        }
    }

    @Test func bandsKeepClearOfTheNotesAround() {
        for bar in [dense.asking(denseFirst), dense.asking(denseSecond), triad.asking([1, 2, 3])] {
            for size in B.sizes {
                let layout = BarLayout(bar: bar, size: size)
                let asked = Set([bar.current!]).union(bar.together)
                for band in layout.highlights {
                    for box in layout.inkBoxes where [.head, .sign, .dot, .rest].contains(box.kind) && !asked.contains(box.symbol!) {
                        #expect(!band.intersects(box.rect), "\(box) at \(size)")
                    }
                }
            }
        }
    }
}

@Suite struct BarRoleTests {
    @Test func marksThenTheGroupThenAnswers() {
        let c5 = triad.note("C5", at: 1), e5 = triad.note("E5", at: 1), g5 = triad.note("G5", at: 1)
        let asked = triad.asking([c5, e5, g5], answered: [0])
        let layout = BarLayout(bar: asked, size: CGSize(width: 904, height: 316))
        #expect(layout.role(of: 0) == .muted)
        #expect([c5, e5, g5].allSatisfy { layout.role(of: $0) == .asked })
        #expect(layout.role(of: 4) == .normal)

        let judged = BarLayout(bar: asked.marking([c5: .right, e5: .wrong(name: "Mi")]), size: CGSize(width: 904, height: 316))
        #expect(judged.role(of: c5) == .right && judged.role(of: e5) == .wrong)
        #expect(judged.role(of: g5) == .asked)
        // A mark wins over an answer.
        let answeredToo = BarDisplay(staves: triad.staves, measure: triad.measure, current: c5, answered: [0, c5], isLastBar: false)
        #expect(BarLayout(bar: answeredToo.marking([c5: .right]), size: CGSize(width: 904, height: 316)).role(of: c5) == .right)
    }

    @Test func aChordsStemStaysInkWhileASingleNotesFollowsIt() throws {
        let c5 = triad.note("C5", at: 1), e5 = triad.note("E5", at: 1), g5 = triad.note("G5", at: 1)
        let size = CGSize(width: 904, height: 316)
        let chord = BarLayout(bar: triad.asking([c5, e5, g5]).marking([c5: .wrong(name: "Do")]), size: size)
        #expect(chord.role(of: try #require(chord.chords.first { $0.column == 1 })) == .normal)

        let single = BarLayout(bar: triad.asking([0]).marking([0: .wrong(name: "Sol")]), size: size)
        #expect(single.role(of: try #require(single.chords.first { $0.column == 0 })) == .wrong)

        // A beamed note's stem goes with its beam: ink until every note it joins is answered.
        let a4 = triad.note("A4", at: 2), b4 = triad.note("B4", at: 2.5)
        let beamed = BarLayout(bar: triad.asking([a4]).marking([a4: .right]), size: size)
        #expect(beamed.role(of: try #require(beamed.chords.first { $0.column == 2 })) == .normal)
        let done = BarLayout(bar: triad.asking([triad.note("C5", at: 3)], answered: [0, 1, 2, 3, a4, b4]), size: size)
        #expect(done.role(of: done.beams[0]) == .muted)
    }
}

@Suite struct BarMarkPillTests {
    /// Results to check, with the number of wrong notes in each.
    static let results: [BarDisplay] = {
        let b4 = screenshot.note("B4", at: 2), g5 = screenshot.note("G5", at: 2)
        let c5 = triad.note("C5", at: 1), e5 = triad.note("E5", at: 1), g5t = triad.note("G5", at: 1)
        let second = [hands.note("D5", at: 2), hands.note("F5", at: 2), hands.note("G2", at: 2, staff: 2), hands.note("D3", at: 2, staff: 2)]
        let cluster = B.bar([B.note(.a, 4, at: 0), B.note(.c, 5, at: 1, .half, chord: 3), B.note(.d, 5, at: 1, .half, chord: 3),
                             B.note(.e, 5, at: 1, .half, chord: 3), B.note(.g, 5, at: 1, .half, chord: 3), B.note(.f, 5, at: 3)])
        let clustered = [cluster.note("C5", at: 1), cluster.note("D5", at: 1), cluster.note("E5", at: 1), cluster.note("G5", at: 1)]
        let seconds = B.bar([B.note(.b, 4, at: 0, .half, chord: 3), B.note(.c, 5, .sharp, at: 0, .half, sign: .sharp, chord: 3),
                             B.note(.d, 5, at: 0, .half, chord: 3), B.note(.a, 4, at: 2), B.note(.g, 4, at: 3)])
        let close = [seconds.note("B4", at: 0), seconds.note("C♯5", at: 0), seconds.note("D5", at: 0)]
        return [
            screenshot.asking([b4, g5]).marking(screenshot.wrong([b4, g5])),
            screenshot.asking([b4, g5]).marking(screenshot.wrong([g5]).merging([b4: .right]) { $1 }),
            triad.asking([c5, e5, g5t]).marking(triad.wrong([e5]).merging([c5: .right, g5t: .right]) { $1 }),
            hands.asking(second, answered: Set(handsFirst)).marking(hands.wrong([second[1], second[2]])
                .merging([second[0]: .right, second[3]: .right]) { $1 }),
            cluster.asking(clustered).marking(cluster.wrong([clustered[1], clustered[2]]).merging([clustered[0]: .right]) { $1 }),
            seconds.asking(close).marking(seconds.wrong(close)),
            hands.asking(handsFirst).marking(hands.wrong([handsFirst[0], handsFirst[2], handsFirst[4]])),
            hands.asking(handsFirst).marking(hands.wrong(handsFirst)),
            dense.asking(denseFirst).marking(dense.wrong([denseFirst[0], denseFirst[1]])),
            dense.asking(denseSecond).marking(dense.wrong([denseSecond[0], denseSecond[2], denseSecond[3]])),
            dense.asking(denseSecond).marking(dense.wrong(denseSecond)),
        ]
    }()

    @Test(arguments: results.indices) func pillsNeverOverlapCoverANoteOrLeaveTheCanvas(_ index: Int) {
        let bar = Self.results[index]
        let wrong = bar.marks.filter { if case .wrong = $0.value { true } else { false } }.keys
        for size in B.sizes {
            for hints in [false, true] {
                var text = BarTextMetrics()
                if hints { text.hintWidth = 1.2 }
                let layout = BarLayout(bar: bar, size: size, text: text)
                #expect(Set(layout.markPills.map(\.symbol)) == Set(wrong) && layout.markPills.count == wrong.count)
                let canvas = CGRect(origin: .zero, size: size)
                for (i, pill) in layout.markPills.enumerated() {
                    #expect(canvas.contains(pill.rect), "pill \(pill.symbol) at \(size)")
                    for other in layout.markPills[(i + 1)...] { #expect(!pill.rect.intersects(other.rect), "pills at \(size)") }
                    for box in layout.inkBoxes where [.head, .sign, .dot, .rest].contains(box.kind) {
                        #expect(!pill.rect.intersects(box.rect), "pill \(pill.symbol) over \(box) at \(size)")
                    }
                    #expect(pill.fontSize <= 0.8 * layout.space + 0.001 && pill.fontSize >= 0.8 * BarLayout.markScales.last! * layout.space - 0.001)
                }
            }
        }
    }

    @Test func pillsStackBesideTheirNotesInTheirOrder() throws {
        // B4 and G5 of the user's bar, and a cluster of seconds: right of the notes, top to bottom as the notes go.
        for bar in [Self.results[0], Self.results[5], Self.results[7]] {
            for size in B.sizes {
                let layout = BarLayout(bar: bar, size: size)
                for staff in layout.staves.indices {
                    let pills = layout.markPills.filter { pill in layout.chords.contains { $0.staff == staff && $0.heads.contains { $0.symbol == pill.symbol } } }
                    let byNote = pills.sorted { head(layout, $0.symbol).center.y < head(layout, $1.symbol).center.y }
                    #expect(byNote.map(\.symbol) == pills.sorted { $0.rect.minY < $1.rect.minY }.map(\.symbol))
                    for pill in pills {
                        let note = head(layout, pill.symbol)
                        #expect(pill.rect.minX > note.center.x + NoteShapes.headInkWidth(note.kind) / 2 * layout.space)
                        // Level with its note, or nudged a little to make way for a neighbour's.
                        #expect(abs(pill.rect.midY - note.center.y) < 1.5 * layout.space)
                    }
                    // In line with each other.
                    #expect(Set(pills.map { Int($0.rect.minX.rounded()) }).count <= 1)
                }
            }
        }
        // Notes far apart keep their pills level with them.
        let layout = BarLayout(bar: Self.results[0], size: CGSize(width: 904, height: 316))
        for pill in layout.markPills { #expect(abs(pill.rect.midY - head(layout, pill.symbol).center.y) < 0.01) }
    }

    @Test func sixWrongNotesFitAtFullSizeOnAGrandStaff() {
        for size in [CGSize(width: 904, height: 316), CGSize(width: 724, height: 316)] {
            let layout = BarLayout(bar: Self.results[7], size: size)
            #expect(layout.markPills.count == 6)
            #expect(layout.markPills.allSatisfy { abs($0.fontSize - 0.8 * layout.space) < 0.001 })
        }
    }

    @Test func pillsShrinkWhereTheBarIsTight() {
        let layout = BarLayout(bar: Self.results[9], size: CGSize(width: 724, height: 316))
        #expect(layout.markPills.count == 3)
        #expect(layout.markPills.allSatisfy { $0.fontSize < 0.8 * layout.space })
    }

    @Test func aPillAboveTheStaffNamesOnlyTheNotesNearest() throws {
        // E5 of C5 E5 G5 is wrong: above the staff the pill would sit over G5, which was right, so it never goes there.
        let layout = BarLayout(bar: Self.results[2], size: CGSize(width: 904, height: 316))
        let pill = try #require(layout.markPills.first)
        #expect(pill.rect.minY > layout.staves[0].geometry.y(8) - layout.space)
        #expect(pill.rect.maxY < layout.staves[0].geometry.y(0) + layout.space)
    }

    @Test func rightMarksGetNoPill() {
        let b4 = screenshot.note("B4", at: 2), g5 = screenshot.note("G5", at: 2)
        let layout = BarLayout(bar: screenshot.asking([b4, g5]).marking([b4: .right, g5: .right]), size: CGSize(width: 904, height: 316))
        #expect(layout.markPills.isEmpty)
        #expect(layout.role(of: b4) == .right && layout.role(of: g5) == .right)
    }

    @Test func marksReplaceTheAnswerPill() {
        var text = BarTextMetrics()
        text.labelSize = CGSize(width: 2, height: 1.1)
        let b4 = screenshot.note("B4", at: 2), g5 = screenshot.note("G5", at: 2)
        let asked = screenshot.asking([b4, g5])
        #expect(BarLayout(bar: asked, size: CGSize(width: 904, height: 316), text: text).label != nil)
        let judged = BarLayout(bar: asked.marking(screenshot.wrong([g5])), size: CGSize(width: 904, height: 316), text: text)
        #expect(judged.label == nil && judged.markPills.count == 1)
    }

    @Test func stackingKeepsBoxesApartAndNearTheirTargets() throws {
        // Two boxes a fifth of their height apart are pushed apart evenly; a third far away stays put.
        let centres = try #require(BarLayout.stack(targets: [0, 0.2, 10], heights: [1, 1, 1], gap: 0.2, within: -100...100))
        #expect(abs(centres[0] - -0.5) < 1e-9 && abs(centres[1] - 0.7) < 1e-9 && abs(centres[2] - 10) < 1e-9)
        // Kept within the limits, still apart.
        let edge = try #require(BarLayout.stack(targets: [0, 0.1], heights: [1, 1], gap: 0.2, within: 0...10))
        #expect(abs(edge[0] - 0.5) < 1e-9 && abs(edge[1] - 1.7) < 1e-9)
        // Too many to fit.
        #expect(BarLayout.stack(targets: [0, 1, 2], heights: [1, 1, 1], gap: 0.2, within: 0...3) == nil)
        #expect(BarLayout.stack(targets: [], heights: [], gap: 0.2, within: 0...1) == [])
    }
}
