import CoreGraphics
import CoreText
import Testing
@testable import Clefwise

/// The bar from Tiersen's Comptine the beams were drawn to match: an eighth rest, then G4 F4
/// sixteenths, a G4 eighth and B4 C5 sixteenths, all one group, then a B4 half note.
private let comptine: BarDisplay = {
    typealias B = BarBuilder
    return B.bar([
        B.rest(at: 0, .eighth),
        B.note(.g, 4, at: 0.5, .sixteenth, beams: [.begin, .begin]),
        B.note(.f, 4, at: 0.75, .sixteenth, beams: [.continue, .end]),
        B.note(.g, 4, at: 1, .eighth, beams: [.continue]),
        B.note(.b, 4, at: 1.5, .sixteenth, beams: [.continue, .begin]),
        B.note(.c, 5, at: 1.75, .sixteenth, beams: [.end, .end]),
        B.note(.b, 4, at: 2, .half),
    ], time: TimeSignature(beats: 4, beatType: 4))
}()

/// Bars with beams of every kind, for the checks every beam must pass.
private let beamedBars: [BarDisplay] = {
    typealias B = BarBuilder
    return [
        comptine,
        // Dotted rhythms with hooks, both ways.
        B.bar([B.note(.g, 4, at: 0, .eighth, dots: 1, beams: [.begin]), B.note(.a, 4, at: 0.75, .sixteenth, beams: [.end, .backwardHook]),
               B.note(.b, 4, at: 1, .sixteenth, beams: [.begin, .forwardHook]), B.note(.c, 5, at: 1.25, .eighth, dots: 1, beams: [.end]),
               B.note(.e, 5, at: 2, .eighth, dots: 1, beams: [.begin]), B.note(.d, 5, at: 2.75, .sixteenth, beams: [.end, .backwardHook]),
               B.note(.f, 5, at: 3, .sixteenth, beams: [.begin, .forwardHook]), B.note(.a, 5, at: 3.25, .eighth, dots: 1, beams: [.end])]),
        // 32nds up and down, steep leaps, same notes, a concave group.
        B.bar(B.beamed([(.c, 4), (.d, 4), (.e, 4), (.f, 4), (.g, 4), (.a, 4), (.b, 4), (.c, 5)], from: 0, .thirtySecond)
              + B.beamed([(.g, 5), (.f, 5), (.e, 5), (.d, 5), (.c, 5), (.b, 4), (.a, 4), (.g, 4)], from: 1, .thirtySecond)
              + B.beamed([(.c, 4), (.c, 6)], from: 2, .eighth) + B.beamed([(.g, 4), (.g, 4)], from: 3, .eighth)),
        B.bar(B.beamed([(.e, 4), (.c, 5), (.e, 4), (.f, 4)], from: 0, .sixteenth) + B.beamed([(.a, 5), (.a, 4)], from: 1, .eighth)
              + B.beamed([(.c, 4), (.g, 4), (.e, 5), (.c, 6)], from: 2, .sixteenth) + B.beamed([(.d, 5), (.a, 5), (.f, 5), (.d, 5)], from: 3, .sixteenth)),
        // Chords, one with a sharp under the beam; two voices; an 8va line.
        B.bar([B.note(.g, 4, at: 0, .sixteenth, chord: 1, beams: [.begin, .begin]), B.note(.d, 5, at: 0, .sixteenth, chord: 1, beams: [.begin, .begin]),
               B.note(.a, 4, at: 0.25, .sixteenth, chord: 2, beams: [.continue, .continue]), B.note(.e, 5, at: 0.25, .sixteenth, chord: 2, beams: [.continue, .continue]),
               B.note(.f, 4, .sharp, at: 0.5, .sixteenth, sign: .sharp, chord: 3, beams: [.continue, .continue]),
               B.note(.d, 5, at: 0.5, .sixteenth, chord: 3, beams: [.continue, .continue]),
               B.note(.g, 4, at: 0.75, .sixteenth, chord: 4, beams: [.end, .end]), B.note(.e, 5, at: 0.75, .sixteenth, chord: 4, beams: [.end, .end])]
              + B.beamed([(.c, 5), (.d, 5), (.e, 5), (.f, 5)], from: 1, .eighth, voice: 1)
              + B.beamed([(.e, 4), (.f, 4), (.g, 4), (.a, 4)], from: 1, .eighth, voice: 2)
              + B.beamed([(.a, 5), (.b, 5), (.c, 6), (.d, 6)], from: 3, .sixteenth, shift: 1)),
        // A grand staff: sixteenths over eighth arpeggios.
        B.bar(B.beamed([(.e, 5), (.d, 5), (.c, 5), (.b, 4)], from: 0, .sixteenth) + B.beamed([(.c, 5), (.e, 5), (.g, 5), (.c, 6)], from: 1, .sixteenth)
              + B.beamed([(.c, 3), (.g, 3)], from: 0, .eighth, staff: 2, clef: .bass)
              + B.beamed([(.e, 3), (.g, 3), (.c, 4)], from: 1, .eighth, staff: 2, clef: .bass)
              + B.beamed([(.c, 2), (.g, 2), (.e, 3), (.g, 3)], from: 2.5, .eighth, staff: 2, clef: .bass), grand: true),
    ]
}()

