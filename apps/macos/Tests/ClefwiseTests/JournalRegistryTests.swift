import Foundation
import Testing
@testable import Clefwise

/// The journals one Mac knows: making, opening, switching, renaming and removing them, and finding
/// each again after it moves. Temporary folders and in-memory defaults only.
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

    // MARK: - Renaming

    /// What's in `documents`, as the file system has the names: case and all.
    private func namesInDocuments() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: documents.path).sorted()
    }

    @Test func renamingRenamesTheFolderAndTheRecordFollows() throws {
        let anna = try registry.create(named: "Anna", in: documents)
        var heard: [JournalRecord] = []
        registry.onMoved = { heard.append($0) }
        let renamed = try registry.rename(anna.id, to: "  Anna's practice\n")
        let folder = documents.appendingPathComponent("Anna's practice", isDirectory: true)
        #expect(try namesInDocuments() == ["Anna's practice"])
        for (name, contents) in JournalLayout.rootFiles {
            #expect(try Data(contentsOf: folder.appendingPathComponent(name)) == contents, "\(name) went with it")
        }
        // The same journal, its path and bookmark following the folder.
        #expect(renamed.id == anna.id && renamed.name == "Anna's practice" && renamed.path == folder.path)
        #expect(registry.records == [renamed] && registry.current == renamed && heard == [renamed])
        #expect(registry.folder(for: renamed) == folder)
        let bookmark = try #require(renamed.bookmark)
        #expect(bookmark != anna.bookmark)
        var isStale = false
        let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil,
                               bookmarkDataIsStale: &isStale)
        #expect(PracticeJournal.isSameFolder(resolved, folder))
        // Kept for the next launch.
        #expect(relaunched().current == renamed)
    }

    @Test func aNameThatWontDoChangesNothing() throws {
        let anna = try registry.create(named: "Anna", in: documents)
        let ben = try registry.create(named: "Ben", in: documents)
        registry.switchTo(anna.id)
        try Data("mine".utf8).write(to: documents.appendingPathComponent("notes.txt"))
        var heard: [JournalRecord] = []
        registry.onMoved = { heard.append($0) }
        let bensFolder = URL(fileURLWithPath: ben.path, isDirectory: true)
        let notes = URL(fileURLWithPath: documents.appendingPathComponent("notes.txt").path, isDirectory: false)
        let refusals: [(name: String, error: JournalError)] = [
            ("", .invalidName("")),
            ("  \n", .invalidName("")),
            ("Anna/Ben", .invalidName("Anna/Ben")),
            ("Anna: piano", .invalidName("Anna: piano")),
            (".Anna", .invalidName(".Anna")),
            ("Ben", .nameTaken(bensFolder)),
            (" Ben ", .nameTaken(bensFolder)),
            ("notes.txt", .nameTaken(notes)),
        ]
        for refusal in refusals {
            #expect(throws: refusal.error, "“\(refusal.name)”") { try registry.rename(anna.id, to: refusal.name) }
        }
        #expect(try namesInDocuments() == ["Anna", "Ben", "notes.txt"])
        #expect(try String(contentsOf: notes, encoding: .utf8) == "mine")
        #expect(registry.records == [anna, ben] && registry.current == anna && heard.isEmpty)
        #expect(relaunched().records == [anna, ben])
        // Said plainly.
        #expect(JournalError.invalidName("").localizedDescription == "Give the journal a name.")
        #expect(JournalError.nameTaken(bensFolder).localizedDescription == "There's already a folder called “Ben” there.")
        #expect(JournalError.nameTaken(notes).localizedDescription == "There's already a file called “notes.txt” there.")
    }

    @Test func theSameNameChangesNothing() throws {
        let anna = try registry.create(named: "Anna", in: documents)
        var heard: [JournalRecord] = []
        registry.onMoved = { heard.append($0) }
        #expect(try registry.rename(anna.id, to: "Anna") == anna)
        #expect(try registry.rename(anna.id, to: " Anna ") == anna)
        #expect(try namesInDocuments() == ["Anna"] && registry.records == [anna] && heard.isEmpty)
    }

    @Test func aChangeOfCaseOnlyIsARenameToo() throws {
        let anna = try registry.create(named: "anna", in: documents)
        let renamed = try registry.rename(anna.id, to: "Anna")
        #expect(try namesInDocuments() == ["Anna"])
        #expect(renamed.name == "Anna" && registry.current == renamed)
        #expect(registry.folder(for: renamed).map(PracticeJournal.isJournal) == true)
        // Through a temporary name, as on a volume that won't change the case in one go.
        try PracticeJournal.renameThroughTemporaryName(URL(fileURLWithPath: renamed.path, isDirectory: true),
                                                       to: documents.appendingPathComponent("ANNA", isDirectory: true))
        #expect(try namesInDocuments() == ["ANNA"])
    }

    @Test func aFolderThatCannotBeRenamedChangesNothing() throws {
        let anna = try registry.create(named: "Anna", in: documents)
        // Nothing can be renamed in the folder it's in.
        let manager = FileManager.default
        try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: documents.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: documents.path) }
        let error = try #require(throws: JournalError.self) { try registry.rename(anna.id, to: "Ben") }
        guard case .renameFailed(let folder, let code) = error else {
            Issue.record("\(error)")
            return
        }
        #expect(folder.lastPathComponent == "Anna" && code == EACCES)
        #expect(error.localizedDescription == "You don't have permission to rename “Anna”.")
        #expect(try namesInDocuments() == ["Anna"] && registry.records == [anna])

        // Gone (a disk unplugged): it can't be found to be renamed.
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: documents.path)
        try manager.removeItem(at: URL(fileURLWithPath: anna.path))
        #expect(throws: JournalError.missing) { try registry.rename(anna.id, to: "Ben") }
        #expect(try namesInDocuments().isEmpty && registry.records == [anna])
        #expect(throws: JournalError.missing) { try registry.rename(UUID(), to: "Ben") }
    }

    @Test func aNewJournalIsSuggestedAFreeName() throws {
        #expect(PracticeJournal.suggestedName(in: documents, fresh: true) == "Clefwise Journal")
        try registry.create(named: "Clefwise Journal", in: documents)
        // The first-launch sheet offers the journal there; New Journal… the next free name.
        #expect(PracticeJournal.suggestedName(in: documents) == "Clefwise Journal")
        #expect(PracticeJournal.suggestedName(in: documents, fresh: true) == "Clefwise Journal 2")
    }
}
