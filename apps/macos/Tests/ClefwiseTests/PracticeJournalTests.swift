import Foundation
import Testing
@testable import Clefwise

// The practice journal's folder: making it, finding it again, and adding files to it without ever
// changing one (spec/practice-journal.md).

@Suite struct PracticeJournalTests {
    private let bench = JournalTestBench()
    private var journal: PracticeJournal { bench.journal }
    private let round = UUID(uuidString: "5C1D2E3F-4A5B-4C6D-8E7F-9A0B1C2D3E4F")!
    private let start = usageTestTime("2026-11-05T09:31:12.948Z")

    /// A finished run's bytes, as the writer leaves them.
    private func runData(extra: [UsageEvent] = []) throws -> Data {
        let events = [JournalFixture.started(round), JournalFixture.answer(round)] + extra + [JournalFixture.ended(round)]
        return try JournalFixture.runFile(round, events, start: start).data
    }

    /// A finished run file outside the journal.
    private func runFile(named name: String = "run.jsonl", _ data: Data? = nil) throws -> URL {
        let folder = bench.temporary.url.appendingPathComponent("Elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try (data ?? runData()).write(to: url)
        return url
    }

    private var header: RunFileHeader {
        RunFileHeader(run: round, device: JournalFixture.device, launch: JournalFixture.launch)
    }

    private func pieceAdded(_ piece: JournalPieceFile, at time: Date) -> LoggedEvent {
        LoggedEvent(.pieceAdded(PieceAdded(piece: piece.hash, title: "Comptine", fileName: "Comptine.mxl",
                                           libraryID: UUID(), originalPath: "/Users/me/Scores/Comptine.mxl")),
                    session: UUID(), sequence: 3, time: time)
    }

    // MARK: - Making it

    @Test func makingAJournalWritesExactlyTheRootFiles() throws {
        let folder = try bench.makeJournal()
        #expect(folder == bench.documents.appendingPathComponent("Clefwise Journal", isDirectory: true))
        #expect(JournalTestBench.files(in: folder) == [".gitattributes", "clefwise.json"])
        #expect(try Data(contentsOf: folder.appendingPathComponent("clefwise.json")) == JournalLayout.markerContents)
        #expect(try Data(contentsOf: folder.appendingPathComponent(".gitattributes")) == JournalLayout.gitAttributesContents)
        #expect(journal.folder == folder && journal.isSet)
        #expect(bench.defaults.object(forKey: PracticeJournal.Keys.path) as? String == folder.path)
        #expect(bench.defaults.object(forKey: PracticeJournal.Keys.bookmark) is Data)
    }

    @Test func aJournalChosenAsTheLocationIsUsedAsItIs() throws {
        let existing = try bench.makeJournal()
        let notes = existing.appendingPathComponent("notes.txt")
        try Data("mine".utf8).write(to: notes)
        // Another device, or this one after its defaults were lost, picks the journal itself…
        let other = PracticeJournal(defaults: InMemoryDefaults())
        #expect(try other.create(named: "Clefwise Journal", in: existing) == existing)
        #expect(other.folder == existing)
        // … or the folder it's in, with its name: the same journal either way, untouched.
        #expect(try PracticeJournal(defaults: InMemoryDefaults()).create(named: "Clefwise Journal", in: bench.documents)
                == existing)
        #expect(JournalTestBench.files(in: existing) == [".gitattributes", "clefwise.json", "notes.txt"])
    }

