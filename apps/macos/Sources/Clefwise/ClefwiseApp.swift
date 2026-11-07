import AppKit
import SwiftUI

@main
struct ClefwiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The journals, and the game, library and progress store of the one in use: each replaced
    /// when the journal changes, so windows and menus read them from here in their own bodies.
    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        Window("Clefwise", id: "main") {
            MainWindowContent(model: model) { appDelegate.mainWindow = $0 }
        }
        .defaultSize(width: 1000, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            // One window, so nothing to make new: File starts with opening a piece instead.
            CommandGroup(replacing: .newItem) {
                FileCommands(model: model)
            }
            ProgressCommands(model: model)
            AppearanceCommands(model: model)
        }

        // Its own window, so it can stay open beside the game and follow along round by round.
        Window("Progress", id: ProgressWindow.id) {
            ProgressWindowContent(model: model)
        }
        .defaultSize(width: 1150, height: 900)
        .windowResizability(.contentMinSize)
        // Without the Window menu item SwiftUI adds for it: Window ▸ Progress below opens it and logs that.
        .commandsRemoved()
    }
}

/// The game's window: the journal in use's game, everything in it made afresh (its key monitor
/// included) when the journal changes.
private struct MainWindowContent: View {
    let model: AppModel
    let onWindow: (NSWindow) -> Void

    var body: some View {
        let game = model.game
        ContentView(game: game)
            .id(ObjectIdentifier(game))
            .tint(Theme.accent)
            // For the whole app: both windows, menus, alerts and the open panel.
            .onChange(of: game.settings.appearance, initial: true) { _, appearance in
                NSApp.appearance = appearance.nsAppearance
            }
            .background(WindowSizeRecorder(recorder: game.recorder))
            .background(WindowReader(onWindow: onWindow))
            // Asks for a journal at first launch, or says when it can't be found.
            .journalSetup(model)
            // The title and the start panel's Journal menu.
            .environment(model)
    }
}

/// The Progress window: the journal in use's, made afresh (and read again) when it changes.
private struct ProgressWindowContent: View {
    let model: AppModel

    var body: some View {
        DashboardView(game: model.game, store: model.progressStore)
            .id(ObjectIdentifier(model.progressStore))
            .tint(Theme.accent)
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
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button("Progress") { ProgressWindow.open(from: "menu", game: model.game, with: openWindow) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
        }
    }
}

/// The File menu's own items, for the journal in use's game.
private struct FileCommands: View {
    let model: AppModel

    var body: some View {
        let game = model.game
        // Like the toolbar settings, a new piece waits for the round to end.
        Button("Open Piece…") { PieceFile.choose(for: game, via: .menu) }
            .keyboardShortcut("o")
            .disabled(game.phase == .playing)
        PieceLibraryCommands(game: game)
        Divider()
        JournalCommands(model: model)
        Divider()
        Button("Export Usage Data…") { UsageData.export(namespace: game.namespace, libraryFolder: model.library.folder) }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        Button("Show Usage Data in Finder") { UsageData.showInFinder() }
    }
}

/// File ▸ Open Recent Piece and All Pieces…, under Open Piece…, once a piece has been kept; with
/// none, the File menu is as it was before the library.
private struct PieceLibraryCommands: View {
    let game: Game

    /// How many pieces Open Recent Piece lists.
    static let count = 10

    var body: some View {
        if !game.library.isEmpty {
            let others = Array(game.library.entries.filter { !$0.isOpen(in: game) }.prefix(Self.count))
            if !others.isEmpty {
                let titles = others.distinctTitles()
                Menu("Open Recent Piece") {
                    ForEach(others) { entry in
                        Button(titles[entry.id] ?? entry.displayTitle) { PieceFile.open(entry, in: game, from: "fileMenu") }
                    }
                }
                .disabled(game.phase == .playing)
            }
            Button("All Pieces…") { PieceListSheet.shared.show(from: "fileMenu", game: game) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(game.phase == .playing)
        }
    }
}

/// File ▸ New Journal…, Open Journal…, Switch Journal ▸ and Show Journal in Finder. Like the start
/// panel's Journal menu, the first three wait for the round to end: a run goes into the journal it
/// started in. Show Journal in Finder doesn't, as it leaves the game alone.
private struct JournalCommands: View {
    let model: AppModel

    var body: some View {
        let isBetweenRounds = model.canChangeJournal
        Button("New Journal…") { model.newJournal(from: "fileMenu") }
            .disabled(!isBetweenRounds)
        Button("Open Journal…") { model.openJournal(from: "fileMenu") }
            .disabled(!isBetweenRounds)
        if !model.registry.records.isEmpty {
            let names = model.registry.displayNames
            Picker("Switch Journal", selection: selection) {
                ForEach(model.registry.records) { record in
                    Text(names[record.id] ?? record.name).tag(Optional(record.id))
                }
            }
            .disabled(!isBetweenRounds)
        }
        Button("Show Journal in Finder") { model.showJournalInFinder(from: "fileMenu") }
            .disabled(!model.canShowJournal)
    }

    /// The journal in use, ticked; picking another switches to it.
    private var selection: Binding<UUID?> {
        Binding(get: { model.registry.currentID }, set: { id in
            guard let record = id.flatMap(model.registry.record(id:)) else { return }
            model.switchJournal(to: record, from: "fileMenu")
        })
    }
}

/// View ▸ Appearance: Match System, Light or Dark.
private struct AppearanceCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            AppearancePicker(model: model)
            Divider()
        }
    }
}

/// View ▸ Appearance's choices. It's one of each journal's settings, so it follows the game in use.
private struct AppearancePicker: View {
    let model: AppModel

    var body: some View {
        @Bindable var game = model.game
        Picker("Appearance", selection: $game.settings.appearance) {
            ForEach(Appearance.allCases) { Text($0.label).tag($0) }
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
    /// The journals and, for the one in use, its game, piece library and progress store; kept here
    /// rather than in the app's state so quitting can end the round. Its progress store lives as
    /// long as the journal is in use, so reopening the Progress window shows the last numbers while
    /// it reads again.
    let model: AppModel
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
        // Brings build 1's journal over, wires the journal in use (its unfinished run first, before
        // anything is logged), logs the launch, then makes the game and restores the run: see
        // `AppModel.init`. A new journal brings in the usage log so far, if it's the first.
        model = AppModel(defaults: .standard, log: .shared, device: DeviceID.current(in: .standard), launch: .current)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets `swift run` (no .app bundle) show a Dock icon and take keyboard focus.
        NSApp.setActivationPolicy(.regular)
        // From now on the journal in use is watched, and read again as files arrive.
        model.didFinishLaunching()
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
        model.game.appDidResignActive()
    }

    /// ⌘Q and closing the game's window (which quits the app) both end here.
    func applicationWillTerminate(_ notification: Notification) {
        model.game.appWillTerminate()
        UsageLog.shared.record(.appTerminated(AppTerminated(sessionSeconds: Date().timeIntervalSince(launchDate))))
        // Written before the process goes, or the session's last events are lost.
        UsageLog.shared.flush()
        // The round just ended goes into its journal; should that take long (a slow network
        // drive), the next launch places it instead.
        model.waitForJournals(timeout: 2)
    }
}
