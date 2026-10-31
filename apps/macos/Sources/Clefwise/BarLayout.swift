import SwiftUI

/// Sizes of the text a bar leaves room for, in staff spaces at the sizes `BarStaffView` draws it.
/// The view measures them; the defaults are close enough for tests.
struct BarTextMetrics {
    /// The widest hint name on any staff (at 0.62 spaces); nil without hints.
    var hintWidth: CGFloat?
    /// The answer pill's text (at 0.8 spaces); nil without a label.
    var labelSize: CGSize?
}

/// Where everything in one bar goes: staves, clefs, key and time signatures, columns of notes by
/// time, heads, stems, flags and beams, accidentals, dots, rests, ties, octave marks, the highlight
/// and the answer pill. Pure geometry (`BarStaffView` draws it), so it can be tested without rendering.
///
/// Horizontally the bar runs from after the widest clef and key signature (and the time signature,
/// where the bar prints one) to the right edge (less the hint column). Every distinct offset on the drawn staves gets one column, so notes struck
/// together line up across a grand staff. Each column gets room growing with the square root of
/// the time until the next one, and never less than its ink needs: wherever ink on a staff would
/// meet the next column's at the same height (`closestDistance`), so a head may tuck under a flag
/// but never touch a sign, dot or second. The bar is stretched to fill the width; a bar too dense
/// to fit shrinks the staff instead. Vertically a staff is sized like `StaffGeometry(size:fitting:)`,
/// so a single staff matches `StaffView`; a grand staff leaves just enough room between its staves
/// for the upper staff's low ledger notes and the lower staff's high ones. Only a bar whose own ink
/// reaches further (a second voice's stems, an octave mark over high notes) gets more room.
///
/// Beams join the chords of a group (a level-1 `begin`…`end` run on one staff and voice): one stem
/// direction for the group, the stem tips on one beam line (`fitBeam`), flags only on notes left
/// unbeamed. Spacing and the vertical room are planned with the beams fitted at estimated widths;
/// once the columns are placed, every beam is fitted again where its stems really are.
struct BarLayout {
    struct Staff {
        let display: BarDisplay.Staff
        let geometry: StaffGeometry
        /// In force at the end of the bar: the hints at the right end name its lines and spaces.
        let endClef: Clef
        let clefLeft: CGFloat
        let keySignatureEnd: CGFloat
        /// The strip of canvas this staff's marks stay in: all of it, or its side of a grand staff's gap.
        let band: ClosedRange<CGFloat>
    }

    struct Column {
        /// In quarter notes from the start of the bar.
        let offset: Double
        /// Where heads on the usual side of their stems are centred.
        let x: CGFloat
    }

    struct Ledger: Equatable {
        let y: CGFloat
        let left: CGFloat
        let right: CGFloat
    }

    struct Head {
        let symbol: Int
        let position: Int
        let kind: NoteValue.Kind
        let center: CGPoint
        /// On the other side of the stem, as the upper (stem up) or lower (stem down) note of a second.
        let isFlipped: Bool
        let accidental: Accidental?
        /// Where the sign is inked.
        let accidentalFrame: CGRect?
        /// Its column in the chord's stack of signs, 0 nearest the notes.
        let accidentalColumn: Int?
        let dots: [CGPoint]
    }

    /// The notes of one voice struck together on one staff, sharing a stem.
    struct Chord {
        let staff: Int
        let voice: Int
        let column: Int
        let value: NoteValue
        let stemUp: Bool
        /// nil for whole notes.
        let stem: CGRect?
        /// Where the flags' origin goes (the stem's left edge at its nominal end); nil without flags.
        let flagOrigin: CGPoint?
        /// Index in `beams` of the group it's beamed in; nil for a note with flags or none.
        let beam: Int?
        /// Low to high.
        let heads: [Head]
        let ledgers: [Ledger]

        /// Flags, or none: a beamed chord has its beams instead.
        var flags: Int { beam == nil ? value.flags : 0 }
    }

    /// The beams of one group: its primary beam over every stem, and the shorter beams and hooks
    /// of the sixteenths and shorter, stacked towards the notes.
    struct Beam {
        let staff: Int
        let voice: Int
        let stemUp: Bool
        /// Indices in `chords`, left to right.
        let chords: [Int]
        /// Every note it joins, for drawing it muted once they're all answered.
        let symbols: [Int]
        let segments: [BeamSegment]
    }

    /// One beam (or hook) of a group: a parallelogram with vertical ends, `thickness` tall.
    struct BeamSegment {
        /// 0 for the primary beam (eighths), 1 for sixteenths…
        let level: Int
        let isHook: Bool
        /// Its upper edge's ends.
        let topLeft: CGPoint
        let topRight: CGPoint
        let thickness: CGFloat

        /// The upper edge's height at `x`.
        func top(at x: CGFloat) -> CGFloat {
            guard topRight.x > topLeft.x else { return topLeft.y }
            return topLeft.y + (topRight.y - topLeft.y) * (x - topLeft.x) / (topRight.x - topLeft.x)
        }

        var path: Path {
            var path = Path()
            path.move(to: topLeft)
            path.addLine(to: topRight)
            path.addLine(to: CGPoint(x: topRight.x, y: topRight.y + thickness))
            path.addLine(to: CGPoint(x: topLeft.x, y: topLeft.y + thickness))
            path.closeSubpath()
            return path
        }

        var frame: CGRect {
            CGRect(x: topLeft.x, y: min(topLeft.y, topRight.y), width: topRight.x - topLeft.x,
                   height: abs(topRight.y - topLeft.y) + thickness)
        }
    }

    struct Rest {
        let symbol: Int
        let staff: Int
        let kind: NoteValue.Kind
        /// Where `NoteShapes.rest(kind)`'s origin goes.
        let origin: CGPoint
        let frame: CGRect
        let dots: [CGPoint]
        let ledger: Ledger?
    }

    struct Tie {
        let staff: Int
        /// The note it's drawn with (muted with it): where it starts, or for a tie from the
        /// previous bar, where it ends.
        let symbol: Int
        let start: CGPoint
        let end: CGPoint
        let up: Bool
    }

    /// A smaller clef (Bravura's change clef) before the first note it applies to.
    struct ClefChange {
        let staff: Int
        let clef: Clef
        let column: Int
        let left: CGFloat
    }

    struct OctaveMark {
        let staff: Int
        let shift: Int
        let symbols: [Int]
        let textLeft: CGFloat
        let lineStart: CGFloat
        let hookX: CGFloat
        /// Through the middle of the digits.
        let lineY: CGFloat
        /// Half the digits' height.
        let halfDigit: CGFloat
    }

    struct Hints {
        /// The right edge `StaffDrawing.drawHints` lays the two columns out from.
        let right: CGFloat
        let column: CGFloat
        let fontSize: CGFloat
        let left: CGFloat
    }

    /// Ink that octave marks and the pill keep clear of, and that tests check stays on the canvas.
    struct InkBox {
        let staff: Int
        let rect: CGRect
        let symbol: Int?
    }

    private(set) var size: CGSize = .zero
    private(set) var space: CGFloat = 0
    private(set) var staves: [Staff] = []
    private(set) var columns: [Column] = []
    private(set) var chords: [Chord] = []
    private(set) var beams: [Beam] = []
    private(set) var rests: [Rest] = []
    private(set) var ties: [Tie] = []
    private(set) var clefChanges: [ClefChange] = []
    private(set) var octaveMarks: [OctaveMark] = []
    /// Left and right ends of the staff lines.
    private(set) var staffLeft: CGFloat = 0
    private(set) var staffRight: CGFloat = 0
    /// The time signature the bar starts with, drawn on every staff after the key signatures; nil
    /// when the bar prints none.
    private(set) var timeSignature: TimeSignature?
    private(set) var timeSignatureLeft: CGFloat = 0
    /// After the widest clef and key signature, and the time signature: where the bar's music starts.
    private(set) var barStart: CGFloat = 0
    /// Where the music ends: before the hint column, or the closing bar line.
    private(set) var notesEnd: CGFloat = 0
    private(set) var hints: Hints?
    /// A soft band behind the note being asked.
    private(set) var highlight: CGRect?
    /// The answer pill, by the note being asked.
    private(set) var label: CGRect?
    private(set) var inkBoxes: [InkBox] = []
    private(set) var isGrandStaff = false
    private(set) var isFinal = false

    // MARK: - Engraving constants, in staff spaces

    enum Metrics {
        static let leadIn: CGFloat = 1.3
        static let gap: CGFloat = 0.45
        static let tieGap: CGFloat = 1.1
        static let trailing: CGFloat = 0.9
        static let accidentalGap: CGFloat = 0.25
        static let ledgerGap: CGFloat = 0.15
        static let accidentalColumnGap: CGFloat = 0.15
        static let ledgerOverhang = SMuFL.legerLineExtension
        static let dotGap: CGFloat = 0.3
        static let dotSpacing: CGFloat = 0.5
        static let thinBarLine = SMuFL.thinBarlineThickness
        static let thickBarLine = SMuFL.thickBarlineThickness
        static let barLineSeparation = SMuFL.thinThickBarlineSeparation
        /// Brace and the gap before the opening line, on a grand staff.
        static let braceRoom: CGFloat = 1.4
        static let margin: CGFloat = 0.5
        static let grandStaffAir: CGFloat = 0.5
        /// Content needs this much more than its bare minimum before the staff shrinks for it.
        static let comfort: CGFloat = 1.05
        static let hintColumnLimit: CGFloat = 3
        /// Room an octave mark takes beyond the notes and stems under it, in staff positions.
        static let octaveMarkRoom: CGFloat = 2.8

        // Beams
        static let beamThickness = SMuFL.beamThickness
        /// From one beam's outer edge to the next one's, towards the notes.
        static let beamPitch = SMuFL.beamThickness + SMuFL.beamSpacing
        /// A hook (a partial beam) is about a note head wide.
        static let hookLength: CGFloat = 1.18
        /// The steepest a beam rises over its group, in spaces: by a quarter of a space a step
        /// between its first and last notes, at most a space, and less over a narrow group.
        static let beamRisePerStep: CGFloat = 0.25
        static let maxBeamRise: CGFloat = 1
        /// The shortest stem in a beamed group, from its head's centre to the beam's outer edge.
        static let shortestBeamedStem: CGFloat = 3.25
        /// How far a beam may be nudged towards the notes from there to avoid a white wedge.
        static let beamNudge: CGFloat = 0.25
    }

    // MARK: - Planning (in spaces, relative to each column's x)

    private struct PlannedHead {
        let symbol: Int
        let position: Int
        var dx: CGFloat = 0
        var isFlipped = false
        var accidental: Accidental?
        var accidentalRight: CGFloat = 0
        var accidentalColumn: Int?
        var dotPosition: Int?
    }

    private struct PlannedChord {
        let staff: Int
        let voice: Int
        let column: Int
        let value: NoteValue
        let stemUp: Bool
        let reachesMiddle: Bool
        var heads: [PlannedHead]
        /// Index in the planned beams of the group it's beamed in.
        var beam: Int?
        /// Where the stem's tip may go (staff positions): inside the staff's strip of canvas.
        var tipLimits: ClosedRange<CGFloat> = -.infinity...(.infinity)
        /// A beamed chord's stem tip: the primary beam's outer edge at its stem (a staff position).
        var beamTip: CGFloat?
        var shift: CGFloat = 0
        var dotX: CGFloat = 0