private func layouts(_ bar: BarDisplay) -> [BarLayout] {
    BarBuilder.sizes.map { BarLayout(bar: bar, size: $0) }
}

@Suite struct BeamGroupTests {
    typealias B = BarBuilder

    @Test func aGroupSharesOneStemDirection() throws {
        // On their own, G4 would go up and the others down; F5 is furthest from the middle line, so all go down.
        let bar = B.bar(B.beamed([(.g, 4), (.b, 4), (.d, 5), (.f, 5)], from: 0, .sixteenth))
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 316))
        let beam = try #require(layout.beams.first)
        #expect(layout.beams.count == 1 && beam.chords.count == 4 && !beam.stemUp)
        #expect(beam.chords.allSatisfy { !layout.chords[$0].stemUp })
        for bar in beamedBars {
            for layout in layouts(bar) {
                for beam in layout.beams {
                    #expect(Set(beam.chords.map { layout.chords[$0].stemUp }) == [beam.stemUp])
                }
            }
        }
    }

    @Test func theScoresDirectionWinsWhenTheGroupAgrees() throws {
        let agreed = B.bar(B.beamed([(.e, 5), (.g, 5)], from: 0, .eighth, stemUp: true))
        #expect(BarLayout(bar: agreed, size: CGSize(width: 904, height: 316)).beams.first?.stemUp == true)
        // Up, then down: the group falls back to the rule (G4 and D5 are as far from the middle; even goes down).
        var notes = B.beamed([(.g, 4), (.d, 5)], from: 0, .eighth)
        notes[0] = B.note(.g, 4, at: 0, .eighth, stemUp: true, beams: [.begin])
        notes[1] = B.note(.d, 5, at: 0.5, .eighth, stemUp: false, beams: [.end])
        let split = BarLayout(bar: B.bar(notes), size: CGSize(width: 904, height: 316))
        let beam = try #require(split.beams.first)
        #expect(!beam.stemUp && beam.chords.allSatisfy { !split.chords[$0].stemUp })
    }

    @Test func twoVoicesKeepTheirSides() {
        let bar = B.bar(B.beamed([(.c, 5), (.d, 5)], from: 0, .eighth, voice: 1) + B.beamed([(.b, 4), (.a, 4)], from: 0, .eighth, voice: 2))
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 316))
        #expect(layout.beams.map(\.stemUp).sorted { $0 && !$1 } == [true, false])
        #expect(layout.beams.first { $0.voice == 1 }?.stemUp == true)
    }

    @Test func groupsFollowTheirBeamParts() {
        let layout = BarLayout(bar: comptine, size: CGSize(width: 904, height: 316))
        #expect(layout.beams.count == 1)
        let beam = layout.beams[0]
        #expect(beam.chords.count == 5 && beam.stemUp)
        // The primary beam over all five, a sixteenth beam over G4 F4 and another over B4 C5.
        #expect(beam.segments.filter { $0.level == 0 }.count == 1)
        let sixteenths = beam.segments.filter { $0.level == 1 }.sorted { $0.topLeft.x < $1.topLeft.x }
        #expect(sixteenths.count == 2 && sixteenths.allSatisfy { !$0.isHook })
        let stems = beam.chords.map { layout.chords[$0].stem! }
        #expect(abs(sixteenths[0].topLeft.x - stems[0].minX) < 0.01 && abs(sixteenths[0].topRight.x - stems[1].maxX) < 0.01)
        #expect(abs(sixteenths[1].topLeft.x - stems[3].minX) < 0.01 && abs(sixteenths[1].topRight.x - stems[4].maxX) < 0.01)
        // The half note and the rest stay out of it.
        #expect(layout.chords.filter { $0.beam == nil }.count == 1)
    }

    @Test func hooksPointTheWayTheirPartsSay() throws {
        let bar = B.bar([B.note(.g, 4, at: 0, .eighth, dots: 1, beams: [.begin]), B.note(.a, 4, at: 0.75, .sixteenth, beams: [.end, .backwardHook]),
                         B.note(.b, 4, at: 1, .sixteenth, beams: [.begin, .forwardHook]), B.note(.a, 4, at: 1.25, .eighth, dots: 1, beams: [.end])])
        for layout in layouts(bar) {
            #expect(layout.beams.count == 2)
            for beam in layout.beams {
                let hooks = beam.segments.filter(\.isHook)
                #expect(beam.segments.count == 2 && hooks.count == 1 && hooks[0].level == 1)
                let hook = hooks[0]
                let stems = beam.chords.map { layout.chords[$0].stem! }
                let length = hook.topRight.x - hook.topLeft.x
                #expect(length > 0.6 * layout.space && length <= (BarLayout.Metrics.hookLength + 0.12) * layout.space)
                if beam.chords.first == layout.beams[0].chords.first {
                    // Backward, on the second note: from the left up to its stem.
                    #expect(abs(hook.topRight.x - stems[1].maxX) < 0.01 && hook.topLeft.x > stems[0].maxX)
                } else {
                    // Forward, on the first note: from its stem towards the next.
                    #expect(abs(hook.topLeft.x - stems[0].minX) < 0.01 && hook.topRight.x < stems[1].minX)
                }
            }
        }
    }

    @Test func levelsStackTowardsTheNotes() throws {
        let bar = B.bar(B.beamed([(.c, 4), (.e, 4), (.g, 4), (.c, 5)], from: 0, .thirtySecond)
                        + B.beamed([(.a, 5), (.f, 5), (.d, 5), (.b, 4)], from: 1, .thirtySecond))
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 420))
        for beam in layout.beams {
            let levels = beam.segments.sorted { $0.level < $1.level }
            #expect(levels.map(\.level) == [0, 1, 2])
            for (outer, inner) in zip(levels, levels.dropFirst()) {
                let x = outer.topLeft.x
                // 0.5 thick, a quarter space apart, each further one nearer the notes.
                let gap = beam.stemUp ? inner.top(at: x) - (outer.top(at: x) + outer.thickness)
                    : outer.top(at: x) - (inner.top(at: x) + inner.thickness)
                #expect(abs(gap - SMuFL.beamSpacing * layout.space) < 0.01)
                #expect(abs(outer.thickness - 0.5 * layout.space) < 0.01)
            }
        }
    }

    @Test func beamedNotesHaveNoFlags() {
        let bar = B.bar(B.beamed([(.c, 5), (.d, 5)], from: 0, .eighth) + [B.note(.e, 5, at: 1, .eighth), B.note(.f, 4, at: 1.5, .sixteenth)])
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 316))
        for chord in layout.chords {
            if chord.beam != nil {
                #expect(chord.flagOrigin == nil && chord.flags == 0)
            } else {
                #expect(chord.flagOrigin != nil && chord.flags == chord.value.flags)
            }
        }
        // A lone note with a beam part (a group cut short) keeps its flag.
        let lone = BarLayout(bar: B.bar([B.note(.c, 5, at: 0, .eighth, beams: [.begin]), B.note(.d, 5, at: 1, .quarter)]),
                             size: CGSize(width: 904, height: 316))
        #expect(lone.beams.isEmpty && lone.chords[0].flagOrigin != nil)
    }
}

