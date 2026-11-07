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
    /// When each piece last changed here, through `add` (added or revised) or `remove`, by its
    /// `pieceID` in lowercase; kept until the journal has that change or a later one, so `adopt`
    /// doesn't undo it meanwhile. A removed piece's time stays here after its entry has gone.
    @ObservationIgnored private var changedHere: [String: Date]

    /// Reads the library in `folder`; nothing is written until a piece is added.
    init(folder: URL, journal: JournalEventRecording? = nil) {
        self.folder = folder
        self.journal = journal
        entries = Self.loadIndex(in: folder)
        changedHere = Self.loadChangesHere(in: folder)
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
            noteChangeHere(to: entries[index].pieceID, at: now)
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
            noteChangeHere(to: hash, at: now)
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
        noteChangeHere(to: entry.pieceID, at: .now)
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
    ///   its file (`PieceAdded.piece`) and title; a `pieceRevised` gives it a new file and title,
    ///   and makes it present again should it come after a `pieceRemoved` (another device revised
    ///   the piece later, and has it); a `pieceRemoved` makes it absent. A piece matches the entry
    ///   with its id as `Entry.pieceID`, compared in lowercase.
    /// - **Added:** present in the journal and not here: a new entry, its copy written from the
    ///   journal's `pieces/<hash>.<ext>` (whichever of `JournalLayout.pieceExtensions` is there),
    ///   checked against the hash. Its `id` is the `libraryID` of its `pieceAdded`, unless that's
    ///   missing or already taken here; `title` the latest; `originalPath` the `pieceAdded`'s
    ///   `originalPath`, failing that its `fileName`; `pieceID` the piece's id; `contentHash` the
    ///   file's hash; `fileName` `<id>.<ext>`, as `add` names copies; `addedAt` and `lastOpenedAt`
    ///   the `pieceAdded`'s `time` (placing it among the others, most recently opened first);
    ///   `settings` nil (a piece's own settings stay on each device). The other device's
    ///   `originalPath` is kept as it is, since old runs and the dashboard know the piece by it,
    ///   even though no such file is likely to be on this Mac. A piece whose `pieceAdded` hasn't
    ///   arrived yet (only a `pieceRevised` has) waits for it.
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
    ///   journal's older state doesn't undo a change still waiting to go in. The library keeps
    ///   when each piece last changed here in `local-changes.json` beside its index (removed pieces
    ///   too), and forgets it once the journal's latest event for the piece is as new or newer:
    ///   the change has arrived, or another device changed the piece after it.
    /// - Calling it again with the same contents changes nothing. The index is saved once, if
    ///   anything changed.
    ///
    /// Scores are small, so they're read and copied here, on the main actor; only the ones an
    /// entry needs are read.
    func adopt(from contents: JournalReader.Contents, journalFolder: URL) {
        var entriesChanged = false
        var changesHereForgotten = false
        for piece in Self.journalPieces(in: contents.pieceEvents) {
            if let changed = changedHere[piece.id] {
                guard piece.changedAt >= changed else { continue }
                changedHere[piece.id] = nil
                changesHereForgotten = true
            }
            let index = entries.firstIndex { $0.pieceID.lowercased() == piece.id }
            switch (piece.file, index) {
            case (nil, let index?):
                let entry = entries.remove(at: index)
                try? FileManager.default.removeItem(at: fileURL(for: entry))
                entriesChanged = true
            case (let file?, let index?):
                if entries[index].contentHash.lowercased() != file {
                    guard let score = Self.journalScore(file, in: journalFolder),
                          (try? write(score.data, as: entries[index].fileName)) != nil else { continue }
                    entries[index].contentHash = file
                } else if entries[index].title == piece.title {
                    continue
                }
                entries[index].title = piece.title
                entriesChanged = true
            case (let file?, nil):
                guard let added = piece.added, let score = Self.journalScore(file, in: journalFolder) else { continue }
                let id = added.event.libraryID.flatMap { self.entry(id: $0) == nil ? $0 : nil } ?? UUID()
                let new = Entry(id: id, title: piece.title, originalPath: added.event.originalPath ?? added.event.fileName,
                                fileName: "\(id.uuidString).\(score.fileExtension)", contentHash: file,
                                pieceID: piece.id, addedAt: added.time, lastOpenedAt: added.time, settings: nil)
                guard (try? write(score.data, as: new.fileName)) != nil else { continue }
                entries.insert(new, at: entries.firstIndex { $0.lastOpenedAt < new.lastOpenedAt } ?? entries.endIndex)
                entriesChanged = true
            case (nil, nil):
                break
            }
        }
        if entriesChanged { saveIndex() }
        if changesHereForgotten { saveChangesHere() }
    }

    /// A piece as the journal's events leave it.
    private struct JournalPiece {
        /// Its id, in lowercase.
        let id: String
        /// Its latest `pieceAdded` and that event's time; nil while none has arrived.
        var added: (event: PieceAdded, time: Date)?
        /// The hash of its file now, in lowercase; nil when it's been removed.
        var file: String?
        var title = ""
        /// The time of its latest event.
        var changedAt: Date
    }

    /// Each piece in `events` (in time order), folded, in the order the pieces first appear.
    private static func journalPieces(in events: [LoggedEvent]) -> [JournalPiece] {
        var order: [String] = []
        var pieces: [String: JournalPiece] = [:]
        for event in events {
            let id: String
            switch event.event {
            case .pieceAdded(let added): id = added.piece.lowercased()
            case .pieceRevised(let revised): id = revised.piece.lowercased()
            case .pieceRemoved(let removed): id = removed.piece.lowercased()
            default: continue
            }
            var piece = pieces[id] ?? JournalPiece(id: id, changedAt: event.time)
            if pieces[id] == nil { order.append(id) }
            piece.changedAt = max(piece.changedAt, event.time)
            switch event.event {
            case .pieceAdded(let added):
                piece.added = (added, event.time)
                piece.file = id
                piece.title = added.title
            case .pieceRevised(let revised):
                piece.file = revised.file.lowercased()
                piece.title = revised.title
            case .pieceRemoved:
                piece.file = nil
            default:
                break
            }
            pieces[id] = piece
        }
        return order.compactMap { pieces[$0] }
    }

    /// The score named `hash` in the journal's `pieces/`, with its extension; nil when it isn't
    /// there yet (still arriving), can't be read, or its bytes don't match its name.
    private static func journalScore(_ hash: String, in journalFolder: URL) -> (data: Data, fileExtension: String)? {
        for fileExtension in JournalLayout.pieceExtensions.sorted() {
            let url = journalFolder.appendingPathComponent(JournalLayout.piecePath(hash: hash, fileExtension: fileExtension))
            if let data = try? Data(contentsOf: url), JournalPieceFile.sha256(of: data) == hash.lowercased() {
                return (data, fileExtension)
            }
        }
        return nil
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

    /// Remembers that `piece` changed here at `time` (see `adopt`), and saves that. The time is
    /// kept to the millisecond, as saved, and as the journal's events have theirs.
    private func noteChangeHere(to piece: String, at time: Date) {
        changedHere[piece.lowercased()] = (try? Self.changeTimeStyle.parse(Self.changeTimeStyle.format(time))) ?? time
        saveChangesHere()
    }

    /// Where a library in `folder` keeps `changedHere`: beside the index, which keeps its own
    /// format (a list of entries), as builds without the journal's adopting read it.
    private static func changesHereURL(in folder: URL) -> URL {
        folder.appendingPathComponent("local-changes.json")
    }

    /// `changedHere` as JSON, each piece's time in UTC to the millisecond, like the journal's.
    private func saveChangesHere() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.changeTimeStyle.format(date))
        }
        guard let data = try? encoder.encode(changedHere) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: Self.changesHereURL(in: folder), options: .atomic)
    }

    /// What `saveChangesHere` saved; nothing when it's missing or unreadable, which only lets the
    /// journal's state win sooner.
    private static func loadChangesHere(in folder: URL) -> [String: Date] {
        guard let data = try? Data(contentsOf: changesHereURL(in: folder)) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try changeTimeStyle.parse(try decoder.singleValueContainer().decode(String.self))
        }
        return (try? decoder.decode([String: Date].self, from: data)) ?? [:]
    }

    private nonisolated static let changeTimeStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

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
