import Foundation
import Testing
@testable import Clefwise

// How `Game` keeps pieces in the library, reopens them with their own settings, and logs it. Every
// test has its own library and its own copies of the fixtures, standing in for the user's files.

@MainActor
@Suite final class PieceLibraryGameTests: GameTestBench {
    /// The user's own folder of scores, which they may tidy up behind the app's back.
    private let scores = FileManager.default.temporaryDirectory
        .appendingPathComponent("clefwise-scores-\(UUID().uuidString)", isDirectory: true)

    /// A copy of the fixture `name` in the user's folder (or a folder inside it).
    private func userFile(_ name: String, in folder: String? = nil, as fileName: String? = nil) throws -> URL {
        let source = try #require(Fixtures.url(name))
        let directory = folder.map { scores.appendingPathComponent($0, isDirectory: true) } ?? scores
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName ?? name)
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    private var pieceEvents: [UsageEvent] {
        recorder.events.map(\.event).filter {
            switch $0 {
            case .pieceOpened, .pieceOpenFailed, .pieceClosed: true
            default: false
            }
        }
    }

    private var lastOpened: PieceOpened? {
        pieceEvents.reversed().lazy.compactMap { if case .pieceOpened(let opened) = $0 { opened } else { nil } }.first
    }

    // MARK: - Keeping pieces

    @Test func openingAFileKeepsItInTheLibrary() throws {
        let url = try userFile("bar-view.musicxml")
        game.openPiece(at: url)
        let entry = try #require(library.entries.first)
        #expect(library.entries.count == 1)
        #expect(entry.title == "Lantern at Dusk" && entry.originalPath == url.path)
        #expect(game.pieceEntryID == entry.id && game.pieceURL == url)
        #expect(game.settings.pieceID == entry.id && game.settings.piecePath == url.path)
        // From the start, with the settings it opened with.
        #expect(entry.settings != nil && library.entry(id: entry.id)?.settings == game.settings.piece)
        #expect(lastOpened?.libraryID == entry.id && lastOpened?.restoredSettings == false)
    }

    @Test func theCopyOpensWhenTheOriginalIsGone() throws {
        let url = try userFile("bar-view.musicxml")
        game.openPiece(at: url)
        let entry = try #require(library.entries.first)
        try FileManager.default.removeItem(at: url)
        game.closePiece()
        #expect(!library.isEmpty) // closing keeps it

        game.open(entry)
        #expect(game.pieceError == nil)
        #expect(game.piece?.title == "Lantern at Dusk")
        // Still known by the original path, so its rounds and progress stay together.
        #expect(game.pieceURL?.path == url.path && game.pieceEntryID == entry.id)
        #expect(lastOpened?.via == .library && lastOpened?.path == url.path)
    }

    @Test func theSameFileElsewhereIsTheSamePiece() throws {
        let first = try userFile("bar-view.musicxml", in: "Scores")
        let second = try userFile("bar-view.musicxml", in: "Downloads", as: "lantern.musicxml")
        game.openPiece(at: first)
        game.openPiece(at: second)
        #expect(library.entries.count == 1)
        #expect(game.pieceURL == first)
        #expect(lastOpened?.path == first.path)
    }

    @Test func theLibrarysOwnCopyPickedInFinderIsThatPiece() throws {
        game.openPiece(at: try userFile("bar-view.musicxml"))
        let entry = try #require(library.entries.first)
        game.openPiece(at: library.fileURL(for: entry), via: .drop)
        #expect(library.entries.count == 1 && game.pieceEntryID == entry.id)
        // Not called by the copy's file name (its id).
        #expect(game.piece?.title == "Lantern at Dusk")
    }

    // MARK: - Settings per piece

