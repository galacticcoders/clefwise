import CryptoKit
import Foundation
import Observation

/// The pieces opened so far, kept so they can be practised again without looking for the file.
/// Each file is copied into Clefwise's own folder, so a moved or deleted original doesn't matter,
/// and `index.json` beside the copies lists them.
@MainActor @Observable
final class PieceLibrary {
    struct Entry: Codable, Equatable, Identifiable {
        let id: UUID
        /// The score's title, as of the last time it was opened.
        var title: String
        /// Where the file was first opened from. The usage log and the dashboard know the piece by
        /// this path, so it stays the same however the piece is opened later.
        let originalPath: String
        /// The copy's file name in the library folder.
        var fileName: String
        /// SHA-256 of the copy's bytes, in hex: the same file opened again is the same entry.
        var contentHash: String
        let addedAt: Date
        var lastOpenedAt: Date
        /// The piece's own practice settings, saved as they change; nil until first saved.
        var settings: Game.PieceSettings?
    }

    static let shared = PieceLibrary(folder: defaultFolder)

    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clefwise/Pieces", isDirectory: true)
    }

    let folder: URL
    /// Most recently opened first.
    private(set) var entries: [Entry]

    /// Reads the library in `folder`; nothing is written until a piece is added.
    init(folder: URL) {
        self.folder = folder
        entries = Self.loadIndex(in: folder)
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Where the copy of `entry` is.
    func fileURL(for entry: Entry) -> URL {
        folder.appendingPathComponent(entry.fileName)
    }

    func entry(id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    /// The entry first opened from `path`, if any.
    func entry(originalPath path: String) -> Entry? {
        entries.first { $0.originalPath == path }
    }

    /// Adds the file at `url` and marks it opened now; returns its entry.
    /// - The same bytes as an entry's copy (including the library's own copy, opened again) are
    ///   that entry: only its title and when it was opened change.
    /// - Different bytes from a path an entry was first opened from (the score was edited and
    ///   exported again) replace that entry's copy, keeping its id and settings.
    /// - Anything else is copied in as a new entry.
    @discardableResult
    func add(_ url: URL, title: String, now: Date = .now) throws -> Entry {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let index: Int
        if let same = entries.firstIndex(where: { $0.contentHash == hash }) {
            index = same
            // The copy may have gone from disk meanwhile; put it back.
            if !FileManager.default.fileExists(atPath: fileURL(for: entries[index]).path) {
                try write(data, as: entries[index].fileName)
            }
        } else if !isInLibrary(url), let updated = entries.firstIndex(where: { $0.originalPath == url.path }) {
            index = updated
            try write(data, as: entries[index].fileName)
            entries[index].contentHash = hash
        } else {
            let id = UUID()
            let fileExtension = url.pathExtension.isEmpty ? "musicxml" : url.pathExtension.lowercased()
            let entry = Entry(id: id, title: title, originalPath: url.path, fileName: "\(id.uuidString).\(fileExtension)",
                              contentHash: hash, addedAt: now, lastOpenedAt: now, settings: nil)
            try write(data, as: entry.fileName)
            entries.insert(entry, at: 0)
            saveIndex()
            return entry
        }
        var entry = entries.remove(at: index)
        entry.title = title
        entry.lastOpenedAt = now
        entries.insert(entry, at: 0)
        saveIndex()
        return entry
    }

    /// Keeps a piece's practice settings, for the next time it's opened.
    func save(settings: Game.PieceSettings, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].settings != settings else { return }
        entries[index].settings = settings
        saveIndex()
    }

    /// Forgets a piece and deletes its copy. The original file is never touched.
    func remove(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        try? FileManager.default.removeItem(at: fileURL(for: entry))
        saveIndex()
    }

    // MARK: - Storage

    private var indexURL: URL { folder.appendingPathComponent("index.json") }

    private func isInLibrary(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent().path == folder.standardizedFileURL.path
    }

    private func write(_ data: Data, as fileName: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: indexURL, options: .atomic)
    }

    /// An unreadable index is set aside (renamed with the time) rather than lost, and the library
    /// starts empty; the copies stay where they are.
    private static func loadIndex(in folder: URL) -> [Entry] {
        let url = folder.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let entries = try? decoder.decode([Entry].self, from: data) {
            return entries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        }
        let stamp = Int(Date().timeIntervalSince1970)
        try? FileManager.default.moveItem(at: url, to: folder.appendingPathComponent("index-unreadable-\(stamp).json"))
        return []
    }
}
