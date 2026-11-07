import AppKit
import Observation

// The app across journals: the one in use and, for it, the game, the piece library and the
// progress store; switching to another between rounds. See spec/practice-journal.md, "Several
// journals".

/// What the app works on: the journals this Mac knows (`registry`) and, for the one in use, its
/// game, piece library and progress store, made afresh each time the journal in use changes. The
/// app delegate makes it at launch, before anything is logged, and keeps it for the app's life.
/// Views and menus read `game` and `library` from here and never keep one: a switch replaces both.
///
/// Every run's lines reach the journal in use through `router`, the usage log's one line sink,
/// and each journal has its own run-file writer, with its own `Current` and `Pending`.
///
/// With no journal in use (before the first is made, or once the last is removed) the game and
/// library are the ones from before there were several journals (build 1's keys and folder), on
/// screen behind the sheet that asks for a journal; runs then get no file.
@MainActor @Observable
final class AppModel {
    /// What the app keeps for the journal in use, handed to `onJournalChanged`.
    struct Context {
        let record: JournalRecord
        /// Where the journal is; nil when it can't be found just now (the missing alert is up).
        let folder: URL?
        let journal: PracticeJournal
        /// Takes the journal's runs; its `outbox` places them, and the library's events.
        let writer: RunFileWriter
        let game: Game
        let library: PieceLibrary
        let progressStore: ProgressStore
    }

    /// The device's own values in the defaults, whichever journal is in use.
    enum Keys {
        /// Set once the usage log so far has gone into a journal, so it goes into one only.
        static let usageLogBroughtIn = "usageLogBroughtIn"
    }

    /// The journals this Mac knows, and the one in use.
    let registry: JournalRegistry
    /// The journals' sheet and alerts on the main window.
    let setup: JournalSetup
    /// The journal in use's game: its settings, note stats and best scores.
    private(set) var game: Game
    /// The journal in use's piece library on this Mac.
    private(set) var library: PieceLibrary
    /// The Progress window's data for the journal in use.
    private(set) var progressStore: ProgressStore

    /// The run the last launch left unfinished (a crash, a force quit, the battery running out),
    /// found before this launch logged anything; nil when there was none. It belongs to the journal
    /// in use at launch: its working file stays open there, so this launch's lines, its
    /// `appLaunched` first, go on in it. `Game.restore` has brought the round back or ended it.
    @ObservationIgnored let pendingRun: PendingRun?
    /// Called after launch (`didFinishLaunching()`), after each switch, and when the journal in
    /// use is made or found again, with what the app now keeps for it; nil once no journal is in
    /// use. Does nothing until the app sets it.
    @ObservationIgnored var onJournalChanged: (Context?) -> Void = { _ in }
    /// The usage log's one line sink, which sends each run to the writer of the journal in use.
    @ObservationIgnored let router: JournalRunRouter
    /// Makes the game, library, store and writer for a journal.
    @ObservationIgnored let factory: Factory
    @ObservationIgnored let log: UsageLog
    @ObservationIgnored let defaults: UserDefaults
    /// Each journal's writer, made the first time it's used and kept: one outbox per `Pending`.
    @ObservationIgnored private var writers: [UUID: RunFileWriter] = [:]
    /// The journal the game, library and store are for; nil for none.
    @ObservationIgnored private var activeID: UUID?
    /// The latest bringing-in of the usage log, for tests to wait on.
    @ObservationIgnored private(set) var usageLogImport: Task<Void, Never>?
    @ObservationIgnored private var isBringingInUsageLog = false