        var halfWidth: CGFloat { NoteShapes.headInkWidth(value.kind) / 2 }
        var lowest: Int { heads.first!.position }
        var highest: Int { heads.last!.position }
        /// The head nearest the stem's tip.
        var nearest: Int { stemUp ? highest : lowest }
        var stemDX: CGFloat { (stemUp ? 1 : -1) * NoteShapes.stemOffset }
        var flagCount: Int { beam == nil && value.hasStem ? value.flags : 0 }
        /// The flags' ink in spaces, y down from their origin; nil without flags.
        var flagBox: CGRect? {
            NoteShapes.flagBounds(flagCount, up: stemUp)
        }
        /// How far (staff positions) the flags reach past the stem's nominal tip, outwards.
        var flagReach: CGFloat {
            guard let box = flagBox else { return 0 }
            return 2 * max(0, stemUp ? -box.minY : box.maxY)
        }

        /// Stem tip as a staff position (fractional): the beam's outer edge for a beamed chord;
        /// otherwise 3.5 spaces past the last head, to the middle line at least on a staff with one
        /// voice, and shortened (not below `NoteShapes.shortestStem`) where it or its flags would
        /// leave the staff's strip of canvas.
        var stemTip: CGFloat {
            if let beamTip { return beamTip }
            let length = NoteShapes.stemLength(flags: value.flags) * 2
            let shortest = NoteShapes.shortestStem(flags: flagCount) * 2
            if stemUp {
                var tip = CGFloat(highest) + length
                if reachesMiddle { tip = max(tip, 4) }
                return max(min(tip, tipLimits.upperBound - flagReach), CGFloat(highest) + shortest)
            }
            var tip = CGFloat(lowest) - length
            if reachesMiddle { tip = min(tip, 4) }
            return min(max(tip, tipLimits.lowerBound + flagReach), CGFloat(lowest) - shortest)
        }

        /// Where the stem's ink ends: past the flags' origin as Bravura's flag anchors say, or in the
        /// middle of the primary beam, where the beam covers its end.
        var stemEnd: CGFloat {
            // Half the beam's thickness, in staff positions (two to a space).
            if beamTip != nil { return stemTip + (stemUp ? -1 : 1) * Metrics.beamThickness / 2 * 2 }
            return stemTip + (flagCount > 0 ? 2 * SMuFL.flagStemAnchor(flagCount, up: stemUp) : 0)
        }

        func ledgerPositions() -> [(position: Int, left: CGFloat, right: CGFloat)] {
            var result: [(Int, CGFloat, CGFloat)] = []
            let reach = halfWidth + Metrics.ledgerOverhang
            if highest >= 10 {
                for ledger in stride(from: 10, through: highest, by: 2) {
                    let xs = heads.filter { $0.position >= ledger }.map { shift + $0.dx }
                    result.append((ledger, xs.min()! - reach, xs.max()! + reach))
                }
            }
            if lowest <= -2 {
                for ledger in stride(from: -2, through: lowest, by: -2) {
                    let xs = heads.filter { $0.position <= ledger }.map { shift + $0.dx }
                    result.append((ledger, xs.min()! - reach, xs.max()! + reach))
                }
            }
            return result
        }

        var headsLeft: CGFloat { heads.map { shift + $0.dx }.min()! - halfWidth }
        var headsRight: CGFloat { heads.map { shift + $0.dx }.max()! + halfWidth }

        /// The flags start at the stem's left edge.
        var flagRight: CGFloat? {
            guard let box = flagBox else { return nil }
            return shift + stemDX - NoteShapes.stemWidth / 2 + box.maxX
        }

        var left: CGFloat {
            var left = headsLeft
            for head in heads where head.accidental != nil {
                left = min(left, head.accidentalRight - StaffMetrics.accidentalWidth(head.accidental!))
            }
            for ledger in ledgerPositions() { left = min(left, ledger.left) }
            return left
        }

        /// The chord's ink for spacing; a tie leaving a head needs a little length before the next note.
        func slabs(tied: (Int) -> Bool) -> [Slab] {
            var result: [Slab] = []
            for head in heads {
                let x = shift + head.dx
                let y = CGFloat(head.position)
                result.append(Slab(staff: staff, x: (x - halfWidth)...(x + halfWidth), y: (y - 1)...(y + 1)))
                if let accidental = head.accidental {
                    let width = StaffMetrics.accidentalWidth(accidental)
                    result.append(Slab(staff: staff, x: (head.accidentalRight - width)...head.accidentalRight,
                                       y: accidentalSpan(accidental, at: head.position)))
                }
                if let dot = head.dotPosition {
                    let right = dotX + CGFloat(value.dots - 1) * Metrics.dotSpacing + NoteShapes.dotRadius
                    result.append(Slab(staff: staff, x: (dotX - NoteShapes.dotRadius)...right,
                                       y: (CGFloat(dot) - 0.5)...(CGFloat(dot) + 0.5)))
                }
                if tied(head.symbol) {
                    let start = max(headsRight, value.dots > 0 ? dotX + NoteShapes.dotRadius : -.infinity)
                    result.append(Slab(staff: staff, x: start...(start + Metrics.tieGap), y: (y - 2)...(y + 2)))
                }
            }
            for ledger in ledgerPositions() {
                result.append(Slab(staff: staff, x: ledger.left...ledger.right,
                                   y: (CGFloat(ledger.position) - 0.3)...(CGFloat(ledger.position) + 0.3)))
            }
            if value.hasStem {
                let stemX = shift + stemDX
                let from = CGFloat(stemUp ? lowest : highest)
                let tip = stemUp ? max(stemTip, stemEnd) : min(stemTip, stemEnd)
                result.append(Slab(staff: staff, x: (stemX - NoteShapes.stemWidth / 2)...(stemX + NoteShapes.stemWidth / 2),
                                   y: min(from, tip)...max(from, tip)))
                if let box = flagBox {
                    let left = stemX - NoteShapes.stemWidth / 2
                    result.append(Slab(staff: staff, x: (left + box.minX)...(left + box.maxX),
                                       y: (stemTip - 2 * box.maxY)...(stemTip - 2 * box.minY)))
                }
            }
            return result
        }

        var right: CGFloat {
            var right = headsRight
            if let flagRight { right = max(right, flagRight) }
            if value.dots > 0 {
                right = max(right, dotX + CGFloat(value.dots - 1) * Metrics.dotSpacing + NoteShapes.dotRadius)
            }
            for ledger in ledgerPositions() { right = max(right, ledger.right) }
            return right
        }
    }

    private struct PlannedRest {
        let symbol: Int
        let staff: Int
        let column: Int?
        let kind: NoteValue.Kind
        let dots: Int
        /// The line a whole rest hangs from, a half rest sits on, or the others are centred on.
        var position: Int
        var voice = 1
        /// The score put it there (`<display-step>`): a beam over it keeps clear of it rather than moving it.
        var isPlacedByScore = false
        /// Where it goes before any beam over it moves it.
        var unbeamedPosition = 0

        var bounds: CGRect { NoteShapes.rest(kind).cgPath.boundingBoxOfPath }
        var slabs: [Slab] {
            var result = [Slab(staff: staff, x: bounds.minX...bounds.maxX, y: span)]
            if dots > 0 {
                result.append(Slab(staff: staff, x: (dotX - NoteShapes.dotRadius)...right,
                                   y: (CGFloat(dotPosition) - 0.5)...(CGFloat(dotPosition) + 0.5)))
            }
            return result
        }
        /// The staff positions it covers, bottom to top.
        var span: ClosedRange<CGFloat> {
            (CGFloat(position) - 2 * bounds.maxY)...(CGFloat(position) - 2 * bounds.minY)
        }
        var dotX: CGFloat { bounds.maxX + Metrics.dotGap + NoteShapes.dotRadius }
        var dotPosition: Int { position % 2 == 0 ? position + 1 : position }
        var left: CGFloat { bounds.minX }
        var right: CGFloat {
            dots > 0 ? dotX + CGFloat(dots - 1) * Metrics.dotSpacing + NoteShapes.dotRadius : bounds.maxX
        }
    }

    /// A beamed group as planned: indices in the planned chords, left to right, with each one's
    /// beam parts (level 1 first).
    private struct PlannedBeam {
        let staff: Int
        let voice: Int
        let stemUp: Bool
        let chords: [Int]
        let parts: [[BeamPart]]
    }

    // MARK: - Layout