@Suite struct BeamGeometryTests {
    typealias B = BarBuilder

    @Test func everyStemMeetsItsBeam() {
        for bar in beamedBars {
            for layout in layouts(bar) {
                for beam in layout.beams {
                    let primary = beam.segments.first { $0.level == 0 }!
                    for index in beam.chords {
                        let stem = layout.chords[index].stem!
                        let end = beam.stemUp ? stem.minY : stem.maxY
                        let top = primary.top(at: stem.midX)
                        #expect(end >= top - 0.01 && end <= top + primary.thickness + 0.01)
                        // The stem runs from its note to the beam, not past it.
                        #expect(stem.minX >= primary.topLeft.x - 0.01 && stem.maxX <= primary.topRight.x + 0.01)
                    }
                }
            }
        }
    }

    @Test func stemsAreLongEnoughAndReachTheMiddleLine() {
        for bar in beamedBars {
            for layout in layouts(bar) {
                for beam in layout.beams {
                    let staff = layout.staves[beam.staff].geometry
                    let primary = beam.segments.first { $0.level == 0 }!
                    let levels = beam.segments.map(\.level).max()! + 1
                    for index in beam.chords {
                        let chord = layout.chords[index]
                        let stem = chord.stem!
                        let outer = beam.stemUp ? primary.top(at: stem.midX) : primary.top(at: stem.midX) + primary.thickness
                        let nearest = beam.stemUp ? chord.heads.last! : chord.heads.first!
                        let length = abs(nearest.center.y - outer) / layout.space
                        // Squeezed between a grand staff's staves, or under an octave mark, a little shorter.
                        let squeezed = bar.staves.count > 1 || chord.heads.contains { bar.measure.symbols[$0.symbol].octaveShift != 0 }
                        let shortest = squeezed ? BarLayout.squeezedBeamedStem(levels: levels)
                            : BarLayout.shortestBeamedStem(levels: levels) - BarLayout.Metrics.beamNudge
                        #expect(length >= shortest - 0.01, "stem \(length) spaces with \(levels) beams, bar \(bar.measure.symbols.count) voice \(beam.voice) up \(beam.stemUp) at \(layout.size)")
                        if bar.staves.count == 1, Set(bar.measure.symbols.map(\.voice)).count == 1 {
                            #expect(beam.stemUp ? outer <= staff.y(4) + 0.01 : outer >= staff.y(4) - 0.01)
                        }
                    }
                }
            }
        }
    }

