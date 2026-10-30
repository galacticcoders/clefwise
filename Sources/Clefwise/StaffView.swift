import CoreText
import SwiftUI

/// Draws a five-line staff with a clef, a key signature and, optionally, one quarter note.
struct StaffView: View {
    let clef: Clef
    /// Drawn after the clef. (Questions carry their own too; this one is used with or without a note.)
    var keySignature = KeySignature.cMajor
    /// Its `printedAccidental`, if any, is drawn in front of the note head.
    var note: Question?
    /// When set, the staff is scaled so notes anywhere in these positions fit (a piece's highest and
    /// lowest notes); nil keeps the usual layout, which fits three ledger lines either side.
    var positionsToFit: ClosedRange<Int>? = nil
    var noteColor: Color = Theme.ink
    /// Shown in a pill beside the note, e.g. to reveal the answer after a miss.
    var noteLabel: String?
    /// When set, the name of every line and space in this range is printed near the end of the staff.
    var hintPositions: ClosedRange<Int>?
    var naming = NamingSystem.letters

    var body: some View {
        Canvas { context, size in
            let staff = StaffGeometry(size: size, fitting: fittedPositions)
            drawLines(in: &context, staff)
            let clefEnd = drawClef(in: &context, staff)
            let keySignatureEnd = drawKeySignature(after: clefEnd, in: &context, staff)
            // On a narrow staff, slide the note right so its own accidental (and ledger lines) clear a
            // long key signature by about a space.
            let noteX = max(staff.noteX, keySignatureEnd + staff.space * 3.5)
            if let hintPositions {
                // Keep clear of the note's ledger lines, with a little air.
                drawHints(for: hintPositions, rightOf: noteX + staff.space * 1.55, in: &context, staff)
            }
            if let note {
                drawNote(note, at: noteX, in: &context, staff)
            }
        }
    }

    /// `positionsToFit` widened to any hint labels, so they aren't cut off either.
    private var fittedPositions: ClosedRange<Int>? {
        guard let positionsToFit, let hintPositions else { return positionsToFit }
        let lowest = min(positionsToFit.lowerBound, hintPositions.lowerBound)
        let highest = max(positionsToFit.upperBound, hintPositions.upperBound)
        return lowest...highest
    }

    private func drawLines(in context: inout GraphicsContext, _ staff: StaffGeometry) {
        var lines = Path()
        for position in stride(from: 0, through: 8, by: 2) {
            let y = staff.y(position)
            lines.move(to: CGPoint(x: staff.left, y: y))
            lines.addLine(to: CGPoint(x: staff.right, y: y))
        }
        context.stroke(lines, with: .color(Theme.ink), lineWidth: staff.lineWidth)
    }