    init(bar: BarDisplay, size: CGSize, text: BarTextMetrics = BarTextMetrics()) {
        self.size = size
        isGrandStaff = bar.staves.count > 1
        isFinal = bar.isLastBar
        guard !bar.staves.isEmpty, size.width > 0, size.height > 0 else { return }

        let symbols = bar.measure.symbols
        var staffIndex: [Int: Int] = [:]
        for (index, staff) in bar.staves.enumerated() where staffIndex[staff.number] == nil {
            staffIndex[staff.number] = index
        }
        let drawn = symbols.indices.filter { staffIndex[symbols[$0].staff] != nil }
        func staffOf(_ index: Int) -> Int { staffIndex[symbols[index].staff]! }

        // Columns: one per distinct offset on the drawn staves (whole-bar rests sit apart).
        var offsets: [Double] = []
        for index in drawn where !symbols[index].isWholeBarRest {
            let offset = symbols[index].offset
            if !offsets.contains(where: { abs($0 - offset) < 1e-6 }) { offsets.append(offset) }
        }
        offsets.sort()
        func columnOf(_ offset: Double) -> Int { offsets.firstIndex { abs($0 - offset) < 1e-6 } ?? 0 }

        var voices = Array(repeating: Set<Int>(), count: bar.staves.count)
        for index in drawn { voices[staffOf(index)].insert(symbols[index].voice) }
        let multiVoice = voices.map { $0.count > 1 }
        let nominal = Self.verticalPlan(bar.staves)

        var (planned, plannedBeams) = Self.planChords(symbols: symbols, drawn: drawn.filter { !symbols[$0].isRest },
                                                      staffOf: staffOf, columnOf: columnOf, multiVoice: multiVoice)
        var plannedRests: [PlannedRest] = []
        // Until the columns are placed, beams are fitted at a guess of the room each column gets.
        var guessedX = [CGFloat(0)]
        for column in offsets.indices.dropFirst() {
            guessedX.append(guessedX[column - 1] + max(NoteShapes.headWidth + Metrics.gap,
                                                       4.5 * Self.idealRoom(offsets[column] - offsets[column - 1])))
        }
        func fitBeams(columnX: (Int) -> CGFloat) {
            Self.fitBeams(plannedBeams, &planned, rests: &plannedRests, columnX: columnX)
        }
        func limitStems(_ plan: VerticalPlan) {
            for index in planned.indices {
                // Room for an octave mark beyond the stems of the notes under it.
                var limits = plan.limits[planned[index].staff]
                let shifts = planned[index].heads.map { symbols[$0.symbol].octaveShift }
                if planned[index].stemUp, shifts.contains(where: { $0 > 0 }) {
                    limits = limits.lowerBound...max(limits.lowerBound, limits.upperBound - Metrics.octaveMarkRoom)
                } else if !planned[index].stemUp, shifts.contains(where: { $0 < 0 }) {
                    limits = min(limits.upperBound, limits.lowerBound + Metrics.octaveMarkRoom)...limits.upperBound
                }
                planned[index].tipLimits = limits
                Self.placeDots(&planned[index], multiVoice: multiVoice[planned[index].staff])
            }
            fitBeams { guessedX[$0] }
        }
        limitStems(nominal)
        Self.shiftVoices(&planned)
        Self.placeAccidentals(&planned)

        plannedRests = drawn.filter { symbols[$0].isRest }.map { index in
            let symbol = symbols[index]
            let kind = symbol.isWholeBarRest ? NoteValue.Kind.whole : symbol.value.kind
            let column = symbol.isWholeBarRest ? nil : columnOf(symbol.offset)
            var rest = PlannedRest(symbol: index, staff: staffOf(index), column: column, kind: kind,
                                   dots: symbol.isWholeBarRest ? 0 : symbol.value.dots,
                                   position: Self.restPosition(symbol, kind: kind, multiVoice: multiVoice[staffOf(index)]))
            if multiVoice[rest.staff], symbol.restPosition == nil {
                // Out of the way of the other voice's notes at the same time: up for the upper voice, down for the lower.
                let others = planned.filter { $0.staff == rest.staff && $0.voice != symbol.voice
                    && (column == nil || $0.column == column) }.flatMap { $0.heads.map(\.position) }
                if let lowest = others.min(), let highest = others.max() {
                    let up = symbol.voice % 2 == 1
                    for _ in 0..<8 {
                        let span = rest.span
                        let clear = up ? span.lowerBound >= CGFloat(highest) + 1.5 : span.upperBound <= CGFloat(lowest) - 1.5
                        if clear { break }
                        rest.position += up ? 2 : -2
                    }
                }
            }
            rest.voice = symbol.voice
            rest.isPlacedByScore = symbol.restPosition != nil
            rest.unbeamedPosition = rest.position
            return rest
        }
        // Again, now that the signs and rests are placed, which the beams keep clear of.
        fitBeams { guessedX[$0] }

        // Room for what this bar draws beyond the staff's usual room, if anything.
        var content = bar.staves.map { _ in CGFloat(0)...CGFloat(8) }
        for chord in planned {
            let reach = Self.extent(of: chord, symbols: symbols, multiVoice: multiVoice[chord.staff])
            let old = content[chord.staff]
            content[chord.staff] = min(old.lowerBound, reach.lowerBound)...max(old.upperBound, reach.upperBound)
        }
        for rest in plannedRests {
            let old = content[rest.staff]
            content[rest.staff] = min(old.lowerBound, rest.span.lowerBound)...max(old.upperBound, rest.span.upperBound)
        }
        let vertical = Self.verticalPlan(bar.staves, content: content)
        // Full-length stems where the bar got more room than the staff usually has.
        limitStems(vertical)

        // Clef changes: a smaller clef before the first symbol on a staff whose clef differs.
        var changes: [(staff: Int, clef: Clef, column: Int)] = []
        var endClefs = bar.staves.map(\.clef)
        for index in drawn where !symbols[index].isWholeBarRest {
            let staff = staffOf(index)
            let symbol = symbols[index]
            if symbol.clef != endClefs[staff] {
                endClefs[staff] = symbol.clef
                changes.append((staff, symbol.clef, columnOf(symbol.offset)))
            }
        }

        // Each column's reach left and right of its x, over every staff.
        var lefts = Array(repeating: CGFloat(-NoteShapes.headWidth / 2), count: offsets.count)
        var rights = Array(repeating: CGFloat(NoteShapes.headWidth / 2), count: offsets.count)
        var staffLefts: [Int: CGFloat] = [:]  // staff * columns + column
        func note(_ staff: Int, _ column: Int, left: CGFloat, right: CGFloat) {
            lefts[column] = min(lefts[column], left)
            rights[column] = max(rights[column], right)
            let key = staff * max(1, offsets.count) + column
            staffLefts[key] = min(staffLefts[key] ?? 0, left)
        }
        for chord in planned { note(chord.staff, chord.column, left: chord.left, right: chord.right) }
        for rest in plannedRests { if let column = rest.column { note(rest.staff, column, left: rest.left, right: rest.right) } }
        var changeLefts: [CGFloat] = []
        var slabs = Array(repeating: [Slab](), count: offsets.count)
        for chord in planned { slabs[chord.column] += chord.slabs(tied: { symbols[$0].tiedToNext }) }
        for rest in plannedRests { if let column = rest.column { slabs[column] += rest.slabs } }
        for change in changes {
            let contentLeft = staffLefts[change.staff * max(1, offsets.count) + change.column] ?? -NoteShapes.headWidth / 2
            let width = StaffMetrics.clefWidth(change.clef, change: true)
            let left = contentLeft - 0.35 - width
            changeLefts.append(left)
            lefts[change.column] = min(lefts[change.column], left)
            let (bottom, top) = StaffMetrics.clefExtent(change.clef, change: true)
            slabs[change.column].append(Slab(staff: change.staff, x: left...(left + width), y: (2 * bottom)...(2 * top)))
        }

        // Ties need room out to the bar line, or in from it (between columns, their slabs keep it).
        var tieOut = false
        var tieIntoFirst = false
        for chord in planned {
            for head in chord.heads {
                let symbol = symbols[head.symbol]
                if symbol.tiedToNext {
                    if Self.tieTarget(of: head.symbol, in: symbols, drawn: drawn) == nil, chord.column == offsets.count - 1 {
                        tieOut = true
                    }
                }
                if symbol.tiedFromPrevious, chord.column == 0, Self.tieSource(of: head.symbol, in: symbols, drawn: drawn) == nil {
                    tieIntoFirst = true
                }
            }
        }

        let barLength = max(bar.measure.length, drawn.map { symbols[$0].offset + symbols[$0].duration }.max() ?? 0)
        var segments: [(min: CGFloat, ideal: CGFloat)] = []
        if !offsets.isEmpty {
            segments.append((Metrics.leadIn - lefts[0] + (tieIntoFirst ? 1 : 0), Self.idealRoom(offsets[0])))
            for column in 0..<(offsets.count - 1) {
                segments.append((Self.closestDistance(slabs[column], slabs[column + 1]),
                                 Self.idealRoom(offsets[column + 1] - offsets[column])))
            }
            let last = offsets.count - 1
            segments.append((rights[last] + Metrics.trailing + (tieOut ? 0.6 : 0), Self.idealRoom(barLength - offsets[last])))
        }

        // Hint columns, as `StaffView` lays them out: two columns as wide as the widest name.
        var hintColumn: CGFloat?
        var hintFontScale: CGFloat = 1
        if let width = text.hintWidth {
            var column = max(0.6, width)
            if column > Metrics.hintColumnLimit {
                hintFontScale = Metrics.hintColumnLimit / column
                column = Metrics.hintColumnLimit
            }
            hintColumn = column
        }
        let hintArea = hintColumn.map { 2 * $0 + 0.8 + 0.25 } ?? 0
        let barLineWidth = isFinal ? Metrics.thinBarLine + Metrics.barLineSeparation + Metrics.thickBarLine : Metrics.thinBarLine

        // The staff's size: what the height allows (as `StaffView`), unless the bar needs more width.
        let staffLeftSpaces = Metrics.margin + (isGrandStaff ? Metrics.braceRoom : 0)
        let clefAndKey = bar.staves.map { StaffMetrics.clefWidth($0.clef) + Self.keySignatureWidth($0.keySignature, clef: $0.clef) }
        timeSignature = bar.measure.printsTime ? bar.measure.time : nil
        let timeWidth = timeSignature.map { StaffMetrics.beforeTimeSignature + StaffMetrics.timeSignatureWidth($0) } ?? 0
        let neededSpaces = staffLeftSpaces + 0.5 + (clefAndKey.max() ?? 0) + timeWidth
            + segments.reduce(0) { $0 + $1.min } * Metrics.comfort + hintArea + barLineWidth + Metrics.margin

        var space = min(size.height / vertical.spacesTall, size.width / 22)
        space = min(space, size.width / neededSpaces)
        self.space = space

        // Staves, top to bottom.
        staffLeft = staffLeftSpaces * space
        staffRight = size.width - Metrics.margin * space
        let blockTop = size.height / 2 - vertical.spacesTall / 2 * space
        var builtStaves: [Staff] = []
        for (index, display) in bar.staves.enumerated() {
            let bottomLineY = blockTop + vertical.middles[index] * space + 2 * space
            let geometry = StaffGeometry(space: space, left: staffLeft, right: staffRight, bottomLineY: bottomLineY,
                                         height: size.height)
            let band: ClosedRange<CGFloat>
            if !isGrandStaff {
                band = 0...size.height
            } else if index == 0 {
                band = 0...(blockTop + vertical.boundary * space)
            } else {
                band = (blockTop + vertical.boundary * space)...size.height
            }
            let clefLeft = staffLeft + 0.5 * space
            let clefEnd = clefLeft + StaffMetrics.clefWidth(display.clef) * space
            let keyEnd = StaffDrawing.keySignatureSigns(display.keySignature, clef: display.clef, after: clefEnd, geometry).end
            builtStaves.append(Staff(display: display, geometry: geometry, endClef: endClefs[index], clefLeft: clefLeft,
                                     keySignatureEnd: keyEnd, band: band))
        }
        staves = builtStaves
        barStart = staves.map(\.keySignatureEnd).max()!
        if let timeSignature {
            timeSignatureLeft = barStart + StaffMetrics.beforeTimeSignature * space
            barStart = timeSignatureLeft + StaffMetrics.timeSignatureWidth(timeSignature) * space
        }
        let barLineLeft = staffRight - barLineWidth * space
        if let hintColumn {
            let right = barLineLeft
            let left = right - (2 * hintColumn + 0.8) * space
            hints = Hints(right: right, column: hintColumn * space, fontSize: 0.62 * space * hintFontScale, left: left)
            notesEnd = left - 0.25 * space
        } else {
            notesEnd = barLineLeft
        }

        // Columns: stretch the room by time to fill the bar.
        let widths = Self.stretch(segments.map { (min: $0.min * space, ideal: $0.ideal) }, toFill: notesEnd - barStart)
        var x = barStart
        var built: [Column] = []
        for (index, offset) in offsets.enumerated() {
            x += widths[index]
            built.append(Column(offset: offset, x: x))
        }
        columns = built

        // The beams where their stems really are.
        fitBeams { built[$0].x / space }

        // Everything in points.
        for chord in planned { chords.append(place(chord)) }
        placeBeams(plannedBeams, planned: planned)
        for rest in plannedRests { rests.append(place(rest)) }
        for (index, change) in changes.enumerated() {
            clefChanges.append(ClefChange(staff: change.staff, clef: change.clef, column: change.column,
                                          left: columns[change.column].x + changeLefts[index] * space))
        }
        collectInk()
        placeTies(symbols: symbols, drawn: drawn, multiVoice: multiVoice)
        placeOctaveMarks(symbols: symbols)
        placeHighlight(bar.current)
        placeLabel(bar.current, size: text.labelSize)
    }

    // MARK: Chords