    @Test func slopesFollowTheNotesWithinLimits() {
        func fit(_ nearest: [Int], xs: [CGFloat], up: Bool = true) -> BarLayout.BeamLine {
            BarLayout.fitBeam(stems: zip(xs, nearest).map { BarLayout.BeamStem(x: $0, nearest: $1, levels: 1) }, up: up,
                              reachesMiddle: true, limits: -100...100)
        }
        // Rising notes, a rising beam; at most a space, however steep the leap.
        let rising = fit([0, 2, 4, 6], xs: [0, 3, 6, 9])
        #expect(rising.last > rising.first)
        let leap = fit([-2, 12], xs: [0, 10])
        #expect(leap.last > leap.first && (leap.last - leap.first) / 2 <= BarLayout.Metrics.maxBeamRise + 0.001)
        // Narrow groups slope less: two notes two spaces apart rise at most half a space.
        let narrow = fit([-2, 12], xs: [0, 2.5])
        #expect((narrow.last - narrow.first) / 2 <= 0.5 + 0.001 && narrow.last > narrow.first)
        // A step rises a quarter space, give or take the nudge.
        let step = fit([2, 3], xs: [0, 4])
        #expect((step.last - step.first) / 2 > 0 && (step.last - step.first) / 2 <= 0.5)
        // Falling notes with stems down fall too.
        let falling = fit([8, 5], xs: [0, 4], up: false)
        #expect(falling.last < falling.first)
        // Flat: the same first and last note, or an inner note further out than both ends.
        #expect(fit([2, 5, 2], xs: [0, 3, 6]).first == fit([2, 5, 2], xs: [0, 3, 6]).last)
        let concave = fit([0, 5, 2], xs: [0, 3, 6])
        #expect(concave.first == concave.last)
        let concaveDown = fit([7, 2, 6], xs: [0, 3, 6], up: false)
        #expect(concaveDown.first == concaveDown.last)
        // Repeated notes in a bar.
        for layout in layouts(B.bar(B.beamed([(.g, 4), (.g, 4), (.g, 4), (.g, 4)], from: 0, .sixteenth))) {
            let primary = layout.beams[0].segments[0]
            #expect(abs(primary.topLeft.y - primary.topRight.y) < 0.01)
        }
    }

