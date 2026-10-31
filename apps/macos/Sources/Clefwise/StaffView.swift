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
            StaffDrawing.drawLines(from: staff.left, to: staff.right, in: &context, staff)
            let clefEnd = StaffDrawing.drawClef(clef, in: &context, staff)
            let keySignatureEnd = StaffDrawing.drawKeySignature(keySignature, clef: clef, after: clefEnd, in: &context, staff)
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

    private func drawHints(for positions: ClosedRange<Int>, rightOf minX: CGFloat,
                           in context: inout GraphicsContext, _ staff: StaffGeometry) {
        // Names carry the key signature's sharps and flats: in G major the top line reads "F♯".
        let names = StaffDrawing.hintNames(for: positions, clef: clef, keySignature: keySignature, naming: naming)
        // Two columns (lines, then spaces) as wide as the longest name, so "Sol" or "komal Dha" don't collide.
        func layout(fontSize: CGFloat) -> (labels: [GraphicsContext.ResolvedText], column: CGFloat) {
            let font = StaffDrawing.hintFont(size: fontSize)
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
        StaffDrawing.drawHints(labels, at: positions, column: column, right: staff.right, in: &context, staff)
    }

    private func drawNote(_ note: Question, at x: CGFloat, in context: inout GraphicsContext, _ staff: StaffGeometry) {
        let space = staff.space
        let position = note.position
        let y = staff.y(position)
        let halfHead = NoteShapes.headWidth / 2 * space

        // Ledger lines for notes above or below the staff, reaching past the head as Bravura's defaults say.
        let ledgerReach = halfHead + SMuFL.legerLineExtension * space
        var ledgers = Path()
        let ledgerPositions = position < 0 ? Array(stride(from: -2, through: position, by: -2))
            : position > 8 ? Array(stride(from: 10, through: position, by: 2)) : []
        for ledger in ledgerPositions {
            ledgers.addRect(CGRect(x: x - ledgerReach, y: staff.y(ledger) - staff.ledgerWidth / 2,
                                   width: 2 * ledgerReach, height: staff.ledgerWidth))
        }
        context.fill(ledgers, with: .color(Theme.ink))

        let head = NoteShapes.head(.quarter).applying(CGAffineTransform(scaleX: space, y: space)
            .concatenating(CGAffineTransform(translationX: x, y: y)))
        context.fill(head, with: .color(noteColor))

        // A little air before the head, or before the ledger lines, which would otherwise cut through the sign.
        var accidentalBounds: CGRect?
        if let accidental = note.printedAccidental {
            let right = x - (ledgerPositions.isEmpty ? halfHead + space * 0.25 : ledgerReach + space * 0.15)
            let placed = StaffDrawing.accidentalPath(accidental, at: position, staff)
                .offsetBy(dx: right - StaffMetrics.accidentalWidth(accidental) * space, dy: 0)
            context.fill(placed, with: .color(noteColor))
            accidentalBounds = placed.cgPath.boundingBoxOfPath
        }

        // Stem up from the right of the head below the middle line, down from the left otherwise, where
        // Bravura's anchors put it; 3.5 spaces long, and always reaching at least the middle line.
        let stemUp = position < 4
        let stemWidth = NoteShapes.stemWidth * space
        let stemX = x + (stemUp ? 1 : -1) * NoteShapes.stemOffset * space
        let stemStart = y + (stemUp ? -1 : 1) * NoteShapes.stemStart * space
        let stemEnd = stemUp ? min(y - space * 3.5, staff.y(4)) : max(y + space * 3.5, staff.y(4))
        let stem = Path(CGRect(x: stemX - stemWidth / 2, y: min(stemStart, stemEnd), width: stemWidth,
                               height: abs(stemEnd - stemStart)))
        context.fill(stem, with: .color(noteColor))

        if note.octaveShift != 0 {
            // The mark goes outside the staff and everything drawn for the note.
            let drawn = head.cgPath.boundingBoxOfPath.union(stem.boundingRect).union(accidentalBounds ?? .null)
            let column = min(drawn.minY, staff.y(8))...max(drawn.maxY, staff.y(0))
            drawOctaveMark(note.octaveShift, at: x, outside: column, accidental: accidentalBounds, in: &context, staff)
        }

        if let noteLabel {
            let text = context.resolve(StaffDrawing.pillText(noteLabel, size: space * 0.8).foregroundStyle(.white))
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
        let size = StaffMetrics.octaveMarkSize(shift)
        let halfDigit = size.height / 2 * space
        let clearance = space * 0.4 + halfDigit
        var lineY = above ? column.lowerBound - clearance : column.upperBound + clearance
        // A note at the very edge of a piece's range leaves less room than that; stay on the canvas.
        lineY = min(max(lineY, halfDigit + space * 0.15), staff.height - halfDigit - space * 0.15)

        var textRight = x - space * 0.8
        var lineStart = textRight + space * 0.25
        if let accidental, lineY - halfDigit < accidental.maxY + space * 0.15,
           lineY + halfDigit > accidental.minY - space * 0.15 {
            // Squeezed against the edge, the number can't clear the accidental: set it before the sign
            // and start the line after it.
            textRight = accidental.minX - space * 0.25
            lineStart = accidental.maxX + space * 0.2
        }
        context.fill(StaffDrawing.octaveMarkPath(shift, left: textRight - size.width * space, middle: lineY, space: space),
                     with: .color(noteColor))
        // Dashes from the number to the hook, which stops short of the answer pill and the hint labels.
        context.fill(StaffDrawing.octaveLinePath(from: lineStart, to: x + space * 1.2, at: lineY, above: above, space: space),
                     with: .color(noteColor))
    }
}
