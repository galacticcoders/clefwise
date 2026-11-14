import SwiftUI

/// Guitar answer input wired to the game: click where you'd play the note, on any string that has
/// it (`Game.answer(at:)`).
struct GuitarPad: View {
    let game: Game

    var body: some View {
        let board = game.fretboard
        let marks = marks(on: board)
        let neckHeight = PianoKeyboard.height - Self.rowHeight - Self.rowSpacing
        // As tall as the piano, so the window keeps its layout whichever input is chosen.
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                // The tuning over the open strings' end of the neck, where it applies; while notes are
                // named together, what to do beside it, as the piano says above its keys.
                HStack(spacing: 16) {
                    GuitarTuningMenu(game: game)
                    if game.namesTogether {
                        Text(caption)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: Self.rowHeight)
                .padding(.leading, NeckLayout(frets: board.frets, size: CGSize(width: geometry.size.width, height: neckHeight)).left)
                GuitarNeck(
                    fretboard: board,
                    naming: game.settings.naming,
                    showsNames: game.settings.showKeyNames,
                    prefersFlats: game.currentKeySignature.fifths < 0,
                    highlight: marks.highlight(at:),
                    onPress: { game.answer(at: $0) },
                    height: neckHeight
                )
                .disabled(!game.isTakingAnswers)
                // Fade as one layer, so the strings don't show through the dimmed dots.
                .compositingGroup()
                .opacity(game.isTakingAnswers ? 1 : 0.5)
            }
        }
        .frame(height: PianoKeyboard.height)
    }

    private static let rowHeight: CGFloat = 22
    private static let rowSpacing: CGFloat = 6

    /// What to do while notes are named together, and once judged how it went.
    private var caption: String {
        guard let group = game.group else {
            return game.phase == .playing ? "Click where you'd play the note"
                : "Notes struck together are played as one answer: click where you'd play each note"
        }
        let count = group.questions.count
        if let result = group.result {
            return result.isAllRight ? "All \(count) right" : "\(result.rightCount) of \(count) right"
        }
        let places = game.groupEntriesNeeded ?? count
        return places == 2 ? "Click where you'd play both notes, in either order (a chosen place again takes it back)"
            : "Click where you'd play all \(places) notes, in any order (a chosen place again takes it back)"
    }

    private func marks(on board: Fretboard) -> GuitarMarks {
        GuitarMarks(board: board, flash: game.flash, question: game.question, isShowingMiss: game.isShowingMiss,
                    group: shownGroup.map { GuitarMarks.Group(questions: $0.questions, entries: $0.entries, result: $0.result) })
    }

    /// The notes named together whose places are marked: the group being answered once a place is
    /// chosen or it's judged, otherwise for a moment the one just named all right (its flash).
    private var shownGroup: Game.NoteGroup? {
        if let group = game.group, !group.entries.isEmpty || group.result != nil { return group }
        return game.groupFlash
    }
}

/// Which places on the neck are marked, and how, mirroring the piano's keys but by place: the
/// place just clicked right or wrong; after a miss every place that sounds the note, since a note
/// lives in several places on a guitar and that's what there is to learn; while notes are named
/// together, the places chosen, then judged, and the missed notes at all their places.
struct GuitarMarks {
    struct Group {
        let questions: [Question]
        let entries: [Game.GroupEntry]
        let result: Game.GroupResult?
    }

    let board: Fretboard
    var flash: Game.Flash?
    var question: Question?
    var isShowingMiss = false
    /// The notes named together being shown, if any (see `GuitarPad.shownGroup`).
    var group: Group?