    private static func planChords(symbols: [BarSymbol], drawn: [Int], staffOf: (Int) -> Int, columnOf: (Double) -> Int,
                                   multiVoice: [Bool]) -> (chords: [PlannedChord], beams: [PlannedBeam]) {
        struct Key: Hashable { let staff, voice, chord, column: Int }
        var order: [Key] = []
        var members: [Key: [Int]] = [:]
        for index in drawn {
            let symbol = symbols[index]
            let key = Key(staff: staffOf(index), voice: symbol.voice, chord: symbol.chord, column: columnOf(symbol.offset))
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(index)
        }
        for key in order {
            members[key]!.sort { (symbols[$0].position!, $0) < (symbols[$1].position!, $1) }
        }

        // Beamed groups: runs of chords on one staff and voice from a level-1 `begin` to its `end`.
        func parts(_ key: Key) -> [BeamPart] {
            members[key]!.lazy.map { symbols[$0].beams }.first { !$0.isEmpty } ?? []
        }
        var groups: [[Key]] = []
        struct Lane: Hashable { let staff, voice: Int }
        let lanes = Dictionary(grouping: order) { Lane(staff: $0.staff, voice: $0.voice) }
        for lane in lanes.keys.sorted(by: { ($0.staff, $0.voice) < ($1.staff, $1.voice) }) {
            var open: [Key] = []
            func close() {
                if open.count > 1 { groups.append(open) }
                open = []
            }
            for key in lanes[lane]!.sorted(by: { $0.column < $1.column }) {
                let value = symbols[members[key]![0]].value
                guard value.flags > 0, let first = parts(key).first else {
                    close()
                    continue
                }
                switch first {
                case .begin:
                    close()
                    open = [key]
                case .continue:
                    open.append(key)
                case .end:
                    open.append(key)
                    close()
                case .forwardHook, .backwardHook:
                    close()
                }
            }
            close()
        }

        // One stem direction for each group: the score's, when its notes agree; else by voice on a
        // staff with two; else away from the group's note furthest from the middle line.
        var groupUp: [Key: Bool] = [:]
        for group in groups {
            let notes = group.flatMap { members[$0]! }
            let declared = Set(notes.compactMap { symbols[$0].stemUp })
            let up = declared.count == 1 ? declared.first!
                : stemDirection(positions: notes.map { symbols[$0].position! }, voice: group[0].voice,
                                multiVoice: multiVoice[group[0].staff])
            for key in group { groupUp[key] = up }
        }

        var chords = order.map { key in
            let notes = members[key]!
            let positions = notes.map { symbols[$0].position! }
            let value = symbols[notes[0]].value
            let stemUp = groupUp[key] ?? notes.lazy.compactMap { symbols[$0].stemUp }.first
                ?? stemDirection(positions: positions, voice: key.voice, multiVoice: multiVoice[key.staff])
            var heads = notes.map { index in
                PlannedHead(symbol: index, position: symbols[index].position!, accidental: symbols[index].accidental)
            }
            let flips = flippedHeads(positions: positions, stemUp: stemUp)
            let flipOffset = value.hasStem ? 2 * NoteShapes.stemOffset : NoteShapes.headInkWidth(.whole) - 0.04
            for index in heads.indices where flips[index] {
                heads[index].isFlipped = true
                heads[index].dx = stemUp ? flipOffset : -flipOffset
            }
            return PlannedChord(staff: key.staff, voice: key.voice, column: key.column, value: value, stemUp: stemUp,
                                reachesMiddle: !multiVoice[key.staff], heads: heads)
        }
        let indexOf = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let beams = groups.enumerated().map { number, group in
            let indices = group.map { indexOf[$0]! }
            for index in indices { chords[index].beam = number }
            return PlannedBeam(staff: group[0].staff, voice: group[0].voice, stemUp: groupUp[group[0]]!, chords: indices,
                               parts: group.map(parts))
        }
        return (chords, beams)
    }

    // MARK: Beams

    /// A stem of a beamed group, as the beam is fitted to it: its x (spaces, from any origin), the
    /// head nearest the beam (a staff position) and how many beams it carries.
    struct BeamStem {
        let x: CGFloat
        let nearest: Int
        let levels: Int
    }

    /// Ink under a beam that the beam keeps clear of: where it is (x in spaces), its edge nearest the
    /// beam and its edge furthest from it (staff positions), and how many beams are stacked over it.
    struct BeamObstacle {
        let x: ClosedRange<CGFloat>
        let reach: CGFloat
        let inner: CGFloat
        let levels: Int
    }

    /// The primary beam's outer edge (the stems' tips) as a straight line: staff positions at the
    /// first and last stems.
    struct BeamLine {
        let firstX: CGFloat
        let lastX: CGFloat
        let first: CGFloat
        let last: CGFloat

        func position(at x: CGFloat) -> CGFloat {
            guard lastX > firstX else { return first }
            return first + (last - first) * (x - firstX) / (lastX - firstX)
        }
    }

    /// How deep (in spaces) a stack of `levels` beams is, from the outer edge to the inner one.
    static func beamStackDepth(_ levels: Int) -> CGFloat {
        Metrics.beamThickness + Metrics.beamPitch * CGFloat(max(levels, 1) - 1)
    }

    /// The shortest a stem carrying `levels` beams may be, from its head's centre to the outer
    /// edge: `Metrics.shortestBeamedStem`, longer where three or four beams need room above the head.
    static func shortestBeamedStem(levels: Int) -> CGFloat {
        max(Metrics.shortestBeamedStem, beamStackDepth(levels) + 1.75)
    }

    /// The least a stem carrying `levels` beams is shortened to where the staff's strip runs out of
    /// room (between a grand staff's staves): as short as a flagged eighth's, the beams still clear
    /// the head by three quarters of a space.
    static func squeezedBeamedStem(levels: Int) -> CGFloat {
        max(NoteShapes.shortestStem(flags: 1), beamStackDepth(levels) + 1.25)
    }

    /// Where a group's primary beam goes, as engravers set it:
    /// - its rise follows the first and last notes, a quarter space a step, at most a space over the
    ///   group and less over a narrow one (a fifth of its width);
    /// - it's flat when the first and last notes are the same, or when an inner note is further out
    ///   (towards the beam) than both;
    /// - the shortest stem is `shortestBeamedStem(levels:)`; on a staff with one voice every stem
    ///   reaches the middle line; `obstacles` stay a quarter space inside the innermost beam;
    /// - it stays within `limits` (the staff's strip), shortening the stems if it must, but not below
    ///   `squeezedBeamedStem(levels:)` (then the bar gets more room, as for any ink that needs it);
    /// - its ends are nudged (by a quarter space at most towards the notes, otherwise outwards) so
    ///   that no beam near the staff leaves a thin white wedge against a line: each one sits on a
    ///   line, straddles it or hangs from it.
    static func fitBeam(stems: [BeamStem], up: Bool, reachesMiddle: Bool, limits: ClosedRange<CGFloat>,
                        obstacles: [BeamObstacle] = []) -> BeamLine {
        guard let first = stems.first, let last = stems.last else { return BeamLine(firstX: 0, lastX: 0, first: 4, last: 4) }
        // Worked out in "outward" units: staff positions, growing away from the notes towards the beam.
        let sign: CGFloat = up ? 1 : -1
        let x0 = first.x
        let span = max(last.x - x0, 0.001)
        let nearest = stems.map { sign * CGFloat($0.nearest) }

        let steps = nearest.last! - nearest.first!
        let innerFurtherOut = nearest.dropFirst().dropLast().contains { $0 > max(nearest.first!, nearest.last!) }
        var rise: CGFloat = 0
        if steps != 0, !innerFurtherOut {
            let most = min(Metrics.maxBeamRise, max(Metrics.beamRisePerStep, span / 5))
            rise = (steps > 0 ? 2 : -2) * min(abs(steps) * Metrics.beamRisePerStep, most)
        }
        let slope = rise / span

        // The line must clear each of these: at x, its outer edge at least u (outward units).
        var needs: [(x: CGFloat, u: CGFloat, slack: CGFloat)] = []
        for (index, stem) in stems.enumerated() {
            needs.append((stem.x, nearest[index] + 2 * shortestBeamedStem(levels: stem.levels), 2 * Metrics.beamNudge))
            if reachesMiddle { needs.append((stem.x, sign * 4, 0)) }
        }
        for obstacle in obstacles {
            let u = sign * obstacle.reach + 2 * (beamStackDepth(obstacle.levels) + 0.25)
            needs.append((obstacle.x.lowerBound, u, 0))
            needs.append((obstacle.x.upperBound, u, 0))
        }
        var start = needs.map { $0.u - slope * ($0.x - x0) }.max()!

        // Squeezed against the edge of the staff's strip: shorter stems, down to `squeezedBeamedStem`.
        let limit = up ? limits.upperBound : -limits.lowerBound
        let floors = stems.indices.map { nearest[$0] + 2 * squeezedBeamedStem(levels: stems[$0].levels) }
        let outermost = max(start, start + rise)
        if outermost > limit {
            let floor = stems.indices.map { floors[$0] - slope * (stems[$0].x - x0) }.max()!
            start = max(start - (outermost - limit), floor)
        }
        let ideal = (first: start, last: start + rise)
        func idealLine(_ x: CGFloat) -> CGFloat { ideal.first + slope * (x - x0) }

        // Every beam level reaching the staff (or within a quarter space of it) sits on a line,
        // straddles it or hangs from it: its lower edge is never half a position above a line.
        func clean(_ outer: CGFloat, levels: Int) -> Bool {
            let position = sign * outer
            for level in 0..<max(levels, 1) {
                let inset = 2 * Metrics.beamPitch * CGFloat(level)
                let lower = up ? position - inset - 2 * Metrics.beamThickness : position + inset
                guard lower >= -1.5 - 1e-6, lower <= 8.5 + 1e-6 else { continue }
                let remainder = (lower.truncatingRemainder(dividingBy: 2) + 2).truncatingRemainder(dividingBy: 2)
                if abs(remainder - 0.5) < 0.01 { return false }
            }
            return true
        }
        func onGrid(_ value: CGFloat) -> CGFloat { (value * 2).rounded(.down) / 2 }
        // First keeping the slope within a quarter space of the ideal; failing that (three or four
        // beams can only hang in the staff, so their ends are a space apart or level), any slope
        // the same way, flat included.
        func search(strictSlope: Bool) -> (first: CGFloat, last: CGFloat)? {
            var best: (first: CGFloat, last: CGFloat)?
            var bestCost = CGFloat.infinity
            for i in -1...4 {
                let q0 = onGrid(ideal.first) + 0.5 * CGFloat(i)
                guard clean(q0, levels: first.levels) else { continue }
                for j in -2...5 {
                    let q1 = onGrid(ideal.last) + 0.5 * CGFloat(j)
                    let qRise = q1 - q0
                    guard abs(qRise) <= 2 * Metrics.maxBeamRise + 1e-6 else { continue }
                    if rise == 0 {
                        guard abs(qRise) < 1e-6 else { continue }
                    } else if strictSlope {
                        guard qRise * rise > 0, abs(qRise - rise) <= 0.5 + 1e-6 else { continue }
                    } else {
                        guard qRise * rise >= 0 else { continue }
                    }
                    // Within the strip, give or take the air it keeps.
                    guard clean(q1, levels: last.levels), max(q0, q1) <= max(limit, ideal.first, ideal.last) + 0.5 + 1e-6 else { continue }
                    let qSlope = qRise / span
                    func line(_ x: CGFloat) -> CGFloat { q0 + qSlope * (x - x0) }
                    let clears = needs.allSatisfy { line($0.x) >= min($0.u, idealLine($0.x)) - $0.slack - 1e-6 }
                        && stems.indices.allSatisfy { line(stems[$0].x) >= floors[$0] - 1e-6 }
                    guard clears else { continue }
                    // Nudging towards the notes costs a little more than away from them.
                    func cost(_ moved: CGFloat) -> CGFloat { moved < 0 ? -1.3 * moved : moved }
                    let total = cost(q0 - ideal.first) + cost(q1 - ideal.last) + 0.5 * abs(qRise - rise)
                    if total < bestCost - 1e-6 {
                        bestCost = total
                        best = (q0, q1)
                    }
                }
            }
            return best
        }
        let fitted = search(strictSlope: true) ?? search(strictSlope: false) ?? ideal
        return BeamLine(firstX: x0, lastX: last.x, first: sign * fitted.first, last: sign * fitted.last)
    }

