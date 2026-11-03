import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Between rounds with a piece loaded: what's being practised and how, in place of the
/// random-notes start panel.
struct PiecePanel: View {
    @Bindable var game: Game

    var body: some View {
        if let piece = game.piece, let part = game.piecePart {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(title(of: piece))
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    Text(details(of: part, showsName: piece.parts.count == 1))
                        .foregroundStyle(.secondary)
                    if part.skippedNoteCount > 0 {
                        Label(skippedText(part.skippedNoteCount), systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .help("Notes in other clefs (alto, tenor…), double sharps and flats and the like are skipped")
                    }
                }

                settings(for: piece, part)

                VStack(spacing: 4) {
                    Button {
                        game.start(via: .button)
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    Text("or press Space")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 20) {
                    openAnother
                    Button("Back to random notes", systemImage: "shuffle") {
                        game.recorder.recordUIAction("backToRandomNotes")
                        game.closePiece()
                    }
                    .help("Close the piece and name random notes from the toolbar settings again")
                }
                .buttonStyle(.borderless)
            }
            .panel()
        }
    }

    /// How many other pieces the Open another… menu lists before its file and library items.
    static let menuPieceCount = 5

    /// Open another…: with other pieces kept, a menu of the latest of them, then a file, then the
    /// whole list; without, the open panel straight away, as before there was a library.
    @ViewBuilder
    private var openAnother: some View {
        let others = game.library.entries.filter { !$0.isOpen(in: game) }
        if others.isEmpty {
            Button("Open another…", systemImage: "folder") { PieceFile.choose(for: game, via: .openAnother) }
                .help("Practise a different MusicXML file (⌘O)")
        } else {
            let recent = Array(others.prefix(Self.menuPieceCount))
            let titles = recent.distinctTitles()
            Menu {
                Section("Your pieces") {
                    ForEach(recent) { entry in
                        Button(titles[entry.id] ?? entry.displayTitle) { PieceFile.open(entry, in: game, from: "pieceMenu") }
                    }
                }
                Divider()
                Button("Choose a File…") { PieceFile.choose(for: game, via: .openAnother) }
                Button("All Pieces…") { PieceListSheet.shared.show(from: "pieceMenu", game: game) }
            } label: {
                Label("Open another…", systemImage: "folder")
            }
            .menuStyle(.button)
            .menuIndicator(.visible)
            .fixedSize()
            .help("Practise one of your other pieces, or a different MusicXML file (⌘O)")
            // SwiftUI doesn't say when a menu opens, so this one is told apart by its items.
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { notification in
                guard let menu = notification.object as? NSMenu,
                      menu.items.contains(where: { $0.title == "Choose a File…" }) else { return }
                game.recorder.recordUIAction("openAnotherMenu")
            }
        }
    }

