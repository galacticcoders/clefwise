import SwiftUI

/// Piano answer input wired to the game: the exact key has to be pressed.
struct PianoPad: View {
    let game: Game

    var body: some View {
        PianoKeyboard(
            keys: game.pianoKeys,
            naming: game.settings.naming,
            showsNames: game.settings.showKeyNames,
            highlight: highlight(for:),
            onPress: { game.answer($0) }
        )
        .disabled(game.phase != .playing)
        // Fade as one layer, otherwise white key edges show through the dimmed black keys.
        .compositingGroup()
        .opacity(game.phase == .playing ? 1 : 0.5)
    }

    private func highlight(for pitch: Pitch) -> KeyHighlight {
        if let flash = game.flash, flash.pitch == pitch {
            return flash.isCorrect ? .correct : .wrong
        }
        if game.isShowingMiss, game.question?.pitch == pitch {
            return .reveal
        }
        return .none
    }
}

/// A keyboard of whole octaves. Only white keys can be pressed, since every question is a natural note.
struct PianoKeyboard: View {
    /// Diatonic indices of the white keys to draw.
    let keys: ClosedRange<Int>
    let naming: NamingSystem
    /// Write the note name on every key.
    let showsNames: Bool
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
                    BlackKey(name: showsNames ? naming.blackKeyName(above: key.letter) : [],
                             width: keyWidth * 0.58)
                        .frame(width: keyWidth * 0.58, height: height * 0.6)
                        .offset(x: CGFloat(key.boundary) * keyWidth - keyWidth * 0.29)
                }
            }
            .frame(width: keyWidth * CGFloat(keys.count), height: height)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 150)
    }

    /// Black keys: the white-key boundary (counted from the left) each sits on, and the white key below it.
    private var blackKeys: [(boundary: Int, letter: NoteLetter)] {
        keys.dropLast().enumerated().compactMap { offset, index in
            let letter = Pitch(diatonicIndex: index).letter
            return [.c, .d, .f, .g, .a].contains(letter) ? (offset + 1, letter) : nil
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

private struct BlackKey: View {
    /// Lines of the key's name; empty to leave it blank.
    let name: [String]
    let width: CGFloat

    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
            .fill(LinearGradient(colors: [Color(white: 0.28), Theme.ink], startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1.5)
            .overlay(alignment: .bottom) {
                // Skipped on very wide keyboards, where the keys are too narrow to read.
                if !name.isEmpty, width >= 24 {
                    VStack(spacing: 1) {
                        ForEach(name, id: \.self) { Text($0) }
                    }
                    .font(.system(size: min(11, width * 0.3), weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 8)
                }
            }
            .contentShape(Rectangle())
            // Never an answer; swallow clicks so the white key underneath isn't pressed by accident.
            .onTapGesture {}
    }
}