    func highlight(at position: GuitarPosition) -> KeyHighlight {
        if let group {
            if let entry = group.entries.firstIndex(where: { $0.position == position }) {
                guard let result = group.result else { return .armed }
                return result.entryIsRight.indices.contains(entry) && result.entryIsRight[entry] ? .correct : .wrong
            }
            if let result = group.result, isShowingMiss {
                let midi = board.midiNumber(at: position)
                if zip(group.questions, result.isRight).contains(where: { !$1 && $0.pitch.midiNumber == midi }) {
                    return .reveal
                }
            }
            return .none
        }
        if let flash, flash.position == position {
            return flash.isCorrect ? .correct : .wrong
        }
        // Matched by sound, so the question's spelling (D♭ or C♯) doesn't matter.
        if isShowingMiss, let question, board.midiNumber(at: position) == question.pitch.midiNumber {
            return .reveal
        }
        return .none
    }
}

/// A guitar neck as tab and most diagrams draw it, for a right-handed player: the nut on the left
/// with the open strings beyond it, frets to the right narrowing up the neck, string 1 (high E) at
/// the top and string 6 at the bottom, so higher notes are higher on screen, as on the staff. Every
/// place is an answer, open strings included. Answers are marked with finger dots, as in chord
/// diagrams. Names are left off unless asked for, as on the piano.
struct GuitarNeck: View {
    let fretboard: Fretboard
    let naming: NamingSystem
    /// Write the note's name in every place.
    let showsNames: Bool
    /// Where a place has no room for both names of a note between the naturals ("F♯/G♭"), the flat
    /// one (a flat key's) rather than the sharp one.
    var prefersFlats = false
    let highlight: (GuitarPosition) -> KeyHighlight
    let onPress: (GuitarPosition) -> Void
    var height = PianoKeyboard.height

    var body: some View {
        GeometryReader { geometry in
            let layout = NeckLayout(frets: fretboard.frets, size: geometry.size)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    NeckDrawing.draw(layout, in: &context)
                }
                .accessibilityHidden(true)
                ForEach(fretboard.positions, id: \.self) { position in
                    place(position, in: layout)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fretboard")
    }

    private func place(_ position: GuitarPosition, in layout: NeckLayout) -> some View {
        let target = layout.target(position)
        let pitch = fretboard.pitch(at: position)
        let names = showsNames ? Self.names(of: pitch, in: naming, prefersFlats: prefersFlats) : []
        return Button {
            onPress(position)
        } label: {
            if names.isEmpty {
                // Something rather than nothing: a button with an empty label isn't drawn at all.
                Color.clear.frame(width: 0, height: 0)
            } else {
                NameLabel(versions: names, fontSize: layout.fontSize)
            }
        }
        .buttonStyle(FretStyle(highlight: highlight(position), hasName: !names.isEmpty, dot: layout.dot(position),
                               markWidth: layout.markWidth(position), alignment: position.fret == 0 ? .leading : .center))
        .frame(width: target.width, height: target.height)
        .offset(x: target.minX, y: target.minY)
        .accessibilityLabel(showsNames ? "\(position.label), \(naming.name(of: pitch))" : position.label)
    }

    /// The name of the note at a place, in versions from the fullest to the shortest, each as its
    /// lines: a note between the naturals is called both ways where there's room ("F♯/G♭", as the
    /// piano's black keys are), otherwise the sharp (or `prefersFlats`, the flat). Sargam has one
    /// name per note ("komal Re"), on two lines where it's narrow.
    static func names(of pitch: Pitch, in naming: NamingSystem, prefersFlats: Bool) -> [[String]] {
        guard pitch.accidental != .natural else { return [[naming.name(of: pitch)]] }
        if naming == .sargam {
            let name = naming.name(of: pitch)
            let words = name.split(separator: " ").map(String.init)
            return words.count > 1 ? [[name], words] : [[name]]
        }
        // Board pitches are spelled with sharps (C♯…A♯); the flat is the next letter's.
        let sharp = pitch.with(.sharp)
        let flat = Pitch(NoteLetter(rawValue: (pitch.letter.rawValue + 1) % 7)!, pitch.octave, .flat)
        let both = "\(naming.name(of: sharp))/\(naming.name(of: flat))"
        return [[both], [naming.name(of: prefersFlats ? flat : sharp)]]
    }
}

/// A place's name: the first version that fits across the place, the last one shrunk if need be.
private struct NameLabel: View {
    let versions: [[String]]
    let fontSize: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(versions.indices, id: \.self) { index in
                let lines = versions[index]
                VStack(spacing: -1) {
                    ForEach(lines, id: \.self) { Text($0) }
                }
                .font(.system(size: lines.count > 1 ? fontSize * 0.8 : fontSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(index == versions.count - 1 ? 0.6 : 1)
            }
        }
    }
}

/// A place on the neck: its finger dot when it's marked, its name when names are shown (on a
/// patch of the wood, so the string doesn't run through it), and a faint dot while it's pressed.
private struct FretStyle: ButtonStyle {
    let highlight: KeyHighlight
    let hasName: Bool
    /// The finger dot's diameter.
    let dot: CGFloat
    /// The width the mark is centred in: the fret's, or the open strings' column.
    let markWidth: CGFloat
    /// Where that width sits in the place's target (an open string's takes the nut too).
    let alignment: Alignment