    /// Fits every group's beam to its stems, `columnX` giving each column's x in spaces, and sets
    /// the tips of its chords' stems on it. The beam clears the group's own signs, then whatever
    /// else on the staff lies under it: another voice's notes and signs, rests.
    private static func fitBeams(_ beams: [PlannedBeam], _ chords: inout [PlannedChord], rests: inout [PlannedRest],
                                 columnX: (Int) -> CGFloat) {
        for beam in beams {
            let members = beam.chords
            let stems = members.enumerated().map { index, chord in
                BeamStem(x: columnX(chords[chord].column) + chords[chord].shift + chords[chord].stemDX,
                         nearest: chords[chord].nearest, levels: beam.parts[index].count)
            }
            let span = stems.first!.x...stems.last!.x
            var limits = chords[members[0]].tipLimits
            for chord in members.dropFirst() {
                let other = chords[chord].tipLimits
                let low = max(limits.lowerBound, other.lowerBound), high = min(limits.upperBound, other.upperBound)
                if low <= high { limits = low...high }
            }
            func levels(at x: CGFloat) -> Int {
                let after = stems.firstIndex { $0.x >= x } ?? stems.count - 1
                return max(stems[max(0, after - 1)].levels, stems[after].levels)
            }
            func obstacle(_ x: ClosedRange<CGFloat>, _ y: ClosedRange<CGFloat>) -> BeamObstacle? {
                let low = max(x.lowerBound, span.lowerBound), high = min(x.upperBound, span.upperBound)
                guard low <= high else { return nil }
                return BeamObstacle(x: low...high, reach: beam.stemUp ? y.upperBound : y.lowerBound,
                                    inner: beam.stemUp ? y.lowerBound : y.upperBound, levels: levels(at: (low + high) / 2))
            }
            func signs(of chord: PlannedChord) -> [BeamObstacle] {
                chord.heads.compactMap { head in
                    guard let accidental = head.accidental, head.accidentalColumn != nil else { return nil }
                    let right = columnX(chord.column) + head.accidentalRight
                    return obstacle((right - StaffMetrics.accidentalWidth(accidental))...right,
                                    accidentalSpan(accidental, at: head.position))
                }
            }
            let own = members.flatMap { signs(of: chords[$0]) }
            var others: [BeamObstacle] = []
            for (index, chord) in chords.enumerated() where chord.staff == beam.staff && !members.contains(index) {
                for head in chord.heads {
                    let x = columnX(chord.column) + chord.shift + head.dx
                    let reach = chord.halfWidth + (head.position <= -2 || head.position >= 10 ? Metrics.ledgerOverhang : 0)
                    let y = CGFloat(head.position)
                    if let found = obstacle((x - reach)...(x + reach), (y - 1)...(y + 1)) { others.append(found) }
                }
                others += signs(of: chord)
            }
            // A rest of the group's own voice within it is moved out of the beam's way (below);
            // any other rest the beam clears.
            let columns = chords[members.first!].column...chords[members.last!].column
            var inside: [Int] = []
            for index in rests.indices where rests[index].staff == beam.staff {
                guard let column = rests[index].column else { continue }
                if rests[index].voice == beam.voice, columns.contains(column), !rests[index].isPlacedByScore {
                    rests[index].position = rests[index].unbeamedPosition
                    inside.append(index)
                    continue
                }
                let x = columnX(column)
                if let found = obstacle((x + rests[index].left)...(x + rests[index].right), rests[index].span) { others.append(found) }
            }
            let reachesMiddle = chords[members[0]].reachesMiddle
            var line = fitBeam(stems: stems, up: beam.stemUp, reachesMiddle: reachesMiddle, limits: limits, obstacles: own)
            let sign: CGFloat = beam.stemUp ? 1 : -1
            var under = others.filter { obstacle in
                let outer = min(line.position(at: obstacle.x.lowerBound) * sign, line.position(at: obstacle.x.upperBound) * sign)
                return obstacle.inner * sign < outer
            }
            if !under.isEmpty {
                line = fitBeam(stems: stems, up: beam.stemUp, reachesMiddle: reachesMiddle, limits: limits, obstacles: own + under)
            }

            // Rests under the beam move towards the notes, a space at a time, until they clear its
            // innermost beam by a quarter space; one that can't (it would meet a note at its time, or
            // go more than three spaces) stays, and the beam clears it instead.
            var refit = false
            for index in inside {
                let x = columnX(rests[index].column!)
                let xs = (x + rests[index].left)...(x + rests[index].right)
                func clear(_ rest: PlannedRest) -> Bool {
                    [xs.lowerBound, xs.upperBound].allSatisfy { at in
                        let innermost = line.position(at: at) * sign - 2 * beamStackDepth(levels(at: at))
                        return (beam.stemUp ? rest.span.upperBound : -rest.span.lowerBound) <= innermost - 0.5
                    }
                }
                func meetsANote(_ rest: PlannedRest) -> Bool {
                    chords.contains { chord in
                        chord.staff == beam.staff && chord.column == rests[index].column && chord.heads.contains {
                            CGFloat($0.position) + 1.5 > rest.span.lowerBound && CGFloat($0.position) - 1.5 < rest.span.upperBound
                        }
                    }
                }
                var moved = rests[index]
                var steps = 0
                while !clear(moved), steps < 3 {
                    moved.position -= beam.stemUp ? 2 : -2
                    steps += 1
                }
                if clear(moved), !meetsANote(moved) {
                    rests[index] = moved
                } else if let found = obstacle(xs, rests[index].span) {
                    under.append(found)
                    refit = true
                }
            }
            if refit {
                line = fitBeam(stems: stems, up: beam.stemUp, reachesMiddle: reachesMiddle, limits: limits, obstacles: own + under)
            }
            for (index, chord) in members.enumerated() { chords[chord].beamTip = line.position(at: stems[index].x) }
        }
    }

    /// Up or down when the score doesn't say: by voice when a staff has two (odd voices up), or
    /// else away from the note furthest from the middle line (down when they're even).
    static func stemDirection(positions: [Int], voice: Int, multiVoice: Bool) -> Bool {
        if multiVoice { return voice % 2 == 1 }
        guard let lowest = positions.min(), let highest = positions.max() else { return true }
        return 4 - lowest > highest - 4
    }

    /// Which heads (low to high) go on the other side of the stem: in each second, the upper note
    /// with the stem up, the lower one with the stem down, working away from the stem's end.
    static func flippedHeads(positions: [Int], stemUp: Bool) -> [Bool] {
        var flipped = Array(repeating: false, count: positions.count)
        let order = stemUp ? Array(positions.indices) : Array(positions.indices.reversed())
        for step in order.indices.dropFirst() {
            let index = order[step], previous = order[step - 1]
            if abs(positions[index] - positions[previous]) <= 1, !flipped[previous] { flipped[index] = true }
        }
        return flipped
    }

    /// Two voices at the same time on a staff: when the lower voice's notes come within a second of
    /// the upper voice's (or cross them), it moves right so the heads don't collide.
    private static func shiftVoices(_ chords: inout [PlannedChord]) {
        for down in chords.indices where !chords[down].stemUp {
            for up in chords.indices where chords[up].stemUp && chords[up].staff == chords[down].staff
                && chords[up].column == chords[down].column && chords[up].voice != chords[down].voice {
                guard chords[down].highest >= chords[up].lowest - 1 else { continue }
                let needed = chords[up].headsRight - (chords[down].headsLeft - chords[down].shift) - NoteShapes.stemWidth
                chords[down].shift = max(chords[down].shift, needed)
            }
        }
    }

    /// Signs stacked in columns before the notes of each staff and column: the highest nearest the
    /// notes, and each other sign in the nearest column where it clears the ones already there.
    private static func placeAccidentals(_ chords: inout [PlannedChord]) {
        struct Group: Hashable { let staff, column: Int }
        let groups = Set(chords.map { Group(staff: $0.staff, column: $0.column) })
        for group in groups {
            let members = chords.indices.filter { chords[$0].staff == group.staff && chords[$0].column == group.column }
            var signs: [(chord: Int, head: Int, position: Int, accidental: Accidental)] = []
            for chord in members {
                for (head, planned) in chords[chord].heads.enumerated() {
                    if let accidental = planned.accidental { signs.append((chord, head, planned.position, accidental)) }
                }
            }
            guard !signs.isEmpty else { continue }
            let headsLeft = members.map { chords[$0].headsLeft }.min()!
            let ledgers = members.flatMap { chords[$0].ledgerPositions() }
            var right = headsLeft - Metrics.accidentalGap
            for sign in signs {
                let span = accidentalSpan(sign.accidental, at: sign.position)
                for ledger in ledgers where CGFloat(ledger.position) > span.lowerBound - 0.5
                    && CGFloat(ledger.position) < span.upperBound + 0.5 {
                    right = min(right, ledger.left - Metrics.ledgerGap)
                }
            }
            let stacked = accidentalColumns(signs.map { ($0.accidental, $0.position) })
            var columnRights: [CGFloat] = []
            var edge = right
            for column in 0...(stacked.max() ?? 0) {
                columnRights.append(edge)
                let width = zip(signs, stacked).filter { $0.1 == column }.map { StaffMetrics.accidentalWidth($0.0.accidental) }.max() ?? 0
                edge -= width + Metrics.accidentalColumnGap
            }
            for (sign, column) in zip(signs, stacked) {
                chords[sign.chord].heads[sign.head].accidentalRight = columnRights[column]
                chords[sign.chord].heads[sign.head].accidentalColumn = column
            }
        }
    }

    /// The staff positions a sign covers, bottom to top.
    static func accidentalSpan(_ accidental: Accidental, at position: Int) -> ClosedRange<CGFloat> {
        let (height, below) = StaffMetrics.accidentalExtent(accidental)
        return (CGFloat(position) - 2 * below)...(CGFloat(position) + 2 * (height - below))
    }

    /// The column for each sign (0 nearest the notes): top to bottom, each in the first column
    /// where it clears every sign already there by at least 0.15 spaces.
    static func accidentalColumns(_ signs: [(accidental: Accidental, position: Int)]) -> [Int] {
        var result = Array(repeating: 0, count: signs.count)
        var taken: [[ClosedRange<CGFloat>]] = []
        let order = signs.indices.sorted { signs[$0].position > signs[$1].position }
        for index in order {
            let span = accidentalSpan(signs[index].accidental, at: signs[index].position)
            let padding: CGFloat = 0.3
            var column = 0
            while column < taken.count, taken[column].contains(where: {
                span.lowerBound < $0.upperBound + padding && $0.lowerBound < span.upperBound + padding
            }) {
                column += 1
            }
            if column == taken.count { taken.append([]) }
            taken[column].append(span)
            result[index] = column
        }
        return result
    }

