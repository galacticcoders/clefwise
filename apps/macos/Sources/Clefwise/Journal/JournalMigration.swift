import Foundation

// Build 1 knew one journal, kept in the defaults, with its device state straight in Application
// Support/Clefwise. Build 2 knows several (`JournalRegistry`), each with its own state. This brings
// build 1's journal over as the first, once. See spec/practice-journal.md, "Several journals".

/// Where build 1 kept what it knew about its one journal on this Mac.
struct BuildOneFolders: Sendable {
    /// Holds `Current` (the working file of a run in progress) and `Pending` (records waiting for
    /// the journal): ~/Library/Application Support/Clefwise.
    var state: URL
    /// The piece library: ~/Library/Application Support/Clefwise/Pieces. The first journal keeps
    /// it where it is (`JournalRecord.libraryFolder`), and the old usage log's pieces come from it.
    var library: URL

    /// The app's. A harness points them elsewhere by replacing this one line.
    static let app = BuildOneFolders(state: RunFileWriter.defaultFolder, library: PieceLibrary.defaultFolder)
}

enum JournalMigration {
    /// Set once build 1's journal has been brought over, so it's done once, even if every journal
    /// is removed later.
    static let doneKey = "journalBroughtOverFromBuildOne"

    /// Brings build 1's journal over as the first journal on this Mac, if there's one to bring and
    /// nothing has been brought before: build 1's `journalPath` is set (`PracticeJournal.Keys`) and
    /// `registry` is empty. Call it at launch, before anything is logged: build 1's unfinished run
    /// moves with the rest.
    ///
    /// - **The record:** build 1's path and bookmark, and its piece library where it is
    ///   (`buildOne.library`), so no score moves. It's the journal in use.
    /// - **Settings, note stats** and the note that a round is being brought back (`Game.Keys`
    ///   `settings`, `noteStats`, `restoringRound`) are copied into the record's namespace. The keys
    ///   build 1 used stay as they were, its best sprint scores (`bestScores`) too: nothing reads
    ///   them now.
    /// - **Device state:** everything in build 1's `Current` and `Pending` moves into the record's
    ///   (`JournalState.current(for:in:)`, `pending(for:in:)`).
    /// - **The usage log** was brought into that journal when build 1 made it, so it's marked as
    ///   brought in (`AppModel.Keys.usageLogBroughtIn`): no journal gets it again.
    ///
    /// Returns the record made; nil when there was nothing to bring over. With no build 1 journal
    /// (a first launch, or build 1's sheet never answered), the app asks for a journal as usual.
    @MainActor @discardableResult
    static func migrateIfNeeded(_ registry: JournalRegistry, from buildOne: BuildOneFolders = .app,
                                stateRoot: URL = JournalState.root) -> JournalRecord? {
        let defaults = registry.defaults
        guard defaults.object(forKey: doneKey) == nil, registry.records.isEmpty,
              let path = defaults.object(forKey: PracticeJournal.Keys.path) as? String else { return nil }
        let record = registry.add(JournalRecord(id: UUID(), path: path,
                                                bookmark: defaults.object(forKey: PracticeJournal.Keys.bookmark) as? Data,
                                                libraryFolder: buildOne.library.path))
        for name in [Game.Keys.settings, Game.Keys.noteStats, Game.Keys.restoringRound] {
            guard let value = defaults.object(forKey: name) else { continue }
            defaults.set(value, forKey: Game.key(name, in: record.defaultsNamespace))
        }
        moveContents(of: buildOne.state.appendingPathComponent("Current", isDirectory: true),
                     into: JournalState.current(for: record.id, in: stateRoot))
        moveContents(of: buildOne.state.appendingPathComponent("Pending", isDirectory: true),
                     into: JournalState.pending(for: record.id, in: stateRoot))
        defaults.set(true, forKey: AppModel.Keys.usageLogBroughtIn)
        defaults.set(true, forKey: doneKey)
        return record
    }

    /// Moves everything in `source` into `destination`, folders merged with any already there. A
    /// file that would replace one already there stays where it was. `source` goes once it's empty.
    static func moveContents(of source: URL, into destination: URL) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: source.path) else { return }
        try? manager.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in names {
            let from = source.appendingPathComponent(name), to = destination.appendingPathComponent(name)
            var isFolder: ObjCBool = false
            if manager.fileExists(atPath: to.path, isDirectory: &isFolder) {
                var isSourceFolder: ObjCBool = false
                if isFolder.boolValue, manager.fileExists(atPath: from.path, isDirectory: &isSourceFolder),
                   isSourceFolder.boolValue {
                    moveContents(of: from, into: to)
                }
                continue
            }
            try? manager.moveItem(at: from, to: to)
        }
        // Only when nothing was left behind.
        rmdir(source.path)
    }
}
