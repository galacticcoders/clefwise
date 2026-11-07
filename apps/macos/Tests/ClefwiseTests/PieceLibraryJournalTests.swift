import Foundation
import Testing
@testable import Clefwise

// The piece library's changes in the practice journal (`pieceAdded`, `pieceRevised`,
// `pieceRemoved`), the piece a run names, and the window's journal setup.

@MainActor
@Suite struct PieceLibraryJournalTests {
    private let sent = CollectingJournalRecorder()
    private let library: PieceLibrary
    private let elsewhere = FileManager.default.temporaryDirectory
        .appendingPathComponent("clefwise-journal-originals-\(UUID().uuidString)", isDirectory: true)

    init() {
        library = PieceLibrary.temporary()
        library.journal = sent
    }

    /// A file outside the library, as a user would open it.
    private func original(_ name: String, _ text: String) throws -> URL {
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let url = elsewhere.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func aNewPieceIsAPieceAddedWithItsScore() throws {
        let url = try original("Comptine.MXL", "zipped score")
        let entry = try library.add(url, title: "Comptine d'un autre été")
        #expect(entry.pieceID == entry.contentHash)
        #expect(sent.events == [.pieceAdded(PieceAdded(piece: entry.contentHash, title: "Comptine d'un autre été",
                                                       fileName: "Comptine.MXL", libraryID: entry.id,
                                                       originalPath: url.path))])
        let piece = try #require(sent.pieces.first ?? nil)
        #expect(piece == JournalPieceFile(data: Data("zipped score".utf8), fileExtension: "mxl"))
        #expect(piece.hash == entry.contentHash)
    }

    @Test func theSameBytesAgainAddNothing() throws {
        let entry = try library.add(try original("a.musicxml", "same"), title: "A")
        try library.add(try original("copy of a.musicxml", "same"), title: "A again")
        try library.add(library.fileURL(for: entry), title: "A")
        #expect(sent.events.count == 1)
    }

    @Test func aScoreExportedAgainIsAPieceRevised() throws {
        let url = try original("Piece.musicxml", "version 1")
        let first = try library.add(url, title: "Piece")
        try Data("version 2".utf8).write(to: url)
        let revised = try library.add(url, title: "Piece, revised")
        let newHash = JournalPieceFile.sha256(of: Data("version 2".utf8))
        #expect(revised.id == first.id && revised.pieceID == first.contentHash && revised.contentHash == newHash)
        #expect(sent.events.last == .pieceRevised(PieceRevised(piece: first.contentHash, file: newHash,
                                                               title: "Piece, revised")))
        #expect(sent.pieces.last == JournalPieceFile(data: Data("version 2".utf8), fileExtension: "musicxml"))
        // The piece keeps its id in the index too.
        #expect(PieceLibrary(folder: library.folder).entry(id: first.id)?.pieceID == first.contentHash)
    }

    @Test func removingIsAPieceRemoved() throws {
        let url = try original("Piece.musicxml", "version 1")
        let entry = try library.add(url, title: "Piece")
        try Data("version 2".utf8).write(to: url)
        try library.add(url, title: "Piece")
        library.remove(entry.id)
        #expect(sent.events.last == .pieceRemoved(PieceRemoved(piece: entry.pieceID)))
        #expect(sent.pieces.last == .some(nil))
    }

    @Test func anEntryKeptBeforeTheJournalIsKnownByItsHash() throws {
        let folder = library.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let index = """
        [{"addedAt":"2026-11-01T10:00:00Z","contentHash":"\(String(repeating: "ab", count: 32))",
          "fileName":"x.musicxml","id":"5C1D2E3F-4A5B-4C6D-8E7F-9A0B1C2D3E4F","lastOpenedAt":"2026-11-02T10:00:00Z",
          "originalPath":"/Users/me/x.musicxml","title":"X"}]
        """
        try Data(index.utf8).write(to: PieceLibrary.indexURL(in: folder))
        let entry = try #require(PieceLibrary(folder: folder).entries.first)
        #expect(entry.pieceID == String(repeating: "ab", count: 32) && entry.settings == nil)
    }

    @Test func withoutAJournalNothingIsSent() throws {
        let quiet = PieceLibrary.temporary()
        let entry = try quiet.add(try original("a.musicxml", "a"), title: "A")
        quiet.remove(entry.id)
        #expect(quiet.journal == nil && sent.events.isEmpty)
    }

    @Test func libraryEventsReachTheJournalStampedInTheLogsSession() throws {
        let bench = JournalTestBench()
        let journal = try bench.makeJournal()
        let log = bench.makeLog()
        let outbox = JournalOutbox(journal: bench.journal, pendingFolder: bench.pendingFolder)
        library.journal = JournalEventRecorder(outbox: outbox, device: JournalFixture.device,
                                               launch: JournalFixture.launch, log: log)
        log.record(JournalFixture.action("before"))
        let entry = try library.add(try original("Minuet.musicxml", "<score-partwise/>"), title: "Minuet")
        library.remove(entry.id)
        log.record(JournalFixture.action("after"))
        log.flush()
        outbox.waitUntilDone()

        let files = JournalTestBench.files(in: journal)
        #expect(files.contains("pieces/\(entry.contentHash).musicxml"))
        let events = files.filter { $0.hasPrefix("events/") }.map { RunFile.read(journal.appendingPathComponent($0)) }
        #expect(events.count == 2)
        let logged = events.compactMap(\.events.first).sorted { $0.sequence < $1.sequence }
        #expect(logged.map(\.event.type) == ["pieceAdded", "pieceRemoved"])
        #expect(logged.map(\.sequence) == [1, 2] && logged.allSatisfy { $0.session == log.session })
        #expect(events.allSatisfy { $0.header?.device == JournalFixture.device && $0.header?.event != nil })
        // Never in the usage log, which has a gap where they are.
        #expect(UsageLog.readEvents(in: bench.usageFolder).events.map(\.sequence) == [0, 3])
        #expect(files.allSatisfy(JournalLayout.fits))
    }
}

@MainActor
@Suite final class JournalPieceRoundTests: GameTestBench {
    @Test func aRoundNamesItsPieceAndFileForTheJournal() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("clefwise-journal-scores-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("grand-staff.musicxml")
        try FileManager.default.copyItem(at: try #require(Fixtures.url("grand-staff.musicxml")), to: url)

        game.settings.mode = .practice
        game.openPiece(at: url)
        let entry = try #require(library.entries.first)
        game.start()
        let started = recorder.events.lazy.compactMap { if case .roundStarted(let round) = $0.event { round } else { nil } }.first
        let piece = try #require(started?.piece)
        #expect(piece.id == entry.pieceID && piece.file == entry.contentHash && piece.libraryID == entry.id)
        #expect(piece.staves == 2)
    }
}