    /// Dots in spaces: a note on a line has its dot in the space above (below, for the lower voice
    /// of two), and a chord's dots never share a space.
    private static func placeDots(_ chord: inout PlannedChord, multiVoice: Bool) {
        guard chord.value.dots > 0 else { return }
        var used = Set<Int>()
        for index in chord.heads.indices.reversed() {
            let position = chord.heads[index].position
            let lowerVoice = multiVoice && !chord.stemUp
            var dot = position % 2 == 0 ? position + (lowerVoice ? -1 : 1) : position
            for candidate in [dot, dot - 2, dot + 2, dot - 4] where !used.contains(candidate) {
                dot = candidate
                break
            }
            used.insert(dot)
            chord.heads[index].dotPosition = dot
        }
        var x = chord.headsRight + Metrics.dotGap + NoteShapes.dotRadius
        if chord.stemUp, let flagRight = chord.flagRight, let box = chord.flagBox {
            // After the flag when its tail comes down by the dots.
            let flagBottom = chord.stemTip - 2 * box.maxY
            let topDot = CGFloat(chord.heads.compactMap(\.dotPosition).max() ?? chord.highest)
            if flagBottom < topDot + 1.2 { x = max(x, flagRight + 0.25 + NoteShapes.dotRadius) }
        }
        chord.dotX = x
    }

    private func place(_ chord: PlannedChord) -> Chord {
        let staff = staves[chord.staff].geometry
        let columnX = columns[chord.column].x
        let s = space
        let heads = chord.heads.map { head -> Head in
            let center = CGPoint(x: columnX + (chord.shift + head.dx) * s, y: staff.y(head.position))
            var frame: CGRect?
            if let accidental = head.accidental {
                let box = StaffDrawing.accidentalPath(accidental, at: head.position, staff).cgPath.boundingBoxOfPath
                frame = box.offsetBy(dx: columnX + head.accidentalRight * s - box.maxX, dy: 0)
            }
            var dots: [CGPoint] = []
            if let dot = head.dotPosition {
                for index in 0..<chord.value.dots {
                    dots.append(CGPoint(x: columnX + (chord.dotX + CGFloat(index) * Metrics.dotSpacing) * s, y: staff.y(dot)))
                }
            }
            return Head(symbol: head.symbol, position: head.position, kind: chord.value.kind, center: center,
                        isFlipped: head.isFlipped, accidental: head.accidental, accidentalFrame: frame,
                        accidentalColumn: head.accidentalColumn, dots: dots)
        }
        var stem: CGRect?
        var flagOrigin: CGPoint?
        if chord.value.hasStem {
            // From the far head's stem anchor to the flag's anchor, or into the beam.
            let stemX = columnX + (chord.shift + chord.stemDX) * s
            let from = staff.y(chord.stemUp ? chord.lowest : chord.highest) + (chord.stemUp ? -1 : 1) * NoteShapes.stemStart * s
            let end = staff.y(chord.stemEnd)
            stem = CGRect(x: stemX - NoteShapes.stemWidth * s / 2, y: min(from, end), width: NoteShapes.stemWidth * s,
                          height: abs(end - from))
            if chord.flagCount > 0 { flagOrigin = CGPoint(x: stemX - NoteShapes.stemWidth * s / 2, y: staff.y(chord.stemTip)) }
        }
        let ledgers = chord.ledgerPositions().map {
            Ledger(y: staff.y($0.position), left: columnX + $0.left * s, right: columnX + $0.right * s)
        }
        return Chord(staff: chord.staff, voice: chord.voice, column: chord.column, value: chord.value, stemUp: chord.stemUp,
                     stem: stem, flagOrigin: flagOrigin, beam: chord.beam, heads: heads, ledgers: ledgers)
    }

    /// The groups' beams in points, at the tips `fitBeams` gave their stems: the primary beam from
    /// the first stem to the last, each further level where its notes' beam parts run (begin to end),
    /// and hooks a note head long, pointing the way their parts say.
    private mutating func placeBeams(_ planned: [PlannedBeam], planned chordPlans: [PlannedChord]) {
        let s = space
        let thickness = Metrics.beamThickness * s
        for plan in planned {
            let staff = staves[plan.staff].geometry
            let stems = plan.chords.map { chords[$0].stem ?? .zero }
            let xs = stems.map(\.midX)
            let outer = (first: staff.y(chordPlans[plan.chords.first!].stemTip), last: staff.y(chordPlans[plan.chords.last!].stemTip))
            func outerY(_ x: CGFloat) -> CGFloat {
                guard xs.last! > xs.first! else { return outer.first }
                return outer.first + (outer.last - outer.first) * (x - xs.first!) / (xs.last! - xs.first!)
            }
            func segment(_ level: Int, from left: CGFloat, to right: CGFloat, hook: Bool = false) -> BeamSegment {
                let inset = Metrics.beamPitch * CGFloat(level) * s
                func top(_ x: CGFloat) -> CGFloat { plan.stemUp ? outerY(x) + inset : outerY(x) - inset - thickness }
                return BeamSegment(level: level, isHook: hook, topLeft: CGPoint(x: left, y: top(left)),
                                   topRight: CGPoint(x: right, y: top(right)), thickness: thickness)
            }
            func hook(_ level: Int, at index: Int, forward: Bool) -> BeamSegment {
                var length = Metrics.hookLength * s
                let neighbour = forward ? index + 1 : index - 1
                if xs.indices.contains(neighbour) { length = min(length, abs(xs[neighbour] - xs[index]) * 0.6) }
                return forward ? segment(level, from: stems[index].minX, to: xs[index] + length, hook: true)
                    : segment(level, from: xs[index] - length, to: stems[index].maxX, hook: true)
            }

            var segments = [segment(0, from: stems.first!.minX, to: stems.last!.maxX)]
            let depth = plan.parts.map(\.count).max() ?? 1
            for level in 1..<max(depth, 1) {
                var start: Int?
                var lastWithLevel: Int?
                func close() {
                    if let start, let end = lastWithLevel, end > start {
                        segments.append(segment(level, from: stems[start].minX, to: stems[end].maxX))
                    }
                    start = nil
                }
                for (index, parts) in plan.parts.enumerated() {
                    guard level < parts.count else {
                        close()
                        continue
                    }
                    switch parts[level] {
                    case .begin:
                        close()
                        start = index
                    case .continue:
                        if start == nil { start = index }
                    case .end:
                        if let open = start, open < index {
                            lastWithLevel = index
                            close()
                        } else {
                            segments.append(hook(level, at: index, forward: index == 0))
                            start = nil
                        }
                    case .forwardHook:
                        segments.append(hook(level, at: index, forward: true))
                    case .backwardHook:
                        segments.append(hook(level, at: index, forward: false))
                    }
                    lastWithLevel = index
                }
                close()
            }
            beams.append(Beam(staff: plan.staff, voice: plan.voice, stemUp: plan.stemUp, chords: plan.chords,
                              symbols: plan.chords.flatMap { chords[$0].heads.map(\.symbol) }, segments: segments))
        }
    }

    // MARK: Rests

    /// The rest's reference line: the score's, else the usual one (a whole rest hangs from the
    /// fourth line, the others sit on or centre on the middle line), moved up for the upper voice
    /// of two and down for the lower.
    static func restPosition(_ symbol: BarSymbol, kind: NoteValue.Kind, multiVoice: Bool) -> Int {
        if var position = symbol.restPosition {
            // Whole and half rests hang from or sit on a line.
            if position % 2 != 0 { position += kind == .whole ? 1 : kind == .half ? -1 : 0 }
            return position
        }
        let usual = kind == .whole ? 6 : 4
        guard multiVoice else { return usual }
        if symbol.voice % 2 == 1 { return usual + (kind == .whole ? 2 : 4) }
        return usual - 4
    }

    private func place(_ rest: PlannedRest) -> Rest {
        let staff = staves[rest.staff].geometry
        let s = space
        let x = rest.column.map { columns[$0].x } ?? (barStart + notesEnd) / 2
        let origin = CGPoint(x: x, y: staff.y(rest.position))
        let bounds = rest.bounds
        let frame = CGRect(x: x + bounds.minX * s, y: origin.y + bounds.minY * s, width: bounds.width * s, height: bounds.height * s)
        let dots = (0..<rest.dots).map {
            CGPoint(x: x + (rest.dotX + CGFloat($0) * Metrics.dotSpacing) * s, y: staff.y(rest.dotPosition))
        }
        var ledger: Ledger?
        if rest.kind == .whole || rest.kind == .half, !(0...8).contains(rest.position) {
            ledger = Ledger(y: origin.y, left: frame.minX - 0.35 * s, right: frame.maxX + 0.35 * s)
        }
        return Rest(symbol: rest.symbol, staff: rest.staff, kind: rest.kind, origin: origin, frame: frame, dots: dots, ledger: ledger)
    }

    // MARK: Spacing

    /// A piece of a column's ink on one staff: x in spaces from the column's x, y in staff positions.
    struct Slab {
        let staff: Int
        let x: ClosedRange<CGFloat>
        let y: ClosedRange<CGFloat>
    }

    /// How close (in spaces) the next column may come: wherever ink on a staff would meet at the same
    /// height, `Metrics.gap` apart, so a head can tuck under the previous note's flag; and never
    /// closer than two heads side by side.
    static func closestDistance(_ column: [Slab], _ next: [Slab]) -> CGFloat {
        var distance = NoteShapes.headWidth + Metrics.gap
        let padding: CGFloat = 0.5
        for a in column {
            for b in next where a.staff == b.staff && a.y.lowerBound < b.y.upperBound + padding
                && b.y.lowerBound < a.y.upperBound + padding {
                distance = max(distance, a.x.upperBound + Metrics.gap - b.x.lowerBound)
            }
        }
        return distance
    }

    /// Room for a column, by the time until the next one (in quarters): growing with its square
    /// root, so a half note gets about 1.4 times a quarter's room and an eighth 0.7.
    static func idealRoom(_ quarters: Double) -> CGFloat {
        CGFloat(max(0, quarters)).squareRoot()
    }

    /// Widths for segments that each need at least `min` (points) and would like `ideal` times a
    /// common factor, chosen so they add up to `width`. Too little width: every segment's minimum.
    static func stretch(_ segments: [(min: CGFloat, ideal: CGFloat)], toFill width: CGFloat) -> [CGFloat] {
        let minimum = segments.reduce(0) { $0 + $1.min }
        guard width > minimum, segments.contains(where: { $0.ideal > 0 }) else { return segments.map(\.min) }
        func total(_ factor: CGFloat) -> CGFloat { segments.reduce(0) { $0 + max($1.min, factor * $1.ideal) } }
        var low: CGFloat = 0
        var high: CGFloat = 1
        while total(high) < width { high *= 2 }
        for _ in 0..<60 {
            let middle = (low + high) / 2
            if total(middle) < width { low = middle } else { high = middle }
        }
        return segments.map { max($0.min, high * $0.ideal) }
    }

    /// The key signature's width after the clef, in spaces (measured at a large size for precision).
    static func keySignatureWidth(_ keySignature: KeySignature, clef: Clef) -> CGFloat {
        let scale: CGFloat = 100
        let geometry = StaffGeometry(space: scale, left: 0, right: 1, bottomLineY: 0, height: 1)
        return StaffDrawing.keySignatureSigns(keySignature, clef: clef, after: 0, geometry).end / scale
    }

    // MARK: Vertical

    private struct VerticalPlan {
        let spacesTall: CGFloat
        /// From the top of the block (centred on the canvas) to each staff's middle line, in spaces.
        let middles: [CGFloat]
        /// The staff positions each staff's stems may reach: its strip, less a little air.
        let limits: [ClosedRange<CGFloat>]
        /// Between a grand staff's two bands.
        let boundary: CGFloat
    }

