import CoreServices
import Foundation

// Watching the journal in use for files arriving, from this Mac or through a sync service, with
// FSEvents. See `JournalWatching`, and spec/practice-journal.md, "Folder sync".

/// Watches a journal's folder with an FSEvents stream: everything in it, however deep, file by file
/// (`kFSEventStreamCreateFlagFileEvents`), as `JournalWatching` promises.
///
/// - **Gathering changes:** `onChange` comes once the folder has been quiet for `quietInterval`
///   (half a second in the app). While changes keep coming it comes at the latest `longestWait`
///   after the first one not yet reported, so a long sync still shows its progress as it goes.
/// - **A folder that isn't there** (not made yet, deleted, or on a disk that's unplugged) is
///   watched all the same, by its path: nothing calls back until something appears there, and
///   then it does. The folder itself appearing, being deleted or being moved away counts as a
///   change too (`kFSEventStreamCreateFlagWatchRoot`), so the app can look for it again. A moved
///   folder isn't followed: the app starts a watch on its new path.
/// - **Links in the path** (`/tmp`, `/var`, a linked folder) are resolved before watching, as far
///   as the path exists: FSEvents reports resolved paths, and resolves the path it's given only
///   when it's all there.
/// - **Should FSEvents refuse the path,** nothing calls back, and nothing else goes wrong.
///
/// The stream calls back on a queue of its own; `stop()`, starting another watch, and letting go
/// of the watcher each end it and release it. Call `start` and `stop` on the main actor.
final class FSEventsJournalWatcher: JournalWatching {
    /// How long the folder must stay quiet after a change before `onChange` is called.
    let quietInterval: TimeInterval
    /// The longest a change waits to be reported while more keep coming.
    let longestWait: TimeInterval

    /// The watch going on, if any.
    private var watch: FolderWatch?

    /// `quietInterval` and `longestWait` are shorter in tests. `longestWait` is at least
    /// `quietInterval`.
    init(quietInterval: TimeInterval = 0.5, longestWait: TimeInterval = 2) {
        self.quietInterval = quietInterval
        self.longestWait = max(longestWait, quietInterval)
    }

    deinit {
        watch?.end()
    }

    func start(watching folder: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        stop()
        watch = FolderWatch(folder: folder, quietInterval: quietInterval, longestWait: longestWait, onChange: onChange)
    }

    func stop() {
        watch?.end()
        watch = nil
    }
}

/// One folder's FSEvents stream, and the changes it has seen and not yet reported. The stream keeps
/// it (through its context's retain and release) until the stream is released in `end()`.
private final class FolderWatch: @unchecked Sendable {
    private let quietInterval: TimeInterval
    private let longestWait: TimeInterval
    private let onChange: @MainActor @Sendable () -> Void
    /// Where the stream calls back, and where the changes waiting to be reported are kept.
    private let queue = DispatchQueue(label: "Clefwise.JournalWatcher")

    /// Guards `stream` and `hasEnded`.
    private let lock = NSLock()
    /// Nil once ended, or when FSEvents wouldn't watch the folder.
    private var stream: FSEventStreamRef?
    /// Read on the main actor just before each call to `onChange`, so none comes once `end()` has
    /// returned.
    private var hasEnded = false

    /// When the first change not yet reported came; on `queue` only.
    private var firstWaiting: DispatchTime?
    /// The report due for the changes waiting; on `queue` only.
    private var report: DispatchWorkItem?

    init(folder: URL, quietInterval: TimeInterval, longestWait: TimeInterval,
         onChange: @escaping @MainActor @Sendable () -> Void) {
        self.quietInterval = quietInterval
        self.longestWait = longestWait
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<FolderWatch>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<FolderWatch>.fromOpaque(info).release()
            },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, _, _, _ in
            guard let info, count > 0 else { return }
            Unmanaged<FolderWatch>.fromOpaque(info).takeUnretainedValue().changed()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        // FSEvents gathers for a fifth of the quiet interval; `changed()` does the rest.
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context,
                                               [Self.resolvedPath(of: folder)] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               quietInterval / 5, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
    }

    /// Stops and releases the stream, and drops any report still to come. Once it returns, and
    /// when called on the main actor, `onChange` isn't called again. Calling it again does nothing.
    func end() {
        let stream: FSEventStreamRef? = lock.withLock {
            guard !hasEnded else { return nil }
            hasEnded = true
            defer { self.stream = nil }
            return self.stream
        }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    /// On `queue`: something changed. Puts the report off until the folder has been quiet for
    /// `quietInterval`, but no later than `longestWait` after the first change waiting.
    private func changed() {
        let now = DispatchTime.now()
        let first = firstWaiting ?? now
        firstWaiting = first
        report?.cancel()
        let report = DispatchWorkItem { [self] in
            firstWaiting = nil
            self.report = nil
            DispatchQueue.main.async { [self] in
                guard !lock.withLock({ hasEnded }) else { return }
                MainActor.assumeIsolated { onChange() }
            }
        }
        self.report = report
        queue.asyncAfter(deadline: min(now + quietInterval, first + longestWait), execute: report)
    }

    /// `folder`'s path with its links resolved as far as it exists, and the rest as it is: what
    /// FSEvents reports changes under, even before the folder is there.
    private static func resolvedPath(of folder: URL) -> String {
        var existing = folder.standardizedFileURL
        var rest: [String] = []
        while true {
            if let resolved = realpath(existing.path, nil) {
                defer { free(resolved) }
                return rest.reversed().reduce(String(cString: resolved)) { ($0 as NSString).appendingPathComponent($1) }
            }
            guard existing.path != "/" else { return folder.path }
            rest.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
    }
}