    @Test func beamsSitStraddleOrHangInTheStaff() {
        // No beam level's lower edge half a position above a line, inside the staff or just outside it.
        func clean(_ line: BarLayout.BeamLine, up: Bool, levels: Int) -> Bool {
            [line.first, line.last].allSatisfy { outer in
                (0..<levels).allSatisfy { level in
                    let inset = 2 * BarLayout.Metrics.beamPitch * CGFloat(level)
                    let lower = up ? outer - inset - 1 : outer + inset
                    guard lower >= -1.5, lower <= 8.5 else { return true }
                    let remainder = (lower.truncatingRemainder(dividingBy: 2) + 2).truncatingRemainder(dividingBy: 2)
                    return abs(remainder - 0.5) > 0.01 && abs(remainder * 2 - (remainder * 2).rounded()) < 0.01
                }
            }
        }
        for first in -3...9 {
            for second in -3...9 {
                for levels in 1...3 {
                    for up in [true, false] {
                        let stems = [BarLayout.BeamStem(x: 0, nearest: first, levels: levels),
                                     BarLayout.BeamStem(x: 5, nearest: second, levels: levels)]
                        let line = BarLayout.fitBeam(stems: stems, up: up, reachesMiddle: true, limits: -100...100)
                        #expect(clean(line, up: up, levels: levels), "\(first) \(second) \(levels) \(up): \(line)")
                    }
                }
            }
        }
    }

