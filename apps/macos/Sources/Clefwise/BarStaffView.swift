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
    /// A beamed note's stem goes with its group's beams, muted once every note they join is answered.
    private func ink(for chord: BarLayout.Chord, in layout: BarLayout) -> Ink {
        if let beam = chord.beam { return ink(for: layout.beams[beam]) }
        if chord.heads.count == 1 { return ink(for: chord.heads[0].symbol) }
        return chord.heads.allSatisfy { bar.answered.contains($0.symbol) } ? .muted : .normal
    }

    private func ink(for beam: BarLayout.Beam) -> Ink {
        beam.symbols.allSatisfy(bar.answered.contains) ? .muted : .normal
    }

    private func draw(_ layout: BarLayout, in context: inout GraphicsContext) {
        let s = layout.space
        guard s > 0 else { return }

        if let band = layout.highlight {
            context.fill(Path(roundedRect: band, cornerRadius: min(band.width / 2, s * 0.9)),
                         with: .color(currentColor.opacity(0.11)))
        }

        drawStaves(layout, in: &context)

        // Answered notes in one translucent layer, so where their parts overlap (a stem under its beam)
        // they don't darken: the layer is drawn opaque, then laid down at 30%.
        var muted = context
        muted.opacity = 0.3
        muted.drawLayer { layer in
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
            if let time = layout.timeSignature {
                context.fill(BarLayout.timeSignaturePath(time, left: layout.timeSignatureLeft, geometry), with: .color(Theme.ink))
            }
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
                    .concatenating(CGAffineTransform(translationX: layout.staffLeft - 0.3 * s, y: top)))
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
        func placed(_ shape: Path, at origin: CGPoint) -> Path {
            shape.applying(CGAffineTransform(scaleX: s, y: s).concatenating(CGAffineTransform(translationX: origin.x, y: origin.y)))
        }
        func dot(_ center: CGPoint, _ ink: Ink) {
            fill(placed(NoteShapes.dot, at: center), ink)
        }
        func ledger(_ ledger: BarLayout.Ledger, _ ink: Ink, _ staff: StaffGeometry) {
            fill(Path(CGRect(x: ledger.left, y: ledger.y - staff.ledgerWidth / 2, width: ledger.right - ledger.left,
                             height: staff.ledgerWidth)), ink)
        }

        for rest in layout.rests {
            let staff = layout.staves[rest.staff].geometry
            if let line = rest.ledger { ledger(line, .normal, staff) }
            fill(placed(NoteShapes.rest(rest.kind), at: rest.origin), .normal)
            for center in rest.dots { dot(center, .normal) }
        }

        // Beams in ink, muted once every note they join is answered.
        for beam in layout.beams {
            for segment in beam.segments { fill(segment.path, ink(for: beam)) }
        }

        for chord in layout.chords {
            let staff = layout.staves[chord.staff].geometry
            let chordInk = ink(for: chord, in: layout)
            // Ledger lines stay in ink, as `StaffView` draws them.
            for line in chord.ledgers { ledger(line, chordInk == .current ? .normal : chordInk, staff) }
            if let stem = chord.stem { fill(Path(stem), chordInk) }
            if let origin = chord.flagOrigin {
                fill(BarLayout.flagPath(chord.flags, at: origin, up: chord.stemUp, space: s), chordInk)
            }
            for head in chord.heads {
                let headInk = ink(for: head.symbol)
                fill(placed(NoteShapes.head(head.kind), at: head.center), headInk)
                if let accidental = head.accidental, let frame = head.accidentalFrame {
                    fill(StaffDrawing.accidentalPath(accidental, at: head.position, staff).offsetBy(dx: frame.minX, dy: 0), headInk)
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

    /// As `StaffView` draws them: Bravura's number, then dashes to a hook.
    private func drawOctaveMarks(_ layout: BarLayout, in context: inout GraphicsContext) {
        let s = layout.space
        for mark in layout.octaveMarks {
            let muted = mark.symbols.allSatisfy { bar.answered.contains($0) }
            let color = muted ? Theme.ink.opacity(0.3) : Theme.ink
            context.fill(StaffDrawing.octaveMarkPath(mark.shift, left: mark.textLeft, middle: mark.lineY, space: s),
                         with: .color(color))
            context.fill(StaffDrawing.octaveLinePath(from: mark.lineStart, to: mark.hookX, at: mark.lineY, above: mark.shift > 0,
                                                     space: s), with: .color(color))
        }
    }

    private func drawLabel(_ layout: BarLayout, in context: inout GraphicsContext) {
        guard let currentLabel, let pill = layout.label else { return }
        let text = context.resolve(StaffDrawing.pillText(currentLabel, size: layout.space * 0.8).foregroundStyle(.white))
        context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(currentColor))
        context.draw(text, at: CGPoint(x: pill.midX, y: pill.midY))
    }
}
