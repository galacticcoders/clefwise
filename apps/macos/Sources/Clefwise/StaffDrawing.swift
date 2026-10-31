import CoreText
import SwiftUI

// What `StaffView` (one note) and `BarStaffView` (a whole bar) draw alike: the staff geometry, Bravura's
// glyphs placed on it (clefs, key and time signatures, accidentals, octave marks), hint labels and the
// answer pill's text.

/// Maps staff positions to points for a given canvas size.
struct StaffGeometry {
    /// Distance between two staff lines.
    let space: CGFloat
    let left: CGFloat
    let right: CGFloat
    let bottomLineY: CGFloat
    let noteX: CGFloat
    /// The whole canvas's, which octave marks stay inside.
    let height: CGFloat

    /// A staff's usual height in spaces: notes on the third ledger line either side, with air.
    static let usualSpacesTall: CGFloat = 13

    /// With `positions`, notes anywhere in them fit; without, the usual three ledger lines either side do.
    init(size: CGSize, fitting positions: ClosedRange<Int>?) {
        let (above, below) = Self.room(fitting: positions)
        // The staff never grows past its usual size, and moves off centre only as far as the range needs.
        let spacesTall = max(Self.usualSpacesTall, above + below)
        let middleFromTop = min(max(spacesTall / 2, above), spacesTall - below)
        space = min(size.height / spacesTall, size.width / 22)
        let width = min(size.width - space, space * 30)
        left = (size.width - width) / 2
        right = left + width
        bottomLineY = size.height / 2 + (middleFromTop - spacesTall / 2) * space + space * 2
        noteX = left + width * 0.55
        height = size.height
    }

    /// A staff placed by the caller (the bar view lays out its staves itself).
    init(space: CGFloat, left: CGFloat, right: CGFloat, bottomLineY: CGFloat, height: CGFloat) {
        self.space = space
        self.left = left
        self.right = right
        self.bottomLineY = bottomLineY
        self.noteX = left + (right - left) * 0.55
        self.height = height
    }

    /// Room above and below the middle line, in spaces. Usually 6.5 each way, 13 spaces tall: notes on
    /// the third ledger line (positions -6 and 14), half a space for the head and a space of air.
    static func room(fitting positions: ClosedRange<Int>?) -> (above: CGFloat, below: CGFloat) {
        guard let positions else { return (6.5, 6.5) }
        // The same room past a piece's outermost notes. On a side the piece barely uses, just enough for
        // the clef, the stems and an octave mark beyond them, so a lopsided range doesn't waste half the height.
        return (max(CGFloat(positions.upperBound - 4) / 2 + 1.5, 5), max(CGFloat(4 - positions.lowerBound) / 2 + 1.5, 5))
    }

    /// Staff lines, as thick as Bravura's engraving defaults say (never under a pixel).
    var lineWidth: CGFloat { max(1, space * SMuFL.staffLineThickness) }
    var ledgerWidth: CGFloat { max(1, space * SMuFL.legerLineThickness) }

    func y(_ position: Int) -> CGFloat {
        bottomLineY - CGFloat(position) * space / 2
    }

    /// For half positions (a dot between two spaces, a rest's edge…).
    func y(_ position: CGFloat) -> CGFloat {
        bottomLineY - position * space / 2
    }
}

/// Bravura's glyphs (see `MusicFont`) set at a size: one staff space to `space` points.
enum MusicGlyph {
    /// The glyph with its SMuFL origin at `origin`: a notehead's left edge on its line or space, a
    /// clef's on its line (G or F), a rest's on its reference line, a flag's at the stem's end.
    static func path(_ glyph: SMuFL.Glyph, at origin: CGPoint, space: CGFloat, scale: CGFloat = 1) -> Path {
        Path(MusicFont.outline(glyph)).applying(CGAffineTransform(scaleX: space * scale, y: space * scale)
            .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y)))
    }

    /// The glyph's ink in staff spaces, y down from its origin.
    static func bounds(_ glyph: SMuFL.Glyph) -> CGRect {
        MusicFont.bounds(glyph)
    }
}

