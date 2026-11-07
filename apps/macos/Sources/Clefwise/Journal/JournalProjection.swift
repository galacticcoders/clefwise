import Foundation

// What the app keeps today (note stats), worked out from the practice journal's
// files alone: the proof that the files are the data and the rest a projection of them. See
// spec/practice-journal.md, "Reading" and "What stays on each device".

/// Note stats folded from a journal's runs, starting from its opening balances, exactly as `Game`
/// keeps them as it goes. The best sprint scores that runs and opening balances from versions until
/// 2026-11-07 hold aren't kept: the sprint is gone, and nothing shows them.
struct JournalProjection: Equatable, Sendable {
    /// As `Game` saves them (`noteStats`), by `statKey`.
    var noteStats: [String: NoteStat] = [:]
    /// Runs folded in.
    var runsRead = 0
    /// Record files left out, runs and event files alike (`JournalReader.Contents.skippedFiles`):
    /// not complete yet (still arriving, no `roundEnded` last), or in a format newer than this
    /// version reads.
    var runsSkipped = 0
    /// Lines that didn't parse in the files folded in (`JournalReader.Contents.unreadableLines`).
    var unreadableLines = 0

    /// The note stats key, as `Game` keeps them: "treble.F♯4", the clef and the pitch's name as
    /// asked (`questionShown`'s `clef` and `pitch.name`), in random and piece rounds alike.
    static func statKey(clef: String, pitch name: String) -> String {
        "\(clef).\(name)"
    }

    // MARK: - From a journal

    /// Reads the journal in `folder` from scratch with a `JournalReader` and folds it with
    /// `init(contents:)`. Files whose names don't fit the layout are ignored, as are runs not
    /// complete yet and files in a newer format. An app that reads the journal again and again
    /// keeps its own `JournalReader`, which then reads only the files it hasn't read yet.
    static func read(journal folder: URL) -> JournalProjection {
        JournalProjection(contents: JournalReader(folder: folder).read())
    }

    // MARK: - From events

    /// Folds `openingBalances`, then `runs` (each a run's events from `roundStarted` to its end) in
    /// the order given.
    static func fold(openingBalances: [StatsSnapshot], runs: [[LoggedEvent]]) -> JournalProjection {
        var projection = JournalProjection()
        for snapshot in openingBalances { projection.apply(snapshot) }
        for run in runs { projection.apply(run: run) }
        return projection
    }

    /// Adds an opening balance. The first is taken as it is; another (a second device's) adds its
    /// attempts and right answers to each note's, and its recent results after the ones already
    /// there (keeping the last eight, as `NoteStat` does).
    mutating func apply(_ snapshot: StatsSnapshot) {
        for (key, stat) in snapshot.noteStats {
            guard var kept = noteStats[key] else {
                noteStats[key] = stat
                continue
            }
            kept.attempts += stat.attempts
            kept.correct += stat.correct
            kept.recent = Array((kept.recent + stat.recent).suffix(8))
            noteStats[key] = kept
        }
    }

    /// Folds one run in, by the rule `Game` follows as it goes: every answer counts towards its
    /// note's stat (`NoteStat.record`), in the order given, in random and piece rounds alike. Notes
    /// asked together are answered one `answerGiven` each, in the order `Game` counts them.
    mutating func apply(run events: [LoggedEvent]) {
        var keys: [UUID: String] = [:]
        for logged in events {
            switch logged.event {
            case .questionShown(let question):
                keys[question.question] = Self.statKey(clef: question.clef, pitch: question.pitch.name)
            case .answerGiven(let answer):
                guard let key = keys[answer.question] else { continue }
                noteStats[key, default: NoteStat()].record(answer.correct)
            default:
                continue
            }
        }
        runsRead += 1
    }
}

// In an extension, so the memberwise initialiser and `init()` stay.
extension JournalProjection {
    /// Folds what a `JournalReader` read: the opening balances (`contents.snapshots`, merged by
    /// `apply(_:)` in time order), then the runs (`contents.runs`, by start time, then id).
    /// `runsSkipped` takes `contents.skippedFiles`, and `unreadableLines` its `unreadableLines`.
    init(contents: JournalReader.Contents) {
        self.init()
        for event in contents.snapshots {
            if case .statsSnapshot(let snapshot) = event.event { apply(snapshot) }
        }
        for run in contents.runs { apply(run: run.events) }
        runsSkipped = contents.skippedFiles
        unreadableLines = contents.unreadableLines
    }
}
