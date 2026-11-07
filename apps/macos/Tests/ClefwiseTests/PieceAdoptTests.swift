import Foundation
import Testing
@testable import Clefwise

// The piece library taking in the pieces the journal brings from other devices
// (`PieceLibrary.adopt(from:journalFolder:)`): added, revised and removed, the latest winning, and
// changes made on this Mac winning while they're still on their way.

@MainActor
@Suite struct PieceAdoptTests {
    private let temporary = UsageTestFolder()
    private let sent = CollectingJournalRecorder()
    private let library: PieceLibrary
    /// Another Mac's piece, and its library entry there.
    private let otherID = UUID(uuidString: "0F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F9")!
    private let otherPath = "/Users/someone/Scores/Comptine.musicxml"
    /// To the second, as the index keeps its dates.
    private let start = usageTestTime("2026-11-05T09:31:12.000Z")

    init() {
        library = PieceLibrary(folder: temporary.url.appendingPathComponent("Library", isDirectory: true), journal: sent)
    }

    private var journal: URL { temporary.url.appendingPathComponent("Clefwise Journal", isDirectory: true) }

    /// Puts `text`'s bytes in the journal's `pieces/`, and returns their hash.
    @discardableResult
    private func score(_ text: String, extension fileExtension: String = "musicxml") throws -> String {
        let file = JournalPieceFile(data: Data(text.utf8), fileExtension: fileExtension)
        let url = journal.appendingPathComponent(JournalLayout.piecePath(hash: file.hash, fileExtension: fileExtension))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.data.write(to: url)
        return file.hash
    }

    private func hash(_ text: String) -> String {
        JournalPieceFile.sha256(of: Data(text.utf8))
    }

    private func logged(_ event: UsageEvent, at time: Date) -> LoggedEvent {
        LoggedEvent(event, session: UUID(), sequence: 0, time: time)
    }

    private func added(_ piece: String, title: String = "Comptine", at time: Date, libraryID: UUID? = nil,
                       originalPath: String? = nil) -> LoggedEvent {
        logged(.pieceAdded(PieceAdded(piece: piece, title: title, fileName: "Comptine.musicxml", libraryID: libraryID,
                                      originalPath: originalPath)), at: time)
    }

    private func revised(_ piece: String, file: String, title: String = "Comptine", at time: Date) -> LoggedEvent {
        logged(.pieceRevised(PieceRevised(piece: piece, file: file, title: title)), at: time)
    }

    private func removed(_ piece: String, at time: Date) -> LoggedEvent {
        logged(.pieceRemoved(PieceRemoved(piece: piece)), at: time)
    }

    /// Adopts `events`, sorted by time as a `JournalReader` gives them.
    private func adopt(_ events: [LoggedEvent], into library: PieceLibrary? = nil) {
        (library ?? self.library).adopt(from: JournalReader.Contents(pieceEvents: events.sorted { $0.time < $1.time }),
                                        journalFolder: journal)
    }

    private func copy(of entry: PieceLibrary.Entry) -> String? {
        (try? Data(contentsOf: library.fileURL(for: entry))).map { String(decoding: $0, as: UTF8.self) }
    }

