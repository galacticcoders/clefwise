import Foundation
import Testing
@testable import Clefwise

/// Stands in for the FSEvents watcher: says what it watches, and calls back when a test says files
/// changed (`fire()`), as the real one does once the folder has been quiet.
final class FakeJournalWatcher: JournalWatching {
    /// The folder watched now; nil when none is.
    private(set) var folder: URL?
    /// Every folder watched, in order.
    private(set) var started: [URL] = []
    /// How many watches have ended, by `stop()` or by starting another.
    private(set) var stopped = 0
    private var onChange: (@MainActor @Sendable () -> Void)?

    func start(watching folder: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        stop()
        self.folder = folder
        started.append(folder)
        self.onChange = onChange
    }

    func stop() {
        guard folder != nil else { return }
        folder = nil
        onChange = nil
        stopped += 1
    }

    /// Files changed in the folder watched.
    @MainActor func fire() {
        onChange?()
    }

    /// Whether `journal` is the folder watched now.
    func isWatching(_ journal: URL) -> Bool {
        folder.map { PracticeJournal.isSameFolder($0, journal) } ?? false
    }
}

/// An app model launched on folders and defaults of its own: never the real ones.
@MainActor
final class AppModelTestBench {
    let temporary = UsageTestFolder()
    let defaults = InMemoryDefaults()
    /// The watcher of the app model launched last: a fake, so nothing watches real folders.
    private(set) var watcher = FakeJournalWatcher()

    var usageFolder: URL { temporary.url.appendingPathComponent("Usage", isDirectory: true) }
    var stateRoot: URL { temporary.url.appendingPathComponent("Clefwise/Journals", isDirectory: true) }
    var buildOne: BuildOneFolders {
        let state = temporary.url.appendingPathComponent("Clefwise", isDirectory: true)
        return BuildOneFolders(state: state, library: state.appendingPathComponent("Pieces", isDirectory: true))
    }
    /// Where journals are made.
    var documents: URL { temporary.url.appendingPathComponent("Documents", isDirectory: true) }

    /// `bringsInUsageLog`: the first journal made brings in the usage log so far. Off by default,
    /// so only the tests about it read the log in the background.
    init(bringsInUsageLog: Bool = false) throws {
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        if !bringsInUsageLog { defaults.set(true, forKey: AppModel.Keys.usageLogBroughtIn) }
    }

    /// The app launching (again) on this bench's defaults and folders, with its own session and a
    /// watcher of its own (`watcher`).
    func launch() -> AppModel {
        watcher = FakeJournalWatcher()
        return AppModel(defaults: defaults, log: UsageLog(folder: usageFolder), stateRoot: stateRoot, buildOne: buildOne,
                        device: JournalFixture.device, launch: JournalFixture.launch, watcher: watcher)
    }

    /// Makes the journal `name` in `documents` with the sheet's button, and returns it.
    @discardableResult
    func makeJournal(_ name: String, in model: AppModel) throws -> JournalRecord {
        try model.createJournal(named: name, in: documents)
        return try #require(model.current)
    }

    /// Logs a run's events through the app's log: started, answered and, unless `ends` is false, ended.
    func logRun(_ round: UUID, in model: AppModel, ends: Bool = true) {
        model.log.record(JournalFixture.started(round))
        model.log.record(JournalFixture.answer(round))
        if ends { model.log.record(JournalFixture.ended(round)) }
    }

    /// Waits until everything logged is written and every record is placed or waiting.
    func settle(_ model: AppModel) {
        model.log.flush()
        model.waitForJournals(timeout: 5)
    }

    /// The run files in `folder` (a journal, or a `Pending` laid out as one).
    func runs(in folder: URL) -> [String] {
        JournalTestBench.files(in: folder).filter { $0.hasPrefix("runs/") }
    }

