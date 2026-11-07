import Foundation
import Testing
@testable import Clefwise

/// An app model launched on folders and defaults of its own: never the real ones.
@MainActor
final class AppModelTestBench {
    let temporary = UsageTestFolder()
    let defaults = InMemoryDefaults()

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

    /// The app launching (again) on this bench's defaults and folders, with its own session.
    func launch() -> AppModel {
        AppModel(defaults: defaults, log: UsageLog(folder: usageFolder), stateRoot: stateRoot, buildOne: buildOne,
                 device: JournalFixture.device, launch: JournalFixture.launch)
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
        model.game.settings.mode = .practice
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
        #expect(model.game.settings.clefChoice == .bass && model.game.settings.mode == .practice)
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
}
