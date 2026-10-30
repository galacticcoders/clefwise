import Foundation

/// Problems reading a score, worded for the person who picked the file.
struct ScoreImportError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

enum MusicXMLImporter {
    /// Reads an uncompressed MusicXML file (.musicxml, .xml) or a compressed one (.mxl).
    static func load(from url: URL) throws -> Score {
        throw ScoreImportError(message: "Opening MusicXML files isn't available yet.")
    }
}
