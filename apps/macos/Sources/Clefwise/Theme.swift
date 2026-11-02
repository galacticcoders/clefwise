import AppKit
import SwiftUI

/// The app's colours, each with a light and a dark value that's picked wherever it's drawn. The
/// light values are the app's original ones. The dark ones were checked for WCAG contrast:
/// ink 12.7:1 on the paper, white on the accent 3.7:1 (large labels), the accent 5:1 on the
/// window, red and green 4.5:1 or more on the paper.
enum Theme {
    /// The staff's card.
    static let paper = Color(light: NSColor(0.992, 0.984, 0.965), dark: NSColor(hex: 0x25262A))
    /// Staff lines, notes and other notation; answer-button letters.
    static let ink = Color(light: NSColor(0.12, 0.11, 0.10), dark: NSColor(hex: 0xE8E6E1))
    static let accent = Color(light: NSColor(0.23, 0.31, 0.63), dark: NSColor(hex: 0x6A7DE0))
    static let correct = Color(light: NSColor(0.18, 0.58, 0.35), dark: NSColor(hex: 0x36A565))
    /// `correct` at ~12% over white, opaque so keys don't show the background through.
    static let correctTint = Color(light: NSColor(0.90, 0.95, 0.92), dark: NSColor(hex: 0x1F3A2A))
    /// Green text on `correctTint`.
    static let correctOnTint = Color(light: NSColor(0.18, 0.58, 0.35), dark: NSColor(hex: 0x6CCF95))
    static let wrong = Color(light: NSColor(0.83, 0.27, 0.24), dark: NSColor(hex: 0xE5625A))
    static let hint = Color(light: NSColor(0.42, 0.49, 0.66), dark: NSColor(hex: 0x8F9CC4))
    static let keyBorder = Color(light: NSColor(0.80, 0.82, 0.87), dark: NSColor(hex: 0x4F525C))
    /// An answer button that isn't lit up.
    static let keyFill = Color(light: .white, dark: NSColor(hex: 0x2F3036))
    /// The start, piece and summary panels.
    static let panel = Color(light: .white, dark: NSColor(hex: 0x303137))
    /// The stat tiles over the window background.
    static let tile = Color(light: NSColor(white: 1, alpha: 0.8), dark: NSColor(white: 1, alpha: 0.06))
    /// What veils the window while a file is dragged over it.
    static let veil = Color(light: NSColor(white: 1, alpha: 0.8), dark: NSColor(hex: 0x303137, alpha: 0.85))

    /// The piano stays a piano in the dark: its white keys are only dimmed, so their labels and
    /// borders keep light-mode inks of their own.
    static let pianoWhiteKey = Color(light: .white, dark: NSColor(hex: 0xCFD0D5))
    static let pianoKeyBorder = Color(light: NSColor(0.80, 0.82, 0.87), dark: NSColor(hex: 0x9A9CA4))
    static let pianoKeyLabel = Color(light: NSColor(0.42, 0.49, 0.66), dark: NSColor(hex: 0x4A587D))
    static let blackKeyTop = Color(light: NSColor(0.28, 0.28, 0.28), dark: NSColor(0.24, 0.24, 0.24))
    static let blackKeyBottom = Color(light: NSColor(0.12, 0.11, 0.10), dark: NSColor(hex: 0x0E0E10))

    static let background = LinearGradient(
        colors: [Color(light: NSColor(0.94, 0.95, 0.97), dark: NSColor(hex: 0x17181C)),
                 Color(light: NSColor(0.88, 0.91, 0.95), dark: NSColor(hex: 0x101114))],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// Light or dark: as macOS is set, or always one of them (View ▸ Appearance).
enum Appearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: Self { self }
    var label: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    /// What `NSApp.appearance` is set to: nil follows macOS.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

extension View {
    /// Made anew when light and dark switch. A pop-up button in a window's content otherwise keeps
    /// its old text colour (black on dark, or white on light) until the window is reopened.
    func rebuiltOnAppearanceChange() -> some View { modifier(RebuiltOnAppearanceChange()) }
}

private struct RebuiltOnAppearanceChange: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View { content.id(colorScheme) }
}

extension Color {
    /// `light` in light appearance and `dark` in dark, resolved wherever the colour is drawn.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension NSColor {
    /// An sRGB colour, as `Color(red:green:blue:)` makes one.
    convenience init(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) {
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    convenience init(hex: Int, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha: alpha)
    }
}
