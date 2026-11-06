import Foundation
import Testing
@testable import Clefwise

// The device's side of a practice run: its working file, teed from the usage log, placed in the
// journal when it ends, kept on the device while the journal can't be reached, and found again at
// the next launch (spec/practice-journal.md, "Writing a run" and "After a crash").

@Suite struct RunFileWriterTests {
    private let bench = JournalTestBench()
    private let round = UUID()
    private let start = usageTestTime("2026-11-05T09:31:12.948Z")

    /// A log whose clock stands still at `start` unless moved.
    private func log(_ clock: UsageTestClock? = nil) -> UsageLog {
        let clock = clock ?? UsageTestClock(start)
        return UsageLog(folder: bench.usageFolder, clock: { clock.now })
    }

    /// Records a whole run with one answer: started, answered, ended.
    private func practise(_ round: UUID, in log: UsageLog) {
        log.record(JournalFixture.started(round))
        log.record(JournalFixture.answer(round))
        log.record(JournalFixture.ended(round))
    }

    private func runPath(_ round: UUID, startedAt: Date? = nil) -> String {
        JournalLayout.runPath(startedAt: startedAt ?? start, run: round)
    }

    // MARK: - While the app runs

    @Test func aRunsLinesAreTheDayFilesLinesUnderItsHeader() throws {
        let journal = try bench.makeJournal()
        let log = bench.makeLog()
        let writer = bench.makeWriter()
        #expect(writer.inspectAtLaunch() == nil)
        log.lineSink = writer
        log.record(.appLaunched(JournalFixture.launch))
        log.record(JournalFixture.started(round))
        log.record(JournalFixture.paused(round))
        // No round id, but it happened during the run: it belongs in the file too.
        log.record(.appActivity(AppActivity(active: false)))
        log.record(JournalFixture.answer(round))
        log.record(JournalFixture.ended(round))
        log.record(JournalFixture.action("afterwards"))
        log.flush()
        writer.outbox.waitUntilDone()

        let dayFile = try #require(UsageLog.eventFiles(in: bench.usageFolder).first)
        let dayLines = JournalTestBench.lines(try Data(contentsOf: dayFile))
        #expect(dayLines.count == 7)
        let startedAt = try #require(UsageLog.event(in: dayLines[1].dropLast())).time
        let runs = JournalTestBench.files(in: journal).filter { $0.hasPrefix("runs/") }
        #expect(runs == [runPath(round, startedAt: startedAt)])
        let runLines = JournalTestBench.lines(try Data(contentsOf: journal.appendingPathComponent(runs[0])))
        // Byte for byte, from the round's start to its end.
        #expect(Array(runLines.dropFirst()) == Array(dayLines[1...5]))

        let header = try #require(RunFileHeader(line: runLines[0]))
        #expect(runLines[0] == (try header.encodedLine()))
        #expect(header == RunFileHeader(run: round, device: JournalFixture.device, launch: JournalFixture.launch))
        #expect(header.format == 1 && header.run == round && header.event == nil && header.platform == "macOS")
        #expect([header.osVersion, header.model, header.appVersion, header.build, header.locale, header.timeZone]
                == ["26.5.2", "MacBookPro18,2", "0.1.0", "7", "sv_SE", "Europe/Stockholm"])
        #expect(JournalTestBench.files(in: bench.stateFolder).isEmpty, "nothing left on the device")
    }

    @Test func aRunWithNoAnswersGetsNoFile() throws {
        let journal = try bench.makeJournal()
        let log = bench.makeLog()
        let writer = bench.makeWriter()
        log.lineSink = writer
        log.record(JournalFixture.started(round))
        log.record(JournalFixture.paused(round))
        log.record(JournalFixture.ended(round))
        log.flush()
        writer.outbox.waitUntilDone()
        #expect(JournalTestBench.files(in: bench.stateFolder).isEmpty)
        #expect(JournalTestBench.files(in: journal) == [".gitattributes", "clefwise.json"])
    }

    @Test func aRoundStartedWhileAnotherIsOpenLeavesTheFirstWhereItIs() throws {
        let journal = try bench.makeJournal()
        let log = bench.makeLog()
        let writer = bench.makeWriter()
        log.lineSink = writer
        let first = UUID()
        log.record(JournalFixture.started(first))
        log.record(JournalFixture.answer(first))
        practise(round, in: log)
        log.flush()
        writer.outbox.waitUntilDone()

        #expect(JournalTestBench.files(in: journal).filter { $0.hasPrefix("runs/") }.count == 1)
        let left = bench.currentFolder.appendingPathComponent("\(first.uuidString.lowercased()).jsonl")
        let read = RunFile.read(left)
        #expect(read.header?.run == first)
        #expect(read.events.map(\.event.type) == ["roundStarted", "answerGiven"])
    }

    // MARK: - Without the journal

    @Test func recordsWaitWhileThereIsNoJournalAndGoInOnceThereIsOne() throws {
        let log = log()
        let writer = bench.makeWriter()
        log.lineSink = writer
        practise(round, in: log)
        let recorder = JournalEventRecorder(outbox: writer.outbox, device: JournalFixture.device,
                                            launch: JournalFixture.launch, log: log, clock: { self.start })
        let piece = JournalPieceFile(data: Data("<score-partwise/>".utf8), fileExtension: "musicxml")
        recorder.recordInJournal(.pieceAdded(PieceAdded(piece: piece.hash, title: "Comptine", fileName: "Comptine.musicxml")),
                                 piece: piece)
        log.flush()
        writer.outbox.waitUntilDone()

        let waiting = JournalTestBench.files(in: bench.pendingFolder)
        #expect(waiting.count == 3)
        #expect(waiting.contains(runPath(round)) && waiting.contains("pieces/\(piece.hash).musicxml"))
        #expect(waiting.allSatisfy(JournalLayout.fits))
        #expect(JournalTestBench.files(in: bench.currentFolder).isEmpty)

        let journal = try bench.makeJournal()
        writer.outbox.placePending()
        writer.outbox.waitUntilDone()
        let placed = JournalTestBench.files(in: journal)
        #expect(placed == ([".gitattributes", "clefwise.json"] + waiting).sorted())
        #expect(JournalTestBench.files(in: bench.pendingFolder).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: bench.pendingFolder.appendingPathComponent("runs").path),
                "empty folders tidied away")
        // The event is numbered in the log's session, between the run's events.
        let event = try #require(placed.first { $0.hasPrefix("events/") })
        let read = RunFile.read(journal.appendingPathComponent(event))
        #expect(read.events.first?.session == log.session && read.events.first?.sequence == 3)
        #expect(read.header?.event == read.events.first?.id && read.header?.run == nil)
    }

    @Test func recordsWaitingGoInWithTheNextOneThatDoes() throws {
        let clock = UsageTestClock(start)
        let log = log(clock)
        let writer = bench.makeWriter()
        log.lineSink = writer
        practise(round, in: log)
        log.flush()
        writer.outbox.waitUntilDone()
        #expect(JournalTestBench.files(in: bench.pendingFolder) == [runPath(round)])

        let journal = try bench.makeJournal()
        let next = UUID()
        clock.advance(600)
        practise(next, in: log)
        log.flush()
        writer.outbox.waitUntilDone()
        #expect(JournalTestBench.files(in: journal).filter { $0.hasPrefix("runs/") }
                == [runPath(round), runPath(next, startedAt: clock.now)].sorted())
        #expect(JournalTestBench.files(in: bench.pendingFolder).isEmpty)
    }

    @Test func aRunThatClashesIsKeptAsideAndTheJournalsCopyStays() throws {
        let journal = try bench.makeJournal()
        let path = runPath(round)
        let theirs = journal.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: theirs.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("another device's\n".utf8).write(to: theirs)

        let log = log()
        let writer = bench.makeWriter()
        log.lineSink = writer
        practise(round, in: log)
        log.flush()
        writer.outbox.waitUntilDone()
        #expect(try Data(contentsOf: theirs) == Data("another device's\n".utf8))
        let kept = bench.pendingFolder.appendingPathComponent("kept/\(path)")
        #expect(RunFile.read(kept).header?.run == round)
        #expect(JournalTestBench.files(in: bench.pendingFolder) == ["kept/\(path)"])

        // Kept aside for good: not tried again.
        writer.outbox.placePending()
        writer.outbox.waitUntilDone()
        #expect(JournalTestBench.files(in: bench.pendingFolder) == ["kept/\(path)"])
    }

    // MARK: - At launch

    @Test func aRunThatEndedButWasNotPlacedIsPlacedAtLaunch() throws {
        let journal = try bench.makeJournal()
        let events = [JournalFixture.started(round), JournalFixture.answer(round), JournalFixture.ended(round)]
        let file = try JournalFixture.runFile(round, events, start: start)
        try bench.leaveWorkingFile(round, file.data)
        let writer = bench.makeWriter()
        #expect(writer.inspectAtLaunch() == nil)
        writer.outbox.waitUntilDone()
        #expect(try Data(contentsOf: journal.appendingPathComponent(runPath(round))) == file.data)
        #expect(JournalTestBench.files(in: bench.stateFolder).isEmpty)
    }

    @Test func runsWithNoAnswersAreDeletedAtLaunch() throws {
        let journal = try bench.makeJournal()
        let unfinished = UUID(), ended = UUID(), cutOff = UUID()
        try bench.leaveWorkingFile(unfinished, JournalFixture.runFile(unfinished, [JournalFixture.started(unfinished),
                                                                                  JournalFixture.paused(unfinished)],
                                                                      start: start).data)
        try bench.leaveWorkingFile(ended, JournalFixture.runFile(ended, [JournalFixture.started(ended),
                                                                        JournalFixture.ended(ended)], start: start).data)
        // Stopped while writing its header.
        try bench.leaveWorkingFile(cutOff, Data(#"{"appVersion":"0.1.0","bui"#.utf8))
        let writer = bench.makeWriter()
        #expect(writer.inspectAtLaunch() == nil)
        writer.outbox.waitUntilDone()
        #expect(JournalTestBench.files(in: bench.stateFolder).isEmpty)
        #expect(JournalTestBench.files(in: journal) == [".gitattributes", "clefwise.json"])
    }

    @Test func anUnfinishedRunIsReopenedAndTheNewLaunchCarriesOnInIt() throws {
        let journal = try bench.makeJournal()
        let before = [JournalFixture.started(round), JournalFixture.answer(round), JournalFixture.paused(round)]
        let file = try JournalFixture.runFile(round, before, start: start)
        // The crash cut the last line off.
        let left = file.data + Data(#"{"schema":1,"type":"answerGiven","id":"5C1"#.utf8)
        let url = try bench.leaveWorkingFile(round, left)

        let writer = bench.makeWriter()
        let pending = try #require(writer.inspectAtLaunch())
        #expect(pending.round == round && pending.file == url)
        #expect(pending.events.map(\.id) == file.logged.map(\.id) && pending.events.map(\.event) == before)

        // This launch's lines go on in it, from its `appLaunched`, until the round ends.
        let log = bench.makeLog()
        log.lineSink = writer
        let after: [UsageEvent] = [
            .appLaunched(JournalFixture.launch),
            .roundRestored(RoundRestored(round: round, activeMs: 4_000, unansweredQuestion: nil)),
            JournalFixture.answer(round),
            JournalFixture.ended(round),
        ]
        for event in after { log.record(event) }
        log.flush()
        writer.outbox.waitUntilDone()

        let placed = journal.appendingPathComponent(runPath(round))
        let data = try Data(contentsOf: placed)
        #expect(data.starts(with: left + Data([0x0A])), "the cut-off line ended, nothing before it changed")
        let read = RunFile.read(placed)
        #expect(read.header == RunFileHeader(run: round, device: JournalFixture.device, launch: JournalFixture.launch))
        #expect(read.events.map(\.event) == before + after)
        #expect(read.unreadableLines == 1)
        #expect(JournalTestBench.files(in: bench.stateFolder).isEmpty)
    }

    @Test func ofSeveralUnfinishedRunsTheNewestComesBack() throws {
        try bench.makeJournal()
        let older = UUID()
        let olderFile = try JournalFixture.runFile(older, [JournalFixture.started(older), JournalFixture.answer(older)],
                                                   start: start)
        let olderURL = try bench.leaveWorkingFile(older, olderFile.data)
        let newerFile = try JournalFixture.runFile(round, [JournalFixture.started(round), JournalFixture.answer(round)],
                                                   start: start.addingTimeInterval(3_600))
        try bench.leaveWorkingFile(round, newerFile.data)

        let pending = try #require(bench.makeWriter().inspectAtLaunch())
        #expect(pending.round == round)
        #expect(try Data(contentsOf: olderURL) == olderFile.data, "left as it was")
    }

    @Test func recordsWaitingFromLastTimeGoInAtLaunch() throws {
        let log = log()
        let writer = bench.makeWriter()
        log.lineSink = writer
        practise(round, in: log)
        log.flush()
        writer.outbox.waitUntilDone()
        #expect(JournalTestBench.files(in: bench.pendingFolder) == [runPath(round)])

        let journal = try bench.makeJournal()
        let relaunched = bench.makeWriter()
        #expect(relaunched.inspectAtLaunch() == nil)
        #expect(relaunched.outbox.waitUntilDone(timeout: 5))
        #expect(JournalTestBench.files(in: journal).contains(runPath(round)))
        #expect(JournalTestBench.files(in: bench.pendingFolder).isEmpty)
    }
}
