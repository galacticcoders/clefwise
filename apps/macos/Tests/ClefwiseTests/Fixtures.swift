import Foundation

/// The shared test scores in `spec/fixtures/scores` at the top of the repository, which every
/// version of Clefwise tests against. Found from this file's own location, so `swift test` works
/// wherever it's run from.
enum Fixtures {
    static let folder: URL? = {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.pathComponents.count > 1 {
            let candidate = url.appendingPathComponent("spec/fixtures/scores", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            url.deleteLastPathComponent()
        }
        return nil
    }()

    /// nil when there's no such file, so a misspelt name fails the test instead of passing as an
    /// unreadable file.
    static func url(_ name: String) -> URL? {
        guard let url = folder?.appendingPathComponent(name),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