    @Test func eachPieceKeepsItsOwnSettings() throws {
        game.openPiece(at: try userFile("bar-view.musicxml"))
        let lantern = try #require(game.pieceEntryID)
        game.settings.piece.startBar = 4
        game.settings.piece.hand = .left

        // A piece new to the library starts at bar 1, with the other settings as they are.
        game.openPiece(at: try userFile("voice-and-piano.musicxml"))
        let evening = try #require(game.pieceEntryID)
        #expect(game.settings.piece.startBar == 1 && game.settings.piece.hand == .left)
        game.settings.piece.order = .shuffled
        game.settings.piece.hand = .both

        game.open(try #require(library.entry(id: lantern)))
        #expect(game.settings.piece.startBar == 4 && game.settings.piece.hand == .left)
        #expect(game.settings.piece.order == .inOrder)
        #expect(lastOpened?.restoredSettings == true)

        game.open(try #require(library.entry(id: evening)))
        #expect(game.settings.piece.order == .shuffled && game.settings.piece.hand == .both)
        #expect(game.settings.piece.startBar == 1)
    }

    @Test func restoredSettingsAreLoggedWithThePieceNotAsChanges() throws {
        game.openPiece(at: try userFile("bar-view.musicxml"))
        let lantern = try #require(game.pieceEntryID)
        game.settings.piece.startBar = 4
        game.openPiece(at: try userFile("voice-and-piano.musicxml"))

        let before = recorder.events.count
        game.open(try #require(library.entry(id: lantern)))
        let changed = recorder.events.dropFirst(before).compactMap {
            if case .settingChanged(let change) = $0.event { change.setting } else { nil }
        }
        // Which piece is open changes; the piece settings only come back.
        #expect(!changed.contains { $0.hasPrefix("piece.") })
        #expect(changed.contains("pieceID") && changed.contains("piecePath"))
        let opened = try #require(lastOpened)
        #expect(opened.restoredSettings == true)
        #expect(opened.pieceSettings == JSONValue(encoding: game.settings.piece))

        // A change after that is the user's, and logged.
        game.settings.piece.startBar = 2
        #expect(recorder.events.contains {
            if case .settingChanged(let change) = $0.event { change.setting == "piece.startBar" && change.to == .number(2) }
            else { false }
        })
        #expect(library.entry(id: lantern)?.settings?.startBar == 2)
    }

    @Test func roundsAndClosingKnowTheLibraryEntry() throws {
        let url = try userFile("bar-view.musicxml")
        game.openPiece(at: url)
        let id = try #require(game.pieceEntryID)
        game.start()
        let started = recorder.events.lazy.compactMap { if case .roundStarted(let round) = $0.event { round } else { nil } }.first
        #expect(started?.piece?.libraryID == id)
        game.closePiece()
        guard case .pieceClosed(let closed) = try #require(pieceEvents.last) else {
            Issue.record("the last piece event isn't pieceClosed")
            return
        }
        #expect(closed.path == url.path && closed.libraryID == id)
    }

    // MARK: - At launch

    @Test func launchReopensTheCopyWithItsSettings() throws {
        let url = try userFile("bar-view.musicxml")
        game.openPiece(at: url)
        game.settings.piece.startBar = 3
        try FileManager.default.removeItem(at: url)

        let launch = MemoryUsageRecorder()
        let relaunched = relaunch(recorder: launch)
        #expect(relaunched.piece?.title == "Lantern at Dusk")
        #expect(relaunched.pieceEntryID == game.pieceEntryID)
        #expect(relaunched.settings.piece.startBar == 3)
        #expect(relaunched.pieceURL == url)
    }

    @Test func settingsFromBeforeTheLibraryBringTheLastPieceIn() throws {
        // What the app saved before the library: only the last file's path.
        let url = try userFile("bar-view.musicxml")
        game.open(try MusicXMLImporter.load(from: url), from: url)
        game.settings.piece.startBar = 5
        #expect(game.settings.piecePath == url.path && game.settings.pieceID == nil && library.isEmpty)

        let relaunched = relaunch()
        let entry = try #require(library.entries.first)
        #expect(entry.originalPath == url.path)
        #expect(relaunched.piece?.title == "Lantern at Dusk" && relaunched.pieceEntryID == entry.id)
        #expect(relaunched.settings.pieceID == entry.id)
        // The same piece as before: its settings carry on, bar 5 included.
        #expect(relaunched.settings.piece.startBar == 5 && entry.settings?.startBar == 5)
    }