    func makeBody(configuration: Configuration) -> some View {
        let isMarked = highlight != .none
        let isPressed = configuration.isPressed && !isMarked
        let isDot = isMarked || isPressed
        configuration.label
            .foregroundStyle(isMarked ? highlight.foreground : Theme.fretLabel)
            .padding(.horizontal, hasName ? 3 : 0)
            .padding(.vertical, hasName && !isDot ? 1 : 0)
            .frame(minWidth: isDot ? dot : nil, minHeight: isDot ? dot : nil)
            .background {
                if isMarked {
                    Pill().fill(highlight.fill)
                } else if isPressed {
                    Pill().fill(Theme.ink.opacity(0.28))
                } else if hasName {
                    Pill().fill(Theme.fretboard)
                }
            }
            .overlay {
                if isMarked {
                    Pill().strokeBorder(highlight.border, lineWidth: highlight == .reveal ? 2.5 : 1)
                }
            }
            .frame(maxWidth: max(dot, markWidth - 2))
            .frame(maxWidth: markWidth, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: highlight)
    }
}

/// A capsule as a plain path: round for a finger dot, stretched round a name. (SwiftUI's own
/// `Capsule` can be drawn as a layer's rounded corners, which window snapshots turn into octagons
/// at this size.)
private struct Pill: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let radius = min(rect.width, rect.height) / 2
        return Path(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    }

    func inset(by amount: CGFloat) -> Pill {
        Pill(inset: inset + amount)
    }
}

/// Where the neck's parts go in a view of a given size. Pure geometry, so it can be tested.
///
/// Across: the open strings' column, the nut, then the frets, each 2^(−1/12) as wide as the one
/// before as on a real guitar, filling the width (but no first fret wider than `widestFret`,
/// centred); a long neck in a narrow window flattens that curve so no fret is narrower than
/// `narrowestFret`. Down: six rows, one per string, string 1 at the top, and the fret numbers
/// under them.
struct NeckLayout: Equatable {
    static let numbersHeight: CGFloat = 14
    static let openWidth: CGFloat = 38
    static let nutWidth: CGFloat = 6
    static let narrowestFret: CGFloat = 22
    static let widestFret: CGFloat = 110
    /// Frets with an inlay, and a number under them: as on most guitars, two dots at 12 and 24.
    static let inlayFrets = [3, 5, 7, 9, 12, 15, 17, 19, 21, 24]
    static func isDoubleInlay(_ fret: Int) -> Bool { fret % 12 == 0 }

    let frets: Int
    /// The open strings' column's left edge.
    let left: CGFloat
    let nutLeft: CGFloat
    /// Fret wires 1…`frets`, left to right: fret n is played between wire n−1 (or the nut) and wire n.
    let wires: [CGFloat]
    /// The strings' rows; the fret numbers go under them.
    let boardHeight: CGFloat

