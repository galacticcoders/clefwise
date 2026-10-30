import CoreText
import SwiftUI

/// Draws a five-line staff with a clef and, optionally, one quarter note.
struct StaffView: View {
    let clef: Clef
    /// Drawn after the clef. (Questions carry their own too; this one is used with or without a note.)
    var keySignature = KeySignature.cMajor
    /// Its `printedAccidental`, if any, is drawn in front of the note head.
    var note: Question?
    var noteColor: Color = Theme.ink
    /// Shown in a pill beside the note, e.g. to reveal the answer after a miss.
    var noteLabel: String?
    /// When set, the name of every line and space in this range is printed near the end of the staff.
    var hintPositions: ClosedRange<Int>?
    var naming = NamingSystem.letters

    var body: some View {
        Canvas { context, size in
            let staff = StaffGeometry(size: size)
            drawLines(in: &context, staff)
            drawClef(in: &context, staff)
            if let hintPositions {
                drawHints(for: hintPositions, in: &context, staff)
            }
            if let note {
                drawNote(at: note.position, in: &context, staff)
            }
        }
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

    private func drawClef(in context: inout GraphicsContext, _ staff: StaffGeometry) {
        // Vertical extent of each clef, in staff spaces above the bottom line.
        let (bottom, top): (CGFloat, CGFloat) = clef == .treble ? (-1.55, 5.45) : (0.48, 4.05)
        let glyph = ClefGlyph.path(for: clef)
        let scale = (top - bottom) * staff.space / glyph.boundingBoxOfPath.height
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: staff.left + staff.space * 0.5,
                                             y: staff.bottomLineY - top * staff.space))
        context.fill(Path(glyph).applying(transform), with: .color(Theme.ink))
    }

    private func drawHints(for positions: ClosedRange<Int>, in context: inout GraphicsContext, _ staff: StaffGeometry) {
        let font = Font.system(size: staff.space * 0.62, weight: .semibold, design: .rounded)
        let labels = positions.map { position in
            context.resolve(Text(naming.name(of: clef.pitch(atPosition: position).letter)).font(font).foregroundStyle(Theme.hint))
        }
        // Two columns (lines, then spaces) as wide as the longest name, so "Sol" or "Dha" don't collide.
        let column = max(staff.space * 0.6, labels.map { $0.measure(in: CGSize(width: 1000, height: 1000)).width }.max() ?? 0)
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

    private func drawNote(at position: Int, in context: inout GraphicsContext, _ staff: StaffGeometry) {
        let space = staff.space
        let x = staff.noteX
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

        // Stem goes up from the right of the head below the middle line, down from the left otherwise,
        // and always reaches at least the middle line.
        let stemUp = position < 4
        let stemWidth = space * 0.12
        let stemX = x + (stemUp ? 1 : -1) * (headWidth / 2 - stemWidth / 2 - space * 0.02)
        let stemEnd = stemUp ? min(y - space * 3.5, staff.y(4)) : max(y + space * 3.5, staff.y(4))
        let stem = Path(CGRect(x: stemX - stemWidth / 2, y: min(y, stemEnd), width: stemWidth, height: abs(stemEnd - y)))
        context.fill(stem, with: .color(noteColor))

        if let noteLabel {
            let text = context.resolve(
                Text(noteLabel).font(.system(size: space * 0.8, weight: .bold, design: .rounded)).foregroundStyle(.white)
            )
            let textSize = text.measure(in: CGSize(width: 1000, height: 1000))
            let pill = CGRect(x: x + space * 1.8, y: y - textSize.height / 2 - space * 0.2,
                              width: textSize.width + space * 0.9, height: textSize.height + space * 0.4)
            context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(noteColor))
            context.draw(text, at: CGPoint(x: pill.midX, y: pill.midY))
        }
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

    init(size: CGSize) {
        // 13 spaces tall leaves room for three ledger lines above and below plus stems.
        space = min(size.height / 13, size.width / 22)
        let width = min(size.width - space, space * 30)
        left = (size.width - width) / 2
        right = left + width
        bottomLineY = size.height / 2 + space * 2
        noteX = left + width * 0.55
    }

    var lineWidth: CGFloat { max(1, space * 0.08) }

    func y(_ position: Int) -> CGFloat {
        bottomLineY - CGFloat(position) * space / 2
    }
}

/// Clef outlines from the system "Apple Symbols" font, shifted so the bounding box starts at
/// the origin with y pointing down.
private enum ClefGlyph {
    private static let treble = outline(of: "\u{1D11E}")
    private static let bass = outline(of: "\u{1D122}")

    static func path(for clef: Clef) -> CGPath {
        clef == .treble ? treble : bass
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
