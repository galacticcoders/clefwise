import Foundation

// What the app keeps today (note stats and best scores), worked out from the practice journal's
// files alone: the proof that the files are the data and the rest a projection of them. See
// spec/practice-journal.md, "Reading" and "What stays on each device".

/// Note stats and best scores folded from a journal's runs, starting from its opening balances,
/// exactly as `Game` keeps them as it goes.
struct JournalProjection: Equatable, Sendable {
    /// As `Game` saves them (`noteStats`), by `statKey`.
    var noteStats: [String: NoteStat] = [:]
    /// As `Game` saves them (`bestScores`), by `Game.bestScoreKey(for:)`.
    var bestScores: [String: Int] = [:]
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
    /// attempts and right answers to each note's, its recent results after the ones already there
    /// (keeping the last eight, as `NoteStat` does), and keeps the higher best score.
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
        bestScores.merge(snapshot.bestScores) { max($0, $1) }
    }

    /// Folds one run in, by the rules `Game` follows as it goes:
    /// - **Note stats:** every answer counts towards its note's stat (`NoteStat.record`), in the
    ///   order given, in random and piece rounds alike. Notes asked together are answered one
    ///   `answerGiven` each, in the order `Game` counts them.
    /// - **Best scores:** a sprint on random notes that ended by running out of time or being
    ///   stopped (not abandoned, quit or interrupted) keeps its score as the best for its setup
    ///   (`Game.bestScoreKey(for:)` with its `roundStarted.settings`) when it beats the best so far:
    ///   a tie keeps the old one, and a first score of 0 sets none.
    mutating func apply(run events: [LoggedEvent]) {
        var keys: [UUID: String] = [:]
        var settings: Game.Settings?
        var isPieceRound = false
        var round: UUID?
        for logged in events {
            switch logged.event {
            case .roundStarted(let started):
                round = started.round
                settings = Self.settings(from: started.settings)
                isPieceRound = started.piece != nil
            case .questionShown(let question):
                keys[question.question] = Self.statKey(clef: question.clef, pitch: question.pitch.name)
            case .answerGiven(let answer):
                guard let key = keys[answer.question] else { continue }
                noteStats[key, default: NoteStat()].record(answer.correct)
            case .roundEnded(let ended) where ended.round == round:
                guard Self.keepsBestScore(ended.reason), !isPieceRound, let settings, settings.mode == .sprint else { continue }
                let key = Game.bestScoreKey(for: settings)
                if ended.score > (bestScores[key] ?? 0) { bestScores[key] = ended.score }
            default:
                continue
            }
        }
        runsRead += 1
    }

    /// The ends `Game.finish` scores: the clock running out, Stop, the end of a piece or of a set
    /// number of notes. A round abandoned, quit or interrupted keeps no score.
    private static func keepsBestScore(_ reason: RoundEndReason) -> Bool {
        switch reason {
        case .timeUp, .stopped, .pieceComplete, .notesDone: true
        case .abandoned, .appQuit, .interrupted: false
        }
    }

    /// `roundStarted.settings` as `Game` reads saved settings: missing keys take their defaults.
    private static func settings(from value: JSONValue) -> Game.Settings? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(Game.Settings.self, from: data)
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