    init(frets: Int, size: CGSize) {
        self.frets = frets
        boardHeight = max(0, size.height - Self.numbersHeight)
        var widths = Self.fretWidths(count: frets, filling: size.width - Self.openWidth - Self.nutWidth,
                                     narrowest: Self.narrowestFret)
        if let first = widths.first, first > Self.widestFret {
            widths = widths.map { $0 * Self.widestFret / first }
        }
        let total = Self.openWidth + Self.nutWidth + widths.reduce(0, +)
        left = max(0, (size.width - total) / 2)
        nutLeft = left + Self.openWidth
        var x = nutLeft + Self.nutWidth
        wires = widths.map { width in
            x += width
            return x
        }
    }

    var nutRight: CGFloat { nutLeft + Self.nutWidth }
    /// The last fret wire.
    var right: CGFloat { wires.last ?? nutRight }
    var rowHeight: CGFloat { boardHeight / 6 }

    func stringY(_ string: Int) -> CGFloat { rowHeight * (CGFloat(string) - 0.5) }

    /// Where fret `fret` is played: from the wire before it (or the nut) to its own; the open
    /// strings' column for 0.
    func fretSpan(_ fret: Int) -> ClosedRange<CGFloat> {
        if fret <= 0 { return left...nutLeft }
        let start = fret == 1 ? nutRight : wires[fret - 2]
        return start...wires[fret - 1]
    }

    /// What clicks the place: its string's row across its fret. The open strings' places take the
    /// nut too, as nothing is played on it. Together they tile the neck.
    func target(_ position: GuitarPosition) -> CGRect {
        let span = position.fret == 0 ? left...nutRight : fretSpan(position.fret)
        return CGRect(x: span.lowerBound, y: rowHeight * CGFloat(position.string - 1),
                      width: span.upperBound - span.lowerBound, height: rowHeight)
    }

    /// The width a place's mark is centred in.
    func markWidth(_ position: GuitarPosition) -> CGFloat {
        let span = fretSpan(position.fret)
        return span.upperBound - span.lowerBound
    }

    /// The finger dot's diameter: most of the room between two strings, less on a narrow fret.
    func dot(_ position: GuitarPosition) -> CGFloat {
        max(0, min(rowHeight * 0.9, markWidth(position) - 4, 22))
    }

    /// The names' size.
    var fontSize: CGFloat { min(11, rowHeight * 0.5) }

    /// String 1 is the thinnest; the wound strings get thicker towards the 6th.
    static func stringWidth(_ string: Int) -> CGFloat {
        [1, 1.25, 1.55, 1.9, 2.3, 2.7][min(max(string, 1), 6) - 1]
    }

    /// The widths of frets 1…`count` filling `width`: each 2^(−1/12) as wide as the one before, as on
    /// a guitar, unless that makes the last narrower than `narrowest`; then the steps are flattened
    /// just enough for it (to all equal, if even that doesn't fit).
    static func fretWidths(count: Int, filling width: CGFloat, narrowest: CGFloat) -> [CGFloat] {
        guard count > 0, width > 0 else { return [] }
        func widths(_ ratio: Double) -> [CGFloat] {
            let terms = (0..<count).map { pow(ratio, Double($0)) }
            let total = terms.reduce(0, +)
            return terms.map { CGFloat($0 / total) * width }
        }
        let guitar = pow(2, -1.0 / 12)
        let real = widths(guitar)
        if real.last! >= narrowest { return real }
        if width / CGFloat(count) <= narrowest { return widths(1) }
        var low = guitar, high = 1.0
        for _ in 0..<50 {
            let middle = (low + high) / 2
            if widths(middle).last! >= narrowest { high = middle } else { low = middle }
        }
        return widths(high)
    }
}