    /// One staff as `StaffGeometry(size:fitting:)` sizes it; a grand staff with each staff's outer
    /// room the same way, and between them just enough for the notes that reach into the gap.
    /// `content` (staff positions each staff's ink reaches in this bar) only ever adds room where the
    /// bar needs more than that: stems and rests of a second voice, octave marks, ties.
    private static func verticalPlan(_ staves: [BarDisplay.Staff], content: [ClosedRange<CGFloat>]? = nil) -> VerticalPlan {
        let air: CGFloat = 0.3
        if staves.count == 1 {
            var (above, below) = StaffGeometry.room(fitting: staves[0].positions)
            var spacesTall = max(StaffGeometry.usualSpacesTall, above + below)
            var middleFromTop = min(max(spacesTall / 2, above), spacesTall - below)
            if let extent = content?.first {
                let needAbove = (extent.upperBound - 4) / 2 + air
                let needBelow = (4 - extent.lowerBound) / 2 + air
                if needAbove > middleFromTop || needBelow > spacesTall - middleFromTop {
                    above = max(above, needAbove)
                    below = max(below, needBelow)
                    spacesTall = max(StaffGeometry.usualSpacesTall, above + below)
                    middleFromTop = min(max(spacesTall / 2, above), spacesTall - below)
                }
            }
            let limits = (4 - 2 * (spacesTall - middleFromTop) + 2 * air)...(4 + 2 * middleFromTop - 2 * air)
            return VerticalPlan(spacesTall: spacesTall, middles: [middleFromTop], limits: [limits], boundary: 0)
        }
        var reach = grandStaffReach(upper: staves[0].positions, lower: staves[1].positions)
        var above = StaffGeometry.room(fitting: staves[0].positions).above
        var below = StaffGeometry.room(fitting: staves[1].positions).below
        if let content, content.count > 1 {
            above = max(above, (content[0].upperBound - 4) / 2 + air)
            reach.upper = max(reach.upper, -content[0].lowerBound / 2 + air)
            reach.lower = max(reach.lower, (content[1].upperBound - 8) / 2 + air)
            below = max(below, (4 - content[1].lowerBound) / 2 + air)
        }
        let gap = reach.upper + reach.lower + Metrics.grandStaffAir
        let upperShare = reach.upper + Metrics.grandStaffAir / 2
        let spacesTall = above + 2 + gap + 2 + below
        let upperMiddle = above
        let lowerMiddle = above + 4 + gap
        let limits: [ClosedRange<CGFloat>] = [(4 - 2 * (2 + upperShare) + 2 * air)...(4 + 2 * above - 2 * air),
                                              (4 - 2 * below + 2 * air)...(4 + 2 * (2 + gap - upperShare) - 2 * air)]
        return VerticalPlan(spacesTall: spacesTall, middles: [upperMiddle, lowerMiddle], limits: limits,
                            boundary: upperMiddle + 2 + upperShare)
    }

    /// How far (in spaces) a grand staff's upper staff reaches below its bottom line and the lower
    /// staff above its top line, from their `positions`: as far as the outermost note's sign (a sharp
    /// hangs 1.25 spaces past its note), and at least as far as a stem with two flags down from the
    /// upper staff's middle line (or up from the lower's). The gap is both plus a little air.
    static func grandStaffReach(upper: ClosedRange<Int>, lower: ClosedRange<Int>) -> (upper: CGFloat, lower: CGFloat) {
        let stems: CGFloat = 1.9
        return (max(CGFloat(max(0, -upper.lowerBound)) / 2 + 1.25, stems),
                max(CGFloat(max(0, lower.upperBound - 8)) / 2 + 1.25, stems))
    }

    /// The staff positions a chord's ink reaches: heads, stem, flags or beam, signs, ties, and room
    /// for an octave mark.
    private static func extent(of chord: PlannedChord, symbols: [BarSymbol], multiVoice: Bool) -> ClosedRange<CGFloat> {
        var low = CGFloat(chord.lowest) - 1
        var high = CGFloat(chord.highest) + 1
        if chord.value.hasStem {
            low = min(low, chord.stemTip, chord.stemEnd)
            high = max(high, chord.stemTip, chord.stemEnd)
            if let box = chord.flagBox {
                low = min(low, chord.stemTip - 2 * box.maxY)
                high = max(high, chord.stemTip - 2 * box.minY)
            }
        }
        for (index, head) in chord.heads.enumerated() {
            if let accidental = head.accidental {
                let span = accidentalSpan(accidental, at: head.position)
                low = min(low, span.lowerBound)
                high = max(high, span.upperBound)
            }
            let symbol = symbols[head.symbol]
            if symbol.tiedToNext || symbol.tiedFromPrevious {
                let up = tieBowsUp(stemUp: chord.stemUp, voice: chord.voice, multiVoice: multiVoice, head: index,
                                   of: chord.heads.count)
                if up { high = max(high, CGFloat(head.position) + 2.8) } else { low = min(low, CGFloat(head.position) - 2.8) }
            }
        }
        let shifts = chord.heads.map { symbols[$0.symbol].octaveShift }
        if shifts.contains(where: { $0 > 0 }) { high += Metrics.octaveMarkRoom }
        if shifts.contains(where: { $0 < 0 }) { low -= Metrics.octaveMarkRoom }
        return low...high
    }

    /// Ties bow away from the stem on a single note; in a chord the upper half bows up and the
    /// lower half down; with two voices on a staff, the upper voice's bow up and the lower's down.
    static func tieBowsUp(stemUp: Bool, voice: Int, multiVoice: Bool, head: Int, of count: Int) -> Bool {
        if multiVoice { return voice % 2 == 1 }
        if count == 1 || (count % 2 == 1 && head == count / 2) { return !stemUp }
        return head >= (count + 1) / 2
    }

    // MARK: Ties

    static func tieTarget(of index: Int, in symbols: [BarSymbol], drawn: [Int]) -> Int? {
        let from = symbols[index]
        guard from.tiedToNext, let pitch = from.pitch else { return nil }
        return drawn.first { other in
            other != index && symbols[other].staff == from.staff && symbols[other].voice == from.voice
                && symbols[other].pitch == pitch && symbols[other].offset > from.offset + 1e-6
        }
    }

    static func tieSource(of index: Int, in symbols: [BarSymbol], drawn: [Int]) -> Int? {
        drawn.first { tieTarget(of: $0, in: symbols, drawn: drawn) == index }
    }

    private mutating func placeTies(symbols: [BarSymbol], drawn: [Int], multiVoice: [Bool]) {
        var headAt: [Int: (chord: Int, head: Int)] = [:]
        for (chordIndex, chord) in chords.enumerated() {
            for (headIndex, head) in chord.heads.enumerated() { headAt[head.symbol] = (chordIndex, headIndex) }
        }
        let s = space
        func direction(_ chord: Chord, _ head: Int) -> Bool {
            Self.tieBowsUp(stemUp: chord.stemUp, voice: chord.voice, multiVoice: multiVoice[chord.staff], head: head,
                           of: chord.heads.count)
        }
        /// Where a tie leaves a head (`outgoing`) or arrives at one.
        func anchor(_ chord: Chord, _ headIndex: Int, up: Bool, outgoing: Bool) -> CGPoint {
            let head = chord.heads[headIndex]
            let halfWidth = NoteShapes.headInkWidth(head.kind) / 2 * s
            if chord.heads.count == 1 {
                var x = head.center.x + (outgoing ? 1 : -1) * halfWidth * 0.5
                if outgoing, let dot = head.dots.last { x = max(x, dot.x + (NoteShapes.dotRadius + 0.15) * s) }
                return CGPoint(x: x, y: head.center.y + (up ? -0.6 : 0.6) * s)
            }
            let xs = chord.heads.map(\.center.x)
            var x: CGFloat
            if outgoing {
                x = xs.max()! + halfWidth + 0.12 * s
                if chord.stemUp, let stem = chord.stem { x = max(x, stem.maxX + 0.12 * s) }
                if let dot = head.dots.last { x = max(x, dot.x + (NoteShapes.dotRadius + 0.15) * s) }
            } else {
                x = xs.min()! - halfWidth - 0.12 * s
            }
            return CGPoint(x: x, y: head.center.y + (up ? -0.25 : 0.25) * s)
        }
        for index in drawn {
            let symbol = symbols[index]
            guard let at = headAt[index] else { continue }
            let chord = chords[at.chord]
            let up = direction(chord, at.head)
            if symbol.tiedToNext {
                let start = anchor(chord, at.head, up: up, outgoing: true)
                if let target = Self.tieTarget(of: index, in: symbols, drawn: drawn), let to = headAt[target] {
                    var finish = anchor(chords[to.chord], to.head, up: up, outgoing: false)
                    finish.y = start.y - chord.heads[at.head].center.y + chords[to.chord].heads[to.head].center.y
                    ties.append(Tie(staff: chord.staff, symbol: index, start: start, end: finish, up: up))
                } else {
                    let finish = CGPoint(x: max(notesEnd - 0.3 * s, start.x + 1.2 * s), y: start.y)
                    ties.append(Tie(staff: chord.staff, symbol: index, start: start, end: finish, up: up))
                }
            }
            if symbol.tiedFromPrevious, Self.tieSource(of: index, in: symbols, drawn: drawn) == nil {
                let finish = anchor(chord, at.head, up: up, outgoing: false)
                let start = CGPoint(x: min(barStart + 0.3 * s, finish.x - 1.2 * s), y: finish.y)
                ties.append(Tie(staff: chord.staff, symbol: index, start: start, end: finish, up: up))
            }
        }
        for tie in ties {
            inkBoxes.append(InkBox(staff: tie.staff, rect: NoteShapes.tie(from: tie.start, to: tie.end, up: tie.up, space: s)
                .cgPath.boundingBoxOfPath, symbol: tie.symbol))
        }
    }

    // MARK: Ink