    /// Everything at launch, in this order: build 1's journal brought over (`JournalMigration`);
    /// the journal in use's working file looked at (`RunFileWriting.inspectAtLaunch()`) and the
    /// router set as `log`'s line sink, both before anything is logged; the library; `appLaunched`
    /// logged; the game made (it reopens last time's piece), and the unfinished run restored; the
    /// progress store. `stateRoot` holds each journal's state folder (`JournalState`); `buildOne`
    /// is where build 1 kept its state; `device` and `launch` go in the journal's file headers.
    init(defaults: UserDefaults = .standard, log: UsageLog = .shared, stateRoot: URL = JournalState.root,
         buildOne: BuildOneFolders = .app, device: UUID, launch: AppLaunched) {
        let registry = JournalRegistry(defaults: defaults)
        // Before anything is logged: build 1's unfinished run moves with the rest.
        JournalMigration.migrateIfNeeded(registry, from: buildOne, stateRoot: stateRoot)
        let factory = Factory(defaults: defaults, log: log, registry: registry, stateRoot: stateRoot,
                              buildOne: buildOne, device: device, launch: launch)
        let record = registry.current
        let writer = record.map(factory.makeWriter(for:))
        // The journal's side first, before anything is logged: a run the last launch left
        // unfinished takes this launch's lines, from its `appLaunched` on.
        let pendingRun = writer?.inspectAtLaunch()
        let router = JournalRunRouter(target: writer)
        if let pendingRun, let writer { router.continueRun(pendingRun.round, in: writer) }
        log.lineSink = router
        // The library's changes go only to the journal, numbered in this session's order.
        let library = factory.makeLibrary(for: record, writer: writer)
        // Before the launch is logged, so it doesn't count as practice so far.
        setup = JournalSetup(registry: registry, usageFolder: log.folder, recorder: log)
        // Before the game exists, so the session's log starts with the launch: making the game
        // reopens last time's piece, which is logged too.
        log.record(.appLaunched(launch))
        let game = factory.makeGame(for: record, library: library)
        // A round the last launch left unfinished comes back paused, or ends as `interrupted`.
        if let pendingRun { game.restore(pendingRun) }
        self.registry = registry
        self.factory = factory
        self.log = log
        self.defaults = defaults
        self.router = router
        self.pendingRun = pendingRun
        self.library = library
        self.game = game
        progressStore = factory.makeStore(for: record)
        if let record, let writer { writers[record.id] = writer }
        activeID = record?.id
    }

    /// The journal in use; nil while there's none.
    var current: JournalRecord? {
        registry.current
    }

    /// "Clefwise — <journal>", or just "Clefwise" with no journal in use.
    var windowTitle: String {
        current.map { "Clefwise — \($0.name)" } ?? "Clefwise"
    }

    /// Journals change only between rounds: a run goes into the journal it started in.
    var canChangeJournal: Bool {
        game.phase != .playing
    }

    /// What the app keeps for the journal in use; nil while there's none.
    var context: Context? {
        guard let activeID, let record = registry.record(id: activeID), let writer = writers[activeID] else { return nil }
        return Context(record: record, folder: registry.folder(for: record), journal: registry.journal(for: record),
                       writer: writer, game: game, library: library, progressStore: progressStore)
    }

    /// Once the app has launched: `onJournalChanged` hears of the journal in use.
    func didFinishLaunching() {
        onJournalChanged(context)
    }

    // MARK: - Switching

    /// Makes `record` the journal in use, with a game, library and progress store of its own:
    /// logs `uiAction` `switchJournal` with `source`, the control used. Refused during a round
    /// (logged as `switchJournalRefused`): returns false, changing nothing.
    @discardableResult
    func switchJournal(to record: JournalRecord, from source: String) -> Bool {
        guard canChangeJournal else {
            log.recordUIAction("switchJournalRefused", detail: source)
            return false
        }
        guard record.id != activeID else { return true }
        log.recordUIAction("switchJournal", detail: source)
        activate(record)
        return true
    }

    /// File ▸ New Journal… and the start panel's: the sheet that makes a journal, which can be
    /// closed without one while there's a journal in use.
    func newJournal(from source: String) {
        guard canChangeJournal else { return }
        log.recordUIAction("newJournal", detail: source)
        setup.askToCreate(cancellable: current != nil)
    }

    /// The sheet's Cancel.
    func cancelNewJournal() {
        log.recordUIAction("createJournalCancelled")
        setup.isAskingToCreate = false
    }

    /// The sheet's Create or Use: makes the journal `name` in `parent`, or takes the one already
    /// there, and makes it the one in use. Everything that waited for it goes in, and if it's the
    /// first journal on this Mac, the usage log so far too (`bringInUsageLog(into:)`).
    func createJournal(named name: String, in parent: URL) throws {
        let existing = PracticeJournal.existingJournal(named: name, in: parent) != nil
        let record = try registry.create(named: name, in: parent)
        log.recordUIAction("createJournal", detail: existing ? "existing" : "new")
        setup.isAskingToCreate = false
        setup.isReportingMissing = false
        if record.id == activeID {
            journalFound(record)
        } else {
            activate(record)
        }
        bringInUsageLog(into: record)
    }

