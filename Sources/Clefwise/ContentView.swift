import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var game: Game
    @State private var keyMonitor: Any?
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
                    Toggle("Show key names", isOn: $game.settings.showKeyNames)
                        .toggleStyle(.checkbox)
                        .help("Write note names on the piano keys (K)")
                        .padding(.trailing, 12)
                }
                // Next to the answer area, where you'd look for it.
                Picker("Answer with", selection: $game.settings.answerInput) {
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
        .overlay {
            if isDropTargeted { DropHighlight() }
        }
        .navigationTitle("Clefwise")
        .toolbar { settingsToolbar }
        // Like the toolbar settings, a new piece waits for the round to end.
        .dropDestination(for: URL.self) { urls, _ in
            guard game.phase != .playing, let url = urls.first else { return false }
            PieceFile.open(url, in: game)
            return true
        } isTargeted: {
            isDropTargeted = $0 && game.phase != .playing
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

    private var shortcutHint: String {
        var parts: [String]
        switch (game.settings.answerInput, game.settings.naming) {
        case (.buttons, .letters): parts = ["Type the note's letter or 1–7"]
        case (.buttons, _): parts = ["Press 1–7 to answer"]
        case (.piano, _): parts = ["Click the exact key"]
        case (.keyboard, _): parts = ["Type the note's name, ⌫ to fix"]
        }
        // Words rather than ♯/♭, which are too small to read at caption size.
        if game.settings.answerInput == .buttons, game.accidentalsPossible {
            parts += game.settings.naming == .sargam ? ["# tivra", "− komal"] : ["# sharp", "− flat"]
        }
        parts += ["Space start", "Esc stop"]
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

                    Picker("Notes", selection: $game.settings.range) {
                        ForEach(NoteRange.allCases) { Text($0.label).tag($0) }
                    }
                    .help(pieceHelp("How far above and below the staff notes can go", piece: "The notes come from the piece"))

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
                .help("Race the clock, or practice without one")
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
        Menu(game.settings.key.shortLabel) {
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
    }

    /// Says why a setting is greyed out while a piece is open, and how to get it back.
    private func pieceHelp(_ help: String, piece: String) -> String {
        game.isPractisingPiece ? "\(piece). Go back to random notes to change this." : help
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [game] event in
            // Leave ⌘/⌃/⌥ shortcuts (⌘Q, ⌘W, …) to the system.
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
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

    var body: some View {
        HStack(spacing: 12) {
            StatTile(title: game.settings.mode == .sprint ? "Time left" : "Time",
                     value: timeText,
                     tint: isRunningOut ? Theme.wrong : Theme.ink)
            StatTile(title: "Score", value: "\(game.score)")
            StatTile(title: "Streak", value: "\(game.streak)")
            StatTile(title: "Accuracy", value: game.accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
            if let progress = game.pieceProgress {
                // A fifth tile only fits a wide window; a narrow one does without rather than overflow.
                ViewThatFits(in: .horizontal) {
                    PieceProgressTile(progress: progress, order: game.settings.piece.order)
                    Color.clear.frame(width: 0, height: 0)
                }
                .layoutPriority(1)
            }
            Spacer()
            // Things you may want mid-round live here; round settings are in the toolbar.
            Group {
                Toggle(isOn: $game.settings.showHints) {
                    Label("Hints", systemImage: "lightbulb")
                }
                .help("Show note names and mnemonics (H)")

                Toggle(isOn: $game.settings.isMuted) {
                    Label("Mute", systemImage: game.settings.isMuted ? "speaker.slash" : "speaker.wave.2")
                }
                .help("Mute sounds (M)")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)

            if game.phase == .playing {
                Button("Stop", systemImage: "stop.fill") { game.stop() }
            }
        }
        .controlSize(.large)
    }

    private var timeText: String {
        let isSprint = game.settings.mode == .sprint
        let seconds = switch game.phase {
        case .idle: isSprint ? Int(Game.sprintLength) : 0
        case .playing, .finished: isSprint ? Int(game.timeRemaining.rounded(.up)) : Int(game.elapsed)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var isRunningOut: Bool {
        game.phase == .playing && game.settings.mode == .sprint && game.timeRemaining <= 10
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
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Where a piece round is: the bar when reading in order (a shuffled round jumps about, so it
/// counts notes instead), with a thin bar along the bottom for notes done.
private struct PieceProgressTile: View {
    let progress: Game.PieceProgress
    let order: Game.PieceSettings.Order

    var body: some View {
        StatTile(title: order == .inOrder ? "Bar" : "Notes",
                 value: order == .inOrder ? "\(progress.bar) / \(progress.bars)" : "\(progress.done) / \(progress.total)",
                 width: 110)
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
            .help("\(progress.done) of \(progress.total) notes done · bar \(progress.bar) of \(progress.bars)")
    }

    private var fraction: CGFloat {
        progress.total > 0 ? CGFloat(min(progress.done, progress.total)) / CGFloat(progress.total) : 0
    }
}

// MARK: - Staff

private struct StaffCard: View {
    let game: Game

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.paper)
                .shadow(color: .black.opacity(0.08), radius: 18, y: 6)

            StaffView(
                clef: game.displayedClef,
                keySignature: game.currentKeySignature,
                note: game.question,
                positionsToFit: game.staffPositionsToFit,
                noteColor: game.isShowingMiss ? Theme.wrong : Theme.ink,
                noteLabel: game.isShowingMiss ? game.question.map(answerLabel) : nil,
                // A piece's notes can go past the range setting, so hints cover as far as they go.
                hintPositions: game.settings.showHints ? game.staffPositionsToFit ?? game.settings.range.positions : nil,
                naming: game.settings.naming
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .opacity(game.phase == .playing ? 1 : 0.35)

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
                EmptyView()
            }
        }
        .frame(minHeight: 340)
    }

    private func answerLabel(_ question: Question) -> String {
        let name = game.settings.naming.name(of: question.pitch)
        let label = question.pitch == Pitch(.c, 4) ? "Middle \(name)" : name
        // On the piano, say so when the name was right but the octave wasn't.
        if let chosen = game.flash?.pitch, chosen.pitchClass == question.pitch.pitchClass,
           chosen.midiNumber != question.pitch.midiNumber {
            return "\(label) · wrong octave"
        }
        return label
    }
}

private struct StartPanel: View {
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            Text(game.settings.mode == .sprint ? "How many notes can you name in 60 seconds?" : "Practice at your own pace")
                .font(.title2.weight(.semibold))
            Text(details)
                .foregroundStyle(.secondary)
            Button {
                game.start()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .padding(.top, 6)
            Text("or press Space")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
                .frame(width: 240)
                .padding(.vertical, 4)
            // Spelled out here as well as in the File menu, so it's found without looking for it.
            HStack(spacing: 10) {
                Button("Practise a piece…", systemImage: "music.note.list") { PieceFile.choose(for: game) }
                    .help("Open a MusicXML file and read its notes (⌘O)")
                Text("MusicXML file, or drop one here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .panel()
    }

    private var details: String {
        var parts = [game.settings.clefChoice.summary, game.settings.range.label]
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
                Text(summary.score == 1 ? "note named" : "notes named")
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
                Button("Done") { game.dismissSummary() }
                Button("Play again") { game.start() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .panel()
    }

    private var title: String {
        if summary.finishedPiece { return "Piece complete" }
        return summary.mode == .practice ? "Practice complete" : summary.timeRanOut ? "Time's up!" : "Round ended"
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
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
    }
}

/// Shown while a file is dragged over the window.
private struct DropHighlight: View {
    var body: some View {
        ZStack {
            // Veils what's underneath so the message reads on its own.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.8))
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
        .disabled(game.phase != .playing)
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
        if let revealed, revealed.letter == letter { return revealed.accidental }
        return game.armedAccidental
    }

    /// Sargam has komal only for Re, Ga, Dha and Ni and tivra only for Ma; the other swaras are
    /// greyed out while one is armed, which also shows where komal and tivra apply.
    private func canAnswer(_ letter: NoteLetter) -> Bool {
        game.settings.naming.answerName(of: letter, game.armedAccidental) != nil
    }

    /// After a miss: the button and sign that name the note. Sargam goes by swara, so a C♯ is komal Re.
    private var revealed: (letter: NoteLetter, accidental: Accidental)? {
        guard game.isShowingMiss, let pitch = game.question?.pitch else { return nil }
        guard game.settings.naming == .sargam else { return (pitch.letter, pitch.accidental) }
        let pitchClass = pitch.pitchClass
        if let natural = NoteLetter.allCases.first(where: { $0.semitone == pitchClass }) { return (natural, .natural) }
        if pitchClass == Pitch(.f, 4, .sharp).pitchClass { return (.f, .sharp) }
        return (NoteLetter.allCases.first { $0.semitone == pitchClass + 1 }!, .flat)
    }

    private func highlight(for letter: NoteLetter) -> KeyHighlight {
        if let flash = game.flash, flash.letter == letter {
            return flash.isCorrect ? .correct : .wrong
        }
        if revealed?.letter == letter {
            return .reveal
        }
        return .none
    }

    private func highlight(for accidental: Accidental) -> KeyHighlight {
        if game.armedAccidental == accidental { return .armed }
        // After a miss, shows the sign the answer needed (the letter alone may have been right).
        if revealed?.accidental == accidental { return .reveal }
        return .none
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
        case .none: .white
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
        case .reveal: Theme.correct
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
