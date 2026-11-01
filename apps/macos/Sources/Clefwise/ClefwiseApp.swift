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
                // For the whole app: both windows, menus, alerts and the open panel.
                .onChange(of: game.settings.appearance, initial: true) { _, appearance in
                    NSApp.appearance = appearance.nsAppearance
                }
                .background(WindowSizeRecorder(recorder: game.recorder))
                .background(WindowReader { appDelegate.mainWindow = $0 })
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
            ProgressCommands(game: game)
            AppearanceCommands(game: game)
        }

        // Its own window, so it can stay open beside the game and follow along round by round.
        Window("Progress", id: ProgressWindow.id) {
            DashboardView(game: game, store: appDelegate.progressStore)
                .tint(Theme.accent)
        }
        .defaultSize(width: 1150, height: 900)
        .windowResizability(.contentMinSize)
        // Without the Window menu item SwiftUI adds for it: Window ▸ Progress below opens it and logs that.
        .commandsRemoved()
    }
}

/// Opening the Progress window, from the menu or the button in the stats bar.
enum ProgressWindow {
    static let id = "progress"

    /// `source` says which control opened it, for the usage log.
    @MainActor
    static func open(from source: String, game: Game, with openWindow: OpenWindowAction) {
        game.recorder.recordUIAction("showProgress", detail: source)
        openWindow(id: id)
    }
}

/// Window ▸ Progress (⇧⌘P).
private struct ProgressCommands: Commands {
    let game: Game
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button("Progress") { ProgressWindow.open(from: "menu", game: game, with: openWindow) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
        }
    }
}

/// View ▸ Appearance: Match System, Light or Dark.
private struct AppearanceCommands: Commands {
    @Bindable var game: Game

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Picker("Appearance", selection: $game.settings.appearance) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0) }
            }
            Divider()
        }
    }
}

/// Hands over the window the view is in, once it's in one.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { ReaderView(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        /// Only watches; clicks go to whatever is underneath.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The app's one game, kept here rather than in the app's state so quitting can end its round.
    let game: Game
    /// Kept for the app's life, so reopening the Progress window shows the last numbers while it
    /// reads the log again.
    let progressStore: ProgressStore
    private let launchDate = Date()

    /// The game's window. Closing it still quits, as when it was the only window: the Progress
    /// window only looks on, and a round shouldn't carry on with nowhere to see it.
    weak var mainWindow: NSWindow? {
        didSet {
            guard mainWindow !== oldValue else { return }
            let center = NotificationCenter.default
            if let oldValue { center.removeObserver(self, name: NSWindow.willCloseNotification, object: oldValue) }
            if let mainWindow {
                center.addObserver(self, selector: #selector(mainWindowWillClose), name: NSWindow.willCloseNotification,
                                   object: mainWindow)
            }
        }
    }

    @MainActor override init() {
        // Before the game exists, so the session's log starts with the launch: making the game
        // reopens last time's piece, which is logged too.
        UsageLog.shared.record(.appLaunched(.current))
        game = Game(library: .shared)
        progressStore = ProgressStore()
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

    @objc private func mainWindowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    // Between becoming active and resigning is the time actually spent in the app.
    func applicationDidBecomeActive(_ notification: Notification) {
        UsageLog.shared.record(.appActivity(AppActivity(active: true)))
    }

    func applicationDidResignActive(_ notification: Notification) {
        UsageLog.shared.record(.appActivity(AppActivity(active: false)))
        game.appDidResignActive()
    }

    /// ⌘Q and closing the game's window (which quits the app) both end here.
    func applicationWillTerminate(_ notification: Notification) {
        game.appWillTerminate()
        UsageLog.shared.record(.appTerminated(AppTerminated(sessionSeconds: Date().timeIntervalSince(launchDate))))
        // Written before the process goes, or the session's last events are lost.
        UsageLog.shared.flush()
    }
}
