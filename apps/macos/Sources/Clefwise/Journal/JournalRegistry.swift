import Foundation
import Observation

// The practice journals this Mac knows, one per person, and the one the app works on. See
// spec/practice-journal.md, "Several journals".

/// The journals this Mac knows (`JournalRecord`s, kept in the defaults under `journals`) and the
/// one in use (its id under `currentJournal`). Each record's folder is found through a
/// `PracticeJournal` of its own, which follows the folder when it's moved or renamed and brings
/// the record's path up to date. Nothing here ever deletes a journal's folder, or anything in it.
@MainActor @Observable
final class JournalRegistry {
    /// Where the defaults keep the list and the one in use.
    enum Keys {
        static let journals = "journals"
        static let current = "currentJournal"
    }

    /// Every journal this Mac knows, in the order they were added.
    private(set) var records: [JournalRecord]
    /// The journal in use; nil while there's none (before the first is made, or once the last is
    /// removed).
    private(set) var currentID: UUID?

    @ObservationIgnored let defaults: UserDefaults
    /// Each record's journal, made when first asked for and kept, so there's one per journal.
    @ObservationIgnored private var journals: [UUID: PracticeJournal] = [:]

    /// Reads the list from `defaults`. A journal in use that isn't on the list any more falls back
    /// to the first on it.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        let records = (defaults.object(forKey: Keys.journals) as? Data)
            .flatMap { try? JSONDecoder().decode([JournalRecord].self, from: $0) } ?? []
        self.records = records
        let saved = (defaults.object(forKey: Keys.current) as? String).flatMap(UUID.init(uuidString:))
        currentID = records.contains { $0.id == saved } ? saved : records.first?.id
    }

    /// The journal in use, if there is one.
    var current: JournalRecord? {
        currentID.flatMap(record(id:))
    }

    func record(id: UUID) -> JournalRecord? {
        records.first { $0.id == id }
    }

    /// The journal of `record`, to write to and to find its folder: the same one each time.
    func journal(for record: JournalRecord) -> PracticeJournal {
        if let journal = journals[record.id] { return journal }
        let journal = makeJournal(record.id, path: record.path, bookmark: record.bookmark)
        journals[record.id] = journal
        return journal
    }

    /// Where `record`'s journal is now: at its path, or else wherever its bookmark finds it, which
    /// then becomes the record's path. Nil when it can't be found (a disk unplugged, the folder
    /// moved out of reach, or deleted).
    func folder(for record: JournalRecord) -> URL? {
        journal(for: record).folder
    }

    /// The journal this Mac knows in `folder`, if any: by its path, or by where it's found now.
    func record(at folder: URL) -> JournalRecord? {
        let known = records
        return known.first { PracticeJournal.isSameFolder(URL(fileURLWithPath: $0.path), folder) }
            ?? known.first { record in self.folder(for: record).map { PracticeJournal.isSameFolder($0, folder) } ?? false }
    }

    /// Each journal's name for a menu: its folder's name, with the folder it's in added where two
    /// share a name.
    var displayNames: [UUID: String] {
        let byName = Dictionary(grouping: records, by: \.name)
        return Dictionary(uniqueKeysWithValues: records.map { record in
            guard byName[record.name, default: []].count > 1 else { return (record.id, record.name) }
            let parent = URL(fileURLWithPath: record.path).deletingLastPathComponent().path
            return (record.id, "\(record.name) (\((parent as NSString).abbreviatingWithTildeInPath))")
        })
    }

    // MARK: - Changing the list

    /// Makes the journal `name` in `parent` (the folder and its root files, with their exact bytes),
    /// adds it to the list and makes it the one in use. A journal already there (`parent` itself,
    /// or one called `name` in it) is taken as it is: when this Mac knows it already, that record
    /// is the one in use; otherwise it's added. Throws as `PracticeJournal.create(named:in:)`.
    @discardableResult
    func create(named name: String, in parent: URL) throws -> JournalRecord {
        if let existing = PracticeJournal.existingJournal(named: name, in: parent), let known = record(at: existing) {
            switchTo(known.id)
            return known
        }
        let id = UUID()
        let journal = makeJournal(id, path: nil, bookmark: nil)
        let folder = try journal.create(named: name, in: parent)
        return add(JournalRecord(id: id, path: folder.path, bookmark: journal.lastKnownBookmark, libraryFolder: nil),
                   journal: journal)
    }

    /// Adds the journal in `folder` (File ▸ Open Journal…) and makes it the one in use; one this Mac
    /// knows already is made the one in use as it is. Throws `JournalError.notAJournal` when
    /// `folder` has no `clefwise.json`.
    @discardableResult
    func open(_ folder: URL) throws -> JournalRecord {
        guard PracticeJournal.isJournal(folder) else { throw JournalError.notAJournal(folder) }
        if let known = record(at: folder) {
            switchTo(known.id)
            return known
        }
        let id = UUID()
        let journal = makeJournal(id, path: nil, bookmark: nil)
        try journal.use(folder)
        return add(JournalRecord(id: id, path: folder.path, bookmark: journal.lastKnownBookmark, libraryFolder: nil),
                   journal: journal)
    }

    /// Keeps `folder`, found again by the user (Locate…), as where the journal `id` is. Throws
    /// `JournalError.notAJournal` when it has no `clefwise.json`, and `JournalError.listedAlready`
    /// when it's another journal on the list.
    func relocate(_ id: UUID, to folder: URL) throws {
        guard let record = record(id: id) else { return }
        guard PracticeJournal.isJournal(folder) else { throw JournalError.notAJournal(folder) }
        if let other = records.first(where: { $0.id != id && PracticeJournal.isSameFolder(URL(fileURLWithPath: $0.path), folder) }) {
            throw JournalError.listedAlready(URL(fileURLWithPath: other.path))
        }
        // The journal tells `relocated` its new path and bookmark.
        try journal(for: record).use(folder)
    }

    /// Adds `record` (build 1's journal, brought over) and makes it the one in use.
    @discardableResult
    func add(_ record: JournalRecord) -> JournalRecord {
        add(record, journal: nil)
    }

    /// Makes the journal `id` the one in use; an id not on the list changes nothing.
    func switchTo(_ id: UUID) {
        guard record(id: id) != nil, currentID != id else { return }
        currentID = id
        save()
    }

    /// Forgets the journal `id` on this Mac: it leaves the list. Its folder and everything in it are
    /// never touched. What this Mac kept about it stays where it is, unused: its keys in the
    /// defaults (`JournalRecord.defaultsNamespace`) and its state folder (`JournalState.folder`),
    /// records waiting in `Pending` included. Opening the journal again adds it as new, with a new
    /// id, so it starts from the default settings. When it was the one in use, none is until
    /// `switchTo`.
    func remove(_ id: UUID) {
        guard record(id: id) != nil else { return }
        records.removeAll { $0.id == id }
        journals[id] = nil
        if currentID == id { currentID = nil }
        save()
    }

    // MARK: - Keeping it

    private func add(_ record: JournalRecord, journal: PracticeJournal?) -> JournalRecord {
        records.append(record)
        if let journal { journals[record.id] = journal }
        currentID = record.id
        save()
        return record
    }

    /// A journal for the record `id`, whose new location goes into the record whenever it's kept
    /// somewhere new (which can happen on the journal outbox's queue).
    private func makeJournal(_ id: UUID, path: String?, bookmark: Data?) -> PracticeJournal {
        PracticeJournal(path: path, bookmark: bookmark) { [weak self] path, bookmark in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.relocated(id, path: path, bookmark: bookmark) }
            } else {
                Task { @MainActor in self?.relocated(id, path: path, bookmark: bookmark) }
            }
        }
    }

    /// The journal `id` was found, made or located at `path`.
    private func relocated(_ id: UUID, path: String, bookmark: Data?) {
        guard let index = records.firstIndex(where: { $0.id == id }),
              records[index].path != path || records[index].bookmark != bookmark else { return }
        records[index].path = path
        records[index].bookmark = bookmark
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(records), forKey: Keys.journals)
        if let currentID {
            defaults.set(currentID.uuidString, forKey: Keys.current)
        } else {
            defaults.removeObject(forKey: Keys.current)
        }
    }
}
