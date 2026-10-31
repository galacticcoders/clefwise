import SwiftUI

/// Piano answer input wired to the game: the exact key has to be pressed.
struct PianoPad: View {
    let game: Game

    var body: some View {
        VStack(spacing: Self.captionSpacing) {
            // Only when naming notes together, so other rounds look as they always did. The keys
            // give up the caption's room, so the window keeps its layout.
            if game.namesTogether {
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: Self.captionHeight)
            }
            PianoKeyboard(
                keys: game.pianoKeys,
                naming: game.settings.naming,
                showsNames: game.settings.showKeyNames,
                answersBlackKeys: game.accidentalsPossible,
                highlight: highlight(for:),
                onPress: { game.answer($0) },
                height: game.namesTogether ? PianoKeyboard.height - Self.captionHeight - Self.captionSpacing : PianoKeyboard.height
            )
            .disabled(!game.isTakingAnswers)
            // Fade as one layer, otherwise white key edges show through the dimmed black keys.
            .compositingGroup()
            .opacity(game.isTakingAnswers ? 1 : 0.5)
        }
    }

    private static let captionHeight: CGFloat = 18
    private static let captionSpacing: CGFloat = 8

    /// What to do while notes are named together, and once judged how it went.
    private var caption: String {
        guard let group = game.group else {
            return game.phase == .playing ? "Click the note's key" : "Notes struck together are played as one answer: click every key"
        }
        let count = group.questions.count
        if let result = group.result {
            return result.isAllRight ? "All \(count) right" : "\(result.rightCount) of \(count) right"
        }
        let keys = game.groupEntriesNeeded ?? count
        return "Click all \(keys) keys, in any order (a chosen key again takes it back)"
    }

    /// Keys are matched by sound: the piano calls a black key C♯ even when the question spells it D♭.
    /// While notes are named together, the keys chosen so far are picked out; once judged they're
    /// coloured right or wrong, and the keys of the notes missed are revealed.
    private func highlight(for pitch: Pitch) -> KeyHighlight {
        if let shown = shownGroup {
            if let entry = shown.entries.firstIndex(where: { $0.pitch?.midiNumber == pitch.midiNumber }) {
                guard let result = shown.result else { return .armed }
                return result.entryIsRight[entry] ? .correct : .wrong
            }
            if let result = shown.result, game.isShowingMiss,
               zip(shown.questions, result.isRight).contains(where: { !$1 && $0.pitch.midiNumber == pitch.midiNumber }) {
                return .reveal
            }
            return .none
        }
        if let flash = game.flash, flash.pitch?.midiNumber == pitch.midiNumber {
            return flash.isCorrect ? .correct : .wrong
        }
        if game.isShowingMiss, game.question?.pitch.midiNumber == pitch.midiNumber {
            return .reveal
        }
        return .none
    }

    /// The notes named together whose keys are coloured: the group being answered once a key is
    /// chosen or it's judged, otherwise for a moment the one just named all right (its flash).
    private var shownGroup: Game.NoteGroup? {
        if let group = game.group, !group.entries.isEmpty || group.result != nil { return group }
        return game.groupFlash
    }
}

/// A keyboard of whole octaves. Black keys are answers only when notes can be sharp or flat;
/// otherwise they swallow clicks so a near miss doesn't press the white key underneath.
struct PianoKeyboard: View {
    /// Diatonic indices of the white keys to draw.
    let keys: ClosedRange<Int>
    let naming: NamingSystem
    /// Write the note name on every key.
    let showsNames: Bool
    let answersBlackKeys: Bool
    /// Called with natural pitches for white keys and sharps (C♯, never D♭) for black keys.
    let highlight: (Pitch) -> KeyHighlight
    let onPress: (Pitch) -> Void
    var height = PianoKeyboard.height

    static let height: CGFloat = 150

