import Foundation
import Testing
@testable import Clefwise

// What this Mac keeps about each journal it knows (spec/practice-journal.md, "Several journals"):
// its state folders, and the record the registry keeps for it.

@Suite struct JournalStateTests {
    private let id = UUID(uuidString: "6F9619FF-8B86-4011-B42D-00C04FC964FF")!
    private let root = URL(fileURLWithPath: "/tmp/clefwise-journal-state-tests/Journals", isDirectory: true)

    @Test func eachJournalHasAFolderOfItsOwnNamedByItsLocalID() {
        let folder = JournalState.folder(for: id, in: root)
        #expect(folder.path == "/tmp/clefwise-journal-state-tests/Journals/6f9619ff-8b86-4011-b42d-00c04fc964ff")
        #expect(JournalState.library(for: id, in: root) == folder.appendingPathComponent("Pieces", isDirectory: true))
        #expect(JournalState.pending(for: id, in: root) == folder.appendingPathComponent("Pending", isDirectory: true))
        #expect(JournalState.current(for: id, in: root) == folder.appendingPathComponent("Current", isDirectory: true))
        #expect(JournalState.folder(for: UUID(), in: root) != folder)
    }

    @Test func theRunWriterKeepsItsFilesInTheJournalsFolders() {
        let writer = RunFileWriter(folder: JournalState.folder(for: id, in: root), journal: PracticeJournal(defaults: InMemoryDefaults()),
                                   device: JournalFixture.device, launch: JournalFixture.launch)
        #expect(writer.currentFolder == JournalState.current(for: id, in: root))
        #expect(writer.outbox.pendingFolder == JournalState.pending(for: id, in: root))
    }

    @Test func theRootIsInApplicationSupport() {
        #expect(JournalState.defaultRoot.path.hasSuffix("/Library/Application Support/Clefwise/Journals"))
        #expect(JournalState.folder(for: id) == JournalState.folder(for: id, in: JournalState.root))
    }

    @Test func aRecordIsNamedByItsFolderAndKeepsItsOwnKeys() throws {
        var record = JournalRecord(id: id, path: "/Users/me/Documents/Ana's Journal", bookmark: nil, libraryFolder: nil)
        #expect(record.name == "Ana's Journal")
        #expect(record.defaultsNamespace == "journal.6f9619ff-8b86-4011-b42d-00c04fc964ff.")
        #expect(Game.key(Game.Keys.settings, in: record.defaultsNamespace) == "journal.6f9619ff-8b86-4011-b42d-00c04fc964ff.settings")
        #expect(record.libraryURL(in: root) == JournalState.library(for: id, in: root))

        record.libraryFolder = "/Users/me/Library/Application Support/Clefwise/Pieces"
        #expect(record.libraryURL(in: root).path == "/Users/me/Library/Application Support/Clefwise/Pieces")

        record.bookmark = Data([1, 2, 3])
        let decoded = try JSONDecoder().decode(JournalRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
        let bare = JournalRecord(id: id, path: "/Volumes/Disk/Journal", bookmark: nil, libraryFolder: nil)
        #expect(try JSONDecoder().decode(JournalRecord.self, from: JSONEncoder().encode(bare)) == bare)
    }
}
