import AppKit
import SwiftUI

@main
struct ClefwiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var game: Game { appDelegate.game }

    var body: some Scene {
        Window("Clefwise", id: "main") {
            ContentView(game: game)
                .tint(Theme.accent)
                .preferredColorScheme(.light)
                .background(WindowSizeRecorder(recorder: game.recorder))
        }
        .defaultSize(width: 1000, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            // One window, so nothing to make new: File starts with opening a piece instead.
            CommandGroup(replacing: .newItem) {
                // Like the toolbar settings, a new piece waits for the round to end.
                Button("Open Piece…") { PieceFile.choose(for: game, via: .menu) }
                    .keyboardShortcut("o")
                    .disabled(game.phase == .playing)
                Divider()
                Button("Export Usage Data…") { UsageData.export() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Show Usage Data in Finder") { UsageData.showInFinder() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The app's one game, kept here rather than in the app's state so quitting can end its round.
    let game: Game
    private let launchDate = Date()

    @MainActor override init() {
        // Before the game exists, so the session's log starts with the launch: making the game
        // reopens last time's piece, which is logged too.
        UsageLog.shared.record(.appLaunched(.current))
        game = Game()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets `swift run` (no .app bundle) show a Dock icon and take keyboard focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // Between becoming active and resigning is the time actually spent in the app.
    func applicationDidBecomeActive(_ notification: Notification) {
        UsageLog.shared.record(.appActivity(AppActivity(active: true)))
    }

    func applicationDidResignActive(_ notification: Notification) {
        UsageLog.shared.record(.appActivity(AppActivity(active: false)))
    }

    /// ⌘Q and closing the window (which quits the app) both end here.
    func applicationWillTerminate(_ notification: Notification) {
        game.appWillTerminate()
        UsageLog.shared.record(.appTerminated(AppTerminated(sessionSeconds: Date().timeIntervalSince(launchDate))))
        // Written before the process goes, or the session's last events are lost.
        UsageLog.shared.flush()
    }
}
