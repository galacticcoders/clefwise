import Foundation

// The practice journal's folder: where it is, making and renaming it, and adding files to it
// without ever changing one. See spec/practice-journal.md, "Where the journal lives", "Layout",
// "Principles" and "Several journals".

/// Why something couldn't go into the journal, or the journal couldn't be made or found.
enum JournalError: LocalizedError, Equatable {
    /// No journal is set, or it can't be found (a disk unplugged, the folder moved out of reach).
    case missing
    /// A run file's header has no `run`.
    case notARun
    /// A different file is already at `path` in the journal. The journal's copy stays, and the one
    /// that clashed is left where it was.
    case clash(path: String)
    /// A score's bytes don't have the hash it's to be named by.
    case damagedScore(hash: String)
    /// A journal can't have this name: empty, hidden, or with a slash or colon in it.
    case invalidName(String)
    /// Something that isn't a journal already has the chosen name there.
    case folderInUse(URL)
    /// A file or folder beside the journal already has the name it was to be renamed to: a folder
    /// when the URL is a directory's, otherwise a file.
    case nameTaken(URL)
    /// The file system wouldn't rename the journal's folder (no permission, the disk gone): `code`
    /// is the `errno` it gave.
    case renameFailed(URL, code: Int32)
    /// The folder picked to locate the journal doesn't hold `clefwise.json`.
    case notAJournal(URL)
    /// The folder picked to locate a journal is another journal this Mac knows already.
    case listedAlready(URL)

    var errorDescription: String? {
        switch self {
        case .missing: "Clefwise can't find your journal."
        case .notARun: "The run file doesn't say which run it is."
        case .clash(let path): "A different file is already in the journal at \(path)."
        case .damagedScore(let hash): "The score doesn't match its name, \(hash)."
        case .invalidName(let name):
            name.isEmpty ? "Give the journal a name." : "Give the journal a name without a slash or colon, not starting with a dot."
        case .folderInUse(let url):
            "There's already a folder called “\(url.lastPathComponent)” there, with other things in it. Choose another name."
        case .nameTaken(let url):
            "There's already a \(url.hasDirectoryPath ? "folder" : "file") called “\(url.lastPathComponent)” there."
        case .renameFailed(let url, let code) where code == EACCES || code == EPERM:
            "You don't have permission to rename “\(url.lastPathComponent)”."
        case .renameFailed(let url, let code):
            "“\(url.lastPathComponent)” couldn't be renamed: \(String(cString: strerror(code)))."
        case .notAJournal(let url): "“\(url.lastPathComponent)” isn't a Clefwise journal: it has no clefwise.json."
        case .listedAlready(let url):
            "“\(url.lastPathComponent)” is another of your journals. Switch to it from the Journal menu instead."
        }
    }
}

/// The practice journal on disk: a folder of plain files the user owns and only ever added to.
/// Where it is comes from a path and a bookmark, so a folder moved in Finder is still found (and
/// the path follows it). The app has one for each journal it knows, its location kept in the
/// journal's `JournalRecord` (`JournalRegistry`); build 1's one journal kept its location in the
/// defaults (`init(defaults:)`). Every disk change goes through one lock, so it's safe to use from
/// any thread: finished runs come from the journal outbox's queue, making and locating it from the
/// main thread.
final class PracticeJournal: JournalWriting, @unchecked Sendable {
    /// Where build 1 kept its one journal's location in the defaults. Build 2 keeps each journal's
    /// in its `JournalRecord`, and reads these only to bring build 1's journal over
    /// (`JournalMigration`). A harness can still preset the first journal with
    /// `defaults write <domain> journalPath -string <folder>`: a path alone is enough.
    enum Keys {
        static let path = "journalPath"
        static let bookmark = "journalBookmark"
    }