/// The neck itself: wood, inlays, fret wires, nut, strings and the fret numbers.
private enum NeckDrawing {
    static func draw(_ layout: NeckLayout, in context: inout GraphicsContext) {
        let height = layout.boardHeight
        guard height > 0, !layout.wires.isEmpty else { return }
        let woodRight = layout.right + 3
        context.fill(Path(roundedRect: CGRect(x: layout.nutLeft, y: 0, width: woodRight - layout.nutLeft, height: height),
                          cornerRadius: 3),
                     with: .color(Theme.fretboard))

        for fret in NeckLayout.inlayFrets where fret <= layout.frets {
            let span = layout.fretSpan(fret)
            let size = min(layout.rowHeight * 0.34, (span.upperBound - span.lowerBound) * 0.32)
            let x = (span.lowerBound + span.upperBound) / 2
            // Between the middle strings; two, between the 2nd and 3rd and the 4th and 5th.
            let ys = NeckLayout.isDoubleInlay(fret) ? [layout.rowHeight * 2, layout.rowHeight * 4] : [height / 2]
            for y in ys {
                context.fill(Path(ellipseIn: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)),
                             with: .color(Theme.fretInlay))
            }
        }

        var wires = Path()
        for x in layout.wires {
            wires.addRect(CGRect(x: x - 1, y: 0, width: 2, height: height))
        }
        context.fill(wires, with: .color(Theme.fretWire))
        context.fill(Path(CGRect(x: layout.nutLeft, y: 0, width: NeckLayout.nutWidth, height: height)),
                     with: .color(Theme.guitarNut))

        // From the open strings' column, past the nut, to the end of the neck.
        for string in 1...6 {
            let width = NeckLayout.stringWidth(string)
            let y = layout.stringY(string)
            context.fill(Path(CGRect(x: layout.left + 4, y: y - width / 2, width: woodRight - layout.left - 4, height: width)),
                         with: .color(Theme.guitarString))
        }

        // A caption, not a key label: it helps count frets, as the inlays do.
        for fret in NeckLayout.inlayFrets where fret <= layout.frets {
            let span = layout.fretSpan(fret)
            let number = context.resolve(Text("\(fret)").font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.hint))
            context.draw(number, at: CGPoint(x: (span.lowerBound + span.upperBound) / 2, y: height + NeckLayout.numbersHeight / 2 + 1))
        }
    }
}

/// The guitar's tuning as a labelled pop-up ("Tuning: Standard"): the presets, and a piece's own
/// tuning when its score asks for one that isn't among them. With a piece open it's the piece's
/// (`Game.guitarTuning`). Fixed while a round plays.
struct GuitarTuningMenu: View {
    @Bindable var game: Game
    /// "Tuning: Standard" on its own; just "Standard" beside a label of its own.
    var showsTitle = true

    var body: some View {
        let tuning = game.guitarTuning
        let scoreTuning = game.piecePart?.guitarTuning
        Menu {
            Picker("Tuning", selection: selection) {
                ForEach(Self.choices(scoreTuning: scoreTuning, inUse: tuning)) { choice in
                    Text(choice == scoreTuning ? "\(choice.name) (the score's)" : choice.name).tag(choice)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(showsTitle ? "Tuning: \(tuning.name)" : tuning.name)
        }
        .menuStyle(.button)
        .menuIndicator(.visible)
        .fixedSize()
        .disabled(game.phase == .playing)
        .help("How the strings are tuned, from the 6th (the lowest) to the 1st: \(tuning.stringNames(in: game.settings.naming))")
        .rebuiltOnAppearanceChange()
    }

    /// The game logs the setting; this also logs the click.
    private var selection: Binding<GuitarTuning> {
        $game.guitarTuning.recordingChanges(as: "guitarTuningMenu", to: game.recorder) { $0.key }
    }

    /// The presets, then the score's tuning and the one in use if they aren't among them.
    static func choices(scoreTuning: GuitarTuning?, inUse: GuitarTuning) -> [GuitarTuning] {
        var choices = GuitarTuning.presets
        for tuning in [scoreTuning, inUse].compactMap({ $0 }) where !choices.contains(tuning) {
            choices.append(tuning)
        }
        return choices
    }
}
