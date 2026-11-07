import Foundation
import Testing
@testable import Clefwise

/// Build 1's one journal becoming the first of several: its record, its keys, its device state.
/// Temporary folders and in-memory defaults only.
@MainActor
@Suite struct JournalMigrationTests {
    private let temporary = UsageTestFolder()
    private let defaults = InMemoryDefaults()

    private var buildOne: BuildOneFolders {
        let state = temporary.url.appendingPathComponent("Clefwise", isDirectory: true)
        return BuildOneFolders(state: state, library: state.appendingPathComponent("Pieces", isDirectory: true))
    }
    private var stateRoot: URL { temporary.url.appendingPathComponent("Clefwise/Journals", isDirectory: true) }
    private var documents: URL { temporary.url.appendingPathComponent("Documents", isDirectory: true) }

    /// Build 1's journal, as it left it: made through its keys in the defaults, with settings (set
    /// for a sprint, as build 1 could be), stats and best sprint scores under the keys it used,
    /// and a working file and a waiting run in its folders. Returns the journal's folder.
    @discardableResult
    private func leaveBuildOne() throws -> URL {
        let folder = try PracticeJournal(defaults: defaults).create(named: "Clefwise Journal", in: documents)
        defaults.set(Data(#"{"clefChoice":"bass","mode":"sprint","naming":"solfege"}"#.utf8), forKey: Game.Keys.settings)
        defaults.set(try JSONEncoder().encode(["bass.C3": NoteStat(attempts: 3, correct: 2, recent: [true, false, true])]),
                     forKey: Game.Keys.noteStats)
        defaults.set(try JSONEncoder().encode(["bass.staff": 17]), forKey: "bestScores")
        defaults.set(UUID().uuidString, forKey: Game.Keys.restoringRound)
        try write("working", to: "Current/1f2e3d4c-0000-4000-8000-000000000001.jsonl")
        try write("waiting", to: "Pending/runs/2026/11/20261105T093112Z-1f2e3d4c-0000-4000-8000-000000000002.jsonl")
        try write("kept", to: "Pending/kept/runs/2026/11/20261104T093112Z-1f2e3d4c-0000-4000-8000-000000000003.jsonl")
        return folder
    }

    private func write(_ text: String, to path: String) throws {
        let url = buildOne.state.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func buildOnesJournalBecomesTheFirst() throws {
        let folder = try leaveBuildOne()
        let registry = JournalRegistry(defaults: defaults)
        let record = try #require(JournalMigration.migrateIfNeeded(registry, from: buildOne, stateRoot: stateRoot))
        #expect(registry.records == [record] && registry.current == record)
        #expect(record.path == folder.path)
        #expect(record.bookmark == defaults.object(forKey: PracticeJournal.Keys.bookmark) as? Data && record.bookmark != nil)
        #expect(record.libraryFolder == buildOne.library.path, "the pieces stay where they are")
        #expect(registry.folder(for: record) == folder)

        // Its values, copied into its namespace; build 1's keys stay.
        for name in [Game.Keys.settings, Game.Keys.noteStats, Game.Keys.restoringRound] {
            let old = try #require(defaults.object(forKey: name))
            let copied = defaults.object(forKey: Game.key(name, in: record.defaultsNamespace))
            #expect((copied as? Data) == (old as? Data) && (copied as? String) == (old as? String), "\(name)")
        }
        // Not its best sprint scores, which nothing reads now; they stay where build 1 left them.
        #expect(defaults.object(forKey: Game.key("bestScores", in: record.defaultsNamespace)) == nil)
        #expect(defaults.data(forKey: "bestScores") != nil)

        // Its working file and waiting records, moved into its own state folder.
        #expect(JournalTestBench.files(in: JournalState.current(for: record.id, in: stateRoot))
                == ["1f2e3d4c-0000-4000-8000-000000000001.jsonl"])
        #expect(JournalTestBench.files(in: JournalState.pending(for: record.id, in: stateRoot)) == [
            "kept/runs/2026/11/20261104T093112Z-1f2e3d4c-0000-4000-8000-000000000003.jsonl",
            "runs/2026/11/20261105T093112Z-1f2e3d4c-0000-4000-8000-000000000002.jsonl"])
        #expect(!FileManager.default.fileExists(atPath: buildOne.state.appendingPathComponent("Current").path))
        #expect(!FileManager.default.fileExists(atPath: buildOne.state.appendingPathComponent("Pending").path))

        // Build 1 brought the usage log into it when it made it.
        #expect(defaults.object(forKey: AppModel.Keys.usageLogBroughtIn) as? Bool == true)
    }

    @Test func aGameInTheFirstJournalHasBuildOnesSettings() throws {
        try leaveBuildOne()
        let registry = JournalRegistry(defaults: defaults)
        let record = try #require(JournalMigration.migrateIfNeeded(registry, from: buildOne, stateRoot: stateRoot))
        let game = Game(defaults: defaults, namespace: record.defaultsNamespace, recorder: MemoryUsageRecorder(),
                        library: PieceLibrary.temporary())
        #expect(game.settings.clefChoice == .bass && game.settings.naming == .solfege)
        // Set for a sprint, it's a practice round now, with no limit.
        #expect(game.roundTimeLimit == nil && game.roundNoteLimit == nil)
    }

    @Test func itHappensOnce() throws {
        try leaveBuildOne()
        let registry = JournalRegistry(defaults: defaults)
        let record = try #require(JournalMigration.migrateIfNeeded(registry, from: buildOne, stateRoot: stateRoot))
        #expect(JournalMigration.migrateIfNeeded(registry, from: buildOne, stateRoot: stateRoot) == nil)
        #expect(JournalMigration.migrateIfNeeded(JournalRegistry(defaults: defaults), from: buildOne, stateRoot: stateRoot) == nil)
        // Not even once every journal has been removed: build 1's keys are still there.
        registry.remove(record.id)
        #expect(JournalMigration.migrateIfNeeded(registry, from: buildOne, stateRoot: stateRoot) == nil)
        #expect(registry.records.isEmpty)
    }

    @Test func withoutBuildOnesJournalThereIsNothingToBringOver() throws {
        // Build 1's sheet never answered: practice so far, but no journal.
        try write("waiting", to: "Pending/runs/2026/11/20261105T093112Z-1f2e3d4c-0000-4000-8000-000000000002.jsonl")
        let registry = JournalRegistry(defaults: defaults)
        #expect(JournalMigration.migrateIfNeeded(registry, from: buildOne, stateRoot: stateRoot) == nil)
        #expect(registry.records.isEmpty && registry.current == nil)
        #expect(defaults.object(forKey: AppModel.Keys.usageLogBroughtIn) == nil, "the first journal made brings the log in")
    }

    @Test func aMissingBuildOneJournalIsStillBroughtOver() throws {
        let folder = try leaveBuildOne()
        try FileManager.default.removeItem(at: folder)
        let registry = JournalRegistry(defaults: defaults)
        let record = try #require(JournalMigration.migrateIfNeeded(registry, from: buildOne, stateRoot: stateRoot))
        #expect(registry.folder(for: record) == nil, "the app says it can't find it, as build 1 did")
        #expect(record.path == folder.path)
    }
}