    /// Returns the clef's right edge.
    private func drawClef(in context: inout GraphicsContext, _ staff: StaffGeometry) -> CGFloat {
        // Vertical extent of each clef, in staff spaces above the bottom line.
        let (bottom, top): (CGFloat, CGFloat) = clef == .treble ? (-1.55, 5.45) : (0.48, 4.05)
        let glyph = MusicGlyph.path(for: clef)
        let scale = (top - bottom) * staff.space / glyph.boundingBoxOfPath.height
        let left = staff.left + staff.space * 0.5
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: left, y: staff.bottomLineY - top * staff.space))
        context.fill(Path(glyph).applying(transform), with: .color(Theme.ink))
        return left + glyph.boundingBoxOfPath.width * scale
    }

    /// Returns where the signature ends (the clef's edge when there's none).
    private func drawKeySignature(after clefEnd: CGFloat, in context: inout GraphicsContext, _ staff: StaffGeometry) -> CGFloat {
        let accidental: Accidental = keySignature.fifths > 0 ? .sharp : .flat
        var end = clefEnd
        // Measured from the clef's real edge, so the bass clef's dots get the same air as the treble's curl.
        var left = clefEnd + staff.space * 0.6
        for position in keySignature.staffPositions(for: clef) {
            let sign = accidentalPath(accidental, at: position, staff)
            context.fill(sign.offsetBy(dx: left - sign.boundingRect.minX, dy: 0), with: .color(Theme.ink))
            end = left + sign.boundingRect.width
            left = end + staff.space * 0.15
        }
        return end
    }

    private func drawHints(for positions: ClosedRange<Int>, rightOf minX: CGFloat,
                           in context: inout GraphicsContext, _ staff: StaffGeometry) {
        // Names carry the key signature's sharps and flats: in G major the top line reads "F♯".
        let names = positions.map { position in
            let pitch = clef.pitch(atPosition: position)
            return naming.name(of: pitch.with(keySignature.accidental(for: pitch.letter)))
        }
        // Two columns (lines, then spaces) as wide as the longest name, so "Sol" or "komal Dha" don't collide.
        func layout(fontSize: CGFloat) -> (labels: [GraphicsContext.ResolvedText], column: CGFloat) {
            let font = Font.system(size: fontSize, weight: .semibold, design: .rounded)
            let labels = names.map { context.resolve(Text($0).font(font).foregroundStyle(Theme.hint)) }
            let widest = labels.map { $0.measure(in: CGSize(width: 1000, height: 1000)).width }.max() ?? 0
            return (labels, max(staff.space * 0.6, widest))
        }
        var (labels, column) = layout(fontSize: staff.space * 0.62)
        // Long sargam names on a narrow staff would reach the note; shrink them to fit instead.
        let room = (staff.right - minX - staff.space * 0.7) / 2
        if column > room {
            (labels, column) = layout(fontSize: staff.space * 0.62 * room / column)
        }
        let spaceX = staff.right - staff.space * 0.4 - column / 2
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

    private func drawNote(_ note: Question, at x: CGFloat, in context: inout GraphicsContext, _ staff: StaffGeometry) {
        let space = staff.space
        let position = note.position
        let y = staff.y(position)

        // Ledger lines for notes above or below the staff.
        var ledgers = Path()
        let ledgerPositions = position < 0 ? Array(stride(from: -2, through: position, by: -2))
            : position > 8 ? Array(stride(from: 10, through: position, by: 2)) : []
        for ledger in ledgerPositions {
            ledgers.move(to: CGPoint(x: x - space * 1.05, y: staff.y(ledger)))
            ledgers.addLine(to: CGPoint(x: x + space * 1.05, y: staff.y(ledger)))
        }
        context.stroke(ledgers, with: .color(Theme.ink), lineWidth: staff.lineWidth * 1.3)

        // Slightly tilted oval note head.
        let headWidth = space * 1.32
        let headHeight = space * 0.94
        let head = Path(ellipseIn: CGRect(x: -headWidth / 2, y: -headHeight / 2, width: headWidth, height: headHeight))
            .applying(CGAffineTransform(rotationAngle: -.pi / 9).concatenating(CGAffineTransform(translationX: x, y: y)))
        context.fill(head, with: .color(noteColor))

        // A little air before the head, or before the ledger lines, which would otherwise cut through the sign.
        var accidentalBounds: CGRect?
        if let accidental = note.printedAccidental {
            let sign = accidentalPath(accidental, at: position, staff)
            let right = x - (ledgerPositions.isEmpty ? headWidth / 2 + space * 0.25 : space * (1.05 + 0.15))
            let placed = sign.offsetBy(dx: right - sign.boundingRect.maxX, dy: 0)
            context.fill(placed, with: .color(noteColor))
            accidentalBounds = placed.cgPath.boundingBoxOfPath
        }

        // Stem goes up from the right of the head below the middle line, down from the left otherwise,
        // and always reaches at least the middle line.
        let stemUp = position < 4
        let stemWidth = space * 0.12
        let stemX = x + (stemUp ? 1 : -1) * (headWidth / 2 - stemWidth / 2 - space * 0.02)
        let stemEnd = stemUp ? min(y - space * 3.5, staff.y(4)) : max(y + space * 3.5, staff.y(4))
        let stem = Path(CGRect(x: stemX - stemWidth / 2, y: min(y, stemEnd), width: stemWidth, height: abs(stemEnd - y)))
        context.fill(stem, with: .color(noteColor))

        if note.octaveShift != 0 {
            // The mark goes outside the staff and everything drawn for the note. The head's ink, that is:
            // its `boundingRect` also takes in the ellipse's control points.
            let drawn = head.cgPath.boundingBoxOfPath.union(stem.boundingRect).union(accidentalBounds ?? .null)
            let column = min(drawn.minY, staff.y(8))...max(drawn.maxY, staff.y(0))
            drawOctaveMark(note.octaveShift, at: x, outside: column, accidental: accidentalBounds, in: &context, staff)
        }

        if let noteLabel {
            let text = context.resolve(pillText(noteLabel, size: space * 0.8).foregroundStyle(.white))
            let textSize = text.measure(in: CGSize(width: 1000, height: 1000))
            let pill = CGRect(x: x + space * 1.8, y: y - textSize.height / 2 - space * 0.2,
                              width: textSize.width + space * 0.9, height: textSize.height + space * 0.4)
            context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(noteColor))
            context.draw(text, at: CGPoint(x: pill.midX, y: pill.midY))
        }
    }

    /// "8va" above a note that sounds an octave higher than written ("15ma" for two), "8vb" or "15mb"
    /// below one that sounds lower: the number before the note, then a dashed line over it that hooks
    /// back towards it. `column` is the vertical span of the staff and the note, which the mark keeps out of.
    private func drawOctaveMark(_ shift: Int, at x: CGFloat, outside column: ClosedRange<CGFloat>, accidental: CGRect?,
                                in context: inout GraphicsContext, _ staff: StaffGeometry) {
        let space = staff.space
        let above = shift > 0
        let fontSize = space * 0.85
        let label = "\(abs(shift) * 7 + 1)\(abs(shift) == 1 ? "v" : "m")\(above ? "a" : "b")"
        let text = context.resolve(Text(label).font(.system(size: fontSize, weight: .bold, design: .serif).italic())
            .foregroundStyle(noteColor))
        let textSize = text.measure(in: CGSize(width: 1000, height: 1000))
        // The line runs through the middle of the digits, which stand about three quarters of an em tall.
        let halfDigit = fontSize * 0.37
        let clearance = space * 0.4 + halfDigit
        var lineY = above ? column.lowerBound - clearance : column.upperBound + clearance
        // A note at the very edge of a piece's range leaves less room than that; stay on the canvas.
        lineY = min(max(lineY, halfDigit + space * 0.15), staff.height - halfDigit - space * 0.15)

        var textRight = x - space * 0.8
        var lineStart = textRight + space * 0.2
        if let accidental, lineY - halfDigit < accidental.maxY + space * 0.15,
           lineY + halfDigit > accidental.minY - space * 0.15 {
            // Squeezed against the edge, the number can't clear the accidental: set it before the sign
            // and start the line after it.
            textRight = accidental.minX - space * 0.25
            lineStart = accidental.maxX + space * 0.2
        }
        let baseline = text.firstBaseline(in: textSize)
        context.draw(text, in: CGRect(x: textRight - textSize.width, y: lineY + halfDigit - baseline,
                                      width: textSize.width, height: textSize.height))

        // Dashes spread evenly from the number to the hook, which stops short of the answer pill and the
        // hint labels; the last dash turns down (or up) into the hook.
        let hookX = x + space * 1.2
        let dash = space * 0.3
        let count = max(2, Int(((hookX - lineStart + space * 0.2) / (space * 0.5)).rounded()))
        let step = (hookX - lineStart - dash) / CGFloat(count - 1)
        var line = Path()
        for index in 0..<count {
            let start = lineStart + CGFloat(index) * step
            line.move(to: CGPoint(x: start, y: lineY))
            line.addLine(to: CGPoint(x: start + dash, y: lineY))
        }
        line.addLine(to: CGPoint(x: hookX, y: lineY + (above ? 1 : -1) * space * 0.45))
        context.stroke(line, with: .color(noteColor), lineWidth: staff.lineWidth * 1.2)
    }

    /// The label in the rounded face, except ♯ and ♭: the rounded face has no sharp of its own and
    /// falls back to one that reads as "#", while the serif face's fallback is a proper sign.
    private func pillText(_ label: String, size: CGFloat) -> Text {
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

    /// The sign sized and set on `position` as engravers do: ♯ and ♮ centred on the line or space,
    /// ♭ with its bowl there. It starts at about x = 0; callers line it up by its bounds.
    private func accidentalPath(_ accidental: Accidental, at position: Int, _ staff: StaffGeometry) -> Path {
        // Height in spaces, and how much of it hangs below the line or space.
        // Sharps and naturals a touch under the usual 2.7–2.8: Apple Symbols draws them wider and
        // heavier than engraving fonts, and at full height they dwarf the note.
        let (height, below): (CGFloat, CGFloat) = switch accidental {
        case .sharp: (2.5, 1.25)
        case .natural: (2.5, 1.25)
        case .flat: (2.3, 0.6)
        }
        let glyph = MusicGlyph.path(for: accidental)
        let scale = height * staff.space / glyph.boundingBoxOfPath.height
        let outline = Path(glyph).applying(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: 0, y: staff.y(position) + (below - height) * staff.space)))
        // Apple Symbols' accidentals are lighter than engraved ones; thicken them to sit with the clef and note.
        return outline.union(outline.strokedPath(StrokeStyle(lineWidth: staff.space * 0.04, lineJoin: .round)))
    }
}

