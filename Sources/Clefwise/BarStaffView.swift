import SwiftUI

/// Draws one bar of a piece: its staff (or a grand staff) with clefs and key signatures, every
/// note and rest with its real note value, and the note being asked picked out.
///
/// `BarLayout` decides where everything goes; this view measures the text it needs and inks it.
/// Notes already answered are drawn muted; the note being asked gets `currentColor` on a soft band.
struct BarStaffView: View {
    let bar: BarDisplay
    /// The note being asked: the accent colour, or `Theme.wrong` while a miss is shown.
    var currentColor: Color = Theme.accent
    /// Shown in a pill by the note being asked, e.g. the answer after a miss.
    var currentLabel: String?
    /// Names every line and space of each staff over its `positions`, like `StaffView`'s hints.
    var showsHints = false
    var naming = NamingSystem.letters

    var body: some View {
        Canvas { context, size in
            let layout = BarLayout(bar: bar, size: size, text: measureText(context))
            draw(layout, in: &context)
        }
    }

    // MARK: - Text sizes

    /// Text sizes in staff spaces, measured at a staff space of 100 points.
    private func measureText(_ context: GraphicsContext) -> BarTextMetrics {
        let unit: CGFloat = 100
        let bounds = CGSize(width: 10_000, height: 10_000)
        var metrics = BarTextMetrics()
        if showsHints {
            var widest: CGFloat = 0
            for staff in bar.staves {
                // Any clef the staff takes in this bar: the hints name the lines for the one it ends with.
                let clefs = Set([staff.clef] + bar.measure.symbols.filter { $0.staff == staff.number }.map(\.clef))
                for clef in clefs {
                    for name in StaffDrawing.hintNames(for: staff.positions, clef: clef, keySignature: staff.keySignature,
                                                       naming: naming) {
                        let text = context.resolve(Text(name).font(StaffDrawing.hintFont(size: 0.62 * unit)))
                        widest = max(widest, text.measure(in: bounds).width)
                    }
                }
            }
            metrics.hintWidth = widest / unit
        }
        if let currentLabel {
            let size = context.resolve(StaffDrawing.pillText(currentLabel, size: 0.8 * unit)).measure(in: bounds)
            metrics.labelSize = CGSize(width: size.width / unit, height: size.height / unit)
        }
        for shift in [-2, -1, 1, 2] {
            let text = context.resolve(Text(StaffDrawing.octaveLabel(shift)).font(StaffDrawing.octaveFont(size: 0.85 * unit)))
            metrics.octaveTextWidths[shift] = text.measure(in: bounds).width / unit
        }
        return metrics
    }

    // MARK: - Drawing

    private enum Ink {
        case normal, muted, current
    }

    private func ink(for symbol: Int) -> Ink {
        if symbol == bar.current { return .current }
        return bar.answered.contains(symbol) ? .muted : .normal
    }

    /// A stem, flags or ledger lines: the note's own colour on a single note; on a chord, muted
    /// only once every note in it is answered (the note being asked colours just its head and sign).
    private func ink(for chord: BarLayout.Chord) -> Ink {
        if chord.heads.count == 1 { return ink(for: chord.heads[0].symbol) }
        return chord.heads.allSatisfy { bar.answered.contains($0.symbol) } ? .muted : .normal
    }

    private func draw(_ layout: BarLayout, in context: inout GraphicsContext) {
        let s = layout.space
        guard s > 0 else { return }

        if let band = layout.highlight {
            context.fill(Path(roundedRect: band, cornerRadius: min(band.width / 2, s * 0.9)),
                         with: .color(currentColor.opacity(0.11)))
        }

        drawStaves(layout, in: &context)

        // Answered notes in one translucent layer, so where their parts overlap they don't darken.
        context.drawLayer { layer in
            layer.opacity = 0.3
            drawMusic(layout, only: [.muted], in: &layer)
        }
        drawMusic(layout, only: [.normal, .current], in: &context)

        drawOctaveMarks(layout, in: &context)
        drawLabel(layout, in: &context)
    }