    var body: some View {
        GeometryReader { geometry in
            let keyWidth = min(64, geometry.size.width / CGFloat(keys.count))
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(keys), id: \.self) { index in
                        let pitch = Pitch(diatonicIndex: index)
                        Button {
                            onPress(pitch)
                        } label: {
                            label(for: pitch, keyWidth: keyWidth)
                        }
                        .buttonStyle(WhiteKeyStyle(highlight: highlight(pitch)))
                        .frame(width: keyWidth, height: height)
                    }
                }
                ForEach(blackKeys, id: \.boundary) { key in
                    let blackKey = BlackKey(name: showsNames ? naming.blackKeyName(above: key.pitch.letter) : [],
                                            width: keyWidth * 0.58,
                                            highlight: highlight(key.pitch))
                    Group {
                        if answersBlackKeys {
                            Button { onPress(key.pitch) } label: { blackKey }
                                .buttonStyle(BlackKeyStyle())
                        } else {
                            // Not an answer; swallow clicks so the white key underneath isn't pressed by accident.
                            blackKey.onTapGesture {}
                        }
                    }
                    .frame(width: keyWidth * 0.58, height: height * 0.6)
                    .offset(x: CGFloat(key.boundary) * keyWidth - keyWidth * 0.29)
                }
            }
            .frame(width: keyWidth * CGFloat(keys.count), height: height)
            .frame(maxWidth: .infinity)
        }
        .frame(height: height)
    }

    /// Black keys: the white-key boundary (counted from the left) each sits on, and its pitch as a sharp.
    private var blackKeys: [(boundary: Int, pitch: Pitch)] {
        keys.dropLast().enumerated().compactMap { offset, index in
            let pitch = Pitch(diatonicIndex: index)
            return [.c, .d, .f, .g, .a].contains(pitch.letter) ? (offset + 1, pitch.with(.sharp)) : nil
        }
    }

    private func label(for pitch: Pitch, keyWidth: CGFloat) -> some View {
        let name = naming.name(of: pitch.letter)
        // Hidden rather than removed: a button with an empty label isn't drawn at all.
        return Text(naming == .letters && pitch.letter == .c ? "\(name)\(pitch.octave)" : name)
            .font(.system(size: min(13, keyWidth * 0.4), weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 2)
            .padding(.bottom, 10)
            .opacity(showsNames ? 1 : 0)
    }
}

private struct WhiteKeyStyle: ButtonStyle {
    let highlight: KeyHighlight

    func makeBody(configuration: Configuration) -> some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
        configuration.label
            .foregroundStyle(highlight == .none ? Theme.hint : highlight.foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background(highlight.fill, in: shape)
            .overlay {
                shape.strokeBorder(highlight == .none ? Theme.keyBorder : highlight.border,
                                   lineWidth: highlight == .reveal ? 2.5 : 1)
            }
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: highlight)
    }
}

/// The black key draws itself; pressing only lightens it.
private struct BlackKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.15 : 0)
    }
}

private struct BlackKey: View {
    /// Lines of the key's name; empty to leave it blank.
    let name: [String]
    let width: CGFloat
    /// Highlighted like the white keys (the right key turns pale green with a green edge), so it
    /// stands out from the row of dark keys.
    let highlight: KeyHighlight

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
        shape
            .fill(highlight == .none
                  ? AnyShapeStyle(LinearGradient(colors: [Color(white: 0.28), Theme.ink], startPoint: .top, endPoint: .bottom))
                  : AnyShapeStyle(highlight.fill))
            .overlay {
                if highlight != .none {
                    shape.strokeBorder(highlight.border, lineWidth: highlight == .reveal ? 2.5 : 1)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1.5)
            .overlay(alignment: .bottom) {
                // Skipped on very wide keyboards, where the keys are too narrow to read.
                if !name.isEmpty, width >= 24 {
                    VStack(spacing: 1) {
                        ForEach(name, id: \.self) { Text($0) }
                    }
                    .font(.system(size: min(11, width * 0.3), weight: .semibold, design: .rounded))
                    .foregroundStyle(highlight == .none ? Color.white.opacity(0.85) : highlight.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 8)
                }
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: highlight)
    }
}
