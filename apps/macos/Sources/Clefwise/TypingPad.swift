import SwiftUI

/// Keyboard answer input: shows what's being typed towards a note name.
struct TypingPad: View {
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 2) {
                SpelledName(name: shown.name, accidental: shown.accidental, size: 34)
                    .foregroundStyle(textColor)
                if showsCaret {
                    Caret()
                }
            }
            .frame(width: 340, height: 76)
            .overlay(alignment: .trailing) {
                // Just outside the box, so it never covers a long name and the box doesn't move.
                if game.typingNeedsReturn {
                    ReturnCue()
                        .fixedSize()
                        .frame(width: 0, alignment: .leading)
                        .offset(x: 14)
                }
            }
            .background(highlight.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(highlight == .none ? Theme.keyBorder : highlight.border, lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            .modifier(Shake(animatableData: CGFloat(game.rejectedKeystrokes)))
            .animation(.easeOut(duration: 0.3), value: game.rejectedKeystrokes)
            .animation(.easeOut(duration: 0.12), value: highlight)

            Text(namesLine)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .opacity(game.phase == .playing ? 1 : 0.5)
    }

    /// Words rather than ♯/♭, which are too small at this size to tell from # and b.
    private var namesLine: String {
        let naming = game.settings.naming
        let names = NoteLetter.allCases.map { naming.name(of: $0) }.joined(separator: "  ·  ")
        guard game.accidentalsPossible else { return names }
        return names + "   —   " + (naming == .sargam ? "add b for komal, # for tivra" : "add # for sharp, b for flat")
    }

    /// The answer just given stays visible, coloured, until you start typing the next one.
    private var highlight: KeyHighlight {
        guard game.typedText.isEmpty, let flash = game.flash else { return .none }
        return flash.isCorrect ? .correct : .wrong
    }

    private var shown: (name: String, accidental: Accidental) {
        if !game.typedText.isEmpty {
            return typedName
        }
        if let flash = game.flash {
            // "komal Ga"; a sign that makes no swara (Sa♭) is shown as typed.
            let naming = game.settings.naming
            if naming == .sargam, let swara = naming.answerName(of: flash.letter, flash.accidental) {
                return (swara, .natural)
            }
            return (naming.name(of: flash.letter), flash.accidental)
        }
        return (game.phase == .playing ? "" : "Type the note", .natural)
    }

    /// Written the way names are: "sol" shows as "Sol", "f#" as "F♯", "sib" as "Si♭". A b is only
    /// a flat after a whole name, so a lone "b" with letter names stays B.
    private var typedName: (name: String, accidental: Accidental) {
        var text = game.typedText
        var accidental = Accidental.natural
        let names = NoteLetter.allCases.map { game.settings.naming.name(of: $0).lowercased() }
        if text.hasSuffix("#") || text.hasSuffix("♯") {
            text.removeLast()
            accidental = .sharp
        } else if text.hasSuffix("♭") || (text.hasSuffix("b") && names.contains(String(text.dropLast()))) {
            text.removeLast()
            accidental = .flat
        }
        return (text.prefix(1).uppercased() + String(text.dropFirst()), accidental)
    }

    private var textColor: Color {
        if highlight != .none { return highlight.foreground }
        return game.typedText.isEmpty ? Theme.hint : Theme.ink
    }

    private var showsCaret: Bool {
        game.phase == .playing && highlight == .none && !game.isShowingMiss
    }
}

/// Shown when the typed name is complete but could still take a ♯ or ♭, so it waits for Return.
private struct ReturnCue: View {
    var body: some View {
        Text("Press Return ↩")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
            }
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