    /// The `uiAction`s logged so far, as "name detail".
    func actions(_ model: AppModel) -> [String] {
        model.log.flush()
        return UsageLog.readEvents(in: usageFolder).events.compactMap {
            guard case .uiAction(let action) = $0.event else { return nil }
            return [action.name, action.detail].compactMap { $0 }.joined(separator: " ")
        }
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Waits until the journal in use has been read into the dashboard, the game's stats and the
    /// library.
    func waitForReading(_ model: AppModel) async throws {
        try await waitUntil { !model.progressStore.isLoading && !model.game.isRefreshingStats && !model.isAdoptingPieces }
    }

    /// Another Mac's practice arriving in the journal in `folder`, as a sync service brings it: a
    /// minute's round on the default settings in which `score` E4s were named right, and the piece
    /// `title` added there, with its score. Returns the piece's id (its score's hash).
    @discardableResult
    func practiseElsewhere(in folder: URL, scoring score: Int, piece title: String) throws -> String {
        let start = Date(timeIntervalSinceNow: -600)
        var log = Log()
        let round = log.round(at: start)
        for index in 0..<score { log.answer(round, at: start.addingTimeInterval(Double(index + 1)), Pitch(.e, 4)) }
        log.end(round, at: start.addingTimeInterval(60), durationMs: 60_000, score: score, attempts: score, reason: .timeUp)
        let file = JournalPieceFile(data: Data("<score-partwise>\(title)</score-partwise>".utf8), fileExtension: "musicxml")
        let url = folder.appendingPathComponent(JournalLayout.piecePath(hash: file.hash, fileExtension: "musicxml"))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.data.write(to: url)
        log.add(.pieceAdded(PieceAdded(piece: file.hash, title: title, fileName: "\(title).musicxml", libraryID: UUID(),
                                       originalPath: "/Scores/\(title).musicxml")), at: start)
        try TestJournal(folder: folder).write(log.events, device: UUID())
        return file.hash
    }

    /// The note stats `record`'s game keeps, as saved.
    func noteStats(of record: JournalRecord) -> [String: NoteStat]? {
        defaults.data(forKey: Game.key(Game.Keys.noteStats, in: record.defaultsNamespace))
            .flatMap { try? JSONDecoder().decode([String: NoteStat].self, from: $0) }
    }

    /// The answers to E4, the note `practiseElsewhere` asks, that `record`'s game has counted, as
    /// saved; nil before any.
    func answersToE4(of record: JournalRecord) -> Int? {
        noteStats(of: record)?["treble.E4"]?.attempts
    }

    /// How each piece opened so far was opened (`pieceOpened`'s `via`), in order.
    func piecesOpened(_ model: AppModel) -> [PieceOpenSource] {
        model.log.flush()
        return UsageLog.readEvents(in: usageFolder).events.compactMap {
            guard case .pieceOpened(let opened) = $0.event else { return nil }
            return opened.via
        }
    }

    /// `settings` as JSON, to compare.
    static func encoded(_ settings: Game.Settings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(settings)
    }
}

@MainActor
@Suite struct AppModelTests {
    private let bench: AppModelTestBench

    init() throws {
        bench = try AppModelTestBench()
    }

    // MARK: - The first journal

    @Test func atFirstLaunchItAsksForAJournal() throws {
        let model = bench.launch()
        #expect(model.current == nil && model.windowTitle == "Clefwise")
        // Behind the sheet, the game and library from before there were several journals.
        #expect(model.game.namespace == "" && model.library.folder == bench.buildOne.library)
        #expect(model.router.writer == nil)
        model.setup.checkAtLaunch()
        #expect(model.setup.isAskingToCreate && !model.setup.canCancelCreate && !model.setup.isReportingMissing)
    }

    @Test func theFirstJournalMadeIsPutInUse() throws {
        let model = bench.launch()
        var changes: [UUID?] = []
        model.onJournalChanged = { changes.append($0?.record.id) }
        model.setup.checkAtLaunch()
        let anna = try bench.makeJournal("Anna", in: model)
        let folder = bench.documents.appendingPathComponent("Anna", isDirectory: true)
        #expect(anna.name == "Anna" && PracticeJournal.isJournal(folder))
        #expect(model.windowTitle == "Clefwise — Anna")
        #expect(model.game.namespace == anna.defaultsNamespace)
        #expect(model.library.folder == JournalState.library(for: anna.id, in: bench.stateRoot))
        #expect(model.router.writer?.folder == JournalState.folder(for: anna.id, in: bench.stateRoot))
        #expect(!model.setup.isAskingToCreate && model.setup.folder == folder)
        #expect(changes == [anna.id])
        #expect(model.context?.folder == folder && model.context?.game === model.game)
        #expect(bench.actions(model).contains("createJournal new"))
    }

