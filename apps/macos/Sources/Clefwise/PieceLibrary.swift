import CryptoKit
import Foundation
import Observation

/// The pieces opened so far, kept so they can be practised again without looking for the file.
/// Each file is copied into Clefwise's own folder, so a moved or deleted original doesn't matter,
/// and `index.json` beside the copies lists them. Its changes also go to the practice journal, as
/// `pieceAdded`, `pieceRevised` and `pieceRemoved` (see `journal`).
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
        /// The piece in the practice journal: the hash of the file it was first added with (its
        /// `pieceAdded`), which stays when a re-export changes `contentHash`. Entries kept before
        /// the journal take their `contentHash`.
        let pieceID: String
        let addedAt: Date
        var lastOpenedAt: Date
        /// The piece's own practice settings, saved as they change; nil until first saved.
        var settings: Game.PieceSettings?
    }

    /// ~/Library/Application Support/Clefwise/Pieces: the one library before there were several
    /// journals (`BuildOneFolders`). The first journal on a Mac that had it keeps it there; each
    /// journal after that has its own (`JournalRecord.libraryURL(in:)`).
    nonisolated static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clefwise/Pieces", isDirectory: true)
    }

    let folder: URL
    /// Most recently opened first.
    private(set) var entries: [Entry]
    /// Where the library's changes go in the practice journal, each with the score it brings in;
    /// nil for nowhere (the default, and in tests that don't look at it). The app sets it at
    /// launch, before the game reopens anything.
    @ObservationIgnored var journal: JournalEventRecording?

    /// Reads the library in `folder`; nothing is written until a piece is added.
    init(folder: URL, journal: JournalEventRecording? = nil) {
        self.folder = folder
        self.journal = journal
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
    ///
    /// In the journal, a new entry is a `pieceAdded` and a replaced copy a `pieceRevised`, each
    /// with the score.
    @discardableResult
    func add(_ url: URL, title: String, now: Date = .now) throws -> Entry {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let index: Int
        if let same = entries.firstIndex(where: { $0.contentHash == hash }) {
            index = same
            // The copy may have gone from disk meanwhile, or been spoilt; put it back.
            if (try? Data(contentsOf: fileURL(for: entries[index]))) != data {
                try write(data, as: entries[index].fileName)
            }
        } else if !isInLibrary(url), let updated = entries.firstIndex(where: { $0.originalPath == url.path }) {
            index = updated
            try write(data, as: entries[index].fileName)
            entries[index].contentHash = hash
            journal?.recordInJournal(.pieceRevised(PieceRevised(piece: entries[index].pieceID, file: hash, title: title)),
                                     piece: Self.journalFile(data, hash: hash, fileName: entries[index].fileName))
        } else {
            let id = UUID()
            let fileExtension = url.pathExtension.isEmpty ? "musicxml" : url.pathExtension.lowercased()
            let entry = Entry(id: id, title: title, originalPath: url.path, fileName: "\(id.uuidString).\(fileExtension)",
                              contentHash: hash, pieceID: hash, addedAt: now, lastOpenedAt: now, settings: nil)
            try write(data, as: entry.fileName)
            entries.insert(entry, at: 0)
            saveIndex()
            journal?.recordInJournal(.pieceAdded(PieceAdded(piece: hash, title: title, fileName: url.lastPathComponent,
                                                            libraryID: id, originalPath: url.path)),
                                     piece: Self.journalFile(data, hash: hash, fileName: entry.fileName))
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

    /// Forgets a piece and deletes its copy: a `pieceRemoved` in the journal, where its files and
    /// runs stay. The original file is never touched.
    func remove(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        try? FileManager.default.removeItem(at: fileURL(for: entry))
        saveIndex()
        journal?.recordInJournal(.pieceRemoved(PieceRemoved(piece: entry.pieceID)), piece: nil)
    }

    // MARK: - From the journal

    /// Brings the library up to date with the piece events in the journal in `journalFolder`
    /// (`contents.pieceEvents`, as a `JournalReader` read them): pieces added, revised or removed on
    /// another device, or on this one in an earlier library. Nothing is written to the journal:
    /// what this does records no `pieceAdded`, `pieceRevised` or `pieceRemoved` (`journal` isn't
    /// called).
    ///
    /// - **The journal's state:** each piece's events, folded in time order (the order of
    ///   `contents.pieceEvents`), the latest winning: a `pieceAdded` makes the piece present, with
    ///   its file (`PieceAdded.piece`) and title; a `pieceRevised` gives it a new file and title; a
    ///   `pieceRemoved` makes it absent. A piece matches the entry with its id as `Entry.pieceID`,
    ///   compared in lowercase.
    /// - **Added:** present in the journal and not here: a new entry, its copy written from the
    ///   journal's `pieces/<hash>.<ext>` (whichever of `JournalLayout.pieceExtensions` is there),
    ///   checked against the hash. Its `id` is the `libraryID` of its `pieceAdded`, unless that's
    ///   missing or already taken here; `title` the latest; `originalPath` the `pieceAdded`'s
    ///   `originalPath`, failing that its `fileName`; `pieceID` the piece's id; `contentHash` the
    ///   file's hash; `fileName` `<id>.<ext>`, as `add` names copies; `addedAt` and `lastOpenedAt`
    ///   the `pieceAdded`'s `time`; `settings` nil (a piece's own settings stay on each device).
    /// - **Revised:** present in both, with another file or title in the journal: the copy gets the
    ///   new file's bytes (checked the same way) and the entry its `contentHash` and `title`. It
    ///   keeps its id, file name, settings and dates.
    /// - **Removed:** absent in the journal and here: the entry leaves the library and its copy is
    ///   deleted.
    /// - **A score not there yet,** or not matching its hash: that piece's change waits, and the
    ///   next call tries again (a `pieceAdded` can arrive before its score).
    /// - **Pieces with no events in the journal** are left alone: for example one added here whose
    ///   `pieceAdded` is still on its way.
    /// - **Changes made here win while they're on their way:** an event older than this library's
    ///   own last change to that piece (adding, revising or removing it here) isn't applied, so the
    ///   journal's older state doesn't undo a change still waiting to go in. The library keeps what
    ///   it needs for that beside its index.
    /// - Calling it again with the same contents changes nothing. The index is saved once, if
    ///   anything changed.
    func adopt(from contents: JournalReader.Contents, journalFolder: URL) {
        // C2
    }

    // MARK: - Storage

    private var indexURL: URL { Self.indexURL(in: folder) }

    /// Where a library in `folder` keeps its index (the export copies it).
    nonisolated static func indexURL(in folder: URL) -> URL {
        folder.appendingPathComponent("index.json")
    }

    private func isInLibrary(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent().path == folder.standardizedFileURL.path
    }

    /// A score for the journal's `pieces/`, with its copy's extension (`musicxml` should that be
    /// one the journal doesn't take).
    private static func journalFile(_ data: Data, hash: String, fileName: String) -> JournalPieceFile {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        return JournalPieceFile(data: data, hash: hash,
                                fileExtension: JournalLayout.pieceExtensions.contains(fileExtension) ? fileExtension : "musicxml")
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
        let url = indexURL(in: folder)
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

extension PieceLibrary.Entry {
    /// An entry whose piece was first added with this copy: its `pieceID` is its `contentHash`.
    init(id: UUID, title: String, originalPath: String, fileName: String, contentHash: String, addedAt: Date,
         lastOpenedAt: Date, settings: Game.PieceSettings?) {
        self.init(id: id, title: title, originalPath: originalPath, fileName: fileName, contentHash: contentHash,
                  pieceID: contentHash, addedAt: addedAt, lastOpenedAt: lastOpenedAt, settings: settings)
    }

    /// Reads an entry from the index. One kept before the journal has no `pieceID`, and takes its
    /// `contentHash`. (In an extension, so the memberwise initialiser stays.)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        originalPath = try container.decode(String.self, forKey: .originalPath)
        fileName = try container.decode(String.self, forKey: .fileName)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        pieceID = try container.decodeIfPresent(String.self, forKey: .pieceID) ?? contentHash
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt)
        settings = try container.decodeIfPresent(Game.PieceSettings.self, forKey: .settings)
    }
}