    private func drawStaves(_ layout: BarLayout, in context: inout GraphicsContext) {
        let s = layout.space
        for staff in layout.staves {
            let geometry = staff.geometry
            StaffDrawing.drawLines(from: layout.staffLeft, to: layout.staffRight, in: &context, geometry)
            let clefEnd = StaffDrawing.drawClef(staff.display.clef, in: &context, geometry, left: staff.clefLeft)
            _ = StaffDrawing.drawKeySignature(staff.display.keySignature, clef: staff.display.clef, after: clefEnd,
                                              in: &context, geometry)
            if let hints = layout.hints {
                let names = StaffDrawing.hintNames(for: staff.display.positions, clef: staff.endClef,
                                                   keySignature: staff.display.keySignature, naming: naming)
                let labels = names.map {
                    context.resolve(Text($0).font(StaffDrawing.hintFont(size: hints.fontSize)).foregroundStyle(Theme.hint))
                }
                StaffDrawing.drawHints(labels, at: staff.display.positions, column: hints.column, right: hints.right,
                                       in: &context, geometry)
            }
        }
        guard let first = layout.staves.first, let last = layout.staves.last else { return }
        let top = first.geometry.y(8)
        let bottom = last.geometry.y(0)
        let thin = max(1, s * BarLayout.Metrics.thinBarLine)
        if layout.isGrandStaff {
            // The brace, and the opening bar line joining the staves.
            let brace = NoteShapes.brace(height: (bottom - top) / s)
                .applying(CGAffineTransform(scaleX: s, y: s)
                    .concatenating(CGAffineTransform(translationX: layout.staffLeft - 0.4 * s, y: top)))
            context.fill(brace, with: .color(Theme.ink))
            context.fill(Path(CGRect(x: layout.staffLeft, y: top, width: thin, height: bottom - top)), with: .color(Theme.ink))
        }
        // The closing bar line, through both staves of a grand staff; thin and thick at the end of the piece.
        if layout.isFinal {
            let thick = s * BarLayout.Metrics.thickBarLine
            context.fill(Path(CGRect(x: layout.staffRight - thick, y: top, width: thick, height: bottom - top)),
                         with: .color(Theme.ink))
            let thinX = layout.staffRight - thick - s * BarLayout.Metrics.barLineSeparation - thin
            context.fill(Path(CGRect(x: thinX, y: top, width: thin, height: bottom - top)), with: .color(Theme.ink))
        } else {
            context.fill(Path(CGRect(x: layout.staffRight - thin, y: top, width: thin, height: bottom - top)),
                         with: .color(Theme.ink))
        }
    }

