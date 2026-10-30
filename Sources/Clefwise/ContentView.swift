import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var game: Game
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 18) {
            StatsBar(game: game)
            StaffCard(game: game)
            MnemonicBar(clef: game.displayedClef, naming: game.settings.naming)
                .opacity(game.settings.showHints ? 1 : 0)
            switch game.settings.answerInput {
            case .buttons: AnswerPad(game: game)
            case .piano: PianoPad(game: game)
            }
            HStack {
                Text("\(answerHint)  ·  Space start  ·  Esc stop  ·  H hints\(game.settings.answerInput == .piano ? "  ·  K key names" : "")  ·  M mute")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .help("Note buttons accept any octave; on the piano you click the exact key")
            }
        }
        .padding(24)
        .frame(minWidth: 820, minHeight: 640)
        .background(Theme.background)
        .navigationTitle("Clefwise")
        .toolbar { settingsToolbar }
        .onAppear(perform: installKeyMonitor)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        }
    }

    private var answerHint: String {
        switch (game.settings.answerInput, game.settings.naming) {
        case (.piano, _): "Click the key in the right octave"
        case (.buttons, .letters): "Type the note's letter or 1–7"
        case (.buttons, _): "Press 1–7 to answer"
        }
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Group {
                Picker("Clef", selection: $game.settings.clefChoice) {
                    ForEach(ClefChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Which clef to read")

                Picker("Notes", selection: $game.settings.range) {
                    ForEach(NoteRange.allCases) { Text($0.label).tag($0) }
                }
                .help("How far above and below the staff notes can go")

                Picker("Mode", selection: $game.settings.mode) {
                    ForEach(Game.Mode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Race the clock, or practice without one")
            }
            .disabled(game.phase == .playing)

            Picker("Note names", selection: $game.settings.naming) {
                ForEach(NamingSystem.allCases) { Text($0.label).tag($0) }
            }
            .help("Name notes with letters, solfège (Do = C) or sargam (Sa = C)")
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [game] event in
            // Leave ⌘/⌃/⌥ shortcuts (⌘Q, ⌘W, …) to the system.
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let characters = event.charactersIgnoringModifiers ?? ""
            let keyCode = event.keyCode
            let handled = MainActor.assumeIsolated {
                game.handleKey(characters: characters, keyCode: keyCode)
            }
            return handled ? nil : event
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
        }
        .frame(width: 96, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                note: game.question,
                noteColor: game.isShowingMiss ? Theme.wrong : Theme.ink,
                noteLabel: game.isShowingMiss ? game.question.map(answerLabel) : nil,
                hintPositions: game.settings.showHints ? game.settings.range.positions : nil,
                naming: game.settings.naming
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .opacity(game.phase == .playing ? 1 : 0.35)

            switch game.phase {
            case .idle:
                StartPanel(game: game)
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
        let name = game.settings.naming.name(of: question.pitch.letter)
        let label = question.pitch == Pitch(.c, 4) ? "Middle \(name)" : name
        // On the piano, say so when the name was right but the octave wasn't.
        if let chosen = game.flash?.pitch, chosen.letter == question.pitch.letter, chosen != question.pitch {
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
        }
        .panel()
    }

    private var details: String {
        var parts = [game.settings.clefChoice.summary, game.settings.range.label]
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
            Text(summary.mode == .practice ? "Practice complete" : summary.timeRanOut ? "Time's up!" : "Round ended")
                .font(.title2.weight(.bold))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(summary.score)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text(summary.score == 1 ? "note named" : "notes named")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if summary.isNewBest {
                Label("New personal best!", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
            } else if let best = summary.bestScore {
                Text("Personal best: \(best)")
                    .foregroundStyle(.secondary)
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

    /// "A4", or "La (A4)" with other naming systems; adds the clef when clefs were mixed.
    private func reviewLabel(_ note: StaffNote) -> String {
        let naming = game.settings.naming
        var details: [String] = []
        if naming != .letters { details.append(note.pitch.name) }
        if summary.mixedClefs { details.append(note.clef.name.lowercased()) }
        let name = naming == .letters ? note.pitch.name : naming.name(of: note.pitch.letter)
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

private extension View {
    func panel() -> some View {
        multilineTextAlignment(.center)
            .padding(.horizontal, 36)
            .padding(.vertical, 22)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
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
            ForEach(NoteLetter.allCases) { letter in
                Button {
                    game.answer(letter)
                } label: {
                    keyLabel(for: letter)
                }
                .buttonStyle(AnswerKeyStyle(highlight: highlight(for: letter)))
            }
        }
        .disabled(game.phase != .playing)
    }

    private func keyLabel(for letter: NoteLetter) -> some View {
        let naming = game.settings.naming
        let name = naming.name(of: letter)
        return Text(name)
            .font(.system(size: name.count > 1 ? 24 : 30, weight: .semibold, design: .serif))
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

    private func highlight(for letter: NoteLetter) -> KeyHighlight {
        if let flash = game.flash, flash.letter == letter {
            return flash.isCorrect ? .correct : .wrong
        }
        if game.isShowingMiss, game.question?.pitch.letter == letter {
            return .reveal
        }
        return .none
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

    var fill: Color {
        switch self {
        case .none: .white
        case .correct: Theme.correct
        case .wrong: Theme.wrong
        case .reveal: Theme.correctTint
        }
    }

    var border: Color {
        switch self {
        case .none: Theme.keyBorder
        case .correct, .reveal: Theme.correct
        case .wrong: Theme.wrong
        }
    }

    var foreground: Color {
        switch self {
        case .none: Theme.ink
        case .correct, .wrong: .white
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
