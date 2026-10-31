import CoreText
import SwiftUI

// What `StaffView` (one note) and `BarStaffView` (a whole bar) draw alike: the staff geometry, the
// clef and accidental outlines, key signatures, hint labels and the answer pill's text.

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

    var lineWidth: CGFloat { max(1, space * 0.08) }

    func y(_ position: Int) -> CGFloat {
        bottomLineY - CGFloat(position) * space / 2
    }

    /// For half positions (a dot between two spaces, a rest's edge…).
    func y(_ position: CGFloat) -> CGFloat {
        bottomLineY - position * space / 2
    }
}

/// Clef and accidental outlines from the system "Apple Symbols" font, shifted so the bounding box
/// starts at the origin with y pointing down. (The font has no rests, flags or note heads:
/// `NoteShapes` draws those.)
enum MusicGlyph {
    private static let treble = outline(of: "\u{1D11E}")
    private static let bass = outline(of: "\u{1D122}")
    private static let sharp = outline(of: "\u{266F}")
    private static let flat = outline(of: "\u{266D}")
    private static let natural = outline(of: "\u{266E}")

    static func path(for clef: Clef) -> CGPath {
        clef == .treble ? treble : bass
    }

    static func path(for accidental: Accidental) -> CGPath {
        switch accidental {
        case .sharp: sharp
        case .flat: flat
        case .natural: natural
        }
    }

    private static func outline(of character: String) -> CGPath {
        let font = CTFontCreateWithName("Apple Symbols" as CFString, 100, nil)
        var utf16 = Array(character.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count),
              let raw = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { return CGMutablePath() }
        var flip = CGAffineTransform(scaleX: 1, y: -1)
        let flipped = raw.copy(using: &flip) ?? raw
        let box = flipped.boundingBoxOfPath
        var shift = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        return flipped.copy(using: &shift) ?? flipped
    }
}

/// Sizes of the clefs and signs, in staff spaces, for layout without drawing.
enum StaffMetrics {
    /// Vertical extent of each clef, in staff spaces above the bottom line.
    static func clefExtent(_ clef: Clef) -> (bottom: CGFloat, top: CGFloat) {
        clef == .treble ? (-1.55, 5.45) : (0.48, 4.05)
    }

    /// The clef's width at full size.
    static func clefWidth(_ clef: Clef) -> CGFloat {
        let (bottom, top) = clefExtent(clef)
        let box = MusicGlyph.path(for: clef).boundingBoxOfPath
        return box.width * (top - bottom) / box.height
    }

    /// The sign's height in spaces, and how much of it hangs below its line or space. Sharps and
    /// naturals a touch under the usual 2.7–2.8: Apple Symbols draws them wider and heavier than
    /// engraving fonts, and at full height they dwarf the note.
    static func accidentalExtent(_ accidental: Accidental) -> (height: CGFloat, below: CGFloat) {
        switch accidental {
        case .sharp: (2.5, 1.25)
        case .natural: (2.5, 1.25)
        case .flat: (2.3, 0.6)
        }
    }

    /// The sign's inked width, thickening included.
    static func accidentalWidth(_ accidental: Accidental) -> CGFloat {
        let box = MusicGlyph.path(for: accidental).boundingBoxOfPath
        return box.width * accidentalExtent(accidental).height / box.height + 0.04
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

    /// The clef's outline with its left edge at `left`; `scale` below 1 gives the smaller clef of a
    /// change partway through a bar, still curled round its own line (G or F).
    static func clefPath(_ clef: Clef, left: CGFloat, _ staff: StaffGeometry, scale size: CGFloat = 1) -> Path {
        var (bottom, top) = StaffMetrics.clefExtent(clef)
        if size != 1 {
            let anchor: CGFloat = clef == .treble ? 1 : 3
            bottom = anchor + (bottom - anchor) * size
            top = anchor + (top - anchor) * size
        }
        let glyph = MusicGlyph.path(for: clef)
        let scale = (top - bottom) * staff.space / glyph.boundingBoxOfPath.height
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: left, y: staff.bottomLineY - top * staff.space))
        return Path(glyph).applying(transform)
    }

    /// Draws the clef at the start of the staff and returns its right edge.
    static func drawClef(_ clef: Clef, in context: inout GraphicsContext, _ staff: StaffGeometry,
                         left: CGFloat? = nil) -> CGFloat {
        let (bottom, top) = StaffMetrics.clefExtent(clef)
        let glyph = MusicGlyph.path(for: clef)
        let scale = (top - bottom) * staff.space / glyph.boundingBoxOfPath.height
        let left = left ?? staff.left + staff.space * 0.5
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: left, y: staff.bottomLineY - top * staff.space))
        context.fill(Path(glyph).applying(transform), with: .color(Theme.ink))
        return left + glyph.boundingBoxOfPath.width * scale
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
        var signs: [Path] = []
        var end = clefEnd
        // Measured from the clef's real edge, so the bass clef's dots get the same air as the treble's curl.
        var left = clefEnd + staff.space * 0.6
        for position in keySignature.staffPositions(for: clef) {
            let sign = accidentalPath(accidental, at: position, staff)
            signs.append(sign.offsetBy(dx: left - sign.boundingRect.minX, dy: 0))
            end = left + sign.boundingRect.width
            left = end + staff.space * 0.15
        }
        return (signs, end)
    }

    /// The sign sized and set on `position` as engravers do: ♯ and ♮ centred on the line or space,
    /// ♭ with its bowl there. It starts at about x = 0; callers line it up by its bounds.
    static func accidentalPath(_ accidental: Accidental, at position: Int, _ staff: StaffGeometry) -> Path {
        let (height, below) = StaffMetrics.accidentalExtent(accidental)
        let glyph = MusicGlyph.path(for: accidental)
        let scale = height * staff.space / glyph.boundingBoxOfPath.height
        let outline = Path(glyph).applying(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: 0, y: staff.y(position) + (below - height) * staff.space)))
        // Apple Symbols' accidentals are lighter than engraved ones; thicken them to sit with the clef and note.
        return outline.union(outline.strokedPath(StrokeStyle(lineWidth: staff.space * 0.04, lineJoin: .round)))
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

    /// The octave mark's number: "8va" an octave up, "15ma" two, "8vb" and "15mb" down.
    static func octaveLabel(_ shift: Int) -> String {
        "\(abs(shift) * 7 + 1)\(abs(shift) == 1 ? "v" : "m")\(shift > 0 ? "a" : "b")"
    }

    static func octaveFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif).italic()
    }
}
