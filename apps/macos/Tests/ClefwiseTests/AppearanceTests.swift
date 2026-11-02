import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Clefwise

// Dark mode: every colour has a light and a dark value. The light ones must stay what the app
// always drew, so light mode looks exactly as before.

extension Color {
    /// The sRGB colour this draws as in `appearance`, as 0xRRGGBB.
    func hex(in appearance: NSAppearance.Name) -> Int {
        var resolved: NSColor?
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            resolved = NSColor(self).usingColorSpace(.sRGB)
        }
        guard let color = resolved else { return -1 }
        let channels = [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
        return channels[0] << 16 | channels[1] << 8 | channels[2]
    }
}

@Suite struct AppearanceTests {
    /// 0xRRGGBB of an sRGB colour given as fractions, as `Color(red:green:blue:)` took them.
    private func hex(_ red: Double, _ green: Double, _ blue: Double) -> Int {
        [red, green, blue].map { Int(($0 * 255).rounded()) }.reduce(0) { $0 << 8 | $1 }
    }

    @Test func lightModeKeepsTheOriginalColours() {
        #expect(Theme.paper.hex(in: .aqua) == hex(0.992, 0.984, 0.965))
        #expect(Theme.ink.hex(in: .aqua) == hex(0.12, 0.11, 0.10))
        #expect(Theme.accent.hex(in: .aqua) == hex(0.23, 0.31, 0.63))
        #expect(Theme.correct.hex(in: .aqua) == hex(0.18, 0.58, 0.35))
        #expect(Theme.correctOnTint.hex(in: .aqua) == Theme.correct.hex(in: .aqua))
        #expect(Theme.wrong.hex(in: .aqua) == hex(0.83, 0.27, 0.24))
        #expect(Theme.hint.hex(in: .aqua) == hex(0.42, 0.49, 0.66))
        #expect(Theme.pianoKeyLabel.hex(in: .aqua) == Theme.hint.hex(in: .aqua))
        #expect(Theme.pianoKeyBorder.hex(in: .aqua) == Theme.keyBorder.hex(in: .aqua))
        #expect(Theme.blackKeyBottom.hex(in: .aqua) == Theme.ink.hex(in: .aqua))
        for white in [Theme.keyFill, Theme.panel, Theme.pianoWhiteKey, DashboardTheme.surface] {
            #expect(white.hex(in: .aqua) == 0xFFFFFF)
        }
        #expect(DashboardTheme.textPrimary.hex(in: .aqua) == 0x0B0B0B)
        #expect(DashboardTheme.series.map { $0.hex(in: .aqua) } == [0x2A78D6, 0xEB6834, 0x1BAF7A])
    }

    @Test func darkModeTurnsTheStaffDark() {
        // A dark card with light ink on it.
        #expect(Theme.paper.hex(in: .darkAqua) == 0x25262A)
        #expect(Theme.ink.hex(in: .darkAqua) == 0xE8E6E1)
        // The piano stays a piano: dimmed white keys, dark black keys.
        #expect(Theme.pianoWhiteKey.hex(in: .darkAqua) == 0xCFD0D5)
        #expect(Theme.blackKeyBottom.hex(in: .darkAqua) == 0x0E0E10)
        // The dashboard takes the palette's dark steps.
        #expect(DashboardTheme.surface.hex(in: .darkAqua) == 0x1A1A19)
        #expect(DashboardTheme.series.map { $0.hex(in: .darkAqua) } == [0x3987E5, 0xD95926, 0x199E70])
    }

    @Test func theSettingDefaultsToMatchingMacOS() throws {
        #expect(Game.Settings().appearance == .system)
        #expect(Appearance.system.nsAppearance == nil)
        #expect(Appearance.dark.nsAppearance?.name == .darkAqua)
        // Settings saved before dark mode existed follow macOS.
        let old = try JSONDecoder().decode(Game.Settings.self, from: Data(#"{"mode":"practice"}"#.utf8))
        #expect(old.appearance == .system)
        let dark = try JSONDecoder().decode(Game.Settings.self, from: JSONEncoder().encode({ var s = Game.Settings(); s.appearance = .dark; return s }()))
        #expect(dark.appearance == .dark)
    }

    @Test func launchesSayHowMacOSWasSet() throws {
        let launch = AppLaunched(appVersion: "1", build: "1", osVersion: "26.5", model: "Mac", locale: "en", timeZone: "UTC",
                                 screen: nil, systemAppearance: "dark")
        let data = try LoggedEvent.encoder.encode(LoggedEvent(.appLaunched(launch), session: UUID(), sequence: 0))
        #expect(try LoggedEvent.decoder.decode(LoggedEvent.self, from: data).event == .appLaunched(launch))
    }
}