/// Maps staff positions to points for a given canvas size.
private struct StaffGeometry {
    /// Distance between two staff lines.
    let space: CGFloat
    let left: CGFloat
    let right: CGFloat
    let bottomLineY: CGFloat
    let noteX: CGFloat
    /// The whole canvas's, which octave marks stay inside.
    let height: CGFloat

    /// With `positions`, notes anywhere in them fit; without, the usual three ledger lines either side do.
    init(size: CGSize, fitting positions: ClosedRange<Int>?) {
        // Room above and below the middle line, in spaces. Usually 6.5 each way, 13 spaces tall: notes on
        // the third ledger line (positions -6 and 14), half a space for the head and a space of air.
        var above: CGFloat = 6.5
        var below: CGFloat = 6.5
        if let positions {
            // The same room past a piece's outermost notes. On a side the piece barely uses, just enough for
            // the clef, the stems and an octave mark beyond them, so a lopsided range doesn't waste half the height.
            above = max(CGFloat(positions.upperBound - 4) / 2 + 1.5, 5)
            below = max(CGFloat(4 - positions.lowerBound) / 2 + 1.5, 5)
        }
        // The staff never grows past its usual size, and moves off centre only as far as the range needs.
        let spacesTall = max(13, above + below)
        let middleFromTop = min(max(spacesTall / 2, above), spacesTall - below)
        space = min(size.height / spacesTall, size.width / 22)
        let width = min(size.width - space, space * 30)
        left = (size.width - width) / 2
        right = left + width
        bottomLineY = size.height / 2 + (middleFromTop - spacesTall / 2) * space + space * 2
        noteX = left + width * 0.55
        height = size.height
    }

    var lineWidth: CGFloat { max(1, space * 0.08) }

    func y(_ position: Int) -> CGFloat {
        bottomLineY - CGFloat(position) * space / 2
    }
}

/// Clef and accidental outlines from the system "Apple Symbols" font, shifted so the bounding box
/// starts at the origin with y pointing down.
private enum MusicGlyph {
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
