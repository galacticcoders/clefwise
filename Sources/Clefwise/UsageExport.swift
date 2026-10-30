import Foundation

enum UsageExport {
    /// Writes everything in `log` to a zip at `destination`: the raw event files, CSV tables and a
    /// description of every field.
    static func export(_ log: UsageLog, to destination: URL) throws {
        throw CocoaError(.featureUnsupported)
    }
}
