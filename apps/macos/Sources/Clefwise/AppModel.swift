import AppKit
import Observation

// The app across journals: the one in use and, for it, the game, the piece library and the
// progress store, all brought up to date as files arrive in it; switching to another between
// rounds. See spec/practice-journal.md, "Several journals" and "Folder sync".

/// What the app works on: the journals this Mac knows (`registry`) and, for the one in use, its
/// game, piece library and progress store, made afresh each time the journal in use changes. The
/// app delegate makes it at launch, before anything is logged, and keeps it for the app's life.
/// Views and menus read `game` and `library` from here and never keep one: a switch replaces both.
///
/// Every run's lines reach the journal in use through `router`, the usage log's one line sink,
/// and each journal has its own run-file writer, with its own `Current` and `Pending`.
///
/// The journal in use is read through one `JournalReader`, which the progress store, the game's
/// note stats, and the library's pieces share, so each file is read once between
/// them. From launch on it's watched (`JournalWatching`): whenever files arrive, from this Mac's
/// runs or through a sync service, all three are brought up to date (`readJournal()`).
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
        /// Reads the journal where it was last found (`folder`, or the record's path while it can't
        /// be found), for the progress store, the game's stats and the library's pieces.
        let reader: JournalReader
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
    /// The journal in use's game: its settings and note stats.
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
    /// use is made or found again (moved and found by its bookmark too), with what the app now
    /// keeps for it; nil once no journal is in use. By then the journal is watched and being read
    /// again. Does nothing until the app sets it.
    @ObservationIgnored var onJournalChanged: (Context?) -> Void = { _ in }
    /// Shows a folder in Finder, for Show Journal in Finder; tests put their own.
    @ObservationIgnored var revealInFinder: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// The usage log's one line sink, which sends each run to the writer of the journal in use.
    @ObservationIgnored let router: JournalRunRouter
    /// Makes the game, library, store, reader and writer for a journal, and has the watcher.
    @ObservationIgnored let factory: Factory
    @ObservationIgnored let log: UsageLog
    @ObservationIgnored let defaults: UserDefaults
    /// Each journal's writer, made the first time it's used and kept: one outbox per `Pending`.
    @ObservationIgnored private var writers: [UUID: RunFileWriter] = [:]
    /// The journal the game, library and store are for; nil for none.
    @ObservationIgnored private var activeID: UUID?
    /// Reads the journal in use where it was last found, for the store, the game and the library;
    /// nil while there's none.
    @ObservationIgnored private var reader: JournalReader?
    /// The bringing-in of the journal's pieces under way (`adoptPieces()`), if any.
    @ObservationIgnored private var pieceAdoption: Task<Void, Never>?
    /// The journal changed again while its pieces were being brought in: once more afterwards.
    @ObservationIgnored private var adoptsPiecesAgain = false
    /// The latest bringing-in of the usage log, for tests to wait on.
    @ObservationIgnored private(set) var usageLogImport: Task<Void, Never>?
    @ObservationIgnored private var isBringingInUsageLog = false

    /// Everything at launch, in this order: build 1's journal brought over (`JournalMigration`);
    /// the journal in use's working file looked at (`RunFileWriting.inspectAtLaunch()`) and the
    /// router set as `log`'s line sink, both before anything is logged; the library; `appLaunched`
    /// logged; the game made (it reopens last time's piece), and the unfinished run restored; the
    /// journal's reader and the progress store. Nothing is read or watched until
    /// `didFinishLaunching()`. `stateRoot` holds each journal's state folder (`JournalState`);
    /// `buildOne` is where build 1 kept its state; `device` and `launch` go in the journal's file
    /// headers; `watcher` watches the journal in use (tests pass a fake).
    init(defaults: UserDefaults = .standard, log: UsageLog = .shared, stateRoot: URL = JournalState.root,
         buildOne: BuildOneFolders = .app, device: UUID, launch: AppLaunched,
         watcher: JournalWatching = FSEventsJournalWatcher()) {
        let registry = JournalRegistry(defaults: defaults)
        // Before anything is logged: build 1's unfinished run moves with the rest.
        JournalMigration.migrateIfNeeded(registry, from: buildOne, stateRoot: stateRoot)
        let factory = Factory(defaults: defaults, log: log, registry: registry, stateRoot: stateRoot,
                              buildOne: buildOne, device: device, launch: launch, watcher: watcher)
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
        let game = factory.makeGame(for: record, library: library, reopeningVia: .launch)
        // A round the last launch left unfinished comes back paused, or ends as `interrupted`.
        if let pendingRun { game.restore(pendingRun) }
        let reader = record.map(factory.makeReader(for:))
        self.registry = registry
        self.factory = factory
        self.log = log
        self.defaults = defaults
        self.router = router
        self.pendingRun = pendingRun
        self.library = library
        self.game = game
        self.reader = reader
        progressStore = factory.makeStore(for: reader)
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

    /// Show Journal in Finder works whenever the journal in use was found when last looked for, a
    /// round playing or not: it leaves the game alone.
    var canShowJournal: Bool {
        setup.folder != nil
    }

    /// What the app keeps for the journal in use; nil while there's none.
    var context: Context? {
        guard let activeID, let record = registry.record(id: activeID), let writer = writers[activeID],
              let reader else { return nil }
        return Context(record: record, folder: registry.folder(for: record), journal: registry.journal(for: record),
                       writer: writer, reader: reader, game: game, library: library, progressStore: progressStore)
    }

    /// Once the app has launched: the journal in use is watched and read (`journalInUseChanged()`),
    /// and `onJournalChanged` hears of it.
    func didFinishLaunching() {
        journalInUseChanged()
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

    /// File ▸ Show Journal in Finder and the start panel's; also mid-round, as it leaves the game
    /// alone (`canShowJournal`). A journal gone since it was last found brings up the alert.
    func showJournalInFinder(from source: String) {
        log.recordUIAction("showJournal", detail: source)
        setup.lookAgain()
        guard let folder = setup.folder else {
            setup.isReportingMissing = current != nil
            return
        }
        revealInFinder(folder)
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
        // No journal left: runs get no file until a new one is made, and nothing is watched. The
        // game stays on screen behind the sheet.
        log.flush()
        router.retarget(to: nil)
        activeID = nil
        reader = nil
        setup.lookAgain()
        // Once the question has gone: one presentation at a time.
        Task { setup.askToCreate(cancellable: false) }
        journalInUseChanged()
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
    /// in, its library, game, reader and progress store are made afresh, and it's watched and read.
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
        game = factory.makeGame(for: record, library: library, reopeningVia: .journalSwitch)
        reader = factory.makeReader(for: record)
        progressStore = factory.makeStore(for: reader)
        activeID = record.id
        setup.lookAgain(reportingMissing: true)
        journalInUseChanged()
    }

    /// The journal in use was made, opened or located again: what waited for it goes in, and it's
    /// watched and read where it is now.
    private func journalFound(_ record: JournalRecord) {
        writer(for: record).outbox.placePending()
        setup.lookAgain(reportingMissing: true)
        journalInUseChanged()
    }

    private func writer(for record: JournalRecord) -> RunFileWriter {
        if let writer = writers[record.id] { return writer }
        let writer = factory.makeWriter(for: record)
        writers[record.id] = writer
        return writer
    }

    // MARK: - Watching and reading the journal

    /// True while the journal's pieces are being brought into the library (`adoptPieces()`), more
    /// asked for meanwhile included.
    var isAdoptingPieces: Bool {
        pieceAdoption != nil
    }

    /// From launch on, after each switch, and when the journal in use is made or found again: the
    /// journal is watched where it is now (one folder at a time, so the last one watched no longer
    /// is), and read (`readJournal()`); then `onJournalChanged` hears of it. With no journal in
    /// use, nothing is watched.
    private func journalInUseChanged() {
        if let record = activeID.flatMap(registry.record(id:)) {
            let reader = follow(record)
            factory.watcher.start(watching: reader.folder) { [weak self] in self?.journalDidChange() }
            readJournal()
        } else {
            factory.watcher.stop()
        }
        onJournalChanged(context)
    }

    /// The reader of `record`'s journal, the one in use, where the journal is now: the reader there
    /// is, or when the journal is now somewhere else (found elsewhere with Locate…, or moved and
    /// found by its bookmark), a new one, with a progress store reading through it. The game and
    /// library stay: they don't read the folder themselves.
    private func follow(_ record: JournalRecord) -> JournalReader {
        if let reader, PracticeJournal.isSameFolder(reader.folder, factory.folder(for: record)) { return reader }
        let reader = factory.makeReader(for: record)
        self.reader = reader
        progressStore = factory.makeStore(for: reader)
        return reader
    }

    /// The watcher saw something change in the journal in use: files arriving (this Mac's runs and
    /// pieces, or another device's through a sync service), or the folder itself appearing, going
    /// or moving. Looks for the journal again, so Show Journal in Finder is up to date. One moved
    /// and found by its bookmark is watched and read where it is now; otherwise it's read again.
    private func journalDidChange() {
        guard let record = activeID.flatMap(registry.record(id:)), let watched = reader else { return }
        setup.lookAgain()
        if follow(record) !== watched {
            journalInUseChanged()
        } else {
            readJournal()
        }
    }

    /// Brings the dashboard, the game's note stats, and the library's pieces up to
    /// date with the journal in use, all through its one reader, each off the main thread: the
    /// progress store reloads, the game refreshes (`Game.refreshStats(from:)`, which never takes
    /// them mid-round or without its own latest rounds), and the pieces are adopted
    /// (`adoptPieces()`). Not while the journal can't be found: reading nothing there would take
    /// the note stats and the dashboard away until it's back.
    private func readJournal() {
        guard let reader, setup.folder != nil else { return }
        progressStore.reload()
        game.refreshStats(from: reader)
        adoptPieces()
    }

    /// Brings the journal's pieces into the library in use (`PieceLibrary.adopt(from:journalFolder:)`):
    /// reads the journal off the main thread, then adopts here. One at a time, so an older read
    /// never lands after a newer one: asked for meanwhile, it runs once more afterwards. A read that
    /// finishes after a switch, or after the journal was found elsewhere, is dropped: it's for the
    /// library or folder before.
    private func adoptPieces() {
        guard pieceAdoption == nil else {
            adoptsPiecesAgain = true
            return
        }
        guard let reader else { return }
        let library = library
        pieceAdoption = Task { [weak self] in
            let contents = await Task.detached(priority: .utility) { reader.read() }.value
            guard let self else { return }
            if library === self.library, reader === self.reader {
                library.adopt(from: contents, journalFolder: reader.folder)
            }
            pieceAdoption = nil
            if adoptsPiecesAgain {
                adoptsPiecesAgain = false
                adoptPieces()
            }
        }
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
    /// Makes what the app keeps for a journal, and has the one watcher, moved from journal to
    /// journal. Each is one call, to change in one place (a harness, or a test).
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
        /// Watches the journal in use, one folder at a time: `FSEventsJournalWatcher` in the app,
        /// a fake in tests.
        let watcher: JournalWatching

        /// Where `record`'s journal is read and watched: where it's found now, or while it can't be
        /// found, its path, where the watcher sees it come back.
        func folder(for record: JournalRecord) -> URL {
            registry.folder(for: record) ?? URL(fileURLWithPath: record.path, isDirectory: true)
        }

        /// Reads `record`'s journal in `folder(for:)`, for its progress store, game and library.
        /// It keeps every file it has read, so it's made once for the journal while in use.
        func makeReader(for record: JournalRecord) -> JournalReader {
            JournalReader(folder: folder(for: record))
        }

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

        /// `record`'s game: its settings and note stats are under its namespace, so a
        /// journal new to this Mac starts from the default settings. With no journal, the keys
        /// from before there were several. The piece it reopens is logged with `reopeningVia`.
        func makeGame(for record: JournalRecord?, library: PieceLibrary, reopeningVia source: PieceOpenSource) -> Game {
            Game(defaults: defaults, namespace: record?.defaultsNamespace ?? "", recorder: log, library: library,
                 reopeningVia: source)
        }

        /// The Progress window's data, from the journal `reader` reads; every report is empty with
        /// no reader (no journal).
        func makeStore(for reader: JournalReader?) -> ProgressStore {
            ProgressStore(reader: reader, defaults: defaults, log: log)
        }
    }
}