    /// Build 1's journal keeps its location in these defaults, under `Keys`, read each time. Nil
    /// for a journal of the registry's, which keeps it here (`storedPath`, `storedBookmark`).
    private let defaults: UserDefaults?
    private var storedPath: String?
    private var storedBookmark: Data?
    /// Told the journal's new path and bookmark each time it's kept somewhere new (found elsewhere
    /// through its bookmark, made, renamed, or located by the user): on the thread that found it,
    /// once the lock is let go.
    private let onRelocated: (@Sendable (_ path: String, _ bookmark: Data?) -> Void)?
    /// What `remember` kept while the lock was held, for `onRelocated` once it's let go.
    private var relocation: (path: String, bookmark: Data?)?
    /// Guards `found`, the location kept here and `relocation`, and serialises every change on disk.
    private let lock = NSLock()
    /// The folder last found, checked again (one look for `clefwise.json`) before each use.
    private var found: URL?

    /// Build 1's journal: `defaults` keeps where it is, under `Keys`; tests pass their own.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        onRelocated = nil
    }

    /// A journal last known at `path` (nil until it's made or located), with `bookmark` to find it
    /// should it move. `onRelocated` gets the new path and bookmark each time they change, on any
    /// thread: the registry keeps them in the journal's record.
    init(path: String?, bookmark: Data?, onRelocated: @escaping @Sendable (_ path: String, _ bookmark: Data?) -> Void) {
        defaults = nil
        storedPath = path
        storedBookmark = bookmark
        self.onRelocated = onRelocated
    }

    // MARK: - Where it is

    /// The journal's folder; nil while none is set, or when it can't be found.
    var folder: URL? {
        locked { locate() }
    }

    /// Whether a journal has been set, found or not: without one, the app asks to make it.
    var isSet: Bool {
        lastKnownPath != nil
    }

    /// Where the journal was last known to be, for telling the user when it can't be found.
    var lastKnownPath: String? {
        lock.withLock { knownPath }
    }

    /// The bookmark kept to find the journal should it move; nil until it's made or located, or
    /// when none could be made.
    var lastKnownBookmark: Data? {
        lock.withLock { knownBookmark }
    }

    /// Called with the lock held.
    private var knownPath: String? {
        if let defaults { return defaults.object(forKey: Keys.path) as? String }
        return storedPath
    }

    /// Called with the lock held.
    private var knownBookmark: Data? {
        if let defaults { return defaults.object(forKey: Keys.bookmark) as? Data }
        return storedBookmark
    }

    /// Whether `url` is a journal: it holds `clefwise.json` (or iCloud Drive's placeholder for it,
    /// when the file isn't downloaded).
    static func isJournal(_ url: URL) -> Bool {
        let manager = FileManager.default
        var isFolder: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else { return false }
        return manager.fileExists(atPath: url.appendingPathComponent(JournalLayout.markerName).path)
            || manager.fileExists(atPath: url.appendingPathComponent(".\(JournalLayout.markerName).icloud").path)
    }

    /// The name to suggest for a journal in `parent`: "Clefwise Journal", unless something already
    /// has it there; then "Clefwise Journal 2", 3 and so on. A journal already there is suggested
    /// as it is, to be used, unless `fresh`: then only a name nothing has there yet, for a journal
    /// that's to be new (File ▸ New Journal…).
    static func suggestedName(in parent: URL, fresh: Bool = false) -> String {
        let base = "Clefwise Journal"
        for number in 1... {
            let name = number == 1 ? base : "\(base) \(number)"
            let url = parent.appendingPathComponent(name, isDirectory: true)
            if !FileManager.default.fileExists(atPath: url.path) || (!fresh && isJournal(url)) { return name }
        }
        return base
    }

    /// The folder last known, if it still holds a journal: by its path first (which a harness may
    /// have set by itself), otherwise by its bookmark, which follows the folder when it's moved or
    /// renamed (and then the path is updated). Keeps the bookmark pointing where the path does.
    /// Called with the lock held.
    private func locate() -> URL? {
        if let found, Self.isJournal(found) { return found }
        found = nil
        guard let path = knownPath else { return nil }
        let atPath = URL(fileURLWithPath: path, isDirectory: true)
        let bookmarked = knownBookmark.flatMap(Self.resolve)
        if Self.isJournal(atPath) {
            if bookmarked.map({ !Self.isSameFolder($0, atPath) }) ?? true { remember(atPath) }
            found = atPath
        } else if let bookmarked, Self.isJournal(bookmarked) {
            remember(bookmarked)
            found = bookmarked
        }
        return found
    }

    /// Keeps `folder` as the journal's location: its path, and a bookmark to find it if it moves.
    /// Called with the lock held.
    private func remember(_ folder: URL) {
        let bookmark = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        if let defaults {
            defaults.set(folder.path, forKey: Keys.path)
            if let bookmark {
                defaults.set(bookmark, forKey: Keys.bookmark)
            } else {
                defaults.removeObject(forKey: Keys.bookmark)
            }
        } else {
            storedPath = folder.path
            storedBookmark = bookmark
            relocation = (folder.path, bookmark)
        }
    }

    /// Runs `body` with the lock held; then, if `body` kept the journal somewhere new, tells
    /// `onRelocated`, once the lock is let go (so it can ask the journal again).
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer {
            let moved = relocation
            relocation = nil
            lock.unlock()
            if let moved { onRelocated?(moved.path, moved.bookmark) }
        }
        return try body()
    }

    /// Where a bookmark points now, without asking the user or mounting anything; nil when it
    /// can't be found.
    private static func resolve(_ bookmark: Data) -> URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil,
                        bookmarkDataIsStale: &isStale)
    }

    /// Whether `a` and `b` are the same folder, symbolic links and all.
    static func isSameFolder(_ a: URL, _ b: URL) -> Bool {
        a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: - Making and locating it

    /// Makes the journal `name` in `parent` (the folder, then its root files with their exact
    /// bytes), keeps it as the journal, and returns its folder. If `parent` is a journal itself, or
    /// already holds one called `name`, that one is kept as it is. A folder called `name` with
    /// anything else in it isn't used.
    @discardableResult
    func create(named name: String, in parent: URL) throws -> URL {
        try locked {
            let folder: URL
            if let existing = Self.existingJournal(named: name, in: parent) {
                folder = existing
            } else {
                folder = parent.appendingPathComponent(try Self.checkedName(name), isDirectory: true)
                try Self.makeJournal(at: folder)
            }
            remember(folder)
            found = folder
            return folder
        }
    }

    /// The journal `create(named:in:)` would keep as it is: `parent` when it's a journal itself,
    /// otherwise a journal called `name` in it; nil when it would make one.
    static func existingJournal(named name: String, in parent: URL) -> URL? {
        if isJournal(parent) { return parent }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let folder = parent.appendingPathComponent(name, isDirectory: true)
        return isJournal(folder) ? folder : nil
    }

    /// Keeps `folder`, a journal found again by the user, as the journal.
    func use(_ folder: URL) throws {
        try locked {
            guard Self.isJournal(folder) else { throw JournalError.notAJournal(folder) }
            remember(folder)
            found = folder
        }
    }

    /// `name` trimmed of spaces and new lines, if a journal can have it: not empty, without a slash
    /// or colon, and not starting with a dot (Finder would hide it). Throws
    /// `JournalError.invalidName` otherwise.
    static func checkedName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":") else {
            throw JournalError.invalidName(name)
        }
        return name
    }

    // MARK: - Renaming it

    /// Renames the journal's folder to `name`, trimmed, in the folder it's in, and keeps it as the
    /// journal there (`onRelocated` hears of it): a journal's name is its folder's. Under the lock,
    /// so it never races a run or a piece being placed. The same name changes nothing, and a change
    /// of case only ("anna" to "Anna") works on a volume that ignores case too. Returns the folder
    /// as it is now.
    ///
    /// Throws, changing nothing: `JournalError.invalidName` for a name that's empty, has a slash or
    /// colon in it, or starts with a dot; `.nameTaken` when a file or folder beside it already has
    /// it; `.missing` when the journal can't be found; `.renameFailed` when the file system won't
    /// (no permission, the disk gone).
    @discardableResult
    func rename(to name: String) throws -> URL {
        let name = try Self.checkedName(name)
        return try locked {
            guard let folder = locate() else { throw JournalError.missing }
            guard name != folder.lastPathComponent else { return folder }
            let renamed = folder.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
            try Self.renameFolder(folder, to: renamed)
            remember(renamed)
            found = renamed
            return renamed
        }
    }

    /// Renames the folder `source` to `destination` beside it, unless something there already has
    /// that name. On a volume that ignores case, a change of case only finds the folder itself
    /// under the new name: that goes through a temporary name when renaming straight away doesn't
    /// take (APFS takes it).
    private static func renameFolder(_ source: URL, to destination: URL) throws {
        let isCaseOnly = isSameItem(source, destination)
        if renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 {
            if !isCaseOnly || hasExactName(destination) { return }
        } else {
            let code = errno
            guard code == EEXIST else { throw JournalError.renameFailed(source, code: code) }
            guard isCaseOnly else { throw nameTaken(destination) }
        }
        try renameThroughTemporaryName(source, to: destination)
    }

    /// Renames `source` to `destination` by way of a hidden name beside them, for a change of case
    /// that a volume won't make in one go. When the second step fails, `source` is put back.
    static func renameThroughTemporaryName(_ source: URL, to destination: URL) throws {
        let temporary = temporaryURL(in: source.deletingLastPathComponent())
        guard renamex_np(source.path, temporary.path, UInt32(RENAME_EXCL)) == 0 else {
            throw JournalError.renameFailed(source, code: errno)
        }
        guard renamex_np(temporary.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            renamex_np(temporary.path, source.path, UInt32(RENAME_EXCL))
            throw code == EEXIST ? nameTaken(destination) : JournalError.renameFailed(source, code: code)
        }
    }

    /// `JournalError.nameTaken` for what's at `url`, telling a folder from a file.
    private static func nameTaken(_ url: URL) -> JournalError {
        var isFolder: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        return .nameTaken(URL(fileURLWithPath: url.path, isDirectory: isFolder.boolValue))
    }

    /// Whether `a` and `b` are the same file or folder: on a volume that ignores case, "Anna" and
    /// "anna" are.
    private static func isSameItem(_ a: URL, _ b: URL) -> Bool {
        var first = stat(), second = stat()
        return lstat(a.path, &first) == 0 && lstat(b.path, &second) == 0
            && first.st_dev == second.st_dev && first.st_ino == second.st_ino
    }

    /// Whether the folder `url` is in lists its name exactly, case and all.
    private static func hasExactName(_ url: URL) -> Bool {
        let names = try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        return names?.contains(url.lastPathComponent) ?? false
    }

    /// Makes the folder (or takes an empty one) and writes the root files. `clefwise.json` goes
    /// last: once it's there, the folder is a journal.
    private static func makeJournal(at folder: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: folder.path) {
            guard let contents = try? manager.contentsOfDirectory(atPath: folder.path),
                  contents.allSatisfy({ $0 == ".DS_Store" }) else { throw JournalError.folderInUse(folder) }
        }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        func order(_ name: String) -> (Int, String) { (name == JournalLayout.markerName ? 1 : 0, name) }
        for (name, contents) in JournalLayout.rootFiles.sorted(by: { order($0.key) < order($1.key) }) {
            try add(contents, at: folder.appendingPathComponent(name), named: name)
        }
    }

    // MARK: - Adding files

    /// As `JournalWriting.place`. A file already at that path is never replaced: with the same
    /// bytes, `runFile` just goes; with different ones it throws `JournalError.clash`, and the
    /// journal outbox moves `runFile` to `Pending/kept/`.
    func place(runFile: URL, header: RunFileHeader, startedAt: Date) throws {
        guard let run = header.run else { throw JournalError.notARun }
        try locked {
            guard let folder = locate() else { throw JournalError.missing }
            let path = JournalLayout.runPath(startedAt: startedAt, run: run)
            let destination = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if try Self.move(runFile, toNew: destination) { return }
            // Already there: the same file placed before (the app stopped before the working file
            // went), or something gone wrong. Never replace it.
            guard try Self.sameBytes(runFile, destination) else { throw JournalError.clash(path: path) }
            try FileManager.default.removeItem(at: runFile)
        }
    }

    /// As `JournalWriting.add`, each file written to a temporary name first and then renamed, so
    /// a reader never sees half of one. An event file already there with different bytes throws
    /// `JournalError.clash`; a score whose bytes don't have its hash, `JournalError.damagedScore`.
    func add(event: LoggedEvent, header: RunFileHeader, piece: JournalPieceFile?) throws {
        var header = header
        header.event = event.id
        let contents = try header.encodedLine() + event.encodedLine()
        try locked {
            guard let folder = locate() else { throw JournalError.missing }
            if let piece { try Self.write(piece, in: folder) }
            let path = JournalLayout.eventPath(at: event.time, event: event.id)
            try Self.add(contents, at: folder.appendingPathComponent(path), named: path)
        }
    }

    /// Writes the score to `pieces/` unless it's already there. A different file under its name
    /// is damaged (its bytes don't have the hash it's named by), and the one change to a file the
    /// format allows is putting a damaged score back to the right bytes.
    private static func write(_ piece: JournalPieceFile, in folder: URL) throws {
        guard JournalPieceFile.sha256(of: piece.data) == piece.hash.lowercased() else {
            throw JournalError.damagedScore(hash: piece.hash)
        }
        let destination = folder.appendingPathComponent(JournalLayout.piecePath(hash: piece.hash,
                                                                                 fileExtension: piece.fileExtension))
        if let existing = try? Data(contentsOf: destination), existing == piece.data { return }
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = temporaryURL(in: directory)
        try writeSynced(piece.data, to: temporary)
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// Writes `contents` as a new file at `destination` (its folders made first): to a temporary
    /// name beside it, then renamed, so a reader never sees half a file. The same bytes already
    /// there count as written; different ones are kept, and it throws.
    private static func add(_ contents: Data, at destination: URL, named path: String) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = temporaryURL(in: directory)
        try writeSynced(contents, to: temporary)
        if try move(temporary, toNew: destination) { return }
        try? FileManager.default.removeItem(at: temporary)
        guard (try? Data(contentsOf: destination)) == contents else { throw JournalError.clash(path: path) }
    }

    /// Moves `source` to `destination` unless something is already there: renamed when both are
    /// on one volume, otherwise copied in under a temporary name first and then renamed, and the
    /// source deleted. Returns false, leaving `source` as it was, when `destination` exists.
    private static func move(_ source: URL, toNew destination: URL) throws -> Bool {
        if renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 { return true }
        switch errno {
        case EEXIST: return false
        case EXDEV: break
        case let code: throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        let temporary = temporaryURL(in: destination.deletingLastPathComponent())
        try writeSynced(try Data(contentsOf: source), to: temporary)
        guard renamex_np(temporary.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temporary)
            if code == EEXIST { return false }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        try FileManager.default.removeItem(at: source)
        return true
    }

    private static func sameBytes(_ a: URL, _ b: URL) throws -> Bool {
        try Data(contentsOf: a) == Data(contentsOf: b)
    }

    /// A hidden name in `directory` that no reader takes for part of the journal.
    private static func temporaryURL(in directory: URL) -> URL {
        directory.appendingPathComponent(".clefwise-\(UUID().uuidString).tmp")
    }

    /// Writes `data` to a new file at `url` and waits for it to reach the disk, so a file renamed
    /// into the journal afterwards is never there without its bytes.
    static func writeSynced(_ data: Data, to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}