    /// Two rows: which notes (part, hand), then how they come (order, start bar). Part and hand
    /// only show when there's a choice to make.
    private func settings(for piece: Score, _ part: ScorePart) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            if piece.parts.count > 1 || part.staffCount == 2 {
                GridRow {
                    if piece.parts.count > 1 {
                        settingLabel("Part")
                        Picker("Part", selection: $game.settings.piece.part) {
                            ForEach(piece.parts.indices, id: \.self) { Text(piece.parts[$0].name).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .rebuiltOnAppearanceChange()
                        .help("Which instrument or voice to read")
                    }
                    if part.staffCount == 2 {
                        settingLabel("Hand")
                        Picker("Hand", selection: $game.settings.piece.hand) {
                            ForEach(Game.PieceSettings.Hand.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .help("Right hand reads the upper staff, left hand the lower one")
                    }
                }
            }
            GridRow {
                settingLabel("Order")
                Picker("Order", selection: $game.settings.piece.order) {
                    ForEach(Game.PieceSettings.Order.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Read the notes as they come in the piece, or mixed up")

                settingLabel("Start at bar")
                HStack(spacing: 6) {
                    Stepper(value: startBar(of: part), in: 1...max(1, part.measureCount)) {
                        Text("\(startBar(of: part).wrappedValue)")
                            .monospacedDigit()
                            .frame(minWidth: 26, alignment: .trailing)
                    }
                    Text("of \(part.measureCount)")
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                .help("Skip ahead to practise a section of the piece")
            }
            // The label lines up with the choices, the hint goes under them.
            GridRow(alignment: .firstTextBaseline) {
                settingLabel("Chords")
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Chords", selection: $game.settings.piece.chords) {
                        ForEach(Game.PieceSettings.Chords.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("How notes struck together are asked: one at a time, only the top or bottom one, "
                          + "or all of them as one answer")
                    Text(chordHint(for: part))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .gridCellColumns(3)
            }
            // Only for parts the bar view can draw (any the importer reads).
            if !part.measures.isEmpty {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    HStack(spacing: 8) {
                        // Naming chords together needs the whole bar: shown on, and greyed out.
                        Toggle("Show the whole bar", isOn: wholeBar)
                            .toggleStyle(.checkbox)
                            .disabled(namesTogether)
                        Text(wholeBarHint(for: part))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .help(namesTogether
                          ? "Notes named together are read in their bar, so the whole bar is always shown."
                          : "Read each note in its bar, as on the sheet: signs earlier in the bar carry on. "
                            + "Off, notes come one at a time, with any sign they need printed on them.")
                    .gridCellColumns(3)
                }
            }
        }
        .multilineTextAlignment(.leading)
    }

    private var namesTogether: Bool { game.settings.piece.chords == .together }

    /// On, and fixed, while chords are named together; the setting itself is kept for later.
    private var wholeBar: Binding<Bool> {
        Binding(get: { namesTogether || game.settings.piece.showsWholeBar },
                set: { game.settings.piece.showsWholeBar = $0 })
    }

    /// What the bar view shows: both staves when both hands are read.
    private func wholeBarHint(for part: ScorePart) -> String {
        if namesTogether { return "Always, to name notes together" }
        return part.staffCount == 2 && game.settings.piece.hand == .both
            ? "Both staves, the note to name highlighted"
            : "Every note in the bar, the one to name highlighted"
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    /// Clamped, so a start bar saved for a longer part never reads "60 of 45".
    private func startBar(of part: ScorePart) -> Binding<Int> {
        Binding(
            get: { min(max(game.settings.piece.startBar, 1), max(1, part.measureCount)) },
            set: { game.settings.piece.startBar = $0 }
        )
    }

    /// Files without a title go by their name.
    private func title(of piece: Score) -> String {
        if !piece.title.isEmpty { return piece.title }
        return game.pieceURL?.deletingPathExtension().lastPathComponent ?? "Untitled piece"
    }

    /// "Piano · 312 notes · 45 bars", or "156 of 312 notes" when the hand, start bar or chord setting
    /// leaves some out; the part's name is left to the picker when there is one.
    private func details(of part: ScorePart, showsName: Bool) -> String {
        var parts = showsName && !part.name.isEmpty ? [part.name] : []
        let total = part.notes.count == 1 ? "1 note" : "\(part.notes.count) notes"
        let asked = game.pieceRoundNoteCount
        parts.append(asked == part.notes.count ? total : "\(asked) of \(total)")
        parts.append(part.measureCount == 1 ? "1 bar" : "\(part.measureCount) bars")
        return parts.joined(separator: "  ·  ")
    }

    private func skippedText(_ count: Int) -> String {
        count == 1 ? "1 note can't be shown and was left out" : "\(count) notes can't be shown and were left out"
    }

    /// One line on how the chosen setting asks chords. With top or bottom notes, which note is
    /// kept: the top one for the upper staff, the bottom one for the lower.
    private func chordHint(for part: ScorePart) -> String {
        let hand = part.staffCount == 2 ? game.settings.piece.hand : .right
        switch game.settings.piece.chords {
        case .eachNote:
            return hand == .both ? "Every note on its own, the left hand's first" : "Every note on its own, bottom to top"
        case .topOrBottom:
            switch hand {
            case .right: return "Only the top note of each chord"
            case .left: return "Only the bottom note of each chord"
            case .both: return "Top note in the right hand, bottom note in the left"
            }
        case .together:
            return hand == .both ? "Name every note struck at once, both hands, as one answer"
                : "Name every note of a chord as one answer, in any order"
        }
    }
}

/// Choosing and opening MusicXML files, for File ▸ Open Piece…, the panels' buttons and drag and drop.
@MainActor
enum PieceFile {
    static let extensions: Set<String> = ["musicxml", "mxl", "xml"]

    /// Asks for a file in a sheet on the window, then opens it. `source` is what asked, for the usage log.
    static func choose(for game: Game, via source: PieceOpenSource) {
        // The menu item greys out during a round, but SwiftUI only notices when the menu opens, so ⌘O still gets here.
        guard game.phase != .playing else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose a MusicXML file (.musicxml, .mxl or .xml) to practise."
        panel.prompt = "Practise"
        guard let window = NSApp.mainWindow else {
            openChoice(of: panel, response: panel.runModal(), in: game, via: source)
            return
        }
        Task {
            openChoice(of: panel, response: await panel.beginSheetModal(for: window), in: game, via: source)
        }
    }

    /// Opens the file picked in `panel`. Cancelling opens nothing for the game to log, so it's logged here.
    private static func openChoice(of panel: NSOpenPanel, response: NSApplication.ModalResponse, in game: Game,
                                   via source: PieceOpenSource) {
        guard response == .OK, let url = panel.url else {
            game.recorder.recordUIAction("openPanelCancelled", detail: source.rawValue)
            return
        }
        open(url, in: game, via: source)
    }

    /// Opens a file; errors land in `game.pieceError`. A summary left from the last round would
    /// hide the new piece's setup, so it goes once the piece is in.
    static func open(_ url: URL, in game: Game, via source: PieceOpenSource) {
        guard extensions.contains(url.pathExtension.lowercased()) else {
            // The game never gets the file, so it's logged here. Mostly these are drops, but the open
            // panel lets other XML through too (.svg, .xhtml…).
            game.recorder.recordUIAction(source == .drop ? "dropRefused" : "fileRefused", detail: url.lastPathComponent)
            game.pieceError = "“\(url.lastPathComponent)” isn't a MusicXML file (.musicxml, .mxl or .xml)."
            return
        }
        game.openPiece(at: url, via: source)
        if game.pieceError == nil, game.phase == .finished { game.dismissSummary() }
    }

    /// Opens a piece kept in the library, closing the "Your pieces" sheet if it's up; errors land in
    /// `game.pieceError`. `list` says which list or menu it was picked from, for the usage log.
    static func open(_ entry: PieceLibrary.Entry, in game: Game, from list: String) {
        // Like Open Piece…, a new piece waits for the round to end.
        guard game.phase != .playing else {
            NSSound.beep()
            return
        }
        game.recorder.recordUIAction("openLibraryPiece", detail: list)
        PieceListSheet.shared.isShown = false
        game.open(entry, via: .library)
        if game.pieceError == nil, game.phase == .finished { game.dismissSummary() }
    }
}