/// Sizes of the clefs and signs, in staff spaces, for layout without drawing.
enum StaffMetrics {
    /// The staff position a clef is set on: the G clef curls round the G line, the F clef's dots
    /// straddle the F line.
    static func clefPosition(_ clef: Clef) -> Int {
        clef == .treble ? 2 : 6
    }

    /// Vertical extent of each clef, in staff spaces above the bottom line; `change` for the smaller
    /// clef of a change partway through a bar.
    static func clefExtent(_ clef: Clef, change: Bool = false) -> (bottom: CGFloat, top: CGFloat) {
        let box = MusicGlyph.bounds(.clef(clef, change: change))
        let line = CGFloat(clefPosition(clef)) / 2
        return (line - box.maxY, line - box.minY)
    }

    /// The clef's inked width.
    static func clefWidth(_ clef: Clef, change: Bool = false) -> CGFloat {
        MusicGlyph.bounds(.clef(clef, change: change)).width
    }

    /// The sign's height in spaces, and how much of it hangs below its line or space.
    static func accidentalExtent(_ accidental: Accidental) -> (height: CGFloat, below: CGFloat) {
        let box = MusicGlyph.bounds(.accidental(accidental))
        return (box.height, box.maxY)
    }

    /// The sign's inked width.
    static func accidentalWidth(_ accidental: Accidental) -> CGFloat {
        MusicGlyph.bounds(.accidental(accidental)).width
    }

    /// Air between a clef and the key signature after it, and between the signature's signs.
    static let clefToKeySignature: CGFloat = 0.7
    static let keySignatureGap: CGFloat = 0.12
    /// Air before a time signature, after the key signature (or the clef, with none).
    static let beforeTimeSignature: CGFloat = 0.9

    /// The glyphs of a time signature and where their origins go: x from its left edge, y as
    /// staff positions. Numbers stand one above the other, centred on each other; common and cut
    /// time sit on the middle line.
    static func timeSignatureGlyphs(_ time: TimeSignature) -> [(glyph: SMuFL.Glyph, x: CGFloat, position: Int)] {
        func number(_ value: Int) -> [SMuFL.Glyph] {
            String(max(0, value)).compactMap(\.wholeNumberValue).map(SMuFL.Glyph.timeSignatureDigit)
        }
        switch time.symbol {
        case .common: return [(.timeSigCommon, 0, 4)]
        case .cut: return [(.timeSigCutCommon, 0, 4)]
        case .numbers:
            let rows = [(number(time.beats), 6), (number(time.beatType), 2)]
            let widths = rows.map { $0.0.reduce(0) { $0 + MusicFont.advance($1) } }
            let width = widths.max() ?? 0
            var result: [(SMuFL.Glyph, CGFloat, Int)] = []
            for (row, rowWidth) in zip(rows, widths) {
                var x = (width - rowWidth) / 2
                for glyph in row.0 {
                    result.append((glyph, x, row.1))
                    x += MusicFont.advance(glyph)
                }
            }
            return result
        }
    }

    /// The time signature's width, side bearings included.
    static func timeSignatureWidth(_ time: TimeSignature) -> CGFloat {
        timeSignatureGlyphs(time).map { $0.x + MusicFont.advance($0.glyph) }.max() ?? 0
    }

    /// How much an octave mark ("8va"…) is scaled from Bravura's size, which is meant for a printed
    /// part, to sit with the notes of a staff as large as Clefwise's.
    static let octaveMarkScale: CGFloat = 0.5

    /// The octave mark's inked width and the height of its number, in spaces.
    static func octaveMarkSize(_ shift: Int) -> CGSize {
        let box = MusicGlyph.bounds(.octave(shift))
        return CGSize(width: box.maxX * octaveMarkScale, height: -box.minY * octaveMarkScale)
    }
}

