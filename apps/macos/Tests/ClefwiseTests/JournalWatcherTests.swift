import Foundation
import Testing
@testable import Clefwise

// Watching the journal's folder for files arriving (`FSEventsJournalWatcher`), in a temporary folder
// of each test's own. The quiet interval is shorter than the app's, and waits poll with a timeout.

@MainActor
@Suite struct JournalWatcherTests {
    private let temporary = UsageTestFolder()
    private var folder: URL { temporary.url.appendingPathComponent("Clefwise Journal", isDirectory: true) }

    /// Counts the calls to `onChange`, and checks each comes on the main thread.
    @MainActor
    final class Calls {
        private(set) var count = 0
        private(set) var allOnMainThread = true

        var onChange: @MainActor @Sendable () -> Void {
            { [self] in
                count += 1
                allOnMainThread = allOnMainThread && Thread.isMainThread
            }
        }
    }

    private func makeFolder(_ path: String = "") throws -> URL {
        let url = path.isEmpty ? folder : folder.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ name: String, in folder: URL) throws {
        try Data("{}\n".utf8).write(to: folder.appendingPathComponent(name))
    }

    /// Polls until `condition` holds, for up to `seconds`.
    private func waitUntil(seconds: Double = 5, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Starts `watcher` on `folder`, and waits out any report of the folders just made: FSEvents can
    /// still report changes from just before a watch began. Returns the calls so far.
    private func start(_ watcher: FSEventsJournalWatcher, on folder: URL, _ calls: Calls,
                       settling seconds: Double = 0.8) async throws -> Int {
        watcher.start(watching: folder, onChange: calls.onChange)
        try await settle(seconds)
        return calls.count
    }

    /// Gives a call that shouldn't come the time it would need: past the quiet interval, and
    /// FSEvents' own delay.
    private func settle(_ seconds: Double = 0.8) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    @Test func aFileWrittenInTheFolderCallsBackOnTheMainThread() async throws {
        let watched = try makeFolder()
        let calls = Calls()
        let watcher = FSEventsJournalWatcher(quietInterval: 0.1)
        watcher.start(watching: watched, onChange: calls.onChange)
        try write("clefwise.json", in: watched)
        try await waitUntil { calls.count > 0 }
        #expect(calls.count >= 1 && calls.allOnMainThread)
    }

    @Test func aFileDeepInTheFolderCallsBack() async throws {
        let watched = try makeFolder()
        let month = try makeFolder("runs/2026/11")
        let calls = Calls()
        let watcher = FSEventsJournalWatcher(quietInterval: 0.1)
        watcher.start(watching: watched, onChange: calls.onChange)
        try write("20261107T093112Z-\(UUID().uuidString.lowercased()).jsonl", in: month)
        try await waitUntil { calls.count > 0 }
        #expect(calls.count >= 1)
    }

    @Test func aBurstOfFilesCallsBackOnce() async throws {
        let watched = try makeFolder()
        let events = try makeFolder("events/2026/11")
        let calls = Calls()
        let watcher = FSEventsJournalWatcher(quietInterval: 0.5, longestWait: 5)
        let before = try await start(watcher, on: watched, calls, settling: 1.2)
        for _ in 0..<25 {
            try write("20261107T101500Z-\(UUID().uuidString.lowercased()).jsonl", in: events)
        }
        try await waitUntil { calls.count > before }
        try await settle(1.2)
        #expect(calls.count == before + 1)
    }

    @Test func changesThatKeepComingAreReportedAsTheyGo() async throws {
        let watched = try makeFolder()
        let calls = Calls()
        let watcher = FSEventsJournalWatcher(quietInterval: 0.3, longestWait: 0.6)
        watcher.start(watching: watched, onChange: calls.onChange)
        // Never quiet for the quiet interval, for three times the longest wait.
        for index in 0..<18 {
            try write("\(index).json", in: watched)
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(calls.count >= 1)
    }

    @Test func stoppingStopsTheCalls() async throws {
        let watched = try makeFolder()
        let calls = Calls()
        let watcher = FSEventsJournalWatcher(quietInterval: 0.1)
        watcher.start(watching: watched, onChange: calls.onChange)
        try write("a.json", in: watched)
        try await waitUntil { calls.count > 0 }
        #expect(calls.count >= 1)

        watcher.stop()
        let stopped = calls.count
        try write("b.json", in: watched)
        try await settle()
        #expect(calls.count == stopped)
        watcher.stop()
    }

    @Test func stoppingDropsChangesNotYetReported() async throws {
        let watched = try makeFolder()
        let calls = Calls()
        // Long enough that the change is gathered, and not yet reported, when the watch stops.
        let watcher = FSEventsJournalWatcher(quietInterval: 1)
        watcher.start(watching: watched, onChange: calls.onChange)
        try write("a.json", in: watched)
        try await Task.sleep(for: .milliseconds(300))
        watcher.stop()
        try await settle(1.5)
        #expect(calls.count == 0)
    }

    @Test func startingAgainWatchesOnlyTheNewFolder() async throws {
        let first = try makeFolder("first")
        let second = try makeFolder("second")
        let firstCalls = Calls(), secondCalls = Calls()
        let watcher = FSEventsJournalWatcher(quietInterval: 0.1)
        watcher.start(watching: first, onChange: firstCalls.onChange)
        let made = try await start(watcher, on: second, secondCalls)
        try write("a.json", in: first)
        try await settle()
        #expect(firstCalls.count == 0 && secondCalls.count == made)

        try write("b.json", in: second)
        try await waitUntil { secondCalls.count > made }
        #expect(firstCalls.count == 0 && secondCalls.count == made + 1)
    }

    @Test func lettingGoOfTheWatcherStopsIt() async throws {
        let watched = try makeFolder()
        let calls = Calls()
        var watcher: FSEventsJournalWatcher? = FSEventsJournalWatcher(quietInterval: 0.1)
        weak var released = watcher
        watcher?.start(watching: watched, onChange: calls.onChange)
        watcher = nil
        #expect(released == nil)
        try write("a.json", in: watched)
        try await settle()
        #expect(calls.count == 0)
    }

    @Test func aMissingFolderIsWatchedUntilItAppears() async throws {
        let calls = Calls()
        let watcher = FSEventsJournalWatcher(quietInterval: 0.1)
        watcher.start(watching: folder, onChange: calls.onChange)
        try await settle(0.3)
        #expect(calls.count == 0)

        let watched = try makeFolder()
        try write("clefwise.json", in: watched)
        try await waitUntil { calls.count > 0 }
        #expect(calls.count >= 1)
        watcher.stop()
    }

    @Test func theFolderBeingDeletedCallsBack() async throws {
        let watched = try makeFolder()
        let calls = Calls()
        let watcher = FSEventsJournalWatcher(quietInterval: 0.1)
        watcher.start(watching: watched, onChange: calls.onChange)
        try FileManager.default.removeItem(at: watched)
        try await waitUntil { calls.count > 0 }
        #expect(calls.count >= 1)

        // Still watching its path: a folder made there again is seen.
        let before = calls.count
        try write("clefwise.json", in: try makeFolder())
        try await waitUntil { calls.count > before }
        #expect(calls.count > before)
    }

    @Test func stoppingWhenNotWatchingDoesNothing() {
        let watcher = FSEventsJournalWatcher()
        watcher.stop()
        watcher.stop()
    }
}
