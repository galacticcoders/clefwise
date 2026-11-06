import Foundation

// What this Mac keeps about each practice journal it knows, outside the journal: its piece library,
// the records waiting for it, and the working file of a run in progress. None of it syncs. See
// spec/practice-journal.md, "What stays on each device" and "Several journals".

/// Where this Mac keeps its own state for each journal it knows: a folder per journal, named by the
/// journal's local id (`JournalRecord.id`), under `root`:
///
/// ```
/// ~/Library/Application Support/Clefwise/Journals/<lowercase local id>/
///     Pieces/     the journal's piece library on this Mac
///     Pending/    records waiting to go into the journal
///     Current/    the working file of a run in progress
/// ```
///
/// The journal's settings on this Mac live in the defaults instead, under
/// `JournalRecord.defaultsNamespace`.
enum JournalState {
    /// ~/Library/Application Support/Clefwise/Journals.
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clefwise/Journals", isDirectory: true)
    }

    /// The root the app uses. A harness points it elsewhere by replacing this one line (keep it on
    /// one line, `defaultRoot` alone on the right).
    static let root = defaultRoot

    /// `<root>/<lowercase id>`: everything this Mac keeps about the journal `id`. This is the
    /// folder to give `RunFileWriter(folder:…)`, which keeps `Current` and `Pending` in it.
    static func folder(for id: UUID, in root: URL = JournalState.root) -> URL {
        root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    /// `<folder>/Pieces`: the journal's piece library on this Mac (`PieceLibrary(folder:)`): a copy
    /// of each of its scores, and `index.json`, which also keeps each piece's own practice
    /// settings. Not used when the journal's record names a library kept elsewhere
    /// (`JournalRecord.libraryFolder`).
    static func library(for id: UUID, in root: URL = JournalState.root) -> URL {
        folder(for: id, in: root).appendingPathComponent("Pieces", isDirectory: true)
    }

    /// `<folder>/Pending`: finished records waiting for the journal while it can't be reached,
    /// laid out as in the journal, and `kept/` for this Mac's copy of any that clashed
    /// (`JournalOutbox.pendingFolder`).
    static func pending(for id: UUID, in root: URL = JournalState.root) -> URL {
        folder(for: id, in: root).appendingPathComponent("Pending", isDirectory: true)
    }

    /// `<folder>/Current`: the working file of the journal's run in progress, at most one, which
    /// goes into the journal when the run ends and is found here again after a crash
    /// (`RunFileWriter.currentFolder`).
    static func current(for id: UUID, in root: URL = JournalState.root) -> URL {
        folder(for: id, in: root).appendingPathComponent("Current", isDirectory: true)
    }
}
