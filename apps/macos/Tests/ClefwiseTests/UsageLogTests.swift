import Foundation
import Testing
@testable import Clefwise

/// A clock tests move by hand; safe to read from the log's threads.
final class UsageTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// A folder of its own under the temporary directory, removed when the test is done.
final class UsageTestFolder {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClefwiseTests-\(UUID().uuidString)", isDirectory: true)

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Parses an ISO 8601 time with milliseconds, like the log's.
func usageTestTime(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text)!
}

@Suite struct UsageLogTests {
    private let temporary = UsageTestFolder()
    private var folder: URL { temporary.url.appendingPathComponent("Usage", isDirectory: true) }
    private let bucharest = TimeZone(identifier: "Europe/Bucharest")!

    private func action(_ name: String) -> UsageEvent { .uiAction(UIAction(name: name, detail: nil)) }

    private func lines(of file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).filter { !$0.isEmpty }
    }

    @Test func linesDecodeBackToWhatWasRecorded() throws {
        let clock = UsageTestClock(usageTestTime("2026-10-30T09:15:00.250Z"))
        let log = UsageLog(folder: folder, clock: { clock.now }, timeZone: bucharest)
        let events: [UsageEvent] = [
            .appLaunched(AppLaunched(appVersion: "0.1.0", build: "7", osVersion: "26.5", model: "Mac15,12",
                                     locale: "en_GB", timeZone: "Europe/Bucharest", screen: nil)),
            .settingChanged(SettingChanged(setting: "piece.hand", from: .string("right"), to: .string("both"))),
            .answerGiven(AnswerGiven(round: UUID(), question: UUID(), responseMs: 1820, source: .typing,
                                     letter: "F", accidental: 1, name: "Fa♯", pitch: nil, correct: true,
                                     wrongOctave: nil, keystrokes: [Keystroke(key: "f", ms: 900, result: .typed)],
                                     scoreAfter: 3, streakAfter: 3)),
        ]
        for event in events {
            log.record(event)
            clock.advance(1.5)
        }
        log.flush()

        let file = folder.appendingPathComponent("usage-2026-10-30.jsonl")
        let decoded = try lines(of: file).map { try LoggedEvent.decoder.decode(LoggedEvent.self, from: Data($0.utf8)) }
        #expect(decoded.map(\.event) == events)
        #expect(decoded.map(\.sequence) == [0, 1, 2])
        #expect(Set(decoded.map(\.session)) == [log.session])
        #expect(decoded.map(\.time) == [0, 1.5, 3].map { usageTestTime("2026-10-30T09:15:00.250Z").addingTimeInterval($0) })
        #expect(Set(decoded.map(\.id)).count == 3)
        #expect(UsageLog.eventFiles(in: folder) == [file])
    }

    @Test func flushMakesEverythingVisible() {
        let log = UsageLog(folder: folder)
        for index in 0..<500 { log.record(action("a\(index)")) }
        log.flush()
        let (events, unreadable) = UsageLog.readEvents(in: folder)
        #expect(events.count == 500 && unreadable == 0)
        #expect(events.map(\.sequence) == Array(0..<500))
    }

    @Test func newFileEachLocalDay() throws {
        // 21:59:59Z is 23:59:59 in Bucharest; two seconds later it's the 31st there but still the 30th in UTC.
        let clock = UsageTestClock(usageTestTime("2026-10-30T21:59:59.000Z"))
        let log = UsageLog(folder: folder, clock: { clock.now }, timeZone: bucharest)
        log.record(action("before midnight"))
        clock.advance(2)
        log.record(action("after midnight"))
        clock.advance(86_400)
        log.record(action("next day"))
        log.flush()

        #expect(UsageLog.eventFiles(in: folder).map(\.lastPathComponent)
                == ["usage-2026-10-30.jsonl", "usage-2026-10-31.jsonl", "usage-2026-11-01.jsonl"])
        for file in UsageLog.eventFiles(in: folder) { #expect(try lines(of: file).count == 1) }
        let (events, _) = UsageLog.readEvents(in: folder)
        #expect(events.map(\.event) == [action("before midnight"), action("after midnight"), action("next day")])
        #expect(events.map(\.sequence) == [0, 1, 2])
    }

    @Test func readingPutsEventsInTimeOrder() {
        // The Mac's clock set back an hour: the file has the later time first.
        let clock = UsageTestClock(usageTestTime("2026-10-30T10:00:00.000Z"))
        let log = UsageLog(folder: folder, clock: { clock.now }, timeZone: bucharest)
        log.record(action("later"))
        clock.advance(-3600)
        log.record(action("earlier"))
        log.flush()
        let events = UsageLog.readEvents(in: folder).events
        #expect(events.map(\.event) == [action("earlier"), action("later")])
        #expect(events.map(\.sequence) == [1, 0])
    }

    @Test func recordingFromManyThreadsKeepsWholeLines() throws {
        let log = UsageLog(folder: folder)
        DispatchQueue.concurrentPerform(iterations: 8) { thread in
            for index in 0..<250 { log.record(action("thread \(thread) event \(index)")) }
        }
        log.flush()
        let file = try #require(UsageLog.eventFiles(in: folder).first)
        let decoded = try lines(of: file).map { try LoggedEvent.decoder.decode(LoggedEvent.self, from: Data($0.utf8)) }
        // Written in the order they were numbered, with no number used twice.
        #expect(decoded.map(\.sequence) == Array(0..<2000))
        #expect(Set(decoded.map(\.event.type)) == ["uiAction"])
    }

    @Test func cutOffLineIsSkippedAndCounted() throws {
        let log = UsageLog(folder: folder)
        for index in 0..<3 { log.record(action("\(index)")) }
        log.flush()
        let file = try #require(UsageLog.eventFiles(in: folder).first)
        // As if the app crashed halfway through a line.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"schema":1,"type":"uiAction","id":"5C1"#.utf8))
        try handle.close()

        var read = UsageLog.readEvents(in: folder)
        #expect(read.events.count == 3 && read.unreadableLines == 1)

        // The next launch starts its first line on a line of its own rather than gluing it on.
        let relaunched = UsageLog(folder: folder)
        relaunched.record(action("after the crash"))
        relaunched.flush()
        read = UsageLog.readEvents(in: folder)
        #expect(read.events.count == 4 && read.unreadableLines == 1)
        #expect(read.events.last?.event == action("after the crash"))
    }

    @Test func recoversWhenTheFolderIsDeleted() throws {
        let log = UsageLog(folder: folder)
        log.record(action("first"))
        log.flush()
        try FileManager.default.removeItem(at: folder)
        log.record(action("second"))
        log.flush()
        let events = UsageLog.readEvents(in: folder).events
        #expect(events.map(\.event) == [action("second")])
        #expect(events.map(\.sequence) == [1])
    }

    @Test func carriesOnWhenItCantWrite() throws {
        // A file where the folder should be: nothing can be written, and nothing throws or crashes.
        try FileManager.default.createDirectory(at: temporary.url, withIntermediateDirectories: true)
        try Data("in the way".utf8).write(to: folder)
        let log = UsageLog(folder: folder)
        log.record(action("lost"))
        log.flush()
        #expect(UsageLog.readEvents(in: folder).events.isEmpty)

        try FileManager.default.removeItem(at: folder)
        log.record(action("kept"))
        log.flush()
        #expect(UsageLog.readEvents(in: folder).events.map(\.event) == [action("kept")])
    }

    @Test func readingAMissingFolderFindsNothing() {
        let read = UsageLog.readEvents(in: folder)
        #expect(read.events.isEmpty && read.unreadableLines == 0)
    }
}