    /// File ▸ Open Journal… and the start panel's: a folder panel; the journal picked becomes the
    /// one in use. A folder that isn't a journal says so.
    func openJournal(from source: String) {
        guard canChangeJournal else { return }
        log.recordUIAction("openJournal", detail: source)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Clefwise journal: a folder with clefwise.json in it."
        panel.prompt = "Open Journal"
        Task {
            let response = if let window = NSApp.mainWindow { await panel.beginSheetModal(for: window) }
                           else { panel.runModal() }
            guard response == .OK, let chosen = panel.url else {
                log.recordUIAction("openJournalCancelled")
                return
            }
            do {
                try open(chosen)
            } catch {
                log.recordUIAction("openJournalRefused", detail: chosen.lastPathComponent)
                setup.notAJournal = chosen
            }
        }
    }

    /// Makes the journal in `folder` the one in use: added to the list, unless this Mac knows it
    /// already. Throws `JournalError.notAJournal` for a folder without `clefwise.json`. Returns nil,
    /// changing nothing, during a round.
    @discardableResult
    func open(_ folder: URL) throws -> JournalRecord? {
        guard canChangeJournal else { return nil }
        let listed = registry.record(at: folder) != nil
        let record = try registry.open(folder)
        log.recordUIAction("openedJournal", detail: listed ? "listed" : "added")
        if record.id == activeID {
            journalFound(record)
        } else {
            activate(record)
        }
        return record
    }

    /// The missing alert's Locate…: a folder panel; the folder picked becomes where the journal in
    /// use is, if it's that journal. Anything else, or cancelling, brings the alert back.
    func locateJournal() {
        log.recordUIAction("locateJournal")
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Find your Clefwise journal: the folder with clefwise.json in it."
        panel.prompt = "Use Journal"
        if let path = current?.path {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        Task {
            let response = if let window = NSApp.mainWindow { await panel.beginSheetModal(for: window) }
                           else { panel.runModal() }
            guard response == .OK, let chosen = panel.url else {
                log.recordUIAction("locateJournalCancelled")
                setup.reportMissingAgain()
                return
            }
            do {
                try relocate(to: chosen)
            } catch {
                setup.locateFailed(error.localizedDescription)
            }
        }
    }

    /// Keeps `folder`, found again by the user, as where the journal in use is; what waited for it
    /// goes in. Throws `JournalError.notAJournal` or `.listedAlready`, changing nothing.
    func relocate(to folder: URL) throws {
        guard let record = current else { return }
        try registry.relocate(record.id, to: folder)
        setup.locateError = nil
        journalFound(record)
    }

    /// File ▸ Show Journal in Finder and the start panel's. A journal gone since it was last
    /// found brings up the alert.
    func showJournalInFinder(from source: String) {
        log.recordUIAction("showJournal", detail: source)
        setup.lookAgain()
        guard let folder = setup.folder else {
            setup.isReportingMissing = current != nil
            return
        }
        NSWorkspace.shared.open(folder)
    }

    /// The start panel's Remove "<name>" from List…: asks first (`remove(_:)`).
    func askToRemove(_ record: JournalRecord) {
        guard canChangeJournal else { return }
        setup.removing = record
    }

    /// Takes `record` off this Mac's list (`JournalRegistry.remove(_:)`: its folder is never
    /// touched). If it was in use, the first left on the list takes its place, or with none left,
    /// the sheet asks for a new journal. Not during a round.
    func remove(_ record: JournalRecord) {
        guard canChangeJournal, registry.record(id: record.id) != nil else { return }
        log.recordUIAction("removeJournal")
        let wasInUse = record.id == activeID
        registry.remove(record.id)
        guard wasInUse else { return }
        if let next = registry.records.first {
            activate(next)
            return
        }
        // No journal left: runs get no file until a new one is made. The game stays on screen
        // behind the sheet.
        log.flush()
        router.retarget(to: nil)
        activeID = nil
        setup.lookAgain()
        // Once the question has gone: one presentation at a time.
        Task { setup.askToCreate(cancellable: false) }
        onJournalChanged(nil)
    }

    /// At quit: waits up to `timeout`, all told, for every journal's records to be in the journal
    /// or waiting in its `Pending` (what's left is placed at the next launch).
    func waitForJournals(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        for writer in writers.values {
            writer.outbox.waitUntilDone(timeout: max(0, deadline.timeIntervalSinceNow))
        }
    }

    /// Makes `record` the journal in use: its writer takes the next run, what waited for it goes
    /// in, and its library, game and progress store are made afresh.
    private func activate(_ record: JournalRecord) {
        // Never drops a round unseen (one brought back after a crash, its journal missing): it
        // ends, and its run goes to the journal it started in.
        if game.phase == .playing { game.stop() }
        registry.switchTo(record.id)
        // Lines logged before the switch go to the journal they belong to.
        log.flush()
        let writer = writer(for: record)
        router.retarget(to: writer)
        writer.outbox.placePending()
        library = factory.makeLibrary(for: record, writer: writer)
        game = factory.makeGame(for: record, library: library)
        progressStore = factory.makeStore(for: record)
        activeID = record.id
        setup.lookAgain(reportingMissing: true)
        onJournalChanged(context)
    }

    /// The journal in use was made, opened or located again: what waited for it goes in.
    private func journalFound(_ record: JournalRecord) {
        writer(for: record).outbox.placePending()
        setup.lookAgain(reportingMissing: true)
        onJournalChanged(context)
    }

    private func writer(for record: JournalRecord) -> RunFileWriter {
        if let writer = writers[record.id] { return writer }
        let writer = factory.makeWriter(for: record)
        writers[record.id] = writer
        return writer
    }

    // MARK: - The usage log so far

    /// Brings the usage log so far, with the pieces of the library from before there were several
    /// journals, into `record`'s journal, unless a journal on this Mac has it already
    /// (`Keys.usageLogBroughtIn`, set once it's in). This session is left out: its runs reach the
    /// journal through the writer. Runs off the main thread, then logs `uiAction`
    /// `broughtInUsageLog` with the counts, or why it failed (to be tried again with the next
    /// journal made).
    func bringInUsageLog(into record: JournalRecord) {
        guard defaults.object(forKey: Keys.usageLogBroughtIn) == nil, !isBringingInUsageLog else { return }
        isBringingInUsageLog = true
        let journal = registry.journal(for: record)
        let log = log, factory = factory
        usageLogImport = Task {
            let detail: String
            do {
                let summary = try await LogImport.bringIn(
                    usageLog: log.folder, pieceLibrary: factory.buildOne.library, device: factory.device,
                    launch: factory.launch, into: journal, skippingSession: log.session)
                defaults.set(true, forKey: Keys.usageLogBroughtIn)
                detail = "runs \(summary.runsWritten), already there \(summary.runsAlreadyPresent), "
                    + "pieces \(summary.piecesWritten), events \(summary.eventsWritten)"
            } catch {
                detail = "failed: \(error.localizedDescription)"
            }
            isBringingInUsageLog = false
            log.recordUIAction("broughtInUsageLog", detail: detail)
        }
    }
}

extension AppModel {
    /// Makes what the app keeps for a journal. Each is one call, to change in one place (a harness,
    /// or a progress store that reads the journal).
    @MainActor
    struct Factory {
        let defaults: UserDefaults
        let log: UsageLog
        let registry: JournalRegistry
        /// Holds each journal's state folder (`JournalState`).
        let stateRoot: URL
        let buildOne: BuildOneFolders
        /// For the journal's file headers.
        let device: UUID
        let launch: AppLaunched