    private func drawMusic(_ layout: BarLayout, only inks: Set<Ink>, in context: inout GraphicsContext) {
        let s = layout.space
        func color(_ ink: Ink) -> Color {
            switch ink {
            case .current: currentColor
            case .normal, .muted: Theme.ink
            }
        }
        func fill(_ path: Path, _ ink: Ink) {
            if inks.contains(ink) { context.fill(path, with: .color(color(ink))) }
        }
        func dot(_ center: CGPoint, _ ink: Ink) {
            let r = NoteShapes.dotRadius * s
            fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), ink)
        }
        func ledger(_ ledger: BarLayout.Ledger, _ ink: Ink, _ staff: StaffGeometry) {
            guard inks.contains(ink) else { return }
            var path = Path()
            path.move(to: CGPoint(x: ledger.left, y: ledger.y))
            path.addLine(to: CGPoint(x: ledger.right, y: ledger.y))
            context.stroke(path, with: .color(color(ink)), lineWidth: staff.lineWidth * 1.3)
        }

        for rest in layout.rests {
            let staff = layout.staves[rest.staff].geometry
            if let line = rest.ledger { ledger(line, .normal, staff) }
            fill(NoteShapes.rest(rest.kind).applying(CGAffineTransform(scaleX: s, y: s)
                .concatenating(CGAffineTransform(translationX: rest.origin.x, y: rest.origin.y))), .normal)
            for center in rest.dots { dot(center, .normal) }
        }

        for chord in layout.chords {
            let staff = layout.staves[chord.staff].geometry
            let chordInk = ink(for: chord)
            // Ledger lines stay in ink, as `StaffView` draws them.
            for line in chord.ledgers { ledger(line, chordInk == .current ? .normal : chordInk, staff) }
            if let stem = chord.stem { fill(Path(stem), chordInk) }
            if let anchor = chord.flagAnchor {
                fill(BarLayout.flagPath(chord.value.flags, at: anchor, up: chord.stemUp, space: s), chordInk)
            }
            for head in chord.heads {
                let headInk = ink(for: head.symbol)
                fill(NoteShapes.head(head.kind).applying(CGAffineTransform(scaleX: s, y: s)
                    .concatenating(CGAffineTransform(translationX: head.center.x, y: head.center.y))), headInk)
                if let accidental = head.accidental, let frame = head.accidentalFrame {
                    let sign = StaffDrawing.accidentalPath(accidental, at: head.position, staff)
                    fill(sign.offsetBy(dx: frame.maxX - sign.cgPath.boundingBoxOfPath.maxX, dy: 0), headInk)
                }
                // Dots go with the note but stay in ink: only the head and its sign take the highlight.
                for center in head.dots { dot(center, headInk == .muted ? .muted : .normal) }
            }
        }

        for tie in layout.ties {
            let tieInk: Ink = ink(for: tie.symbol) == .muted ? .muted : .normal
            fill(NoteShapes.tie(from: tie.start, to: tie.end, up: tie.up, space: s), tieInk)
        }

        for change in layout.clefChanges {
            fill(BarLayout.clefChangePath(change, layout.staves[change.staff].geometry), .normal)
        }
    }

    /// As `StaffView` draws them: the number in bold serif italics, then dashes to a hook.
    private func drawOctaveMarks(_ layout: BarLayout, in context: inout GraphicsContext) {
        let s = layout.space
        for mark in layout.octaveMarks {
            let muted = mark.symbols.allSatisfy { bar.answered.contains($0) }
            let color = muted ? Theme.ink.opacity(0.3) : Theme.ink
            let text = context.resolve(Text(StaffDrawing.octaveLabel(mark.shift))
                .font(StaffDrawing.octaveFont(size: mark.fontSize)).foregroundStyle(color))
            let textSize = text.measure(in: CGSize(width: 1000, height: 1000))
            let baseline = text.firstBaseline(in: textSize)
            context.draw(text, in: CGRect(x: mark.textLeft, y: mark.lineY + mark.halfDigit - baseline,
                                          width: textSize.width, height: textSize.height))
            let dash = s * 0.3
            let count = max(2, Int(((mark.hookX - mark.lineStart + s * 0.2) / (s * 0.5)).rounded()))
            let step = (mark.hookX - mark.lineStart - dash) / CGFloat(count - 1)
            var line = Path()
            for index in 0..<count {
                let start = mark.lineStart + CGFloat(index) * step
                line.move(to: CGPoint(x: start, y: mark.lineY))
                line.addLine(to: CGPoint(x: start + dash, y: mark.lineY))
            }
            line.addLine(to: CGPoint(x: mark.hookX, y: mark.lineY + (mark.shift > 0 ? 1 : -1) * s * 0.45))
            context.stroke(line, with: .color(color), lineWidth: layout.staves[mark.staff].geometry.lineWidth * 1.2)
        }
    }

    private func drawLabel(_ layout: BarLayout, in context: inout GraphicsContext) {
        guard let currentLabel, let pill = layout.label else { return }
        let text = context.resolve(StaffDrawing.pillText(currentLabel, size: layout.space * 0.8).foregroundStyle(.white))
        context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(currentColor))
        context.draw(text, at: CGPoint(x: pill.midX, y: pill.midY))
    }
}
