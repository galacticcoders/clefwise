import AppKit
import SwiftUI

@main
struct ClefwiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var game = Game()

    var body: some Scene {
        Window("Clefwise", id: "main") {
            ContentView(game: game)
                .tint(Theme.accent)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1000, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            // One window, so nothing to make new: File starts with opening a piece instead.
            CommandGroup(replacing: .newItem) {
                // Like the toolbar settings, a new piece waits for the round to end.
                Button("Open Piece…") { PieceFile.choose(for: game) }
                    .keyboardShortcut("o")
                    .disabled(game.phase == .playing)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets `swift run` (no .app bundle) show a Dock icon and take keyboard focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