    @Test func aFolderWithOtherThingsInItIsNotTaken() throws {
        let taken = bench.documents.appendingPathComponent("Clefwise Journal", isDirectory: true)
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: taken.appendingPathComponent("essay.txt"))
        #expect(PracticeJournal.suggestedName(in: bench.documents) == "Clefwise Journal 2")
        #expect(throws: JournalError.folderInUse(taken)) {
            try journal.create(named: "Clefwise Journal", in: bench.documents)
        }
        #expect(!journal.isSet)
        let made = try journal.create(named: "Clefwise Journal 2", in: bench.documents)
        #expect(made.lastPathComponent == "Clefwise Journal 2" && journal.folder == made)
        // An empty folder of that name is fine.
        let empty = bench.documents.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(try PracticeJournal(defaults: InMemoryDefaults()).create(named: "Empty", in: bench.documents) == empty)
    }

    @Test func theSuggestedNameIsTheJournalAlreadyThere() throws {
        #expect(PracticeJournal.suggestedName(in: bench.documents) == "Clefwise Journal")
        try bench.makeJournal()
        #expect(PracticeJournal.suggestedName(in: bench.documents) == "Clefwise Journal")
    }

    @Test func namesAFolderCannotHaveAreRefused() throws {
        for name in ["", "   ", ".hidden", "a/b", "a:b"] {
            #expect(throws: JournalError.self) { try journal.create(named: name, in: bench.documents) }
        }
        #expect(!journal.isSet)
    }

    // MARK: - Finding it

    @Test func thereIsNoJournalUntilOneIsSetOrWhenItIsGone() throws {
        #expect(journal.folder == nil && !journal.isSet)
        let folder = try bench.makeJournal()
        try FileManager.default.removeItem(at: folder)
        #expect(journal.folder == nil && journal.isSet)
        #expect(journal.lastKnownPath == folder.path)
    }

    @Test func aPathAloneFindsTheJournal() throws {
        let folder = try bench.makeJournal()
        // As a harness would preset it, with `defaults write`.
        let defaults = InMemoryDefaults()
        defaults.set(folder.path, forKey: PracticeJournal.Keys.path)
        let found = PracticeJournal(defaults: defaults)
        #expect(found.folder?.path == folder.path)
        #expect(defaults.object(forKey: PracticeJournal.Keys.bookmark) is Data, "a bookmark to follow it from now on")
    }

    @Test func theBookmarkFollowsAMovedFolder() throws {
        let folder = try bench.makeJournal()
        let moved = bench.temporary.url.appendingPathComponent("Synced/Practice", isDirectory: true)
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: folder, to: moved)

        let relaunched = PracticeJournal(defaults: bench.defaults)
        let found = try #require(relaunched.folder)
        #expect(found.resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path)
        let path = try #require(bench.defaults.object(forKey: PracticeJournal.Keys.path) as? String)
        #expect(URL(fileURLWithPath: path).resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path)
        // The journal already open finds it too.
        #expect(journal.folder?.resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path)
    }

    @Test func locatingTakesOnlyAJournal() throws {
        let folder = try bench.makeJournal()
        let other = PracticeJournal(defaults: InMemoryDefaults())
        #expect(throws: JournalError.notAJournal(bench.documents)) { try other.use(bench.documents) }
        #expect(!other.isSet)
        try other.use(folder)
        #expect(other.folder == folder)
    }

    // MARK: - Runs

    @Test func aRunIsMovedIntoItsMonthFolder() throws {
        let folder = try bench.makeJournal()
        let source = try runFile()
        let bytes = try Data(contentsOf: source)
        try journal.place(runFile: source, header: header, startedAt: start)
        let placed = folder.appendingPathComponent("runs/2026/11/20261105T093112Z-5c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f.jsonl")
        #expect(try Data(contentsOf: placed) == bytes)
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test func aRunNeedsAJournalAndARunID() throws {
        let source = try runFile()
        #expect(throws: JournalError.missing) { try journal.place(runFile: source, header: header, startedAt: start) }
        try bench.makeJournal()
        var eventHeader = header
        eventHeader.run = nil
        #expect(throws: JournalError.notARun) { try journal.place(runFile: source, header: eventHeader, startedAt: start) }
        #expect(FileManager.default.fileExists(atPath: source.path), "left to be placed later")
    }

    @Test func nothingInTheJournalIsEverReplaced() throws {
        let folder = try bench.makeJournal()
        let original = try runData()
        try journal.place(runFile: try runFile(original), header: header, startedAt: start)
        let path = JournalLayout.runPath(startedAt: start, run: round)

        // The same bytes again (placed before, then the app stopped): the copy just goes.
        let again = try runFile(named: "again.jsonl", original)
        try journal.place(runFile: again, header: header, startedAt: start)
        #expect(!FileManager.default.fileExists(atPath: again.path))
        #expect(try Data(contentsOf: folder.appendingPathComponent(path)) == original)

        // Different bytes: the journal's copy stays, and so does this one, where it was.
        let different = try runFile(named: "different.jsonl", try runData(extra: [JournalFixture.paused(round)]))
        #expect(throws: JournalError.clash(path: path)) {
            try journal.place(runFile: different, header: header, startedAt: start)
        }
        #expect(try Data(contentsOf: folder.appendingPathComponent(path)) == original)
        #expect(FileManager.default.fileExists(atPath: different.path))
    }

    // MARK: - Events and scores

    @Test func anEventFileIsItsHeaderAndItsOneLine() throws {
        let folder = try bench.makeJournal()
        let piece = JournalPieceFile(data: Data("<score-partwise/>".utf8), fileExtension: "mxl")
        let event = pieceAdded(piece, at: start)
        let eventHeader = RunFileHeader(event: UUID(), device: JournalFixture.device, launch: JournalFixture.launch)
        try journal.add(event: event, header: eventHeader, piece: piece)

        let path = JournalLayout.eventPath(at: start, event: event.id)
        var expectedHeader = eventHeader
        expectedHeader.event = event.id
        #expect(try Data(contentsOf: folder.appendingPathComponent(path)) == expectedHeader.encodedLine() + event.encodedLine())
        let read = RunFile.read(folder.appendingPathComponent(path))
        #expect(read.header == expectedHeader && read.events.map(\.event) == [event.event] && read.unreadableLines == 0)
        // The score is named by its hash, and nothing half-written is left about.
        #expect(try Data(contentsOf: folder.appendingPathComponent("pieces/\(piece.hash).mxl")) == piece.data)
        #expect(JournalTestBench.files(in: folder) == [".gitattributes", "clefwise.json", path, "pieces/\(piece.hash).mxl"].sorted())
    }

    @Test func aScoreAlreadyThereIsLeftAlone() throws {
        let folder = try bench.makeJournal()
        let piece = JournalPieceFile(data: Data("<score-partwise/>".utf8), fileExtension: "musicxml")
        let header = RunFileHeader(event: UUID(), device: JournalFixture.device, launch: JournalFixture.launch)
        try journal.add(event: pieceAdded(piece, at: start), header: header, piece: piece)
        let score = folder.appendingPathComponent(JournalLayout.piecePath(hash: piece.hash, fileExtension: "musicxml"))
        let before = try FileManager.default.attributesOfItem(atPath: score.path)[.systemFileNumber] as? Int
        try journal.add(event: pieceAdded(piece, at: start.addingTimeInterval(60)), header: header, piece: piece)
        let after = try FileManager.default.attributesOfItem(atPath: score.path)[.systemFileNumber] as? Int
        #expect(before != nil && before == after, "the same file, not written again")
        #expect(JournalTestBench.files(in: folder.appendingPathComponent("events")).count == 2)
    }

    @Test func aDamagedScoreIsPutBackAndAWrongHashRefused() throws {
        let folder = try bench.makeJournal()
        let piece = JournalPieceFile(data: Data("<score-partwise/>".utf8), fileExtension: "xml")
        let score = folder.appendingPathComponent(JournalLayout.piecePath(hash: piece.hash, fileExtension: "xml"))
        try FileManager.default.createDirectory(at: score.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<score-part".utf8).write(to: score)
        let header = RunFileHeader(event: UUID(), device: JournalFixture.device, launch: JournalFixture.launch)
        try journal.add(event: pieceAdded(piece, at: start), header: header, piece: piece)
        #expect(try Data(contentsOf: score) == piece.data)

        let wrong = JournalPieceFile(data: Data("other".utf8), hash: piece.hash, fileExtension: "xml")
        #expect(throws: JournalError.damagedScore(hash: piece.hash)) {
            try journal.add(event: pieceAdded(wrong, at: start), header: header, piece: wrong)
        }
        #expect(try Data(contentsOf: score) == piece.data)
    }

    @Test func anEventFileIsNeverReplacedEither() throws {
        let folder = try bench.makeJournal()
        let event = LoggedEvent(.pieceRemoved(PieceRemoved(piece: String(repeating: "a", count: 64))), session: UUID(),
                                sequence: 0, time: start)
        let header = RunFileHeader(event: UUID(), device: JournalFixture.device, launch: JournalFixture.launch)
        try journal.add(event: event, header: header, piece: nil)
        try journal.add(event: event, header: header, piece: nil) // the same bytes: fine
        var otherDevice = header
        otherDevice.device = UUID()
        let path = JournalLayout.eventPath(at: start, event: event.id)
        #expect(throws: JournalError.clash(path: path)) { try journal.add(event: event, header: otherDevice, piece: nil) }
        #expect(RunFile.read(folder.appendingPathComponent(path)).header?.device == JournalFixture.device)
        #expect(throws: JournalError.missing) {
            try PracticeJournal(defaults: InMemoryDefaults()).add(event: event, header: header, piece: nil)
        }
    }

    @Test func everythingWrittenFitsTheLayout() throws {
        let folder = try bench.makeJournal()
        try journal.place(runFile: try runFile(), header: header, startedAt: start)
        let piece = JournalPieceFile(data: Data("<score-partwise/>".utf8), fileExtension: "musicxml")
        let eventHeader = RunFileHeader(event: UUID(), device: JournalFixture.device, launch: JournalFixture.launch)
        try journal.add(event: pieceAdded(piece, at: start), header: eventHeader, piece: piece)
        let files = JournalTestBench.files(in: folder)
        #expect(files.count == 5)
        for path in files {
            #expect(JournalLayout.fits(path), "\(path)")
        }
    }
}