/// Drawing shared by the staff views.
enum StaffDrawing {
    static func drawLines(from left: CGFloat, to right: CGFloat, in context: inout GraphicsContext, _ staff: StaffGeometry) {
        var lines = Path()
        for position in stride(from: 0, through: 8, by: 2) {
            let y = staff.y(position)
            lines.move(to: CGPoint(x: left, y: y))
            lines.addLine(to: CGPoint(x: right, y: y))
        }
        context.stroke(lines, with: .color(Theme.ink), lineWidth: staff.lineWidth)
    }

    /// The clef with its inked left edge at `left`, on its line; `change` gives the smaller clef of a
    /// change partway through a bar.
    static func clefPath(_ clef: Clef, left: CGFloat, _ staff: StaffGeometry, change: Bool = false) -> Path {
        let glyph = SMuFL.Glyph.clef(clef, change: change)
        let origin = CGPoint(x: left - MusicGlyph.bounds(glyph).minX * staff.space, y: staff.y(StaffMetrics.clefPosition(clef)))
        return MusicGlyph.path(glyph, at: origin, space: staff.space)
    }

    /// Draws the clef at the start of the staff and returns its right edge.
    static func drawClef(_ clef: Clef, in context: inout GraphicsContext, _ staff: StaffGeometry,
                         left: CGFloat? = nil) -> CGFloat {
        let left = left ?? staff.left + staff.space * 0.5
        context.fill(clefPath(clef, left: left, staff), with: .color(Theme.ink))
        return left + StaffMetrics.clefWidth(clef) * staff.space
    }

    /// Draws the signature after the clef and returns where it ends (the clef's edge when there's none).
    static func drawKeySignature(_ keySignature: KeySignature, clef: Clef, after clefEnd: CGFloat,
                                 in context: inout GraphicsContext, _ staff: StaffGeometry) -> CGFloat {
        let (signs, end) = keySignatureSigns(keySignature, clef: clef, after: clefEnd, staff)
        for sign in signs {
            context.fill(sign, with: .color(Theme.ink))
        }
        return end
    }

    /// The signature's signs in place after the clef, and where they end (the clef's edge when there's none).
    static func keySignatureSigns(_ keySignature: KeySignature, clef: Clef, after clefEnd: CGFloat,
                                  _ staff: StaffGeometry) -> (signs: [Path], end: CGFloat) {
        let accidental: Accidental = keySignature.fifths > 0 ? .sharp : .flat
        let width = StaffMetrics.accidentalWidth(accidental) * staff.space
        var signs: [Path] = []
        var end = clefEnd
        var left = clefEnd + staff.space * StaffMetrics.clefToKeySignature
        for position in keySignature.staffPositions(for: clef) {
            signs.append(accidentalPath(accidental, at: position, staff).offsetBy(dx: left, dy: 0))
            end = left + width
            left = end + staff.space * StaffMetrics.keySignatureGap
        }
        return (signs, end)
    }

    /// The sign on `position` as SMuFL sets it (♯ and ♮ centred on the line or space, ♭ with its bowl
    /// there), its left edge at x = 0.
    static func accidentalPath(_ accidental: Accidental, at position: Int, _ staff: StaffGeometry) -> Path {
        MusicGlyph.path(.accidental(accidental), at: CGPoint(x: 0, y: staff.y(position)), space: staff.space)
    }

    /// The time signature with its left edge at `left`.
    static func timeSignaturePath(_ time: TimeSignature, left: CGFloat, _ staff: StaffGeometry) -> Path {
        var path = Path()
        for item in StaffMetrics.timeSignatureGlyphs(time) {
            path.addPath(MusicGlyph.path(item.glyph, at: CGPoint(x: left + item.x * staff.space, y: staff.y(item.position)),
                                         space: staff.space))
        }
        return path
    }

