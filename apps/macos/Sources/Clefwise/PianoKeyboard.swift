import SwiftUI

/// Piano answer input wired to the game: the exact key has to be pressed.
struct PianoPad: View {
    let game: Game

    var body: some View {
        PianoKeyboard(
            keys: game.pianoKeys,
            naming: game.settings.naming,
            showsNames: game.settings.showKeyNames,
            answersBlackKeys: game.accidentalsPossible,
            highlight: highlight(for:),
            onPress: { game.answer($0) }
        )
        .disabled(!game.isTakingAnswers)
        // Fade as one layer, otherwise white key edges show through the dimmed black keys.
        .compositingGroup()
        .opacity(game.isTakingAnswers ? 1 : 0.5)
    }

    /// Keys are matched by sound: the piano calls a black key C♯ even when the question spells it D♭.
    private func highlight(for pitch: Pitch) -> KeyHighlight {
        if let flash = game.flash, flash.pitch?.midiNumber == pitch.midiNumber {
            return flash.isCorrect ? .correct : .wrong
        }
        if game.isShowingMiss, game.question?.pitch.midiNumber == pitch.midiNumber {
            return .reveal
        }
        return .none
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
        .frame(height: 150)
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