    @Test func beamsClearSignsOtherVoicesAndRests() {
        typealias B = BarBuilder
        let restInside = B.bar([
            B.note(.e, 5, at: 0, .sixteenth, beams: [.begin, .forwardHook]), B.rest(at: 0.25, .sixteenth),
            B.note(.g, 5, at: 0.5, .sixteenth, beams: [.continue, .begin]), B.note(.a, 5, at: 0.75, .sixteenth, beams: [.end, .end]),
            B.note(.c, 4, at: 1, .eighth, beams: [.begin]), B.rest(at: 1.5, .eighth), B.note(.e, 4, at: 2, .eighth, beams: [.continue]),
            B.note(.d, 4, at: 2.5, .eighth, beams: [.end]),
        ])
        for bar in beamedBars + [restInside] {
            for layout in layouts(bar) {
                for beam in layout.beams {
                    let own = Set(beam.chords.flatMap { layout.chords[$0].heads.map(\.symbol) })
                    // Heads of other groups and voices, every sign and ledger line, every rest on the staff.
                    var ink: [CGRect] = []
                    for (index, chord) in layout.chords.enumerated() where chord.staff == beam.staff {
                        for ledger in chord.ledgers {
                            ink.append(CGRect(x: ledger.left, y: ledger.y - 0.08 * layout.space, width: ledger.right - ledger.left,
                                              height: 0.16 * layout.space))
                        }
                        for head in chord.heads {
                            if let frame = head.accidentalFrame { ink.append(frame) }
                            if !beam.chords.contains(index), !own.contains(head.symbol) {
                                let box = NoteShapes.head(head.kind).cgPath.boundingBoxOfPath
                                ink.append(CGRect(x: head.center.x + box.minX * layout.space, y: head.center.y + box.minY * layout.space,
                                                  width: box.width * layout.space, height: box.height * layout.space))
                            }
                        }
                    }
                    ink += layout.rests.filter { $0.staff == beam.staff }.map(\.frame)
                    for segment in beam.segments {
                        for rect in ink where rect.maxX > segment.topLeft.x && rect.minX < segment.topRight.x {
                            for x in stride(from: max(rect.minX, segment.topLeft.x), through: min(rect.maxX, segment.topRight.x),
                                            by: max(0.5, layout.space / 8)) {
                                let top = segment.top(at: x)
                                #expect(rect.maxY <= top + 0.5 || rect.minY >= top + segment.thickness - 0.5,
                                        "beam meets ink at \(rect) in \(layout.size)")
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func aRestInsideAGroupMovesOutOfTheBeamsWay() throws {
        let bar = B.bar([B.note(.c, 4, at: 0, .eighth, beams: [.begin]), B.rest(at: 0.5, .eighth),
                         B.note(.d, 4, at: 1, .eighth, beams: [.continue]), B.note(.c, 4, at: 1.5, .eighth, beams: [.end])])
        let layout = BarLayout(bar: bar, size: CGSize(width: 904, height: 316))
        let beam = try #require(layout.beams.first)
        #expect(beam.chords.count == 3 && beam.stemUp)
        // Down from the middle line, under the beam.
        let rest = try #require(layout.rests.first)
        #expect(rest.origin.y > layout.staves[0].geometry.y(4))
    }

    @Test func beamsUnderAnOctaveLineStayUnderIt() throws {
        let bar = B.bar(B.beamed([(.g, 5), (.a, 5), (.b, 5), (.c, 6)], from: 0, .sixteenth, shift: 1, stemUp: true)
                        + [B.note(.d, 6, at: 1, .half, shift: 1)])
        for layout in layouts(bar) {
            let mark = try #require(layout.octaveMarks.first)
            for segment in layout.beams.flatMap(\.segments) {
                #expect(segment.frame.minY > mark.lineY + mark.halfDigit)
            }
        }
    }
}

@Suite struct TimeSignatureLayoutTests {
    typealias B = BarBuilder

    @Test func theTimeSignatureFollowsTheKeyAndPushesTheMusicOn() throws {
        let notes = [B.note(.c, 5, at: 0), B.note(.d, 5, at: 1)]
        let size = CGSize(width: 904, height: 316)
        let plain = BarLayout(bar: B.bar(notes, fifths: 3, length: 3), size: size)
        let timed = BarLayout(bar: B.bar(notes, fifths: 3, length: 3, time: TimeSignature(beats: 3, beatType: 4)), size: size)
        #expect(plain.timeSignature == nil)
        let time = try #require(timed.timeSignature)
        #expect(time.beats == 3)
        let keyEnd = timed.staves[0].keySignatureEnd
        #expect(timed.timeSignatureLeft > keyEnd)
        let width = StaffMetrics.timeSignatureWidth(time) * timed.space
        #expect(abs(timed.barStart - (timed.timeSignatureLeft + width)) < 0.01)
        #expect(timed.columns[0].x > plain.columns[0].x)
        // Its ink is on the staff and out of the notes' way.
        let ink = BarLayout.timeSignaturePath(time, left: timed.timeSignatureLeft, timed.staves[0].geometry).cgPath.boundingBoxOfPath
        let staff = timed.staves[0].geometry
        #expect(ink.minY >= staff.y(8) - 0.1 * timed.space && ink.maxY <= staff.y(0) + 0.1 * timed.space)
        let firstHead = timed.chords.flatMap(\.heads).map(\.center.x).min()!
        #expect(ink.maxX < firstHead - NoteShapes.headWidth / 2 * timed.space)
    }

    @Test func numbersStackAndSymbolsStandAlone() {
        let sixEight = StaffMetrics.timeSignatureGlyphs(TimeSignature(beats: 6, beatType: 8))
        #expect(sixEight.map(\.glyph) == [.timeSig6, .timeSig8] && sixEight.map(\.position) == [6, 2])
        let twelve = StaffMetrics.timeSignatureGlyphs(TimeSignature(beats: 12, beatType: 8))
        #expect(twelve.map(\.glyph) == [.timeSig1, .timeSig2, .timeSig8])
        // The lone 8 is centred under the 12.
        let width = StaffMetrics.timeSignatureWidth(TimeSignature(beats: 12, beatType: 8))
        #expect(abs(twelve[2].x + MusicFont.advance(.timeSig8) / 2 - width / 2) < 0.001)
        #expect(StaffMetrics.timeSignatureGlyphs(TimeSignature(beats: 4, beatType: 4, symbol: .common)).map(\.glyph) == [.timeSigCommon])
        #expect(StaffMetrics.timeSignatureGlyphs(TimeSignature(beats: 2, beatType: 2, symbol: .cut)).map(\.glyph) == [.timeSigCutCommon])
    }
}

@Suite struct MusicFontTests {
    @Test func bravuraLoads() throws {
        let url = try #require(MusicFont.url)
        #expect(url.lastPathComponent == "Bravura.otf")
        let font = try #require(MusicFont.font)
        #expect(CTFontCopyFamilyName(font) as String == "Bravura")
        // Four points to the em: one staff space to the point.
        #expect(CTFontGetSize(font) == 4)
    }

    @Test(arguments: SMuFL.Glyph.allCases) func everyGlyphIsThere(_ glyph: SMuFL.Glyph) {
        #expect(MusicFont.hasGlyph(glyph), "\(glyph)")
        #expect(!MusicFont.outline(glyph).isEmpty, "\(glyph)")
        #expect(MusicFont.advance(glyph) > 0, "\(glyph)")
    }

    @Test func outlinesMatchBravurasMetadata() {
        for (glyph, box) in SMuFL.boundingBoxes {
            // The outline is y down; the metadata y up.
            let ink = MusicFont.bounds(glyph)
            #expect(abs(ink.minX - box.sw.x) < 0.01 && abs(ink.maxX - box.ne.x) < 0.01, "\(glyph)")
            #expect(abs(ink.minY + box.ne.y) < 0.01 && abs(ink.maxY + box.sw.y) < 0.01, "\(glyph)")
        }
    }

    @Test func glyphsSitWhereSMuFLPutsThem() {
        // A notehead is centred on its line, a sharp too, a flat's bowl sits on it.
        let head = NoteShapes.head(.quarter).cgPath.boundingBoxOfPath
        #expect(abs(head.midX) < 0.001 && abs(head.midY) < 0.001 && abs(head.width - NoteShapes.headWidth) < 0.001)
        #expect(abs(StaffMetrics.accidentalExtent(.sharp).below - 1.392) < 0.001)
        #expect(abs(StaffMetrics.accidentalExtent(.flat).below - 0.7) < 0.001)
        // The G clef curls round the G line and reaches about 1.6 spaces under the staff and 5.4 above its bottom line.
        let treble = StaffMetrics.clefExtent(.treble)
        #expect(abs(treble.bottom + 1.632) < 0.001 && abs(treble.top - 5.392) < 0.001)
        // The stem's outer edge on the head's edge, starting a little off its centre.
        #expect(abs(NoteShapes.stemOffset + NoteShapes.stemWidth / 2 - NoteShapes.headWidth / 2) < 0.001)
    }
}