        /// The writer of `record`'s runs, with its `Current` and `Pending` in the journal's state
        /// folder.
        func makeWriter(for record: JournalRecord) -> RunFileWriter {
            RunFileWriter(folder: JournalState.folder(for: record.id, in: stateRoot), journal: registry.journal(for: record),
                          device: device, launch: launch)
        }

        /// `record`'s piece library on this Mac, its changes going to the journal through `writer`'s
        /// outbox. With no journal, the library from before there were several, its changes going
        /// nowhere.
        func makeLibrary(for record: JournalRecord?, writer: RunFileWriter?) -> PieceLibrary {
            guard let record, let writer else { return PieceLibrary(folder: buildOne.library) }
            return PieceLibrary(folder: record.libraryURL(in: stateRoot),
                                journal: JournalEventRecorder(outbox: writer.outbox, device: device, launch: launch, log: log))
        }

        /// `record`'s game: its settings, note stats and best scores are under its namespace, so a
        /// journal new to this Mac starts from the default settings. With no journal, the keys
        /// from before there were several.
        func makeGame(for record: JournalRecord?, library: PieceLibrary) -> Game {
            Game(defaults: defaults, namespace: record?.defaultsNamespace ?? "", recorder: log, library: library)
        }

        /// The Progress window's data for `record`.
        func makeStore(for record: JournalRecord?) -> ProgressStore {
            ProgressStore(defaults: defaults, log: log)
        }
    }
}