    @Test func aPieceTakenOffTheListIsForgottenAtLaunch() throws {
        game.openPiece(at: try userFile("bar-view.musicxml"))
        let id = try #require(game.pieceEntryID)
        library.remove(id)

        let launch = MemoryUsageRecorder()
        let relaunched = relaunch(recorder: launch)
        #expect(relaunched.piece == nil && relaunched.pieceError == nil)
        #expect(relaunched.settings.pieceID == nil && relaunched.settings.piecePath == nil)
        #expect(launch.events.contains {
            if case .pieceOpenFailed(let failed) = $0.event { failed.libraryID == id && failed.via == .launch } else { false }
        })
    }

    @Test func anUnreadableCopySaysWhatToDo() throws {
        let url = try userFile("bar-view.musicxml")
        game.openPiece(at: url)
        let entry = try #require(library.entries.first)
        game.closePiece()
        try Data("not a score".utf8).write(to: library.fileURL(for: entry))

        game.open(entry)
        let error = try #require(game.pieceError)
        #expect(error.contains("can no longer be read") && error.contains("bar-view.musicxml"))
        #expect(game.piece == nil && library.entry(id: entry.id) != nil)

        // Opening the original again mends it.
        game.openPiece(at: url)
        #expect(game.pieceEntryID == entry.id && library.entries.count == 1)
        game.closePiece()
        game.open(try #require(library.entry(id: entry.id)))
        #expect(game.piece?.title == "Lantern at Dusk")
    }

    @Test func closingKeepsThePieceButNothingReopens() throws {
        game.openPiece(at: try userFile("bar-view.musicxml"))
        game.closePiece()
        #expect(library.entries.count == 1)
        #expect(game.settings.pieceID == nil && game.settings.piecePath == nil)
        #expect(relaunch().piece == nil)
    }

    // MARK: - What the lists show

    @Test func isOpenIsTheGamesEntry() throws {
        game.openPiece(at: try userFile("bar-view.musicxml"))
        game.openPiece(at: try userFile("voice-and-piano.musicxml"))
        #expect(library.entries.map { $0.isOpen(in: game) } == [true, false])
        game.closePiece()
        #expect(library.entries.allSatisfy { !$0.isOpen(in: game) })
    }
}

@Suite struct PieceListWordsTests {
    private func entry(_ title: String, _ path: String) -> PieceLibrary.Entry {
        PieceLibrary.Entry(id: UUID(), title: title, originalPath: path, fileName: "x.musicxml", contentHash: "",
                           addedAt: .now, lastOpenedAt: .now, settings: nil)
    }

    @Test func titlesThatClashGetTheirFileOrFolder() {
        let minuet = entry("Minuet", "/Users/me/Scores/minuet.musicxml")
        let minuetToo = entry("Minuet", "/Users/me/Scores/minuet-in-g.musicxml")
        let sameName = entry("Etude", "/Users/me/A/etude.musicxml")
        let sameNameToo = entry("Etude", "/Users/me/B/etude.musicxml")
        let alone = entry("Song", "/Users/me/song.musicxml")
        let untitled = entry("  ", "/Users/me/Scores/sketch.mxl")
        let titles = [minuet, minuetToo, sameName, sameNameToo, alone, untitled].distinctTitles()
        #expect(titles[minuet.id] == "Minuet (minuet.musicxml)")
        #expect(titles[minuetToo.id] == "Minuet (minuet-in-g.musicxml)")
        #expect(titles[sameName.id]?.hasPrefix("Etude (") == true && titles[sameName.id]?.contains("/A/etude") == true)
        #expect(titles[alone.id] == "Song")
        #expect(titles[untitled.id] == "sketch")
    }

    @Test func datesReadAsDaysThenADate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Stockholm"))
        calendar.locale = Locale(identifier: "en_GB")
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9)))
        func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now)! }
        #expect(PieceDates.relative(now, now: now, calendar: calendar) == "today")
        #expect(PieceDates.relative(daysAgo(1), now: now, calendar: calendar) == "yesterday")
        #expect(PieceDates.relative(daysAgo(6), now: now, calendar: calendar) == "6 days ago")
        #expect(PieceDates.relative(daysAgo(7), now: now, calendar: calendar) == "27 Oct")
        // Another year adds the year (the month's short name depends on the locale data).
        #expect(PieceDates.relative(daysAgo(400), now: now, calendar: calendar).hasSuffix("2025"))
        #expect(!PieceDates.relative(daysAgo(7), now: now, calendar: calendar).contains("2026"))
        // A clock put back reads as today.
        #expect(PieceDates.relative(daysAgo(-1), now: now, calendar: calendar) == "today")
    }
}