    @Test func launchingTellsTheHookAboutTheJournalInUse() throws {
        let anna = try bench.makeJournal("Anna", in: bench.launch())
        let model = bench.launch()
        var changes: [UUID?] = []
        model.onJournalChanged = { changes.append($0?.record.id) }
        model.didFinishLaunching()
        #expect(changes == [anna.id] && model.current == anna && model.windowTitle == "Clefwise — Anna")
    }

    // MARK: - Switching

    @Test func switchingMakesAGameOfThatJournal() throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        let annasGame = model.game, annasLibrary = model.library, annasStore = model.progressStore
        let ben = try bench.makeJournal("Ben", in: model)
        #expect(model.game !== annasGame && model.library !== annasLibrary && model.progressStore !== annasStore)
        #expect(model.game.namespace == ben.defaultsNamespace && model.game.library === model.library)

        #expect(model.switchJournal(to: anna, from: "test"))
        #expect(model.current == anna && model.windowTitle == "Clefwise — Anna")
        #expect(model.game.namespace == anna.defaultsNamespace)
        #expect(model.library.folder == JournalState.library(for: anna.id, in: bench.stateRoot))
        #expect(bench.actions(model).contains("switchJournal test"))
        // Kept for the next launch.
        #expect(bench.launch().current == anna)
    }

    @Test func aNewJournalStartsWithTheDefaultSettings() throws {
        let model = bench.launch()
        try bench.makeJournal("Anna", in: model)
        model.game.settings.clefChoice = .bass
        model.game.settings.naming = .solfege
        model.newJournal(from: "test")
        #expect(model.setup.isAskingToCreate && model.setup.canCancelCreate)
        try bench.makeJournal("Ben", in: model)
        #expect(try AppModelTestBench.encoded(model.game.settings) == AppModelTestBench.encoded(Game.Settings()))
    }

    @Test func settingsAndStatsStayWithTheirJournal() throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        model.game.settings.isMuted = true
        model.game.settings.clefChoice = .bass
        model.game.start()
        for _ in 0..<3 {
            let pitch = try #require(model.game.question?.pitch)
            model.game.answer(pitch)
        }
        model.game.stop()
        let ben = try bench.makeJournal("Ben", in: model)
        #expect(model.game.settings.clefChoice == .treble)
        let defaults = bench.defaults
        #expect(defaults.object(forKey: Game.key(Game.Keys.noteStats, in: anna.defaultsNamespace)) != nil)
        #expect(defaults.object(forKey: Game.key(Game.Keys.noteStats, in: ben.defaultsNamespace)) == nil)
        model.game.settings.clefChoice = .both

