import Foundation

// The journals one Mac knows, one per person, and watching the one in use for files arriving. The
// registry and the watcher are built against these. See spec/practice-journal.md, "Several
// journals" and "Folder sync".

/// A journal this Mac knows: where it is, and where this Mac keeps its state about it. Kept on
/// this Mac only, never in the journal. The app works on one journal at a time, and switches only
/// between rounds.
struct JournalRecord: Codable, Equatable, Identifiable, Sendable {
    /// The journal's id on this Mac only: it names its state folder (`JournalState.folder(for:)`)
    /// and its namespace in the defaults (`defaultsNamespace`). Another Mac knows the same journal
    /// by another id.
    var id: UUID
    /// The journal's folder as last found. `bookmark` follows the folder when it's moved or
    /// renamed, and then this path is brought up to date.
    var path: String
    /// A bookmark to the folder, to find it again after it's moved or renamed; nil when one
    /// couldn't be made.
    var bookmark: Data?
    /// The path of a piece library kept somewhere other than the journal's state folder: the
    /// first journal on a Mac that ran build 1 keeps that build's
    /// `Application Support/Clefwise/Pieces`. Nil for `JournalState.library(for: id)`.
    var libraryFolder: String?

    /// The journal's name, as the user sees it: its folder's name.
    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// The prefix of every key this journal's values have in the defaults on this Mac:
    /// `journal.<lowercase id>.`. Give it to `Game(defaults:namespace:…)`; `Game.key(_:in:)` makes
    /// the full key.
    var defaultsNamespace: String {
        "journal.\(id.uuidString.lowercased())."
    }

    /// The journal's piece library on this Mac: `libraryFolder` when set, otherwise
    /// `JournalState.library(for: id, in: root)`.
    func libraryURL(in root: URL = JournalState.root) -> URL {
        libraryFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? JournalState.library(for: id, in: root)
    }
}

/// Watches a journal's folder for files arriving, from this Mac or through a sync service, so the
/// app can read it again (a `JournalReader` then reads only the new files). The app watches the
/// journal in use, and nothing else.
///
/// - **Recursive and file-level:** a file added, renamed, changed or removed anywhere in the
///   folder counts, however deep (`runs/2026/11/…`), including names readers ignore (`.DS_Store`,
///   temporary names): the reader sorts those out.
/// - **Debounced:** changes are gathered for about half a second after the first, then reported
///   once, so a sync bringing in hundreds of files calls back a few times, not hundreds.
/// - **On the main actor:** `onChange` is always called there, never on the watcher's own queue.
/// - **Also for this Mac's own writes:** a run this Mac placed or a piece it added calls back
///   too; it's not filtered out.
/// - It says only that something changed, not what: no paths, no kinds of change.
///
/// The app calls `start` and `stop` on the main actor.
protocol JournalWatching: AnyObject {
    /// Starts watching `folder` and everything in it, calling `onChange` (debounced, on the main
    /// actor) after files change. Watching another folder, or the same one again, stops the
    /// earlier watch first: one folder at a time.
    func start(watching folder: URL, onChange: @escaping @MainActor @Sendable () -> Void)

    /// Stops watching. Once it returns, `onChange` isn't called again, even for changes already
    /// gathered. Stopping when not watching does nothing.
    func stop()
}
