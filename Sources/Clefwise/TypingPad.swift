import SwiftUI

/// Keyboard answer input: shows what's being typed towards a note name.
struct TypingPad: View {
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 2) {
                Text(text)
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundStyle(textColor)
                if showsCaret {
                    Caret()
                }
            }
            .frame(width: 340, height: 76)
            .background(highlight.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(highlight == .none ? Theme.keyBorder : highlight.border, lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            .modifier(Shake(animatableData: CGFloat(game.rejectedKeystrokes)))
            .animation(.easeOut(duration: 0.3), value: game.rejectedKeystrokes)
            .animation(.easeOut(duration: 0.12), value: highlight)

            Text(NoteLetter.allCases.map { game.settings.naming.name(of: $0) }.joined(separator: "  ·  "))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .opacity(game.phase == .playing ? 1 : 0.5)
    }

    /// The answer just given stays visible, coloured, until you start typing the next one.
    private var highlight: KeyHighlight {
        guard game.typedText.isEmpty, let flash = game.flash else { return .none }
        return flash.isCorrect ? .correct : .wrong
    }

    private var text: String {
        if !game.typedText.isEmpty {
            // Match how the names are written: "sol" shows as "Sol".
            return game.typedText.prefix(1).uppercased() + game.typedText.dropFirst()
        }
        if let flash = game.flash {
            return game.settings.naming.name(of: flash.letter)
        }
        return game.phase == .playing ? "" : "Type the note"
    }

    private var textColor: Color {
        if highlight != .none { return highlight.foreground }
        return game.typedText.isEmpty ? Theme.hint : Theme.ink
    }

    private var showsCaret: Bool {
        game.phase == .playing && highlight == .none && !game.isShowingMiss
    }
}

private struct Caret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.accent)
                .frame(width: 2.5, height: 36)
                .opacity(Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0)
        }
    }
}

/// Side-to-side wobble; animating `animatableData` up by 1 plays one shake.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(animatableData * .pi * 4), y: 0))
    }
}