    /// An octave mark's number ("8va", "15mb"…) with its left edge at `left` and its digits'
    /// vertical middle on `middle`.
    static func octaveMarkPath(_ shift: Int, left: CGFloat, middle: CGFloat, space: CGFloat) -> Path {
        let size = StaffMetrics.octaveMarkSize(shift)
        return MusicGlyph.path(.octave(shift), at: CGPoint(x: left, y: middle + size.height / 2 * space), space: space,
                               scale: StaffMetrics.octaveMarkScale)
    }

    /// The dashed line from an octave mark's number to the end of its run, where it turns down (for
    /// a mark above) or up into a hook.
    static func octaveLinePath(from start: CGFloat, to hookX: CGFloat, at y: CGFloat, above: Bool, space: CGFloat) -> Path {
        let dash = space * 0.45
        let count = max(2, Int(((hookX - start + space * 0.3) / (space * 0.8)).rounded()))
        let step = (hookX - start - dash) / CGFloat(count - 1)
        var line = Path()
        for index in 0..<count {
            let x = start + CGFloat(index) * step
            line.move(to: CGPoint(x: x, y: y))
            line.addLine(to: CGPoint(x: x + dash, y: y))
        }
        line.addLine(to: CGPoint(x: hookX, y: y + (above ? 1 : -1) * space * 0.6))
        return line.strokedPath(StrokeStyle(lineWidth: max(1, space * SMuFL.octaveLineThickness)))
    }

    /// Hint names for `positions`, carrying the key signature's sharps and flats: in G major the
    /// treble's top line reads "F♯".
    static func hintNames(for positions: ClosedRange<Int>, clef: Clef, keySignature: KeySignature,
                          naming: NamingSystem) -> [String] {
        positions.map { position in
            let pitch = clef.pitch(atPosition: position)
            return naming.name(of: pitch.with(keySignature.accidental(for: pitch.letter)))
        }
    }

    static func hintFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    /// Hint labels in two columns (lines, then spaces) `column` wide, the spaces' column ending
    /// 0.4 spaces before `right`. Staff lines are knocked out behind the names on them.
    static func drawHints(_ labels: [GraphicsContext.ResolvedText], at positions: ClosedRange<Int>, column: CGFloat,
                          right: CGFloat, in context: inout GraphicsContext, _ staff: StaffGeometry) {
        let spaceX = right - staff.space * 0.4 - column / 2
        let lineX = spaceX - column - staff.space * 0.3
        for (position, label) in zip(positions, labels) {
            let isLine = position % 2 == 0
            let point = CGPoint(x: isLine ? lineX : spaceX, y: staff.y(position))
            if isLine {
                // Knock the staff line out behind the name so it stays legible.
                let knockout = CGRect(x: point.x - column / 2 - staff.space * 0.1, y: point.y - staff.space * 0.32,
                                      width: column + staff.space * 0.2, height: staff.space * 0.64)
                context.fill(Path(knockout), with: .color(Theme.paper))
            }
            context.draw(label, at: point)
        }
    }

    /// The label in the rounded face, except ♯ and ♭: the rounded face has no sharp of its own and
    /// falls back to one that reads as "#", while the serif face's fallback is a proper sign.
    static func pillText(_ label: String, size: CGFloat) -> Text {
        let rounded = Font.system(size: size, weight: .bold, design: .rounded)
        let serif = Font.system(size: size * 1.15, weight: .bold, design: .serif)
        let characters = Array(label)
        return characters.indices.reduce(Text("")) { text, index in
            var piece = Text(String(characters[index])).font("♯♭".contains(characters[index]) ? serif : rounded)
            // That ♭ comes with wide margins on both sides; pull its neighbours in.
            if index + 1 < characters.count, characters[index + 1] == "♭" || characters[index] == "♭" {
                piece = piece.kerning(-size * 0.3)
            }
            return Text("\(text)\(piece)")
        }
    }
}
