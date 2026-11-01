import Foundation
import Testing
@testable import Clefwise

extension PieceLibrary {
    /// A library in a folder of its own under the temporary directory, for tests.
    static func temporary() -> PieceLibrary {
        PieceLibrary(folder: FileManager.default.temporaryDirectory
            .appendingPathComponent("clefwise-library-\(UUID().uuidString)", isDirectory: true))
    }
}

@MainActor
@Suite struct PieceLibraryTests {
    private let library = PieceLibrary.temporary()
    private let elsewhere = FileManager.default.temporaryDirectory
        .appendingPathComponent("clefwise-library-originals-\(UUID().uuidString)", isDirectory: true)

    /// A file outside the library, as a user would open it.
    private func original(_ name: String, _ text: String) throws -> URL {
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let url = elsewhere.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func addingCopiesTheFileAndRemembersIt() throws {
        let url = try original("Minuet.musicxml", "<score-partwise/>")
        let start = Date(timeIntervalSince1970: 1_000)
        let entry = try library.add(url, title: "Minuet", now: start)
        #expect(entry.title == "Minuet" && entry.originalPath == url.path && entry.addedAt == start)
        #expect(entry.fileName.hasSuffix(".musicxml"))
        #expect(try Data(contentsOf: library.fileURL(for: entry)) == Data("<score-partwise/>".utf8))

        // The original can go; the copy stays, and a new library on the same folder finds it.
        try FileManager.default.removeItem(at: url)
        let reopened = PieceLibrary(folder: library.folder)
        #expect(reopened.entries == [entry])
        #expect(FileManager.default.fileExists(atPath: reopened.fileURL(for: entry).path))
    }

    @Test func theSameBytesAreTheSameEntry() throws {
        let first = try library.add(try original("a.musicxml", "same"), title: "A", now: Date(timeIntervalSince1970: 1))
        let again = try library.add(try original("copy of a.musicxml", "same"), title: "A again",
                                    now: Date(timeIntervalSince1970: 2))
        #expect(again.id == first.id && library.entries.count == 1)
        // Known by where it was first opened from; title and time follow the latest opening.
        #expect(again.originalPath == first.originalPath && again.title == "A again")
        #expect(again.lastOpenedAt == Date(timeIntervalSince1970: 2))

        // Opening the library's own copy is the same entry too.
        let fromCopy = try library.add(library.fileURL(for: again), title: "A", now: Date(timeIntervalSince1970: 3))
        #expect(fromCopy.id == first.id && fromCopy.originalPath == first.originalPath)
    }

    @Test func aScoreExportedAgainToTheSamePathUpdatesItsEntry() throws {
        let url = try original("Piece.musicxml", "version 1")
        var entry = try library.add(url, title: "Piece")
        var settings = Game.PieceSettings()
        settings.startBar = 9
        library.save(settings: settings, for: entry.id)
        try Data("version 2".utf8).write(to: url)
        entry = try library.add(url, title: "Piece")
        #expect(library.entries.count == 1 && entry.settings == settings)
        #expect(try Data(contentsOf: library.fileURL(for: entry)) == Data("version 2".utf8))
    }

    @Test func mostRecentlyOpenedComesFirst() throws {
        let a = try library.add(try original("a.musicxml", "a"), title: "A", now: Date(timeIntervalSince1970: 1))
        let b = try library.add(try original("b.musicxml", "b"), title: "B", now: Date(timeIntervalSince1970: 2))
        #expect(library.entries.map(\.id) == [b.id, a.id])
        try library.add(library.fileURL(for: a), title: "A", now: Date(timeIntervalSince1970: 3))
        #expect(library.entries.map(\.id) == [a.id, b.id])
        #expect(PieceLibrary(folder: library.folder).entries.map(\.id) == [a.id, b.id])
    }

    @Test func settingsAreKeptPerPiece() throws {
        let entry = try library.add(try original("a.musicxml", "a"), title: "A")
        var settings = Game.PieceSettings()
        settings.hand = .both
        settings.chords = .together
        library.save(settings: settings, for: entry.id)
        #expect(PieceLibrary(folder: library.folder).entry(id: entry.id)?.settings == settings)
    }

    @Test func removingDeletesTheCopyButNotTheOriginal() throws {
        let url = try original("a.musicxml", "a")
        let entry = try library.add(url, title: "A")
        library.remove(entry.id)
        #expect(library.isEmpty && library.entry(id: entry.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: library.fileURL(for: entry).path))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(PieceLibrary(folder: library.folder).isEmpty)
    }

    @Test func anUnreadableIndexIsSetAside() throws {
        try FileManager.default.createDirectory(at: library.folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: library.folder.appendingPathComponent("index.json"))
        let reopened = PieceLibrary(folder: library.folder)
        #expect(reopened.isEmpty)
        let kept = try FileManager.default.contentsOfDirectory(atPath: library.folder.path)
        #expect(kept.contains { $0.hasPrefix("index-unreadable-") })
    }

    @Test func aMissingCopyIsWrittenBack() throws {
        let url = try original("a.musicxml", "a")
        let entry = try library.add(url, title: "A")
        try FileManager.default.removeItem(at: library.fileURL(for: entry))
        try library.add(url, title: "A")
        #expect(FileManager.default.fileExists(atPath: library.fileURL(for: entry).path))
    }
}
