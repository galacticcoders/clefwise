import Foundation

/// The usage log on disk: one JSON Lines file per day in Application Support.
final class UsageLog: UsageRecorder {
    static let shared = UsageLog(folder: defaultFolder)

    /// ~/Library/Application Support/Clefwise/Usage
    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clefwise/Usage", isDirectory: true)
    }

    let folder: URL
    /// One per launch, stamped on every event.
    let session = UUID()

    init(folder: URL) {
        self.folder = folder
    }

    func record(_ event: UsageEvent) {}

    /// Returns once everything recorded so far is written (before quitting or exporting).
    func flush() {}
}
