import SwiftUI

/// Sizes of the text a bar leaves room for, in staff spaces at the sizes `BarStaffView` draws it.
/// The view measures them; the defaults are close enough for tests.
struct BarTextMetrics {
    /// The widest hint name on any staff (at 0.62 spaces); nil without hints.
    var hintWidth: CGFloat?
    /// The answer pill's text (at 0.8 spaces); nil without a label.
    var labelSize: CGSize?
    /// "8va", "15ma", "8vb" and "15mb" (at 0.85 spaces), by octave shift.
    var octaveTextWidths: [Int: CGFloat] = [1: 1.5, -1: 1.55, 2: 2.1, -2: 2.15]

    func octaveTextWidth(_ shift: Int) -> CGFloat { octaveTextWidths[shift] ?? 2.15 }
}

/// Where everything in one bar goes: staves, clefs, columns of notes by time, heads, stems,
/// accidentals, dots, rests, ties, octave marks, the highlight and the answer pill. Pure geometry
/// (`BarStaffView` draws it), so it can be tested without rendering.
///
/// Horizontally the bar runs from after the widest clef and key signature to the right edge (less
/// the hint column). Every distinct offset on the drawn staves gets one column, so notes struck
/// together line up across a grand staff. Each column gets room growing with the square root of
/// the time until the next one, and never less than its ink needs: wherever ink on a staff would
/// meet the next column's at the same height (`closestDistance`), so a head may tuck under a flag
/// but never touch a sign, dot or second. The bar is stretched to fill the width; a bar too dense
/// to fit shrinks the staff instead. Vertically a staff is sized like `StaffGeometry(size:fitting:)`,
/// so a single staff matches `StaffView`; a grand staff leaves just enough room between its staves
/// for the upper staff's low ledger notes and the lower staff's high ones. Only a bar whose own ink
/// reaches further (a second voice's stems, an octave mark over high notes) gets more room.
///
/// Beams, later: group chords, put their stem tips on one slanted line in place of
/// `PlannedChord.stemTip`, and draw beams instead of flags (`Chord.flagAnchor`).
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
        /// The stem's tip at its right edge, where flags start; nil without flags.
        let flagAnchor: CGPoint?
        /// Low to high.
        let heads: [Head]
        let ledgers: [Ledger]
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

    struct ClefChange {
        let staff: Int
        let clef: Clef
        let column: Int
        let left: CGFloat
        static let scale: CGFloat = 0.7
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
        let fontSize: CGFloat
        var halfDigit: CGFloat { fontSize * 0.37 }
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
    private(set) var rests: [Rest] = []
    private(set) var ties: [Tie] = []
    private(set) var clefChanges: [ClefChange] = []
    private(set) var octaveMarks: [OctaveMark] = []
    /// Left and right ends of the staff lines.
    private(set) var staffLeft: CGFloat = 0
    private(set) var staffRight: CGFloat = 0
    /// After the widest clef and key signature: where the bar's music starts.
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
        static let ledgerOverhang: CGFloat = 0.41
        static let dotGap: CGFloat = 0.3
        static let dotSpacing: CGFloat = 0.5
        static let thinBarLine: CGFloat = 0.13
        static let thickBarLine: CGFloat = 0.45
        static let barLineSeparation: CGFloat = 0.35
        /// Brace and the gap before the opening line, on a grand staff.
        static let braceRoom: CGFloat = 1.4
        static let margin: CGFloat = 0.5
        static let grandStaffAir: CGFloat = 0.5
        /// Content needs this much more than its bare minimum before the staff shrinks for it.
        static let comfort: CGFloat = 1.05
        static let hintColumnLimit: CGFloat = 3
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
        /// Where the stem's tip may go (staff positions): inside the staff's strip of canvas.
        var tipLimits: ClosedRange<CGFloat> = -.infinity...(.infinity)
        var shift: CGFloat = 0
        var dotX: CGFloat = 0

        var halfWidth: CGFloat { NoteShapes.headInkWidth(value.kind) / 2 }
        var lowest: Int { heads.first!.position }
        var highest: Int { heads.last!.position }
        var stemDX: CGFloat { (stemUp ? 1 : -1) * NoteShapes.stemOffset }

        /// Stem tip as a staff position (fractional): 3.5 spaces past the last head (more for three
        /// or four flags), to the middle line at least on a staff with one voice, and shortened
        /// (not below `NoteShapes.shortestStem`) where it would leave the staff's strip of canvas.
        var stemTip: CGFloat {
            let length = NoteShapes.stemLength(flags: value.flags) * 2
            let shortest = NoteShapes.shortestStem(flags: value.flags) * 2
            if stemUp {
                var tip = CGFloat(highest) + length
                if reachesMiddle { tip = max(tip, 4) }
                return max(min(tip, tipLimits.upperBound), CGFloat(highest) + shortest)
            }
            var tip = CGFloat(lowest) - length
            if reachesMiddle { tip = min(tip, 4) }
            return min(max(tip, tipLimits.lowerBound), CGFloat(lowest) - shortest)
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

        var flagRight: CGFloat? {
            guard value.flags > 0 else { return nil }
            return shift + stemDX + NoteShapes.stemWidth / 2 + NoteShapes.flags(value.flags).cgPath.boundingBoxOfPath.maxX
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
                result.append(Slab(staff: staff, x: (stemX - NoteShapes.stemWidth / 2)...(stemX + NoteShapes.stemWidth / 2),
                                   y: min(from, stemTip)...max(from, stemTip)))
                if value.flags > 0 {
                    let box = NoteShapes.flags(value.flags).cgPath.boundingBoxOfPath
                    let left = stemX + NoteShapes.stemWidth / 2
                    let reach = 2 * box.maxY
                    result.append(Slab(staff: staff, x: (left + box.minX)...(left + box.maxX),
                                       y: stemUp ? (stemTip - reach)...stemTip : stemTip...(stemTip + reach)))
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

        var planned = Self.planChords(symbols: symbols, drawn: drawn.filter { !symbols[$0].isRest },
                                      staffOf: staffOf, columnOf: columnOf, multiVoice: multiVoice)
        func limitStems(_ plan: VerticalPlan) {
            for index in planned.indices {
                // Room for an octave mark beyond the stems of the notes under it.
                var limits = plan.limits[planned[index].staff]
                let shifts = planned[index].heads.map { symbols[$0.symbol].octaveShift }
                if planned[index].stemUp, shifts.contains(where: { $0 > 0 }) {
                    limits = limits.lowerBound...max(limits.lowerBound, limits.upperBound - 2.6)
                } else if !planned[index].stemUp, shifts.contains(where: { $0 < 0 }) {
                    limits = min(limits.upperBound, limits.lowerBound + 2.6)...limits.upperBound
                }
                planned[index].tipLimits = limits
                Self.placeDots(&planned[index], multiVoice: multiVoice[planned[index].staff])
            }
        }
        limitStems(nominal)
        Self.shiftVoices(&planned)
        Self.placeAccidentals(&planned)

        let plannedRests = drawn.filter { symbols[$0].isRest }.map { index in
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
            return rest
        }

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
            let width = StaffMetrics.clefWidth(change.clef) * ClefChange.scale
            let left = contentLeft - 0.35 - width
            changeLefts.append(left)
            lefts[change.column] = min(lefts[change.column], left)
            let (bottom, top) = StaffMetrics.clefExtent(change.clef)
            let anchor: CGFloat = change.clef == .treble ? 1 : 3
            slabs[change.column].append(Slab(staff: change.staff, x: left...(left + width),
                                             y: (2 * (anchor + (bottom - anchor) * ClefChange.scale))...(2 * (anchor + (top - anchor) * ClefChange.scale))))
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
        let neededSpaces = staffLeftSpaces + 0.5 + (clefAndKey.max() ?? 0)
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

        // Everything in points.
        for chord in planned { chords.append(place(chord)) }
        for rest in plannedRests { rests.append(place(rest)) }
        for (index, change) in changes.enumerated() {
            clefChanges.append(ClefChange(staff: change.staff, clef: change.clef, column: change.column,
                                          left: columns[change.column].x + changeLefts[index] * space))
        }
        collectInk()
        placeTies(symbols: symbols, drawn: drawn, multiVoice: multiVoice)
        placeOctaveMarks(symbols: symbols, text: text)
        placeHighlight(bar.current)
        placeLabel(bar.current, size: text.labelSize)
    }

    // MARK: Chords

    private static func planChords(symbols: [BarSymbol], drawn: [Int], staffOf: (Int) -> Int, columnOf: (Double) -> Int,
                                   multiVoice: [Bool]) -> [PlannedChord] {
        struct Key: Hashable { let staff, voice, chord, column: Int }
        var order: [Key] = []
        var members: [Key: [Int]] = [:]
        for index in drawn {
            let symbol = symbols[index]
            let key = Key(staff: staffOf(index), voice: symbol.voice, chord: symbol.chord, column: columnOf(symbol.offset))
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(index)
        }
        return order.map { key in
            let notes = members[key]!.sorted { (symbols[$0].position!, $0) < (symbols[$1].position!, $1) }
            let positions = notes.map { symbols[$0].position! }
            let value = symbols[notes[0]].value
            let stemUp = notes.lazy.compactMap { symbols[$0].stemUp }.first
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
        if chord.stemUp, let flagRight = chord.flagRight {
            // After the flag when its tail comes down by the dots.
            let flagBottom = chord.stemTip - 2 * NoteShapes.flags(chord.value.flags).cgPath.boundingBoxOfPath.maxY
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
        var flagAnchor: CGPoint?
        if chord.value.hasStem {
            let stemX = columnX + (chord.shift + chord.stemDX) * s
            let from = staff.y(chord.stemUp ? chord.lowest : chord.highest)
            let tip = staff.y(chord.stemTip)
            stem = CGRect(x: stemX - NoteShapes.stemWidth * s / 2, y: min(from, tip), width: NoteShapes.stemWidth * s,
                          height: abs(tip - from))
            if chord.value.flags > 0 { flagAnchor = CGPoint(x: stemX + NoteShapes.stemWidth * s / 2, y: tip) }
        }
        let ledgers = chord.ledgerPositions().map {
            Ledger(y: staff.y($0.position), left: columnX + $0.left * s, right: columnX + $0.right * s)
        }
        return Chord(staff: chord.staff, voice: chord.voice, column: chord.column, value: chord.value, stemUp: chord.stemUp,
                     stem: stem, flagAnchor: flagAnchor, heads: heads, ledgers: ledgers)
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

    /// The staff positions a chord's ink reaches: heads, stem, signs, ties, and room for an octave mark.
    private static func extent(of chord: PlannedChord, symbols: [BarSymbol], multiVoice: Bool) -> ClosedRange<CGFloat> {
        var low = CGFloat(chord.lowest) - 1
        var high = CGFloat(chord.highest) + 1
        if chord.value.hasStem {
            low = min(low, chord.stemTip)
            high = max(high, chord.stemTip)
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
        if shifts.contains(where: { $0 > 0 }) { high += 2.6 }
        if shifts.contains(where: { $0 < 0 }) { low -= 2.6 }
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
            if let anchor = chord.flagAnchor {
                inkBoxes.append(InkBox(staff: chord.staff, rect: Self.flagPath(chord.value.flags, at: anchor, up: chord.stemUp, space: s)
                    .cgPath.boundingBoxOfPath, symbol: symbol))
            }
            for ledger in chord.ledgers {
                inkBoxes.append(InkBox(staff: chord.staff, rect: CGRect(x: ledger.left, y: ledger.y - 0.08 * s,
                                                                       width: ledger.right - ledger.left, height: 0.16 * s), symbol: nil))
            }
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

    /// Flags at the stem's tip, mirrored for a stem going down.
    static func flagPath(_ count: Int, at anchor: CGPoint, up: Bool, space: CGFloat) -> Path {
        NoteShapes.flags(count).applying(CGAffineTransform(scaleX: space, y: up ? space : -space)
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y)))
    }

    static func clefChangePath(_ change: ClefChange, _ staff: StaffGeometry) -> Path {
        StaffDrawing.clefPath(change.clef, left: change.left, staff, scale: ClefChange.scale)
    }

    // MARK: Octave marks

    /// Over (or under) each run of notes in a row on a staff with the same octave shift: the number
    /// at the start, a dashed line to the end and a hook, clear of everything in between.
    private mutating func placeOctaveMarks(symbols: [BarSymbol], text: BarTextMetrics) {
        let s = space
        let fontSize = 0.85 * s
        let halfDigit = fontSize * 0.37
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
                let textWidth = text.octaveTextWidth(shift) * s
                let lineStart = textLeft + textWidth + 0.2 * s
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
                                      lineStart: lineStart, hookX: hookX, lineY: lineY, fontSize: fontSize)
                octaveMarks.append(mark)
                let hook = (above ? 1 : -1) * 0.45 * s
                let box = CGRect(x: textLeft, y: min(lineY - halfDigit * 1.6, lineY + hook), width: hookX - textLeft,
                                 height: halfDigit * 2.6 + abs(hook))
                inkBoxes.append(InkBox(staff: staffIndex, rect: box, symbol: nil))
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
            if let anchor = chord.flagAnchor {
                let flag = Self.flagPath(chord.value.flags, at: anchor, up: chord.stemUp, space: s).cgPath.boundingBoxOfPath
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