        model.switchJournal(to: anna, from: "test")
        #expect(model.game.settings.clefChoice == .bass)
        model.switchJournal(to: ben, from: "test")
        #expect(model.game.settings.clefChoice == .both)
        // Nothing went under the keys from before there were several journals.
        #expect(defaults.object(forKey: Game.Keys.settings) == nil && defaults.object(forKey: Game.Keys.noteStats) == nil)
    }

    @Test func switchingWaitsForTheRoundToEnd() throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        let ben = try bench.makeJournal("Ben", in: model)
        let game = model.game
        game.settings.isMuted = true
        game.start()
        #expect(!model.canChangeJournal)
        #expect(!model.switchJournal(to: anna, from: "test"))
        #expect(model.current == ben && model.game === game)
        model.newJournal(from: "test")
        #expect(!model.setup.isAskingToCreate)
        let elsewhere = try PracticeJournal(defaults: InMemoryDefaults()).create(named: "Family", in: bench.documents)
        #expect(try model.open(elsewhere) == nil && model.registry.records.count == 2)
        model.askToRemove(ben)
        #expect(model.setup.removing == nil)

        game.stop()
        #expect(model.switchJournal(to: anna, from: "test") && model.current == anna)
        let actions = bench.actions(model)
        #expect(actions.contains("switchJournalRefused test") && actions.contains("switchJournal test"))
    }

    // MARK: - Runs

    @Test func aRunGoesToTheJournalItStartedIn() throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        let ben = try bench.makeJournal("Ben", in: model)
        model.switchJournal(to: anna, from: "test")
        let first = UUID(), second = UUID()
        bench.logRun(first, in: model, ends: false)
        // The journal changes before the run ends (the app's controls wait for the end).
        model.switchJournal(to: ben, from: "test")
        model.log.record(JournalFixture.ended(first))
        bench.logRun(second, in: model)
        bench.settle(model)

        let annasRuns = bench.runs(in: URL(fileURLWithPath: anna.path))
        let bensRuns = bench.runs(in: URL(fileURLWithPath: ben.path))
        #expect(annasRuns.count == 1 && annasRuns[0].contains(first.uuidString.lowercased()))
        #expect(bensRuns.count == 1 && bensRuns[0].contains(second.uuidString.lowercased()))
    }

    @Test func aFinishedRunLandsInTheJournalSwitchedTo() throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        let ben = try bench.makeJournal("Ben", in: model)
        model.switchJournal(to: anna, from: "test")
        model.game.settings.isMuted = true
        model.game.start()
        for _ in 0..<2 {
            let pitch = try #require(model.game.question?.pitch)
            model.game.answer(pitch)
        }
        model.game.stop()
        bench.settle(model)
        #expect(bench.runs(in: URL(fileURLWithPath: anna.path)).count == 1)
        #expect(bench.runs(in: URL(fileURLWithPath: ben.path)).isEmpty)
    }

    @Test func eachJournalKeepsItsOwnWorkingFileAndWaitingRuns() throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        let folder = URL(fileURLWithPath: anna.path, isDirectory: true)
        try FileManager.default.removeItem(at: folder)
        let round = UUID()
        bench.logRun(round, in: model, ends: false)
        model.log.flush()
        #expect(JournalTestBench.files(in: JournalState.current(for: anna.id, in: bench.stateRoot))
                == ["\(round.uuidString.lowercased()).jsonl"])
        model.log.record(JournalFixture.ended(round))
        bench.settle(model)
        // The journal can't be found: the run waits in its own Pending.
        #expect(bench.runs(in: JournalState.pending(for: anna.id, in: bench.stateRoot)).count == 1)
        #expect(JournalTestBench.files(in: JournalState.current(for: anna.id, in: bench.stateRoot)).isEmpty)

        let ben = try bench.makeJournal("Ben", in: model)
        bench.settle(model)
        #expect(JournalTestBench.files(in: JournalState.folder(for: ben.id, in: bench.stateRoot)).isEmpty)
        #expect(bench.runs(in: URL(fileURLWithPath: ben.path)).isEmpty)

        // Found again (Locate…): what waited goes in.
        model.switchJournal(to: anna, from: "test")
        try FileManager.default.createDirectory(at: bench.temporary.url.appendingPathComponent("Back"), withIntermediateDirectories: true)
        let back = try PracticeJournal(defaults: InMemoryDefaults()).create(named: "Anna", in: bench.temporary.url.appendingPathComponent("Back"))
        try model.relocate(to: back)
        bench.settle(model)
        #expect(bench.runs(in: back).count == 1)
        #expect(bench.runs(in: JournalState.pending(for: anna.id, in: bench.stateRoot)).isEmpty)
    }

    @Test func aRunLeftUnfinishedBelongsToTheJournalInUseAtLaunch() throws {
        let first = bench.launch()
        let anna = try bench.makeJournal("Anna", in: first)
        let ben = try bench.makeJournal("Ben", in: first)
        first.switchJournal(to: anna, from: "test")
        bench.settle(first)
        // The app stopped mid-round, with the round's working file in Anna's state.
        let round = UUID()
        let run = try JournalFixture.runFile(round, [JournalFixture.started(round), JournalFixture.answer(round)],
                                             start: Date().addingTimeInterval(-60))
        let current = JournalState.current(for: anna.id, in: bench.stateRoot)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try run.data.write(to: current.appendingPathComponent("\(round.uuidString.lowercased()).jsonl"))

        let model = bench.launch()
        #expect(model.current == anna && model.pendingRun?.round == round)
        bench.settle(model)
        #expect(JournalTestBench.files(in: JournalState.folder(for: ben.id, in: bench.stateRoot)).isEmpty)
        // This launch's lines went on in it, wherever the round is now: still going, or ended.
        let file = JournalTestBench.files(in: current).first.map { current.appendingPathComponent($0) }
            ?? bench.runs(in: URL(fileURLWithPath: anna.path)).first.map { URL(fileURLWithPath: anna.path).appendingPathComponent($0) }
        let events = RunFile.read(try #require(file)).events
        #expect(events.contains { if case .appLaunched = $0.event { true } else { false } })
    }

    // MARK: - The usage log so far

    @Test func theUsageLogGoesIntoTheFirstJournalOnly() async throws {
        let bench = try AppModelTestBench(bringsInUsageLog: true)
        // Practice before there was a journal, in an earlier session.
        let earlier = UsageLog(folder: bench.usageFolder)
        let round = UUID()
        earlier.record(JournalFixture.started(round))
        earlier.record(JournalFixture.answer(round))
        earlier.record(JournalFixture.ended(round))
        earlier.flush()

        let model = bench.launch()
        #expect(model.setup.bringsInPractice)
        let anna = try bench.makeJournal("Anna", in: model)
        await model.usageLogImport?.value
        let imported = model.usageLogImport
        #expect(bench.runs(in: URL(fileURLWithPath: anna.path)).count == 1)
        #expect(bench.defaults.object(forKey: AppModel.Keys.usageLogBroughtIn) as? Bool == true)
        #expect(!model.setup.bringsInPractice)
        #expect(bench.actions(model).contains { $0.hasPrefix("broughtInUsageLog runs 1") })

        let ben = try bench.makeJournal("Ben", in: model)
        #expect(model.usageLogImport == imported, "nothing more is brought in")
        bench.settle(model)
        #expect(bench.runs(in: URL(fileURLWithPath: ben.path)).isEmpty)
    }

    // MARK: - Opening, finding and removing

    @Test func openingTakesOnlyAJournal() throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        #expect(throws: JournalError.notAJournal(bench.documents)) { try model.open(bench.documents) }
        #expect(model.current == anna && model.registry.records.count == 1)

        let elsewhere = bench.temporary.url.appendingPathComponent("Shared", isDirectory: true)
        let family = try PracticeJournal(defaults: InMemoryDefaults()).create(named: "Family", in: elsewhere)
        let opened = try #require(try model.open(family))
        #expect(model.current == opened && opened.name == "Family" && model.game.namespace == opened.defaultsNamespace)
        #expect(bench.actions(model).contains("openedJournal added"))
    }

    @Test func aJournalThatCannotBeFoundIsReported() throws {
        let first = bench.launch()
        let anna = try bench.makeJournal("Anna", in: first)
        let ben = try bench.makeJournal("Ben", in: first)
        first.switchJournal(to: anna, from: "test")
        try FileManager.default.removeItem(at: URL(fileURLWithPath: anna.path))

        let model = bench.launch()
        model.setup.checkAtLaunch()
        #expect(model.setup.isReportingMissing && !model.setup.isAskingToCreate && model.setup.folder == nil)
        #expect(model.setup.missingPath == (anna.path as NSString).abbreviatingWithTildeInPath)
        #expect(model.setup.others == [ben])
        // The alert's Switch to "Ben".
        #expect(model.switchJournal(to: ben, from: "missingAlert"))
        #expect(model.current == ben && model.setup.folder?.path == URL(fileURLWithPath: ben.path).path)
    }

    @Test func removingTheJournalInUseSwitchesToAnotherOrAsksForOne() async throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        let ben = try bench.makeJournal("Ben", in: model)
        var changes: [UUID?] = []
        model.onJournalChanged = { changes.append($0?.record.id) }

        model.askToRemove(ben)
        #expect(model.setup.removing == ben)
        model.remove(ben)
        #expect(model.current == anna && model.game.namespace == anna.defaultsNamespace)
        #expect(PracticeJournal.isJournal(URL(fileURLWithPath: ben.path)), "its folder stays")

        model.remove(anna)
        #expect(model.current == nil && model.registry.records.isEmpty && model.router.writer == nil)
        #expect(model.windowTitle == "Clefwise")
        try await bench.waitUntil { model.setup.isAskingToCreate }
        #expect(model.setup.isAskingToCreate && !model.setup.canCancelCreate)
        #expect(changes == [anna.id, nil])
        #expect(bench.actions(model).filter { $0 == "removeJournal" }.count == 2)
    }

    @Test func showJournalInFinderWorksMidRound() throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        let folder = URL(fileURLWithPath: anna.path, isDirectory: true)
        var shown: [URL] = []
        model.revealInFinder = { shown.append($0) }
        model.game.settings.isMuted = true
        model.game.start()
        #expect(!model.canChangeJournal && model.canShowJournal)
        model.showJournalInFinder(from: "fileMenu")
        #expect(shown.count == 1 && shown.allSatisfy { PracticeJournal.isSameFolder($0, folder) })
        #expect(model.game.phase == .playing && !model.setup.isReportingMissing)
        #expect(bench.actions(model).contains("showJournal fileMenu"))

        // Greyed out only while the journal can't be found.
        model.game.stop()
        try FileManager.default.removeItem(at: folder)
        model.setup.lookAgain()
        #expect(!model.canShowJournal)
    }

    // MARK: - A piece reopened by a switch

    @Test func switchingBackReopensTheJournalsPieceAsASwitch() throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        let scores = bench.temporary.url.appendingPathComponent("Scores", isDirectory: true)
        try FileManager.default.createDirectory(at: scores, withIntermediateDirectories: true)
        let tune = scores.appendingPathComponent("clarinet-tune.musicxml")
        try FileManager.default.copyItem(at: try #require(Fixtures.url("clarinet-tune.musicxml")), to: tune)
        model.game.openPiece(at: tune)
        #expect(model.game.isPractisingPiece)

        try bench.makeJournal("Ben", in: model)
        #expect(!model.game.isPractisingPiece)
        model.switchJournal(to: anna, from: "test")
        #expect(model.game.isPractisingPiece)
        #expect(bench.piecesOpened(model) == [.menu, .journalSwitch])
    }

    // MARK: - Watching the journal

    @Test func launchingWatchesAndReadsTheJournalInUse() async throws {
        let anna = try bench.makeJournal("Anna", in: bench.launch())
        let folder = URL(fileURLWithPath: anna.path, isDirectory: true)
        let piece = try bench.practiseElsewhere(in: folder, scoring: 6, piece: "Gymnopédie")

        let model = bench.launch()
        #expect(bench.watcher.folder == nil, "nothing is watched until the app has launched")
        model.didFinishLaunching()
        #expect(bench.watcher.isWatching(folder))
        #expect(model.context.map { PracticeJournal.isSameFolder($0.reader.folder, folder) } == true)
        // Read once straight away, without waiting for a change.
        try await bench.waitForReading(model)
        #expect(model.progressStore.report.totals.answers == 6)
        #expect(bench.answersToE4(of: anna) == 6 && bench.noteStats(of: anna) == JournalProjection.read(journal: folder).noteStats)
        #expect(model.library.entries.map(\.pieceID) == [piece])
    }

    @Test func filesArrivingAreReadIntoTheDashboardTheStatsAndTheLibrary() async throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        let folder = URL(fileURLWithPath: anna.path, isDirectory: true)
        #expect(bench.watcher.isWatching(folder))
        // Made, the journal is read once straight away: there's nothing in it yet.
        try await bench.waitForReading(model)
        #expect(model.progressStore.hasLoaded && model.progressStore.report.isEmpty)

        // Another Mac's round and piece arrive through the sync service: read once the watcher
        // says files changed.
        let piece = try bench.practiseElsewhere(in: folder, scoring: 7, piece: "Gymnopédie")
        #expect(model.library.isEmpty && bench.answersToE4(of: anna) == nil)
        bench.watcher.fire()
        #expect(model.progressStore.isLoading && model.game.isRefreshingStats && model.isAdoptingPieces)
        try await bench.waitForReading(model)

        #expect(model.progressStore.report.totals.answers == 7 && model.progressStore.report.totals.rounds == 1)
        #expect(bench.answersToE4(of: anna) == 7)
        let stats = bench.noteStats(of: anna)
        #expect(stats == JournalProjection.read(journal: folder).noteStats && stats?.isEmpty == false)
        let entry = try #require(model.library.entries.first)
        #expect(model.library.entries.count == 1 && entry.pieceID == piece && entry.title == "Gymnopédie")
        #expect(PieceLibrary(folder: model.library.folder).entries.map(\.pieceID) == [piece])
    }

    @Test func switchingMovesTheWatchToTheJournalSwitchedTo() async throws {
        let model = bench.launch()
        let watcher = bench.watcher
        let anna = try bench.makeJournal("Anna", in: model)
        let ben = try bench.makeJournal("Ben", in: model)
        let annasFolder = URL(fileURLWithPath: anna.path, isDirectory: true)
        let bensFolder = URL(fileURLWithPath: ben.path, isDirectory: true)
        #expect(watcher.isWatching(bensFolder) && watcher.started.count == 2 && watcher.stopped == 1)

        #expect(model.switchJournal(to: anna, from: "test"))
        #expect(watcher.isWatching(annasFolder) && watcher.started.count == 3 && watcher.stopped == 2)
        let context = try #require(model.context)
        #expect(PracticeJournal.isSameFolder(context.reader.folder, annasFolder))

        // What arrives in Anna's journal goes to her game, library and dashboard.
        try await bench.waitForReading(model)
        let piece = try bench.practiseElsewhere(in: annasFolder, scoring: 4, piece: "Arabesque")
        watcher.fire()
        try await bench.waitForReading(model)
        #expect(bench.answersToE4(of: anna) == 4 && model.library.entries.map(\.pieceID) == [piece])
        #expect(model.progressStore.report.totals.answers == 4)
        #expect(bench.noteStats(of: ben)?.isEmpty != false)

        // With no journal left, nothing is watched.
        model.remove(anna)
        #expect(watcher.isWatching(bensFolder))
        model.remove(ben)
        #expect(watcher.folder == nil && watcher.started.count == 4 && watcher.stopped == 4)
    }

    @Test func aJournalMovedWhileInUseIsFollowed() async throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        try await bench.waitForReading(model)
        let store = model.progressStore
        var changes: [URL?] = []
        model.onJournalChanged = { changes.append($0?.folder) }

        let moved = bench.temporary.url.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.moveItem(at: URL(fileURLWithPath: anna.path, isDirectory: true), to: moved)
        bench.watcher.fire()
        // Found by its bookmark: watched and read where it is now.
        #expect(bench.watcher.isWatching(moved))
        #expect(model.context.map { PracticeJournal.isSameFolder($0.reader.folder, moved) } == true)
        #expect(model.progressStore !== store && model.canShowJournal)
        #expect(changes.count == 1 && changes.allSatisfy { $0.map { PracticeJournal.isSameFolder($0, moved) } == true })
        try await bench.waitForReading(model)
    }

    @Test func aJournalThatCannotBeFoundIsReadOnceItsBack() async throws {
        let model = bench.launch()
        let anna = try bench.makeJournal("Anna", in: model)
        let folder = URL(fileURLWithPath: anna.path, isDirectory: true)
        try bench.practiseElsewhere(in: folder, scoring: 5, piece: "Arabesque")
        bench.watcher.fire()
        try await bench.waitForReading(model)
        #expect(bench.answersToE4(of: anna) == 5)

        // Gone (a disk unplugged): reading nothing there would take the stats away, so it isn't
        // read; it's still watched by its path.
        let elsewhere = bench.temporary.url.appendingPathComponent("Copy", isDirectory: true)
        try FileManager.default.copyItem(at: folder, to: elsewhere)
        try FileManager.default.removeItem(at: folder)
        bench.watcher.fire()
        #expect(!model.canShowJournal && !model.game.isRefreshingStats && !model.progressStore.isLoading)
        #expect(bench.watcher.isWatching(folder) && bench.answersToE4(of: anna) == 5)

        // Back where it was.
        try FileManager.default.copyItem(at: elsewhere, to: folder)
        bench.watcher.fire()
        #expect(model.canShowJournal && model.game.isRefreshingStats)
        try await bench.waitForReading(model)
        #expect(bench.answersToE4(of: anna) == 5 && model.progressStore.report.totals.answers == 5)
    }
}
