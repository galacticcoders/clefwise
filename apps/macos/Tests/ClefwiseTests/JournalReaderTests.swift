import Foundation
import Testing
@testable import Clefwise

// Reading a journal's runs and event files (spec/practice-journal.md, "Folder sync" and
// "Reading"): in order, each file read once, files still arriving tried again, names that don't
// fit ignored.

@Suite struct JournalReaderTests {
    private let temporary = UsageTestFolder()
    private var folder: URL { temporary.url.appendingPathComponent("Journal", isDirectory: true) }
    private let start = usageTestTime("2026-11-05T09:31:12.250Z")

    // MARK: - Writing files as a journal holds them

    /// A run starting at `start`, answered, then ended unless it's still arriving, at its path in
    /// the journal.
    @discardableResult
    private func writeRun(_ round: UUID = UUID(), at start: Date, ended: Bool = true) throws
        -> (path: String, round: UUID, logged: [LoggedEvent]) {
        var events = [JournalFixture.started(round), JournalFixture.answer(round)]
        if ended { events.append(JournalFixture.ended(round)) }
        let file = try JournalFixture.runFile(round, events, start: start)
        let path = JournalLayout.runPath(startedAt: start, run: round)
        try write(file.data, at: path)
        return (path, round, file.logged)
    }

    /// An event file holding `event` at `time`, at its path in the journal.
    @discardableResult
    private func writeEvent(_ event: UsageEvent, at time: Date) throws -> (path: String, logged: LoggedEvent) {
        let logged = LoggedEvent(event, session: UUID(), sequence: 0, time: time)
        let header = RunFileHeader(event: logged.id, device: JournalFixture.device, launch: JournalFixture.launch)
        let path = JournalLayout.eventPath(at: time, event: logged.id)
        try write(try header.encodedLine() + logged.encodedLine(), at: path)
        return (path, logged)
    }

    private func write(_ data: Data, at path: String) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func snapshot(_ attempts: Int) -> UsageEvent {
        .statsSnapshot(StatsSnapshot(reason: "beforeUsageLog",
                                     noteStats: ["treble.C4": NoteStat(attempts: attempts, correct: attempts)]))
    }

    private func added(_ title: String) -> UsageEvent {
        .pieceAdded(PieceAdded(piece: String(repeating: "a", count: 64), title: title, fileName: "\(title).musicxml"))
    }

    // MARK: - Tests