    /// A file outside the library, as a user would open it.
    private func original(_ name: String, _ text: String) throws -> URL {
        let folder = temporary.url.appendingPathComponent("Originals", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    // MARK: - Added, revised, removed

    @Test func anAddedPieceGetsAnEntryWithItsScoreCopied() throws {
        let piece = try score("<score-partwise>Comptine</score-partwise>")
        adopt([added(piece, title: "Comptine d'un autre été", at: start, libraryID: otherID, originalPath: otherPath)])

        let entry = try #require(library.entries.first)
        #expect(library.entries.count == 1)
        #expect(entry.id == otherID && entry.title == "Comptine d'un autre été" && entry.originalPath == otherPath)
        #expect(entry.pieceID == piece && entry.contentHash == piece)
        #expect(entry.fileName == "\(otherID.uuidString).musicxml")
        #expect(entry.addedAt == start && entry.lastOpenedAt == start && entry.settings == nil)
        #expect(copy(of: entry) == "<score-partwise>Comptine</score-partwise>")
        #expect(PieceLibrary(folder: library.folder).entries == library.entries)
        #expect(sent.events.isEmpty)
    }

    @Test func aPieceWithoutItsLibraryIDOrPathIsKnownByItsFileName() throws {
        let piece = try score("zipped", extension: "mxl")
        adopt([added(piece, at: start)])
        let entry = try #require(library.entries.first)
        #expect(entry.originalPath == "Comptine.musicxml" && entry.fileName == "\(entry.id.uuidString).mxl")
        #expect(copy(of: entry) == "zipped")
    }

    @Test func aLibraryIDTakenHereIsNotReused() throws {
        let first = try score("first")
        let second = try score("second")
        adopt([added(first, at: start, libraryID: otherID), added(second, at: start + 1, libraryID: otherID)])
        #expect(library.entries.count == 2)
        #expect(Set(library.entries.map(\.id)).count == 2 && library.entries.contains { $0.id == otherID })
    }

    @Test func aRevisedPieceGetsTheNewBytesAndTitle() throws {
        let piece = try score("version 1")
        adopt([added(piece, at: start, libraryID: otherID, originalPath: otherPath)])
        var settings = Game.PieceSettings()
        settings.startBar = 9
        library.save(settings: settings, for: otherID)

        let file = try score("version 2")
        adopt([added(piece, at: start, libraryID: otherID, originalPath: otherPath),
               revised(piece, file: file, title: "Comptine, revised", at: start + 60)])
        let entry = try #require(library.entries.first)
        #expect(library.entries.count == 1 && entry.id == otherID && entry.pieceID == piece)
        #expect(entry.contentHash == file && entry.title == "Comptine, revised" && copy(of: entry) == "version 2")
        #expect(entry.fileName == "\(otherID.uuidString).musicxml" && entry.settings == settings)
        #expect(entry.addedAt == start && entry.lastOpenedAt == start)
        #expect(PieceLibrary(folder: library.folder).entries == library.entries)
        #expect(sent.events.isEmpty)
    }

    @Test func aRemovedPieceLeavesWithItsCopy() throws {
        let piece = try score("score")
        adopt([added(piece, at: start)])
        let entry = try #require(library.entries.first)
        adopt([added(piece, at: start), removed(piece, at: start + 60)])
        #expect(library.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: library.fileURL(for: entry).path))
        #expect(PieceLibrary(folder: library.folder).entries.isEmpty)
        #expect(sent.events.isEmpty)
    }

    @Test func theLatestEventWins() throws {
        let again = try score("added again")
        let gone = try score("gone")
        let revivedByRevision = try score("revised after removal")
        let revision = try score("the revision")
        adopt([added(again, at: start), removed(again, at: start + 1), added(again, title: "Back", at: start + 2),
               added(gone, at: start), removed(gone, at: start + 2),
               added(revivedByRevision, at: start), removed(revivedByRevision, at: start + 1),
               revised(revivedByRevision, file: revision, title: "Revised", at: start + 2)])
        #expect(library.entries.map(\.title).sorted() == ["Back", "Revised"])
        #expect(library.entries.first { $0.pieceID == revivedByRevision }?.contentHash == revision)
    }

    @Test func idsAreComparedWithoutRegardToCase() throws {
        let piece = try score("score")
        adopt([added(piece, at: start)])
        adopt([added(piece, at: start), removed(piece.uppercased(), at: start + 1)])
        #expect(library.entries.isEmpty)
    }

    @Test func adoptedPiecesTakeTheirPlaceAmongTheOthers() throws {
        try library.add(try original("Oldest.musicxml", "oldest"), title: "Oldest", now: start - 3600)
        try library.add(try original("Newest.musicxml", "newest"), title: "Newest", now: start + 3600)
        let piece = try score("between")
        adopt([added(piece, title: "Between", at: start)])
        #expect(library.entries.map(\.title) == ["Newest", "Between", "Oldest"])
        #expect(PieceLibrary(folder: library.folder).entries.map(\.title) == ["Newest", "Between", "Oldest"])
    }

    @Test func piecesTheJournalDoesNotKnowAreLeftAlone() throws {
        let entry = try library.add(try original("Mine.musicxml", "mine"), title: "Mine")
        adopt([added(try score("theirs"), title: "Theirs", at: start)])
        #expect(library.entries.count == 2 && library.entry(id: entry.id) == entry)
    }

    // MARK: - Still arriving

    @Test func aScoreNotThereYetIsAdoptedOnceItArrives() throws {
        let piece = hash("late score")
        adopt([added(piece, at: start)])
        #expect(library.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: PieceLibrary.indexURL(in: library.folder).path))

        try score("late score")
        adopt([added(piece, at: start)])
        #expect(library.entries.first?.contentHash == piece)
    }

    @Test func aDamagedScoreIsNotAdopted() throws {
        let piece = hash("the real score")
        let url = journal.appendingPathComponent(JournalLayout.piecePath(hash: piece, fileExtension: "musicxml"))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("damaged".utf8).write(to: url)
        adopt([added(piece, at: start)])
        #expect(library.entries.isEmpty)
    }

    @Test func aRevisionWhoseScoreIsNotThereYetWaits() throws {
        let piece = try score("version 1")
        adopt([added(piece, at: start)])
        let file = hash("version 2")
        let events = [added(piece, at: start), revised(piece, file: file, title: "New title", at: start + 60)]
        adopt(events)
        let entry = try #require(library.entries.first)
        #expect(entry.contentHash == piece && entry.title == "Comptine" && copy(of: entry) == "version 1")

        try score("version 2")
        adopt(events)
        #expect(library.entries.first?.contentHash == file && library.entries.first?.title == "New title")
    }

    @Test func aRevisionBeforeItsPieceAddedWaitsForIt() throws {
        let piece = try score("version 1")
        let file = try score("version 2")
        adopt([revised(piece, file: file, at: start + 60)])
        #expect(library.entries.isEmpty)
        adopt([added(piece, at: start), revised(piece, file: file, at: start + 60)])
        #expect(library.entries.first?.contentHash == file)
    }

    @Test func adoptingTheSameAgainChangesNothing() throws {
        let piece = try score("version 1")
        let file = try score("version 2")
        let other = try score("other")
        let events = [added(piece, at: start, libraryID: otherID), revised(piece, file: file, at: start + 1),
                      added(other, at: start), removed(other, at: start + 2)]
        adopt(events)
        let after = library.entries
        // Nothing to save: the index isn't written again.
        try FileManager.default.removeItem(at: PieceLibrary.indexURL(in: library.folder))
        adopt(events)
        #expect(library.entries == after)
        #expect(!FileManager.default.fileExists(atPath: PieceLibrary.indexURL(in: library.folder).path))
        #expect(sent.events.isEmpty)
    }

    // MARK: - Changes made here

    @Test func aPieceRemovedHereStaysRemovedUntilTheJournalHasSomethingNewer() throws {
        let piece = try score("score")
        adopt([added(piece, at: start)])
        let entry = try #require(library.entries.first)
        library.remove(entry.id)
        #expect(sent.events == [.pieceRemoved(PieceRemoved(piece: piece))])

        // The journal doesn't have the removal yet; it's remembered across launches.
        let reopened = PieceLibrary(folder: library.folder)
        adopt([added(piece, at: start)], into: reopened)
        adopt([added(piece, at: start)])
        #expect(library.entries.isEmpty && reopened.entries.isEmpty)

        // Another device adds it again later.
        adopt([added(piece, at: start), added(piece, title: "Again", at: .now + 60)])
        #expect(library.entries.map(\.title) == ["Again"])
        #expect(sent.events.count == 1)
    }

    @Test func aPieceAddedHereStaysWhileTheJournalSaysItWasRemovedBefore() throws {
        let url = try original("Comptine.musicxml", "score")
        let piece = try score("score")
        let entry = try library.add(url, title: "Comptine")
        adopt([added(piece, at: start), removed(piece, at: start + 1)])
        #expect(library.entries == [entry])
    }

    @Test func aRevisionMadeHereIsNotUndoneByTheJournalsOlderFile() throws {
        let url = try original("Comptine.musicxml", "version 1")
        let first = try library.add(url, title: "Comptine", now: start)
        let piece = try score("version 1")
        try Data("version 2".utf8).write(to: url)
        let revised = try library.add(url, title: "Comptine")
        adopt([added(piece, at: start)])
        #expect(library.entries == [revised] && copy(of: revised) == "version 2" && revised.id == first.id)
    }

    @Test func aChangeHereIsForgottenOnceTheJournalHasIt() throws {
        let piece = try score("score")
        adopt([added(piece, at: start)])
        let entry = try #require(library.entries.first)
        library.remove(entry.id)
        let changes = library.folder.appendingPathComponent("local-changes.json")
        #expect(try String(contentsOf: changes, encoding: .utf8).contains(piece))

        // The removal arrives in the journal.
        adopt([added(piece, at: start), removed(piece, at: .now + 1)])
        #expect(try !String(contentsOf: changes, encoding: .utf8).contains(piece))
        // From then on the journal decides.
        adopt([added(piece, at: start), removed(piece, at: .now + 1), added(piece, title: "Back", at: .now + 2)])
        #expect(library.entries.map(\.title) == ["Back"])
    }

    // MARK: - Through a real journal

    @Test func aPieceAddedOnAnotherMacArrivesThroughTheJournal() throws {
        let bench = JournalTestBench()
        let folder = try bench.makeJournal()
        let outbox = JournalOutbox(journal: bench.journal, pendingFolder: bench.pendingFolder)
        let log = bench.makeLog()
        let elsewhere = PieceLibrary(folder: bench.temporary.url.appendingPathComponent("Other Mac", isDirectory: true),
                                     journal: JournalEventRecorder(outbox: outbox, device: UUID(),
                                                                   launch: JournalFixture.launch, log: log))
        let theirs = try elsewhere.add(try original("Comptine.musicxml", "<score-partwise/>"), title: "Comptine")
        outbox.waitUntilDone()

        let reader = JournalReader(folder: folder)
        library.adopt(from: reader.read(), journalFolder: folder)
        let entry = try #require(library.entries.first)
        #expect(entry.id == theirs.id && entry.originalPath == theirs.originalPath && entry.pieceID == theirs.pieceID)
        #expect(copy(of: entry) == "<score-partwise/>" && sent.events.isEmpty)

        // The Mac it came from has it already: nothing changes there, and nothing goes back.
        let files = JournalTestBench.files(in: folder)
        let before = elsewhere.entries
        elsewhere.adopt(from: reader.read(), journalFolder: folder)
        outbox.waitUntilDone()
        #expect(elsewhere.entries == before && JournalTestBench.files(in: folder) == files)
    }
}
