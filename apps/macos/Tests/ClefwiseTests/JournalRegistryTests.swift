import Foundation
import Testing
@testable import Clefwise

/// The journals one Mac knows: making, opening, switching and removing them, and finding each
/// again after it moves. Temporary folders and in-memory defaults only.
@MainActor
@Suite struct JournalRegistryTests {
    private let temporary = UsageTestFolder()
    private let defaults = InMemoryDefaults()
    private let registry: JournalRegistry

    init() throws {
        registry = JournalRegistry(defaults: defaults)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    }

    private var documents: URL { temporary.url.appendingPathComponent("Documents", isDirectory: true) }

    /// The app launching again on the same defaults.
    private func relaunched() -> JournalRegistry {
        JournalRegistry(defaults: defaults)
    }

    // MARK: - Making and opening

    @Test func withoutJournalsThereIsNoneInUse() {
        #expect(registry.records.isEmpty && registry.current == nil)
    }

    @Test func aJournalMadeIsAddedAndPutInUse() throws {
        let record = try registry.create(named: "Anna", in: documents)
        let folder = documents.appendingPathComponent("Anna", isDirectory: true)
        #expect(registry.records == [record] && registry.current == record)
        #expect(record.name == "Anna" && record.path == folder.path && record.bookmark != nil && record.libraryFolder == nil)
        for (name, contents) in JournalLayout.rootFiles {
            #expect(try Data(contentsOf: folder.appendingPathComponent(name)) == contents, "\(name) has its exact bytes")
        }
        // Kept for the next launch.
        let again = relaunched()
        #expect(again.records == [record] && again.currentID == record.id)
    }

    @Test func makingOneWhereAJournalIsTakesIt() throws {
        let anna = try registry.create(named: "Anna", in: documents)
        let ben = try registry.create(named: "Ben", in: documents)
        #expect(registry.current == ben)
        // Picked again in the sheet: the same journal, in use again, not a second record.
        #expect(try registry.create(named: "Anna", in: documents) == anna)
        #expect(registry.records.count == 2 && registry.current == anna)
    }

    @Test func openingTakesOnlyAJournal() throws {
        let elsewhere = temporary.url.appendingPathComponent("Shared", isDirectory: true)
        let folder = try PracticeJournal(defaults: InMemoryDefaults()).create(named: "Family", in: elsewhere)
        #expect(throws: JournalError.notAJournal(documents)) { try registry.open(documents) }
        #expect(registry.records.isEmpty)

        let record = try registry.open(folder)
        #expect(registry.current == record && record.path == folder.path && record.bookmark != nil)
        // Opening it again changes nothing but the one in use.
        _ = try registry.create(named: "Anna", in: documents)
        #expect(try registry.open(folder) == record)
        #expect(registry.records.count == 2 && registry.current == record)
    }

    // MARK: - Switching and removing

    @Test func switchingChangesOnlyTheOneInUse() throws {
        let anna = try registry.create(named: "Anna", in: documents)
        let ben = try registry.create(named: "Ben", in: documents)
        registry.switchTo(anna.id)
        #expect(registry.current == anna && registry.records == [anna, ben])
        #expect(relaunched().current == anna)
        registry.switchTo(UUID())
        #expect(registry.current == anna, "an id not on the list changes nothing")
    }

    @Test func removingForgetsTheJournalButNeverItsFolder() throws {
        let anna = try registry.create(named: "Anna", in: documents)
        let ben = try registry.create(named: "Ben", in: documents)
        let folder = try #require(registry.folder(for: ben))
        registry.remove(ben.id)
        #expect(registry.records == [anna] && registry.current == nil)
        #expect(PracticeJournal.isJournal(folder), "the folder stays as it was")
        let again = relaunched()
        #expect(again.records == [anna] && again.current == anna, "with the one in use gone, the first on the list")
    }

    @Test func eachJournalHasOneJournalObject() throws {
        let anna = try registry.create(named: "Anna", in: documents)
        #expect(registry.journal(for: anna) === registry.journal(for: anna))
        let round = UUID()
        let file = temporary.url.appendingPathComponent("run.jsonl")
        let run = try JournalFixture.runFile(round, [JournalFixture.started(round), JournalFixture.answer(round),
                                                     JournalFixture.ended(round)], start: Date())
        try run.data.write(to: file)
        try registry.journal(for: anna).place(runFile: file, header: RunFileHeader(run: round, device: JournalFixture.device,
                                                                                    launch: JournalFixture.launch),
                                              startedAt: run.logged[0].time)
        let folder = try #require(registry.folder(for: anna))
        #expect(JournalTestBench.files(in: folder).filter { $0.hasPrefix("runs/") }.count == 1)
    }

    // MARK: - Finding it again

    @Test func theBookmarkFollowsAMovedFolder() throws {
        let anna = try registry.create(named: "Anna", in: documents)
        let moved = temporary.url.appendingPathComponent("Synced/Anna's practice", isDirectory: true)
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: URL(fileURLWithPath: anna.path), to: moved)

        let again = relaunched()
        let record = try #require(again.current)
        let found = try #require(again.folder(for: record))
        #expect(found.resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path)
        // The record follows, and is kept so.
        let updated = try #require(again.current)
        #expect(URL(fileURLWithPath: updated.path).resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path)
        #expect(updated.name == "Anna's practice")
        #expect(relaunched().current?.path == updated.path)
    }

    @Test func locatingTakesOnlyThatJournal() throws {
        let anna = try registry.create(named: "Anna", in: documents)
        let ben = try registry.create(named: "Ben", in: documents)
        let moved = temporary.url.appendingPathComponent("Anna", isDirectory: true)
        try FileManager.default.moveItem(at: URL(fileURLWithPath: anna.path), to: moved)
        #expect(throws: JournalError.notAJournal(documents)) { try registry.relocate(anna.id, to: documents) }
        #expect(throws: JournalError.listedAlready(URL(fileURLWithPath: ben.path))) {
            try registry.relocate(anna.id, to: URL(fileURLWithPath: ben.path))
        }
        try registry.relocate(anna.id, to: moved)
        #expect(registry.record(id: anna.id)?.path == moved.path)
        #expect(registry.folder(for: try #require(registry.record(id: anna.id))) == moved)
    }

    @Test func journalsWithTheSameNameAreToldApart() throws {
        let elsewhere = temporary.url.appendingPathComponent("Shared", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let first = try registry.create(named: "Clefwise Journal", in: documents)
        let second = try registry.create(named: "Clefwise Journal", in: elsewhere)
        let anna = try registry.create(named: "Anna", in: documents)
        let names = registry.displayNames
        #expect(names[anna.id] == "Anna")
        #expect(names[first.id] != names[second.id])
        #expect(names[first.id]?.hasPrefix("Clefwise Journal (") == true)
    }

    @Test func aNewJournalIsSuggestedAFreeName() throws {
        #expect(PracticeJournal.suggestedName(in: documents, fresh: true) == "Clefwise Journal")
        try registry.create(named: "Clefwise Journal", in: documents)
        // The first-launch sheet offers the journal there; New Journal… the next free name.
        #expect(PracticeJournal.suggestedName(in: documents) == "Clefwise Journal")
        #expect(PracticeJournal.suggestedName(in: documents, fresh: true) == "Clefwise Journal 2")
    }
}