    @Test func runsComeByStartThenIDAndEventsByTime() throws {
        // Written out of order; two start in the same millisecond.
        let late = try writeRun(at: start.addingTimeInterval(3600))
        let low = UUID(uuidString: "0A000000-0000-4000-8000-000000000000")!
        let high = UUID(uuidString: "F0000000-0000-4000-8000-000000000000")!
        try writeRun(high, at: start)
        try writeRun(low, at: start)
        // The name has the start to the second, and this one's id comes first; but the order goes by
        // its `roundStarted`, to the millisecond.
        let sameSecond = try writeRun(UUID(uuidString: "00000000-0000-4000-8000-000000000000")!,
                                      at: start.addingTimeInterval(0.5))

        let laterSnapshot = try writeEvent(snapshot(2), at: start.addingTimeInterval(60))
        let firstSnapshot = try writeEvent(snapshot(1), at: start)
        let removed = try writeEvent(.pieceRemoved(PieceRemoved(piece: String(repeating: "a", count: 64))),
                                     at: start.addingTimeInterval(120))
        let revised = try writeEvent(.pieceRevised(PieceRevised(piece: String(repeating: "a", count: 64),
                                                                file: String(repeating: "b", count: 64), title: "Tune")),
                                     at: start.addingTimeInterval(90))
        let first = try writeEvent(added("Tune"), at: start.addingTimeInterval(30))
        // Event files the reader keeps nowhere: not a snapshot or a library change.
        try writeEvent(JournalFixture.action("somethingElse"), at: start)

        let contents = JournalReader(folder: folder).read()
        #expect(contents.runs.map(\.id) == [low, high, sameSecond.round, late.round])
        #expect(contents.runs[2].startedAt == start.addingTimeInterval(0.5))
        #expect(contents.runs[3].path == late.path)
        #expect(contents.runs[3].events == late.logged)
        #expect(contents.runs[3].header == RunFileHeader(run: late.round, device: JournalFixture.device,
                                                          launch: JournalFixture.launch))
        #expect(contents.snapshots == [firstSnapshot.logged, laterSnapshot.logged])
        #expect(contents.pieceEvents == [first.logged, revised.logged, removed.logged])
        #expect(contents.skippedFiles == 0 && contents.unreadableLines == 0)
    }

    @Test func aFileIsReadOnce() throws {
        let run = try writeRun(at: start)
        let event = try writeEvent(snapshot(5), at: start)
        let reader = JournalReader(folder: folder)
        #expect(reader.read().runs.map(\.events) == [run.logged])

        // Files in a journal never change, so a file read once isn't read again: other bytes
        // under the same names don't show.
        let other = try JournalFixture.runFile(run.round, [JournalFixture.started(run.round), JournalFixture.ended(run.round)],
                                               start: start)
        try write(other.data, at: run.path)
        try write(Data("not a journal file\n".utf8), at: event.path)
        let again = reader.read()
        #expect(again.runs.map(\.events) == [run.logged])
        #expect(again.snapshots == [event.logged])
        #expect(again.skippedFiles == 0 && again.unreadableLines == 0)

        // A reader starting afresh reads what's there now.
        let fresh = JournalReader(folder: folder).read()
        #expect(fresh.runs.map(\.events) == [other.logged])
        #expect(fresh.snapshots.isEmpty && fresh.skippedFiles == 1)
    }

    @Test func newFilesAppearAndGoneOnesDisappear() throws {
        let reader = JournalReader(folder: folder)
        #expect(reader.read().runs.isEmpty) // no folder yet
        let first = try writeRun(at: start)
        #expect(reader.read().runs.count == 1)

        let second = try writeRun(at: start.addingTimeInterval(-60))
        let snapshot = try writeEvent(snapshot(3), at: start)
        var contents = reader.read()
        #expect(contents.runs.map(\.path) == [second.path, first.path])
        #expect(contents.snapshots == [snapshot.logged])

        try FileManager.default.removeItem(at: folder.appendingPathComponent(first.path))
        try FileManager.default.removeItem(at: folder.appendingPathComponent(snapshot.path))
        contents = reader.read()
        #expect(contents.runs.map(\.path) == [second.path])
        #expect(contents.snapshots.isEmpty)
    }

    @Test func aFileStillArrivingIsSkippedUntilItsComplete() throws {
        let round = UUID()
        let complete = try JournalFixture.runFile(round, [JournalFixture.started(round), JournalFixture.answer(round),
                                                          JournalFixture.ended(round)], start: start)
        let path = JournalLayout.runPath(startedAt: start, run: round)
        let lines = JournalTestBench.lines(complete.data)
        // Arriving: no `roundEnded` yet, then its last line cut off.
        try write(lines[0] + lines[1] + lines[2], at: path)
        let event = LoggedEvent(snapshot(4), session: UUID(), sequence: 0, time: start)
        let eventPath = JournalLayout.eventPath(at: start, event: event.id)
        let eventHeader = try RunFileHeader(event: event.id, device: JournalFixture.device, launch: JournalFixture.launch)
            .encodedLine()
        try write(eventHeader, at: eventPath) // its event line not there yet

        let reader = JournalReader(folder: folder)
        var contents = reader.read()
        #expect(contents.runs.isEmpty && contents.snapshots.isEmpty)
        #expect(contents.skippedFiles == 2)

        try write(lines[0] + lines[1] + lines[2] + lines[3].prefix(20), at: path)
        try write(eventHeader + (try event.encodedLine()).prefix(30), at: eventPath)
        contents = reader.read()
        #expect(contents.runs.isEmpty && contents.snapshots.isEmpty)
        #expect(contents.skippedFiles == 2)
        // A file skipped isn't counted for its lines.
        #expect(contents.unreadableLines == 0)

        try write(complete.data, at: path)
        try write(eventHeader + (try event.encodedLine()), at: eventPath)
        contents = reader.read()
        #expect(contents.runs.map(\.events) == [complete.logged])
        #expect(contents.snapshots == [event])
        #expect(contents.skippedFiles == 0)
    }

    @Test func namesThatDontFitAreIgnored() throws {
        let run = try writeRun(at: start)
        let bytes = try Data(contentsOf: folder.appendingPathComponent(run.path))
        let name = (run.path as NSString).lastPathComponent
        let monthFolder = (run.path as NSString).deletingLastPathComponent
        for junk in [
            "\(monthFolder)/.DS_Store",
            "\(monthFolder)/\(name.replacingOccurrences(of: ".jsonl", with: " (conflicted copy).jsonl"))",
            "\(monthFolder)/\(name.replacingOccurrences(of: ".jsonl", with: " 2.jsonl"))",
            "\(monthFolder)/.clefwise-\(UUID().uuidString).tmp",
            "\(monthFolder)/.\(name).icloud",
            "\(monthFolder)/\(name.uppercased())",
            "runs/2026/12/\(name)", // the wrong month for the time in its name
            "runs/\(name)",
        ] {
            try write(bytes, at: junk)
        }
        try write(bytes, at: "runs/.DS_Store")
        try write(bytes, at: "pieces/\(name)")
        try write(bytes, at: "notes.txt")

        let reader = JournalReader(folder: folder)
        for _ in 0..<2 {
            let contents = reader.read()
            #expect(contents.runs.map(\.path) == [run.path])
            #expect(contents.skippedFiles == 0 && contents.unreadableLines == 0)
        }
    }

    @Test func filesFromANewerFormatOrWithoutAHeaderAreSkipped() throws {
        let round = UUID()
        let complete = try JournalFixture.runFile(round, [JournalFixture.started(round), JournalFixture.answer(round),
                                                          JournalFixture.ended(round)], start: start)
        var newer = RunFileHeader(run: round, device: JournalFixture.device, launch: JournalFixture.launch)
        newer.format = RunFileHeader.currentFormat + 1
        let events = JournalTestBench.lines(complete.data).dropFirst().reduce(Data(), +)
        try write(try newer.encodedLine() + events, at: JournalLayout.runPath(startedAt: start, run: round))
        // No header at all: the events start on line 1.
        let headless = UUID()
        let file = try JournalFixture.runFile(headless, [JournalFixture.started(headless), JournalFixture.answer(headless),
                                                         JournalFixture.ended(headless)], start: start)
        try write(JournalTestBench.lines(file.data).dropFirst().reduce(Data(), +),
                  at: JournalLayout.runPath(startedAt: start, run: headless))

        let reader = JournalReader(folder: folder)
        for _ in 0..<2 {
            let contents = reader.read()
            #expect(contents.runs.isEmpty)
            #expect(contents.skippedFiles == 2)
        }
    }

    @Test func unreadableLinesInAKeptFileAreCountedAndLeftOut() throws {
        let round = UUID()
        let file = try JournalFixture.runFile(round, [JournalFixture.started(round), JournalFixture.answer(round),
                                                      JournalFixture.ended(round)], start: start)
        let lines = JournalTestBench.lines(file.data)
        try write(lines[0] + lines[1] + Data("{\"schema\":1,\"type\":\"fromTheFuture\"}\n".utf8) + lines[2] + lines[3],
                  at: JournalLayout.runPath(startedAt: start, run: round))
        let reader = JournalReader(folder: folder)
        for _ in 0..<2 {
            let contents = reader.read()
            #expect(contents.runs.map(\.events) == [file.logged])
            #expect(contents.unreadableLines == 1 && contents.skippedFiles == 0)
        }
    }

    @Test func readingFromSeveralThreadsAtOnceGivesTheSameContents() throws {
        for offset in 0..<20 { try writeRun(at: start.addingTimeInterval(Double(offset) * 60)) }
        let reader = JournalReader(folder: folder)
        let results = ResultBox()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            results.add(reader.read().runs.map(\.path))
        }
        let expected = JournalReader(folder: folder).read().runs.map(\.path)
        #expect(expected.count == 20)
        #expect(results.all.count == 8 && results.all.allSatisfy { $0 == expected })
    }

    @Test func theProjectionFoldsWhatTheReaderRead() throws {
        try writeEvent(snapshot(10), at: start)
        try writeRun(at: start.addingTimeInterval(60))
        try writeRun(at: start.addingTimeInterval(120), ended: false)
        let reader = JournalReader(folder: folder)
        let projection = JournalProjection(contents: reader.read())
        #expect(projection == JournalProjection.read(journal: folder))
        #expect(projection.runsRead == 1 && projection.runsSkipped == 1)
        #expect(projection.noteStats["treble.C4"]?.attempts == 10)
    }
}

/// Collects results from several threads.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [[String]] = []

    func add(_ result: [String]) { lock.withLock { results.append(result) } }
    var all: [[String]] { lock.withLock { results } }
}
