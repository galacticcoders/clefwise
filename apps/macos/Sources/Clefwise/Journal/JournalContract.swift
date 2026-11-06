import CryptoKit
import Foundation

// What the journal's parts promise each other: the run-file writer (fed by the usage log), the
// journal folder, and the crash restore in `Game`. See spec/practice-journal.md, "Writing a run"
// and "After a crash".

/// A run's working file found at launch with answers in it and no end: the app stopped mid-round
/// without quitting (a crash, a force quit, the battery running out). `Game` rebuilds the round
/// from `events` and records `roundRestored`, or, when it can't, ends it with a `roundEnded` whose
/// reason is `interrupted`.
struct PendingRun: Equatable, Sendable {
    /// The round's id: the `round` in its events, and the header's `run`.
    var round: UUID
    /// The working file. It stays open for appending, so this launch's lines (its `appLaunched`
    /// first) go on after the ones already there.
    var file: URL
    /// The file's events, in the order written, the header left out.
    var events: [LoggedEvent]
}

/// Tees each practice run's lines from the usage log into a working file of its own on the device,
/// and hands the finished file to the journal. The app makes one at launch, calls
/// `inspectAtLaunch()`, then sets it as `UsageLog.lineSink` before recording `appLaunched`.
///
/// As a `RunLineSink` (on the log's queue): a `roundStarted` opens a working file and writes the
/// header (`RunFileHeader(run:device:launch:)`), then the line; every line after it, whatever its
/// type, is appended byte for byte; its `roundEnded` is appended, the file synced and closed, and
/// then a run with no `answerGiven` is deleted and any other placed in the journal
/// (`JournalWriting.place`). A device runs one round at a time, so there's at most one working file.
protocol RunFileWriting: RunLineSink {
    /// Looks for a working file left by the last launch, before this launch records anything:
    /// - none: nil;
    /// - one already ending with `roundEnded` (the app stopped before placing it) is placed in the
    ///   journal as it is: nil;
    /// - one with no `answerGiven` is deleted: nil;
    /// - otherwise it stays open for appending, so the lines this launch logs go on in it until the
    ///   round's `roundEnded`, and it's returned for `Game` to restore.
    func inspectAtLaunch() -> PendingRun?
}

/// The practice journal: the folder of plain files the user owns, where finished runs, event files
/// and scores go. Only ever added to. Used from any thread (finished runs come from the usage
/// log's queue, library events from the main thread), so implementations keep their file work
/// safe to call from several at once.
protocol JournalWriting: AnyObject, Sendable {
    /// The journal's folder; nil while there's none (before it's made at first launch), or when it
    /// can't be found (a disk unplugged, the folder moved out of reach).
    var folder: URL? { get }

    /// Moves a finished run file into the journal, at
    /// `JournalLayout.runPath(startedAt:run:)` with `header.run`; `startedAt` is its `roundStarted`'s
    /// `time`. The file already starts with `header`. Throws when there's no journal, `header` has
    /// no `run`, or the move fails; the file is then left where it was, to be placed later.
    func place(runFile: URL, header: RunFileHeader, startedAt: Date) throws

    /// Writes an event file: `header` (with `event` set to `event.id`) and `event` as its one line,
    /// at `JournalLayout.eventPath(at:event:)` from the event's `time` and `id`. A score it brings
    /// in (`pieceAdded`, `pieceRevised`) is written to `pieces/` first, unless it's already there.
    /// Throws when there's no journal or a write fails.
    func add(event: LoggedEvent, header: RunFileHeader, piece: JournalPieceFile?) throws
}

/// A score going into the journal's `pieces/`, named by its hash
/// (`JournalLayout.piecePath(hash:fileExtension:)`).
struct JournalPieceFile: Equatable, Sendable {
    /// The score's exact bytes.
    var data: Data
    /// SHA-256 of `data`, lowercase hex: the piece's name, and its id in the journal when it's the
    /// file the piece was first added with.
    var hash: String
    /// `musicxml`, `xml` or `mxl`, without the dot.
    var fileExtension: String
}

extension JournalPieceFile {
    /// `data` named by its own SHA-256.
    init(data: Data, fileExtension: String) {
        self.init(data: data, hash: Self.sha256(of: data), fileExtension: fileExtension)
    }

    /// SHA-256 in lowercase hex, as `PieceLibrary.Entry.contentHash` is worked out.
    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