    private mutating func collectInk() {
        let s = space
        for (index, staff) in staves.enumerated() {
            let (bottom, top) = StaffMetrics.clefExtent(staff.display.clef)
            let clefTop = staff.geometry.bottomLineY - top * s
            let start = CGRect(x: staff.clefLeft, y: clefTop, width: staff.keySignatureEnd - staff.clefLeft, height: (top - bottom) * s)
            inkBoxes.append(InkBox(staff: index, rect: start, symbol: nil))
            if let timeSignature {
                inkBoxes.append(InkBox(staff: index, rect: Self.timeSignaturePath(timeSignature, left: timeSignatureLeft, staff.geometry)
                    .cgPath.boundingBoxOfPath, symbol: nil))
            }
            if let hints {
                let positions = staff.display.positions
                let top = staff.geometry.y(positions.upperBound) - 0.4 * s
                let bottom = staff.geometry.y(positions.lowerBound) + 0.4 * s
                inkBoxes.append(InkBox(staff: index, rect: CGRect(x: hints.left, y: top, width: hints.right - hints.left,
                                                                 height: bottom - top), symbol: nil))
            }
        }
        for chord in chords {
            for head in chord.heads {
                let box = NoteShapes.head(head.kind).cgPath.boundingBoxOfPath
                let rect = CGRect(x: head.center.x + box.minX * s, y: head.center.y + box.minY * s, width: box.width * s,
                                  height: box.height * s)
                inkBoxes.append(InkBox(staff: chord.staff, rect: rect, symbol: head.symbol))
                if let frame = head.accidentalFrame { inkBoxes.append(InkBox(staff: chord.staff, rect: frame, symbol: head.symbol)) }
                for dot in head.dots {
                    let r = NoteShapes.dotRadius * s
                    inkBoxes.append(InkBox(staff: chord.staff, rect: CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r),
                                           symbol: head.symbol))
                }
            }
            let symbol = chord.heads.count == 1 ? chord.heads[0].symbol : nil
            if let stem = chord.stem { inkBoxes.append(InkBox(staff: chord.staff, rect: stem, symbol: symbol)) }
            if let origin = chord.flagOrigin {
                inkBoxes.append(InkBox(staff: chord.staff, rect: Self.flagPath(chord.flags, at: origin, up: chord.stemUp, space: s)
                    .cgPath.boundingBoxOfPath, symbol: symbol))
            }
            for ledger in chord.ledgers {
                let thickness = SMuFL.legerLineThickness * s
                inkBoxes.append(InkBox(staff: chord.staff, rect: CGRect(x: ledger.left, y: ledger.y - thickness / 2,
                                                                       width: ledger.right - ledger.left, height: thickness), symbol: nil))
            }
        }
        for beam in beams {
            for segment in beam.segments { inkBoxes.append(InkBox(staff: beam.staff, rect: segment.frame, symbol: nil)) }
        }
        for rest in rests {
            inkBoxes.append(InkBox(staff: rest.staff, rect: rest.frame, symbol: rest.symbol))
            for dot in rest.dots {
                let r = NoteShapes.dotRadius * s
                inkBoxes.append(InkBox(staff: rest.staff, rect: CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r),
                                       symbol: rest.symbol))
            }
        }
        for change in clefChanges {
            inkBoxes.append(InkBox(staff: change.staff, rect: Self.clefChangePath(change, staves[change.staff].geometry)
                .cgPath.boundingBoxOfPath, symbol: nil))
        }
    }

    /// Bravura's flags for a stem going up or down, their origin at `origin`.
    static func flagPath(_ count: Int, at origin: CGPoint, up: Bool, space: CGFloat) -> Path {
        NoteShapes.flags(count, up: up).applying(CGAffineTransform(scaleX: space, y: space)
            .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y)))
    }

    static func clefChangePath(_ change: ClefChange, _ staff: StaffGeometry) -> Path {
        StaffDrawing.clefPath(change.clef, left: change.left, staff, change: true)
    }

    static func timeSignaturePath(_ time: TimeSignature, left: CGFloat, _ staff: StaffGeometry) -> Path {
        StaffDrawing.timeSignaturePath(time, left: left, staff)
    }

    // MARK: Octave marks

    /// Over (or under) each run of notes in a row on a staff with the same octave shift: the number
    /// at the start, a dashed line to the end and a hook, clear of everything in between.
    private mutating func placeOctaveMarks(symbols: [BarSymbol]) {
        let s = space
        for staffIndex in staves.indices {
            var notes: [(symbol: Int, offset: Double, shift: Int, left: CGFloat, right: CGFloat)] = []
            for chord in chords where chord.staff == staffIndex {
                for head in chord.heads {
                    let halfWidth = NoteShapes.headInkWidth(head.kind) / 2 * s
                    var left = head.center.x - halfWidth
                    if let frame = head.accidentalFrame { left = min(left, frame.minX) }
                    var right = head.center.x + halfWidth
                    if let dot = head.dots.last { right = max(right, dot.x + NoteShapes.dotRadius * s) }
                    let symbol = symbols[head.symbol]
                    notes.append((head.symbol, symbol.offset, symbol.octaveShift, left, right))
                }
            }
            notes.sort { ($0.offset, $0.symbol) < ($1.offset, $1.symbol) }
            // Runs in each voice, then runs of different voices joined where they overlap in time.
            var runs: [[Int]] = []
            for voice in Set(notes.map { symbols[$0.symbol].voice }).sorted() {
                var previousShift = 0
                for index in notes.indices where symbols[notes[index].symbol].voice == voice {
                    let shift = notes[index].shift
                    if shift != 0, shift == previousShift { runs[runs.count - 1].append(index) } else if shift != 0 { runs.append([index]) }
                    previousShift = shift
                }
            }
            var merged = true
            while merged {
                merged = false
                outer: for a in runs.indices {
                    for b in runs.indices where b > a && notes[runs[a][0]].shift == notes[runs[b][0]].shift {
                        let spanA = notes[runs[a].first!].offset...notes[runs[a].last!].offset
                        let spanB = notes[runs[b].first!].offset...notes[runs[b].last!].offset
                        if spanA.overlaps(spanB) {
                            runs[a] = (runs[a] + runs[b]).sorted()
                            runs.remove(at: b)
                            merged = true
                            break outer
                        }
                    }
                }
            }
            let staff = staves[staffIndex]
            for run in runs {
                let shift = notes[run[0]].shift
                let above = shift > 0
                let textLeft = run.map { notes[$0].left }.min()!
                let markSize = StaffMetrics.octaveMarkSize(shift)
                let halfDigit = markSize.height / 2 * s
                let lineStart = textLeft + markSize.width * s + 0.25 * s
                let hookX = max(run.map { notes[$0].right }.max()! + 0.3 * s, lineStart + 0.8 * s)
                let span = (textLeft - 0.2 * s)...(hookX + 0.2 * s)
                let nearby = inkBoxes.filter { $0.staff == staffIndex && $0.rect.maxX >= span.lowerBound && $0.rect.minX <= span.upperBound }
                let clearance = 0.4 * s + halfDigit
                var lineY: CGFloat
                if above {
                    let top = min(nearby.map(\.rect.minY).min() ?? .infinity, staff.geometry.y(8))
                    lineY = max(top - clearance, staff.band.lowerBound + halfDigit + 0.15 * s)
                } else {
                    let bottom = max(nearby.map(\.rect.maxY).max() ?? -.infinity, staff.geometry.y(0))
                    lineY = min(bottom + clearance, staff.band.upperBound - halfDigit - 0.15 * s)
                }
                let mark = OctaveMark(staff: staffIndex, shift: shift, symbols: run.map { notes[$0].symbol }, textLeft: textLeft,
                                      lineStart: lineStart, hookX: hookX, lineY: lineY, halfDigit: halfDigit)
                octaveMarks.append(mark)
                let glyph = StaffDrawing.octaveMarkPath(shift, left: textLeft, middle: lineY, space: s).cgPath.boundingBoxOfPath
                let line = StaffDrawing.octaveLinePath(from: lineStart, to: hookX, at: lineY, above: above, space: s)
                inkBoxes.append(InkBox(staff: staffIndex, rect: glyph.union(line.cgPath.boundingBoxOfPath), symbol: nil))
            }
        }
    }

    // MARK: Highlight and label

    private func currentHead(_ current: Int?) -> (chord: Chord, head: Head)? {
        guard let current else { return nil }
        for chord in chords {
            if let head = chord.heads.first(where: { $0.symbol == current }) { return (chord, head) }
        }
        return nil
    }

    /// A soft rounded band behind the note being asked (and its sign), the height of its staff.
    private mutating func placeHighlight(_ current: Int?) {
        guard let found = currentHead(current) else { return }
        let (chord, head) = found
        let s = space
        let staff = staves[chord.staff].geometry
        let halfWidth = NoteShapes.headInkWidth(head.kind) / 2 * s
        let left = min(head.center.x - halfWidth, head.accidentalFrame?.minX ?? .infinity) - 0.4 * s
        let right = head.center.x + halfWidth + 0.4 * s
        let top = min(staff.y(8) - 0.8 * s, head.center.y - 1.1 * s)
        let bottom = max(staff.y(0) + 0.8 * s, head.center.y + 1.1 * s)
        highlight = CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The pill goes outside the staff by the note (above on the upper staff, below on the lower),
    /// failing that beside it, then on the staff's other side; always on the canvas, never over the note.
    private mutating func placeLabel(_ current: Int?, size textSize: CGSize?) {
        guard let textSize, let found = currentHead(current) else { return }
        let (chord, head) = found
        let s = space
        let staff = staves[chord.staff]
        let pill = CGSize(width: (textSize.width + 0.9) * s, height: (textSize.height + 0.4) * s)
        let canvas = CGRect(origin: .zero, size: size)
        let headBox = inkBoxes.first { $0.symbol == head.symbol && abs($0.rect.midX - head.center.x) < 0.01 * s }?.rect
            ?? CGRect(x: head.center.x - 0.65 * s, y: head.center.y - 0.5 * s, width: 1.3 * s, height: 1)
        let air = 0.35 * s

        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, 0.2 * s), size.width - 0.2 * s - pill.width) }
        func outside(above: Bool) -> CGRect {
            let x = clampX(head.center.x - pill.width / 2)
            let nearby = inkBoxes.filter { $0.staff == chord.staff && $0.rect.maxX > x - 0.1 * s && $0.rect.minX < x + pill.width + 0.1 * s }
            if above {
                let top = min(nearby.map(\.rect.minY).min() ?? .infinity, staff.geometry.y(8))
                return CGRect(x: x, y: top - air - pill.height, width: pill.width, height: pill.height)
            }
            let bottom = max(nearby.map(\.rect.maxY).max() ?? -.infinity, staff.geometry.y(0))
            return CGRect(x: x, y: bottom + air, width: pill.width, height: pill.height)
        }
        func fits(_ rect: CGRect) -> Bool {
            rect.minY >= staff.band.lowerBound + 0.1 * s && rect.maxY <= staff.band.upperBound - 0.1 * s
                && canvas.insetBy(dx: 0.1 * s, dy: 0).contains(rect)
        }
        let outward = chord.staff == 0
        let beside: CGRect = {
            // Right of the chord's heads and dots, and of its flag where that comes down beside the pill.
            var right = headBox.maxX
            for other in chord.heads {
                right = max(right, other.center.x + NoteShapes.headInkWidth(other.kind) / 2 * s)
                if let dot = other.dots.last { right = max(right, dot.x + NoteShapes.dotRadius * s) }
            }
            let y = head.center.y - pill.height / 2
            if let origin = chord.flagOrigin {
                let flag = Self.flagPath(chord.flags, at: origin, up: chord.stemUp, space: s).cgPath.boundingBoxOfPath
                if flag.maxY > y, flag.minY < y + pill.height { right = max(right, flag.maxX) }
            }
            for ledger in chord.ledgers where ledger.y > y && ledger.y < y + pill.height { right = max(right, ledger.right - 0.25 * s) }
            return CGRect(x: right + 0.5 * s, y: y, width: pill.width, height: pill.height)
        }()
        func isClear(_ rect: CGRect) -> Bool {
            !inkBoxes.contains { $0.rect.intersects(rect.insetBy(dx: -0.15 * s, dy: -0.1 * s)) }
        }
        let candidates = [outside(above: outward), beside.maxX <= notesEnd && isClear(beside) ? beside : nil,
                          outside(above: !outward)].compactMap { $0 }
        if let rect = candidates.first(where: fits) {
            label = rect
            return
        }
        // Squeezed: whichever place, kept on the canvas, covers the least ink, and never the note itself.
        func onCanvas(_ rect: CGRect) -> CGRect {
            var rect = rect
            rect.origin.x = clampX(rect.minX)
            rect.origin.y = min(max(rect.minY, 0.1 * s), size.height - 0.1 * s - rect.height)
            return rect
        }
        func covered(_ rect: CGRect) -> CGFloat {
            inkBoxes.reduce(0) { total, box in
                let overlap = box.rect.intersection(rect)
                return overlap.isNull ? total : total + overlap.width * overlap.height + (box.symbol == head.symbol ? 1e9 : 0)
            }
        }
        label = [outside(above: outward), beside, outside(above: !outward)].map(onCanvas).min { covered($0) < covered($1) }
    }
}
