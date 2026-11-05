import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var game: Game
    @State private var keyMonitor: Any?
    /// The window this view is in: keys typed in another one (Progress) aren't answers.
    @State private var hostWindow = WeakWindow()
    /// A file is being dragged over the window between rounds.
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 18) {
            StatsBar(game: game)
            StaffCard(game: game)
            MnemonicBar(clef: game.displayedClef, naming: game.settings.naming)
                .opacity(game.settings.showHints ? 1 : 0)
            switch game.settings.answerInput {
            case .buttons: AnswerPad(game: game)
            case .piano: PianoPad(game: game)
            case .keyboard: TypingPad(game: game)
            }
            HStack {
                Text(shortcutHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if game.settings.answerInput == .piano {
                    Toggle("Show key names", isOn: showKeyNames)
                        .toggleStyle(.checkbox)
                        .help("Write note names on the piano keys (K)")
                        .padding(.trailing, 12)
                }
                // Next to the answer area, where you'd look for it.
                Picker("Answer with", selection: answerInput) {
                    ForEach(Game.AnswerInput.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
                .fixedSize()
                .disabled(game.phase == .playing)
                .help("Note buttons and typing accept any octave; on the piano you click the exact key")
            }
        }
        .padding(24)
        .frame(minWidth: 820, minHeight: 640)
        .background(Theme.background)
        .background(WindowReader { [hostWindow] in hostWindow.window = $0 })
        .overlay {
            if isDropTargeted { DropHighlight() }
        }
        .navigationTitle("Clefwise")
        .toolbar { settingsToolbar }
        // Like the toolbar settings, a new piece waits for the round to end.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            guard game.phase != .playing else {
                // The game never gets the file, so it's logged here.
                game.recorder.recordUIAction("dropRefused", detail: url.lastPathComponent)
                return false
            }
            PieceFile.open(url, in: game, via: .drop)
            return true
        } isTargeted: {
            isDropTargeted = $0 && game.phase != .playing
        }
        // Every piece kept, from the start panel, the piece panel's menu or the File menu.
        .sheet(isPresented: Bindable(PieceListSheet.shared).isShown) {
            PieceListView(game: game)
                .tint(Theme.accent)
        }
        .alert("Couldn't open the piece", isPresented: isShowingPieceError, presenting: game.pieceError) { _ in
            Button("OK") {}
        } message: {
            Text($0)
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        }
    }

    private var isShowingPieceError: Binding<Bool> {
        Binding(get: { game.pieceError != nil }, set: { if !$0 { game.pieceError = nil } })
    }

    // The game logs the settings; these also log the clicks (K shows key names too).
    private var showKeyNames: Binding<Bool> {
        $game.settings.showKeyNames.recordingChanges(as: "keyNamesCheckbox", to: game.recorder)
    }

    private var answerInput: Binding<Game.AnswerInput> {
        $game.settings.answerInput.recordingChanges(as: "answerInputSwitch", to: game.recorder) { $0.rawValue }
    }

    private var shortcutHint: String {
        var parts: [String]
        switch (game.settings.answerInput, game.settings.naming) {
        case (.buttons, .letters): parts = ["Type the note's letter or 1–7"]
        case (.buttons, _): parts = ["Press 1–7 to answer"]
        case (.piano, _): parts = ["Click the exact key"]
        case (.keyboard, _): parts = ["Type the note's name, ⌫ to fix"]
        }
        // Naming notes together, entries can be taken back.
        if game.namesTogether {
            switch game.settings.answerInput {
            case .buttons: parts.append("⌫ take one back")
            case .piano: parts = ["Click the exact keys"]
            case .keyboard: parts = ["Type the names one after another, ⌫ to fix"]
            }
        }
        // Words rather than ♯/♭, which are too small to read at caption size.
        if game.settings.answerInput == .buttons, game.accidentalsPossible {
            parts += game.settings.naming == .sargam ? ["# tivra", "− komal"] : ["# sharp", "− flat"]
        }
        parts += [game.phase == .playing ? "Space pause" : "Space start", "Esc stop"]
        switch game.settings.answerInput {
        case .buttons: parts += ["H hints", "M mute"]
        case .piano: parts += ["H hints", "K key names", "M mute"]
        case .keyboard: break // letters are typed during a round, so H and M aren't shortcuts then
        }
        return parts.joined(separator: "  ·  ")
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Group {
                // A piece brings its own clefs, notes and keys. Disabled rather than hidden, so the
                // toolbar doesn't jump when a piece is opened or closed.
                Group {
                    Picker("Clef", selection: $game.settings.clefChoice) {
                        ForEach(ClefChoice.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .help(pieceHelp("Which clef to read", piece: "The piece sets the clef"))

                    keyMenu

                    Toggle("Accidentals", isOn: $game.settings.addsAccidentals)
                        .toggleStyle(.checkbox)
                        .help(pieceHelp("Now and then put a ♯, ♭ or ♮ in front of a note, on top of the key signature",
                                        piece: "The piece's own ♯, ♭ and ♮ are shown"))
                }
                .disabled(game.isPractisingPiece)

                // A pop-up rather than segments, so the key controls fit without the toolbar overflowing.
                Picker("Mode", selection: $game.settings.mode) {
                    ForEach(Game.Mode.allCases) { Text($0.label).tag($0) }
                }
                .help("Race the clock, or practice at your own pace")
            }
            .disabled(game.phase == .playing)

            Picker("Note names", selection: $game.settings.naming) {
                ForEach(NamingSystem.allCases) { Text($0.label).tag($0) }
            }
            .help("Name notes with letters, solfège (Do = C) or sargam (Sa = C)")
        }
    }

    /// A menu with a short title rather than a picker: a toolbar picker is as wide as its longest
    /// item ("C major · no ♯/♭"), and the toolbar has no room to spare.
    private var keyMenu: some View {
        // With a piece open the menu is disabled and names the piece's key, not the setting.
        Menu(game.isPractisingPiece ? KeyChoice.fixed(game.currentKeySignature).shortLabel : game.settings.key.shortLabel) {
            Picker("Key", selection: $game.settings.key) {
                ForEach(KeyChoice.allCases) { choice in
                    if choice.startsMenuGroup { Divider() }
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .help(pieceHelp("Key signature: the sharps or flats that hold for every note", piece: "The piece sets the key signature"))
        // SwiftUI doesn't say when a menu opens, so this one is told apart by its items.
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { notification in
            guard let menu = notification.object as? NSMenu,
                  menu.items.contains(where: { $0.title == KeyChoice.random.label }) else { return }
            game.recorder.recordUIAction("keyMenu")
        }
    }

    /// Says why a setting is greyed out while a piece is open, and how to get it back.
    private func pieceHelp(_ help: String, piece: String) -> String {
        game.isPractisingPiece ? "\(piece). Go back to random notes to change this." : help
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [game, hostWindow] event in
            // Leave ⌘/⌃/⌥ shortcuts (⌘Q, ⌘W, …) to the system.
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            // Space in the Progress window isn't a round starting.
            guard event.window === hostWindow.window else { return event }
            // The open panel and alerts are windows of their own: typing and Return belong to them.
            guard !(event.window is NSPanel), event.window?.attachedSheet == nil else { return event }
            let characters = event.charactersIgnoringModifiers ?? ""
            let keyCode = event.keyCode
            let handled = MainActor.assumeIsolated {
                game.handleKey(characters: characters, keyCode: keyCode)
            }
            return handled ? nil : event
        }
    }
}

/// A window held without keeping it alive, shared with the key monitor's closure.
private final class WeakWindow {
    weak var window: NSWindow?
}

fileprivate extension KeyChoice {
    /// "G major", "Random key".
    var shortLabel: String {
        switch self {
        case .fixed(let key): "\(key.majorKey) major"
        case .random: "Random key"
        }
    }

    /// The first sharp key, the first flat key and Random each start a new block in the key menu.
    var startsMenuGroup: Bool {
        switch self {
        case .fixed(let key): abs(key.fifths) == 1
        case .random: true
        }
    }
}

// MARK: - Stats

private struct StatsBar: View {
    @Bindable var game: Game
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if game.notesLeft == nil {
            row(showsStreak: true)
        } else {
            // A round of a set number of notes has a fifth tile, which must stay: it's how far along
            // the round is. A narrow window gives up the streak for it rather than overflow.
            ViewThatFits(in: .horizontal) {
                row(showsStreak: true)
                row(showsStreak: false)
            }
        }
    }

    private func row(showsStreak: Bool) -> some View {
        HStack(spacing: 12) {
            StatTile(title: game.roundTimeLimit == nil ? "Time" : "Time left",
                     value: timeText,
                     tint: isRunningOut ? Theme.wrong : Theme.ink)
            StatTile(title: "Score", value: "\(game.score)")
            if showsStreak {
                StatTile(title: "Streak", value: "\(game.streak)")
            }
            StatTile(title: "Accuracy", value: game.accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
            if let progress = game.pieceProgress {
                // A fifth tile only fits a wide window; a narrow one does without rather than overflow.
                ViewThatFits(in: .horizontal) {
                    PieceProgressTile(progress: progress, order: game.settings.piece.order)
                    Color.clear.frame(width: 0, height: 0)
                }
                .layoutPriority(1)
            }
            if let notesLeft = game.notesLeft, let total = game.roundNoteLimit {
                ProgressTile(title: "Notes left", value: notesLeft.formatted(),
                             fraction: CGFloat(total - notesLeft) / CGFloat(total),
                             help: "\((total - notesLeft).formatted()) of \(total.formatted()) notes done")
            }
            Spacer()
            // Between rounds only: mid-round its window would take the keys the answers come from,
            // and Stop needs the room. Spelled out, unlike the toggles: an icon alone was easy to miss.
            if game.phase != .playing {
                Button {
                    ProgressWindow.open(from: "statsBar", game: game, with: openWindow)
                } label: {
                    Label("Progress", systemImage: "chart.xyaxis.line")
                }
                .labelStyle(.titleAndIcon)
                .help("Your progress over time, in a window of its own (⇧⌘P)")
            }

            // Things you may want mid-round live here; round settings are in the toolbar.
            Group {
                // The game logs the settings; these also log the clicks (H and M toggle them too).
                Toggle(isOn: $game.settings.showHints.recordingChanges(as: "hintsButton", to: game.recorder)) {
                    Label("Hints", systemImage: "lightbulb")
                }
                .help("Show note names and mnemonics (H)")

                Toggle(isOn: $game.settings.isMuted.recordingChanges(as: "muteButton", to: game.recorder)) {
                    Label("Mute", systemImage: game.settings.isMuted ? "speaker.slash" : "speaker.wave.2")
                }
                .help("Mute sounds (M)")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)

            if game.phase == .playing {
                // Spelled out, and it says what it will do: Pause, then Resume.
                Button(game.isPaused ? "Resume" : "Pause", systemImage: game.isPaused ? "play.fill" : "pause.fill") {
                    game.recorder.recordUIAction(game.isPaused ? "resumeButton" : "pauseButton")
                    game.togglePause(via: .button)
                }
                .help(game.isPaused ? "Carry on with the round (Space)" : "Stop the clock and hide the note for a moment (Space)")
                .fixedSize()

                Button("Stop", systemImage: "stop.fill") {
                    game.recorder.recordUIAction("stopButton")
                    game.stop()
                }
                .fixedSize()
            }
        }
        .controlSize(.large)
    }

    private var timeText: String {
        let limit = game.roundTimeLimit
        let seconds = switch game.phase {
        case .idle: limit.map { Int($0) } ?? 0
        case .playing, .finished: limit == nil ? Int(game.elapsed) : Int(game.timeRemaining.rounded(.up))
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var isRunningOut: Bool {
        game.phase == .playing && game.roundTimeLimit != nil && game.timeRemaining <= 10
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = Theme.ink
    var width: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        // A narrow window takes a little from each tile rather than squeeze the buttons' labels.
        .frame(minWidth: min(width, 72), maxWidth: width, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Where a piece round is: the bar when reading in order (a shuffled round jumps about, so it
/// counts notes instead), with a thin bar along the bottom for notes done.
private struct PieceProgressTile: View {
    let progress: Game.PieceProgress
    let order: Game.PieceSettings.Order

    var body: some View {
        ProgressTile(title: order == .inOrder ? "Bar" : "Notes",
                     value: order == .inOrder ? "\(progress.bar) / \(progress.bars)" : "\(progress.done) / \(progress.total)",
                     fraction: fraction,
                     help: "\(progress.done) of \(progress.total) notes done · bar \(progress.bar) of \(progress.bars)")
    }

    private var fraction: CGFloat {
        progress.total > 0 ? CGFloat(min(progress.done, progress.total)) / CGFloat(progress.total) : 0
    }
}

/// A stat tile with a thin bar along its bottom for how far along the round is.
private struct ProgressTile: View {
    let title: String
    let value: String
    let fraction: CGFloat
    let help: String

    var body: some View {
        StatTile(title: title, value: value, width: 110)
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.accent.opacity(0.15))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: proxy.size.width * fraction)
                        }
                }
                .frame(height: 3)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }
            .help(help)
    }
}

// MARK: - Staff

private struct StaffCard: View {
    let game: Game

    var body: some View {
        let bar = game.barDisplay
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.paper)
                .shadow(color: .black.opacity(0.08), radius: 18, y: 6)

            Group {
                if let bar {
                    VStack(spacing: BarStripView.spacing) {
                        BarStaffView(
                            // Paused, the bar's notes are left out until the round carries on.
                            bar: game.isPaused ? bar.withoutNotes : bar,
                            // Notes asked together are marked one by one once judged (`bar.marks`, which
                            // carry their names); the view then leaves the label out.
                            currentColor: game.isShowingMiss ? Theme.wrong : Theme.accent,
                            currentLabel: game.isShowingMiss && !game.isPaused ? game.question.map(answerLabel) : nil,
                            showsHints: game.settings.showHints,
                            naming: game.settings.naming
                        )
                        // Room is kept for it between rounds too, so the staff doesn't jump when one starts.
                        BarStripView(strip: game.barStrip)
                    }
                } else {
                    StaffView(
                        clef: game.displayedClef,
                        keySignature: game.currentKeySignature,
                        // Paused, the note is left out until the round carries on.
                        note: game.isPaused ? nil : game.question,
                        positionsToFit: game.staffPositionsToFit,
                        noteColor: game.isShowingMiss ? Theme.wrong : Theme.ink,
                        noteLabel: game.isShowingMiss && !game.isPaused ? game.question.map(answerLabel) : nil,
                        // A piece's notes can go past the range setting, so hints cover as far as they go.
                        hintPositions: game.settings.showHints ? game.staffPositionsToFit ?? game.settings.range.span : nil,
                        naming: game.settings.naming
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .opacity(game.isTakingAnswers ? 1 : 0.35)

            switch game.phase {
            case .idle:
                if game.isPractisingPiece {
                    PiecePanel(game: game)
                } else {
                    StartPanel(game: game)
                }
            case .finished:
                if let summary = game.summary {
                    SummaryPanel(summary: summary, game: game)
                }
            case .playing:
                if game.isPaused {
                    PausedPanel(game: game)
                }
            }
        }
        .frame(minHeight: 340)
    }

    /// On the piano it says so when the name was right but the octave wasn't.
    private func answerLabel(_ question: Question) -> String {
        game.missLabel(for: question.pitch, answeredWith: game.flash?.pitch)
    }
}

/// Where a piece round in the bar view is: one segment per bar from the round's first bar to its
/// last, done bars filled, the current one raised, the rest light. Shuffled rounds jump about, so
/// they mark only the current bar. With too many bars for gaps between them (a long piece), the
/// segments run together into one track, and the current bar keeps a marker wide enough to see.
private struct BarStripView: View {
    /// Between the staff and the strip.
    static let spacing: CGFloat = 8
    /// Nothing is drawn without one, but the room stays.
    let strip: Game.BarStrip?

    private static let height: CGFloat = 12
    private static let trackHeight: CGFloat = 6
    private static let gap: CGFloat = 3
    /// Short pieces don't stretch across the card: the strip reads as bars, not a progress bar.
    private static let widestSegment: CGFloat = 36
    /// Narrower than this, segments run together.
    private static let narrowestSegment: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            guard let strip else { return }
            draw(strip, in: &context, size: size)
        }
        .frame(height: Self.height)
        .padding(.horizontal, 24)
        .help(strip.map(description) ?? "")
        .accessibilityElement()
        .accessibilityLabel(strip.map(description) ?? "")
        .accessibilityHidden(strip == nil)
    }

    /// "Bar 9 of 32", and the round's bars when it doesn't go through the whole piece.
    private func description(_ strip: Game.BarStrip) -> String {
        var text = "Bar \(strip.current) of \(strip.pieceBars)"
        if strip.bars != 1...strip.pieceBars {
            text += strip.bars.count == 1 ? " · this round: bar \(strip.bars.lowerBound)"
                : " · this round: bars \(strip.bars.lowerBound)–\(strip.bars.upperBound)"
        }
        return text
    }

    private func draw(_ strip: Game.BarStrip, in context: inout GraphicsContext, size: CGSize) {
        let count = CGFloat(strip.bars.count)
        let current = CGFloat(strip.current - strip.bars.lowerBound)
        let trackY = (size.height - Self.trackHeight) / 2
        let done = Theme.accent, upcoming = Theme.accent.opacity(0.16)
        let fitted = (size.width - Self.gap * (count - 1)) / count

        func segment(_ x: CGFloat, _ width: CGFloat, raised: Bool = false) -> Path {
            let rect = raised ? CGRect(x: x, y: 0, width: width, height: size.height)
                : CGRect(x: x, y: trackY, width: width, height: Self.trackHeight)
            return Path(roundedRect: rect, cornerRadius: min(2, width / 2))
        }

        if fitted >= Self.narrowestSegment {
            let width = min(fitted, Self.widestSegment)
            let left = (size.width - (width * count + Self.gap * (count - 1))) / 2
            for offset in 0..<strip.bars.count {
                let x = left + CGFloat(offset) * (width + Self.gap)
                let isCurrent = CGFloat(offset) == current
                let isDone = strip.showsDone && CGFloat(offset) < current
                context.fill(segment(x, width, raised: isCurrent), with: .color(isCurrent || isDone ? done : upcoming))
            }
        } else {
            // One track: done up to the current bar, light after it, and a marker for the bar itself.
            let width = size.width / count
            context.fill(segment(0, size.width), with: .color(upcoming))
            if strip.showsDone, current > 0 {
                context.fill(segment(0, width * current), with: .color(done))
            }
            let marker = max(width, 4)
            let x = min(max(width * (current + 0.5) - marker / 2, 0), size.width - marker)
            // A paper-coloured edge sets the marker off from the done bars beside it.
            context.fill(segment(x - 1.5, marker + 3, raised: true), with: .color(Theme.paper))
            context.fill(segment(x, marker, raised: true), with: .color(done))
        }
    }
}

private extension BarDisplay {
    /// The bar's staves with nothing on them, for a paused round: no studying the notes while the
    /// clock is stopped.
    var withoutNotes: BarDisplay {
        BarDisplay(staves: staves,
                   measure: ScoreMeasure(number: measure.number, start: measure.start, length: measure.length,
                                         staves: measure.staves, symbols: []),
                   current: nil, answered: [], isLastBar: isLastBar)
    }
}

private struct PausedPanel: View {
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            Text("Paused")
                .font(.title2.weight(.semibold))
            Text(game.pausedVia == .appSwitch
                 ? "Paused while you were in another app. The \(notes) hidden until you carry on."
                 : "The clock is stopped and the \(notes) hidden until you carry on.")
                .foregroundStyle(.secondary)
            Button {
                game.recorder.recordUIAction("resumePanelButton")
                game.resume(via: .button)
            } label: {
                Label("Resume", systemImage: "play.fill")
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .padding(.top, 6)
            Text("or press Space")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panel()
    }

    private var notes: String { game.group == nil ? "note is" : "notes are" }
}

private struct StartPanel: View {
    let game: Game

    var body: some View {
        // As many of the latest pieces as the card has room for, so the panel never outgrows it:
        // four in a roomy window, fewer down to none (still with All pieces…) in a short one, and
        // last of all a tighter panel, for a short window with the practice length rows showing.
        ViewThatFits(in: .vertical) {
            ForEach(game.library.isEmpty ? [0] : Array((0...4).reversed()), id: \.self) { count in
                panel(recentPieces: count)
                    .padding(.vertical, 8)
            }
            panel(recentPieces: 0, isTight: true)
                .padding(.vertical, 8)
        }
    }

    /// Without kept pieces, the panel as it was before there was a library. `isTight` leaves out
    /// what can go: the footer says Space starts too.
    private func panel(recentPieces: Int, isTight: Bool = false) -> some View {
        VStack(spacing: 10) {
            Text(heading)
                .font(.title2.weight(.semibold))
            Text(details)
                .foregroundStyle(.secondary)
            NoteRangeControls(game: game)
                .padding(.top, 4)
            if game.settings.mode == .practice {
                PracticeLimitControls(game: game)
            }
            Button {
                game.start(via: .button)
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .padding(.top, 6)
            if !isTight {
                Text("or press Space")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                    .frame(width: 240)
                    .padding(.vertical, 4)
            }
            // Spelled out here as well as in the File menu, so it's found without looking for it.
            HStack(spacing: 10) {
                Button("Practise a piece…", systemImage: "music.note.list") { PieceFile.choose(for: game, via: .button) }
                    .help("Open a MusicXML file and read its notes (⌘O)")
                Text("MusicXML file, or drop one here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !game.library.isEmpty {
                RecentPiecesSection(game: game, count: recentPieces)
                    .padding(.top, 4)
            }
        }
        .panel()
    }

    private var heading: String {
        guard game.settings.mode == .practice else { return "How many notes can you name in 60 seconds?" }
        switch game.settings.practiceLimit {
        case .endless: return "Practice at your own pace"
        case .time: return "How many notes can you name in \(game.settings.practiceMinutes) minutes?"
        case .notes: return "How fast can you name \(game.settings.practiceNotes.formatted()) notes?"
        }
    }

    private var details: String {
        // The notes' range has its own checkboxes just below.
        var parts = [game.settings.clefChoice.summary]
        // Plain C major goes unsaid, as before keys existed.
        if game.accidentalsPossible {
            parts.append(game.settings.key.shortLabel + (game.settings.addsAccidentals ? " + accidentals" : ""))
        }
        if game.settings.mode == .sprint, let best = game.bestScore {
            parts.append("Best: \(best)")
        }
        return parts.joined(separator: "  ·  ")
    }
}

/// Which notes random rounds ask: below, on and above the staff in any mix, and how far below
/// and above reaches.
private struct NoteRangeControls: View {
    @Bindable var game: Game

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Text("Notes")
                    .foregroundStyle(.secondary)
                zone("Above the staff", \.above, help: "Notes above the staff, on and between ledger lines")
                zone("On the staff", \.onStaff, help: "Notes on the staff's lines and spaces")
                zone("Below the staff", \.below, help: "Notes below the staff, on and between ledger lines")
            }
            HStack(spacing: 8) {
                Text("Ledger lines")
                    .foregroundStyle(.secondary)
                Picker("Ledger lines", selection: $game.settings.range.ledgerLines) {
                    ForEach(1...NoteRange.maxLedgerLines, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .disabled(!range.above && !range.below)
            .help(range.above || range.below
                  ? "How many ledger lines notes above and below the staff go out to"
                  : "Tick Above or Below the staff to choose how far notes go")
        }
    }

    private var range: NoteRange { game.settings.range }

    /// A checkbox for one part of the range. The last one ticked can't be unticked.
    private func zone(_ title: String, _ zone: WritableKeyPath<NoteRange, Bool>, help: String) -> some View {
        let isLastTicked = range[keyPath: zone] && [range.below, range.onStaff, range.above].filter { $0 }.count == 1
        return Toggle(title, isOn: $game.settings.range[dynamicMember: zone])
            .toggleStyle(.checkbox)
            .disabled(isLastTicked)
            .help(isLastTicked ? "\(help). Tick another part before unticking this one." : help)
    }
}

/// How a practice round ends: when stopped, after a set time, or after a set number of notes.
private struct PracticeLimitControls: View {
    @Bindable var game: Game

    var body: some View {
        VStack(spacing: 8) {
            row("Length", help: "Practice until you stop, for a set time, or for a set number of notes") {
                Picker("Length", selection: $game.settings.practiceLimit) {
                    ForEach(Game.PracticeLimit.allCases) { Text($0.label).tag($0) }
                }
            }
            switch game.settings.practiceLimit {
            case .endless:
                EmptyView()
            case .time:
                row("Minutes", help: "How long the round runs; pausing stops the clock") {
                    Picker("Minutes", selection: $game.settings.practiceMinutes) {
                        ForEach(Game.practiceMinuteChoices, id: \.self) { Text("\($0)").tag($0) }
                    }
                }
            case .notes:
                row("Notes to name", help: "How many notes the round asks; a wrong answer counts as one") {
                    Picker("Notes to name", selection: $game.settings.practiceNotes) {
                        ForEach(Game.practiceNoteChoices, id: \.self) { Text($0.formatted()).tag($0) }
                    }
                }
            }
        }
    }

    private func row(_ title: String, help: String, @ViewBuilder picker: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            picker()
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
        }
        .help(help)
    }
}

private struct SummaryPanel: View {
    let summary: RoundSummary
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.title2.weight(.bold))
                if let pieceTitle = summary.pieceTitle {
                    Text(pieceTitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(summary.score)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text(summary.finishedNotes ? "of \(summary.attempts.formatted()) right"
                     : summary.score == 1 ? "note named" : "notes named")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            // Pieces keep no best score: one piece's score says nothing about another's.
            if summary.pieceTitle == nil {
                if summary.isNewBest {
                    Label("New personal best!", systemImage: "star.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                } else if let best = summary.bestScore {
                    Text("Personal best: \(best)")
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 32) {
                if let seconds = summary.noteRoundSeconds {
                    Metric(title: "Time", value: String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60))
                }
                Metric(title: "Accuracy", value: summary.accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                Metric(title: "Avg. per note", value: summary.averageSeconds.map { String(format: "%.1f s", $0) } ?? "–")
                Metric(title: "Best streak", value: "\(summary.bestStreak)")
            }
            .padding(.vertical, 4)
            if summary.attempts > 0 {
                Text(summary.notesToReview.isEmpty
                     ? "No mistakes. Clean round!"
                     : "Notes to review: \(summary.notesToReview.map(reviewLabel).joined(separator: ", "))")
                    .font(.callout)
                    .foregroundStyle(summary.notesToReview.isEmpty ? Theme.correct : Theme.wrong)
            }
            HStack(spacing: 12) {
                Button("Done") {
                    game.recorder.recordUIAction("summaryDone")
                    game.dismissSummary()
                }
                Button("Play again") { game.start(via: .playAgain) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .panel()
    }

    private var title: String {
        if summary.finishedPiece { return "Piece complete" }
        if summary.finishedNotes { return "\(summary.attempts.formatted()) notes done" }
        if summary.timeRanOut { return "Time's up!" }
        return summary.mode == .practice && !summary.hadLimit ? "Practice complete" : "Round ended"
    }

    /// "F♯4", or "Fa♯ (F♯4)" with other naming systems; adds the clef when clefs were mixed.
    private func reviewLabel(_ note: StaffNote) -> String {
        let naming = game.settings.naming
        var details: [String] = []
        if naming != .letters { details.append(note.pitch.name) }
        if summary.mixedClefs { details.append(note.clef.name.lowercased()) }
        let name = naming == .letters ? note.pitch.name : naming.name(of: note.pitch)
        return details.isEmpty ? name : "\(name) (\(details.joined(separator: ", ")))"
    }
}

private struct Metric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// The white card the start, piece and summary panels sit on, over the staff.
    func panel() -> some View {
        multilineTextAlignment(.center)
            .padding(.horizontal, 36)
            .padding(.vertical, 22)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
    }
}

/// Shown while a file is dragged over the window.
private struct DropHighlight: View {
    var body: some View {
        ZStack {
            // Veils what's underneath so the message reads on its own.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.veil)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.accent.opacity(0.06))
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
            Label("Drop a MusicXML file to practise it", systemImage: "music.note.list")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(10)
        .allowsHitTesting(false)
    }
}

private struct MnemonicBar: View {
    let clef: Clef
    let naming: NamingSystem

    var body: some View {
        HStack(spacing: 32) {
            if naming == .letters {
                Text("\(clef.name) lines  \(Text(naming.names(of: clef.lineLetters)).bold())  —  \(clef.lineMnemonic)")
                Text("Spaces  \(Text(naming.names(of: clef.spaceLetters)).bold())  —  \(clef.spaceMnemonic)")
            } else {
                Text("\(clef.name) lines  \(Text(naming.names(of: clef.lineLetters)).bold())")
                Text("Spaces  \(Text(naming.names(of: clef.spaceLetters)).bold())")
            }
        }
        .font(.callout)
        .foregroundStyle(Theme.hint)
    }
}

// MARK: - Answer keys

private struct AnswerPad: View {
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            // Only when naming notes together, so other rounds look as they always did.
            if game.namesTogether {
                GroupEntryStrip(game: game)
            }
            HStack(spacing: 12) {
                // Only when a note can be sharp or flat, so C major without accidentals looks as it always did.
                if game.accidentalsPossible {
                    modifierButton(.flat)
                        .padding(.trailing, 8)
                }
                ForEach(NoteLetter.allCases) { letter in
                    Button {
                        game.answer(letter)
                    } label: {
                        keyLabel(for: letter)
                    }
                    .buttonStyle(AnswerKeyStyle(highlight: highlight(for: letter)))
                    .disabled(!canAnswer(letter))
                }
                if game.accidentalsPossible {
                    modifierButton(.sharp)
                        .padding(.leading, 8)
                }
            }
            .disabled(!game.isTakingAnswers)
        }
    }

    /// ♭ or ♯: arms the sign for the next letter pressed.
    private func modifierButton(_ accidental: Accidental) -> some View {
        Button {
            game.toggleArmedAccidental(accidental)
        } label: {
            VStack(spacing: 0) {
                Text(accidental.symbol)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                Text(Self.word(for: accidental, in: game.settings.naming))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                // The shortcut; a minus sign reads better than a hyphen this small.
                Text(accidental == .sharp ? "#" : "−")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .opacity(0.45)
                    .padding(7)
            }
        }
        .buttonStyle(AnswerKeyStyle(highlight: highlight(for: accidental)))
        .help(accidental == .sharp ? "Sharp the next note you press (# or =)" : "Flat the next note you press (-)")
    }

    private static func word(for accidental: Accidental, in naming: NamingSystem) -> String {
        switch (accidental, naming) {
        case (.flat, .sargam): "komal"
        case (.sharp, .sargam): "tivra"
        case (.flat, _): "flat"
        default: "sharp"
        }
    }

    /// The letter's name with the sign it would answer: the armed one, or while it's highlighted,
    /// the one it was answered or revealed with ("F♯"). Sargam puts komal/tivra on a line of its own.
    private func keyLabel(for letter: NoteLetter) -> some View {
        let naming = game.settings.naming
        let name = naming.name(of: letter)
        let accidental = shownAccidental(for: letter)
        let size: CGFloat = name.count > 1 ? 24 : 30
        let isAlteredSwara = naming == .sargam && accidental != .natural && naming.answerName(of: letter, accidental) != nil
        return VStack(spacing: 0) {
            if isAlteredSwara {
                Text(Self.word(for: accidental, in: naming))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            SpelledName(name: name, accidental: naming == .sargam ? .natural : accidental, size: size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            // With letter names the letter is the shortcut; otherwise show the number key.
            if naming != .letters {
                Text("\(letter.rawValue + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .opacity(0.45)
                    .padding(7)
            }
        }
    }

    private func shownAccidental(for letter: NoteLetter) -> Accidental {
        if let flash = game.flash, flash.letter == letter { return flash.accidental }
        if let revealed = revealed.first(where: { $0.letter == letter }) { return revealed.accidental }
        return game.armedAccidental
    }

    /// Sargam has komal only for Re, Ga, Dha and Ni and tivra only for Ma; the other swaras are
    /// greyed out while one is armed, which also shows where komal and tivra apply.
    private func canAnswer(_ letter: NoteLetter) -> Bool {
        game.settings.naming.answerName(of: letter, game.armedAccidental) != nil
    }

    /// After a miss: the buttons and signs that name the note, or the notes asked together that
    /// were missed.
    private var revealed: [(letter: NoteLetter, accidental: Accidental)] {
        guard game.isShowingMiss else { return [] }
        if let group = game.group, let result = group.result {
            return zip(group.questions, result.isRight).filter { !$0.1 }.map { Self.buttonName(for: $0.0.pitch, in: game.settings.naming) }
        }
        return game.question.map { [Self.buttonName(for: $0.pitch, in: game.settings.naming)] } ?? []
    }

    /// The button and sign that name `pitch`. Sargam goes by swara, so a C♯ is komal Re.
    static func buttonName(for pitch: Pitch, in naming: NamingSystem) -> (letter: NoteLetter, accidental: Accidental) {
        guard naming == .sargam else { return (pitch.letter, pitch.accidental) }
        let pitchClass = pitch.pitchClass
        if let natural = NoteLetter.allCases.first(where: { $0.semitone == pitchClass }) { return (natural, .natural) }
        if pitchClass == Pitch(.f, 4, .sharp).pitchClass { return (.f, .sharp) }
        return (NoteLetter.allCases.first { $0.semitone == pitchClass + 1 }!, .flat)
    }

    private func highlight(for letter: NoteLetter) -> KeyHighlight {
        if let flash = game.flash, flash.letter == letter {
            return flash.isCorrect ? .correct : .wrong
        }
        if revealed.contains(where: { $0.letter == letter }) {
            return .reveal
        }
        return .none
    }

    private func highlight(for accidental: Accidental) -> KeyHighlight {
        if game.armedAccidental == accidental { return .armed }
        // After a miss, shows the sign the answer needed (the letter alone may have been right).
        if revealed.contains(where: { $0.accidental == accidental }) { return .reveal }
        return .none
    }
}

/// Above the note buttons while notes are named together: the names entered so far as chips
/// (click one, or press ⌫ for the last, to take it back) and empty slots for the rest, coloured
/// right or wrong once judged. It keeps its room through the round, a lone note included, so the
/// buttons don't jump.
private struct GroupEntryStrip: View {
    let game: Game

    var body: some View {
        HStack(spacing: 8) {
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.trailing, 4)
            if let shown {
                ForEach(Array(shown.entries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        game.removeGroupEntry(at: index)
                    } label: {
                        chipLabel(for: entry, removable: shown.result == nil)
                    }
                    .buttonStyle(ChipStyle(highlight: highlight(of: index, in: shown)))
                    .disabled(shown.result != nil || !game.isTakingAnswers || game.isShowingMiss)
                    .help("Click to take it back (⌫ takes back the last one)")
                }
                if shown.result == nil {
                    ForEach(0..<max(0, (game.groupEntriesNeeded ?? shown.questions.count) - shown.entries.count), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.keyBorder, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .frame(width: 62, height: 40)
                    }
                }
            }
        }
        .frame(height: 40)
        // Faded with the buttons while answers don't count (paused, between rounds).
        .opacity(game.isTakingAnswers ? 1 : 0.5)
    }

    /// The group being answered; once it has no entries yet, the one just named all right for a
    /// moment (its flash).
    private var shown: Game.NoteGroup? {
        if let group = game.group, !group.entries.isEmpty || group.result != nil { return group }
        return game.groupFlash ?? game.group
    }

    private var caption: String {
        guard let shown else {
            return game.phase == .playing ? "Name the note" : "Notes struck together are named as one answer"
        }
        let count = shown.questions.count
        guard let result = shown.result else { return count == 2 ? "Name both notes, in either order" : "Name all \(count) notes, in any order" }
        return result.isAllRight ? "All \(count) right" : "\(result.rightCount) of \(count) right"
    }

    private func highlight(of entry: Int, in group: Game.NoteGroup) -> KeyHighlight {
        guard let result = group.result else { return .none }
        return result.entryIsRight[entry] ? .correct : .wrong
    }

    private func chipLabel(for entry: Game.GroupEntry, removable: Bool) -> some View {
        let naming = game.settings.naming
        // "komal Re" in sargam, as the buttons call it; otherwise the name and its sign.
        let swara = naming == .sargam ? naming.answerName(of: entry.letter, entry.accidental) : nil
        return HStack(spacing: 5) {
            SpelledName(name: swara ?? naming.name(of: entry.letter), accidental: swara == nil ? entry.accidental : .natural,
                        size: swara == nil ? 20 : 15)
            if removable {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.45)
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 62, minHeight: 40)
    }
}

/// A chip on the entry strip, coloured like the answer keys.
private struct ChipStyle: ButtonStyle {
    let highlight: KeyHighlight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(highlight.foreground)
            .background(highlight.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(highlight.border, lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// A note name and its ♯/♭ in the serif face of the answer keys and typing box.
struct SpelledName: View {
    let name: String
    let accidental: Accidental
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(name)
            if accidental != .natural {
                // The serif face has no ♯/♭; the fallback's ♭ comes with wide margins.
                Text(accidental.symbol)
                    .padding(.horizontal, accidental == .flat ? -size * 0.2 : 0)
            }
        }
        .font(.system(size: size, weight: .semibold, design: .serif))
    }
}

/// Feedback shown on an answer button or piano key.
enum KeyHighlight {
    /// Not involved in the latest answer.
    case none
    /// Pressed, and right.
    case correct
    /// Pressed, and wrong.
    case wrong
    /// The right answer, shown after a miss.
    case reveal
    /// A ♯/♭ button that's switched on for the next note.
    case armed

    var fill: Color {
        switch self {
        case .none: Theme.keyFill
        case .correct: Theme.correct
        case .wrong: Theme.wrong
        case .reveal: Theme.correctTint
        case .armed: Theme.accent
        }
    }

    var border: Color {
        switch self {
        case .none: Theme.keyBorder
        case .correct, .reveal: Theme.correct
        case .wrong: Theme.wrong
        case .armed: Theme.accent
        }
    }

    var foreground: Color {
        switch self {
        case .none: Theme.ink
        case .correct, .wrong, .armed: .white
        case .reveal: Theme.correctOnTint
        }
    }
}

private struct AnswerKeyStyle: ButtonStyle {
    let highlight: KeyHighlight

    func makeBody(configuration: Configuration) -> some View {
        AnswerKey(configuration: configuration, highlight: highlight)
    }

    private struct AnswerKey: View {
        let configuration: Configuration
        let highlight: KeyHighlight
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(highlight.foreground)
                .frame(width: 76, height: 76)
                .background(highlight.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(highlight.border, lineWidth: highlight == .reveal ? 3 : 1.5)
                }
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .animation(.easeOut(duration: 0.12), value: highlight)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}
