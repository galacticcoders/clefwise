import Foundation

// The usage log: everything that happens in the app, kept so progress can be analysed later.
// Each event is one JSON object per line, its payload flattened next to the envelope fields:
//   {"schema":1,"type":"answerGiven","id":"…","time":"2026-10-30T17:02:11.348Z","session":"…",
//    "sequence":42,"round":"…","question":"…","correct":true,"responseMs":1820,…}
// Payload fields must not reuse the envelope names (schema, type, id, time, session, sequence).
// Add fields freely; bump `LoggedEvent.schemaVersion` only when a field changes meaning.

/// Where events go. The app writes them to disk (`UsageLog`); tests keep them in memory.
protocol UsageRecorder: AnyObject {
    /// Records `event` as happening now.
    func record(_ event: UsageEvent)
    /// Records `event` as happening at `time` rather than now, for an event that belongs to an
    /// earlier moment: an `interrupted` round end takes the time of the round's last event (and
    /// says when it was written in `RoundEnded.recordedAt`). It's still numbered in the order
    /// recorded.
    func record(_ event: UsageEvent, at time: Date)
}

enum UsageEvent: Equatable {
    case appLaunched(AppLaunched)
    case appTerminated(AppTerminated)
    case appActivity(AppActivity)
    case windowResized(WindowResized)
    case settingChanged(SettingChanged)
    case roundStarted(RoundStarted)
    case questionShown(QuestionShown)
    case answerGiven(AnswerGiven)
    case inputIgnored(InputIgnored)
    case roundPaused(RoundPaused)
    case roundResumed(RoundResumed)
    case roundRestored(RoundRestored)
    case roundEnded(RoundEnded)
    case pieceOpened(PieceOpened)
    case pieceOpenFailed(PieceOpenFailed)
    case pieceClosed(PieceClosed)
    case pieceAdded(PieceAdded)
    case pieceRevised(PieceRevised)
    case pieceRemoved(PieceRemoved)
    case uiAction(UIAction)
    case statsSnapshot(StatsSnapshot)
}

// MARK: - Payloads

struct AppLaunched: Codable, Equatable {
    var appVersion: String
    var build: String
    var osVersion: String
    /// Mac model identifier, e.g. "Mac15,12".
    var model: String
    var locale: String
    var timeZone: String
    var screen: Size?
    /// How macOS was set at launch, `light` or `dark`, whatever the app's own Appearance setting.
    var systemAppearance: String?
}

struct AppTerminated: Codable, Equatable {
    /// Since launch.
    var sessionSeconds: Double
}

/// The app became the active app (`active`) or stopped being it, for counting time actually spent.
struct AppActivity: Codable, Equatable {
    var active: Bool
}

struct WindowResized: Codable, Equatable {
    var size: Size
}

struct Size: Codable, Equatable {
    var width: Double
    var height: Double
}

/// One setting changed, by its key in the saved settings (e.g. "naming", "piece.hand").
struct SettingChanged: Codable, Equatable {
    var setting: String
    var from: JSONValue
    var to: JSONValue
}

struct RoundStarted: Codable, Equatable {
    var round: UUID
    var via: StartSource
    /// All settings at the start of the round, as saved.
    var settings: JSONValue
    /// The key signature the round is in (random keys resolved); for pieces, the first note's.
    var keyFifths: Int
    var piece: PieceContext?

    /// The round was a 60-second sprint. Versions until 2026-11-07 offered sprints beside practice
    /// rounds and saved which in the settings' `mode` (`sprint` or `practice`); rounds logged since
    /// have no `mode` and are all practice rounds.
    var wasSprint: Bool {
        guard case .object(let values) = settings else { return false }
        return values["mode"] == .string("sprint")
    }
}

struct PieceContext: Codable, Equatable {
    var title: String
    var path: String
    var part: String
    var partIndex: Int
    var hand: String
    var order: String
    var startBar: Int
    /// Only the top note of right-hand chords and the bottom note of left-hand ones: `chords` is
    /// `topOrBottom`.
    var oneNotePerChord: Bool
    /// Notes this round asks, and bars in the part.
    var noteCount: Int
    var measureCount: Int
    /// How chords are asked: `eachNote`, `topOrBottom` or `together` (`Game.PieceSettings.Chords`);
    /// nil in rounds logged before the setting existed.
    var chords: String? = nil
    /// The piece's entry in the piece library; nil for a piece that couldn't be kept there, and in
    /// rounds logged before the library.
    var libraryID: UUID? = nil
    /// The piece in the practice journal: the SHA-256 (lowercase hex) of the file it was first
    /// added with, as in the journal's `pieceAdded`. Nil for a piece not in the journal, and in
    /// rounds logged before it.
    var id: String? = nil
    /// The SHA-256 of the exact file practised; differs from `id` once the piece was revised (the
    /// score exported again with changes). Nil whenever `id` is.
    var file: String? = nil
    /// Staves in the part practised: 1, or 2 for a grand staff. Nil in rounds logged before the
    /// journal.
    var staves: Int? = nil
}

struct QuestionShown: Codable, Equatable {
    var round: UUID
    var question: UUID
    /// 0-based count of questions shown so far this round.
    var index: Int
    var clef: String
    /// As played, and as written (they differ under 8va/8vb).
    var pitch: LoggedPitch
    var written: LoggedPitch
    /// Staff position of the written note: 0 = bottom line, each step a line or space.
    var position: Int
    var keyFifths: Int
    /// −1 flat, 0 natural, 1 sharp; nil when no sign is printed before the note.
    var printedAccidental: Int?
    var octaveShift: Int
    var pieceNote: PieceNoteRef?
    /// Chance this note had of being picked (random and shuffled rounds), to study the adaptive picking.
    var pickChance: Double?
    var naming: String
    var input: String
    var hintsVisible: Bool
    var keyNamesVisible: Bool
    /// Pieces only: asked in the whole-bar view (true) or on its own (false); nil for random notes.
    var barView: Bool? = nil
    /// The staves the bar view drew, top to bottom: [1, 2] for a grand staff; nil outside it.
    var barStaves: [Int]? = nil
    /// Notes asked together as one question ("All together") share a group id, and each says how
    /// many they were; nil for a note asked on its own.
    var group: UUID? = nil
    var groupSize: Int? = nil
}

struct LoggedPitch: Codable, Equatable {
    /// "F♯4"
    var name: String
    var letter: String
    /// −1 flat, 0 natural, 1 sharp.
    var accidental: Int
    var octave: Int
    var midi: Int

    init(_ pitch: Pitch) {
        name = pitch.name
        letter = pitch.letter.name
        accidental = pitch.accidental.rawValue
        octave = pitch.octave
        midi = pitch.midiNumber
    }
}

struct PieceNoteRef: Codable, Equatable {
    var measure: Int
    var staff: Int
    /// Quarter notes from the start of the piece.
    var onset: Double
    var chord: Int
    /// Where the note is drawn in its bar: its index among the bar's notes and rests on all
    /// staves (`ScoreNote.symbolIndex`); nil when the piece has no bar layout.
    var symbolIndex: Int? = nil
}

struct AnswerGiven: Codable, Equatable {
    var round: UUID
    var question: UUID
    /// From the question appearing to the answer.
    var responseMs: Int
    var source: AnswerSource
    /// What was answered: letter and sign, its name in the naming system in use ("Fa♯", "komal Re"),
    /// and the exact key for piano answers.
    var letter: String
    var accidental: Int
    var name: String
    var pitch: LoggedPitch?
    var correct: Bool
    /// Piano only: the right note in the wrong octave.
    var wrongOctave: Bool?
    /// Every key pressed while this question was up, in order.
    var keystrokes: [Keystroke]
    var scoreAfter: Int
    var streakAfter: Int
    /// How long the round was paused while this question was up; nil when it wasn't. `responseMs`
    /// leaves pauses out.
    var pausedMs: Int? = nil
    /// Notes asked together are answered one `answerGiven` per note, all at once, as in their
    /// `questionShown`: the same group id and size, response time, source, score and streak (after
    /// the whole group). Each has its own `correct`, and the entry judged with it: the one matched
    /// to it, or for a note named wrong one left over. Keystrokes go with the first note. Nil for a
    /// note answered on its own.
    var group: UUID? = nil
    var groupSize: Int? = nil
}

struct Keystroke: Codable, Equatable {
    /// The character typed, a key name ("Return", "Delete"…), or "click ♯" / "click ♭" for the
    /// note buttons' sign buttons. While notes are asked together, also clicks towards them:
    /// "click Sol♯" (a note button), "piano G♯4" (a key chosen or taken back), "remove Sol♯" (an
    /// entry taken back).
    var key: String
    /// Since the question appeared.
    var ms: Int
    var result: KeystrokeResult
}

/// An answer or keystroke that didn't count (during the pause after a miss, a sign with no name…).
struct InputIgnored: Codable, Equatable {
    var round: UUID?
    var reason: String
    var source: AnswerSource?
    var detail: String?
}

/// The round's clock stopped: the Pause button or Space.
struct RoundPaused: Codable, Equatable {
    var round: UUID
    /// The question on screen, if one was.
    var question: UUID?
    var via: PauseSource
    /// Round time so far, earlier pauses left out.
    var activeMs: Int
}

/// The round carried on after a pause.
struct RoundResumed: Codable, Equatable {
    var round: UUID
    var question: UUID?
    var via: PauseSource
    /// How long this pause lasted. After a `roundRestored`, counted from it.
    var pausedMs: Int
}

/// The round came back, paused, at the launch after a crash (or a force quit, or the battery
/// running out), rebuilt from its run file. The new session's `appLaunched` comes just before.
/// The time between the round's last event and this one counts as neither round time nor paused
/// time. See spec/practice-journal.md, "After a crash".
struct RoundRestored: Codable, Equatable {
    var round: UUID
    /// The round time brought back: up to the round's last event before the crash, pauses left out.
    var activeMs: Int
    /// The question on screen at the crash, if one was. It stays unanswered: when the round
    /// resumes, its note is asked again as a new question.
    var unansweredQuestion: UUID?
}

struct RoundEnded: Codable, Equatable {
    var round: UUID
    var reason: RoundEndReason
    /// How long the round ran, pauses left out.
    var durationMs: Int
    /// Time spent paused; nil when the round never was.
    var pausedMs: Int? = nil
    var score: Int
    var attempts: Int
    var bestStreak: Int
    var averageResponseMs: Int?
    /// Sprints only, so only in rounds logged by versions until 2026-11-07: the best score for the
    /// round's setup, and whether this round set it. Read so old lines still decode, never written.
    var bestScore: Int? = nil
    var isNewBest: Bool? = nil
    var notesToReview: [String]
    /// The question still on screen when the round ended (time up, stopped, quit…), if any.
    var unansweredQuestion: UnansweredQuestion? = nil
    /// When this event was written, for one timed earlier than that: an `interrupted` end takes the
    /// time of the round's last event and is written at a later launch. Nil otherwise.
    var recordedAt: Date? = nil
}

/// A question left without an answer: how long it was up and the keys pressed meanwhile.
struct UnansweredQuestion: Codable, Equatable {
    var question: UUID
    /// How long it was up, pauses left out.
    var shownMs: Int
    var keystrokes: [Keystroke]
    /// How long the round was paused while it was up; nil when it wasn't.
    var pausedMs: Int? = nil
    /// Notes asked together: their group, `question` being the first of them; nil otherwise.
    var group: UUID? = nil
}

struct PieceOpened: Codable, Equatable {
    /// Where the file was first opened from: a piece opened from the library, or another copy of
    /// the same file, keeps the path it was first opened from.
    var path: String
    var title: String
    var via: PieceOpenSource
    var parts: [PartInfo]
    /// The piece's entry in the piece library; nil when it couldn't be kept there (`libraryError`),
    /// and in events logged before the library.
    var libraryID: UUID? = nil
    /// The piece came back with the settings it was last practised with (from the library), rather
    /// than taking the ones in use. Nil in events logged before the library.
    var restoredSettings: Bool? = nil
    /// The piece settings it opened with, as saved (`piece` in the settings), fitted to the score.
    /// Restored settings are logged here only, not as `settingChanged`.
    var pieceSettings: JSONValue? = nil
    /// Why the piece couldn't be kept in the library (it was opened all the same).
    var libraryError: String? = nil
}

struct PartInfo: Codable, Equatable {
    var name: String
    var notes: Int
    var measures: Int
    var staves: Int
    var skipped: Int
}

struct PieceOpenFailed: Codable, Equatable {
    var path: String
    var via: PieceOpenSource
    var error: String
    /// The library entry that didn't open (its copy can't be read, or it's gone from the library).
    var libraryID: UUID? = nil
}

struct PieceClosed: Codable, Equatable {
    var path: String?
    /// The closed piece's entry in the piece library, when it had one.
    var libraryID: UUID? = nil
}

// The piece library's changes, as the practice journal keeps them: each is one event file in its
// `events/`, never a line in the usage log. See spec/practice-journal.md, "Event files".

/// A score joined the library. Its file is written to the journal's `pieces/` first.
struct PieceAdded: Codable, Equatable {
    /// The piece's id: the SHA-256 (lowercase hex) of the file it was first added with, which is
    /// that file's name in `pieces/`.
    var piece: String
    var title: String
    /// The original file's name, without its folder.
    var fileName: String
    /// The piece's entry in the adding device's piece library, and where the file was first
    /// opened from: the `libraryID` and `path` the usage log knows the piece by, so runs logged
    /// before the journal map to it. Nil when unknown.
    var libraryID: UUID? = nil
    var originalPath: String? = nil
}

/// A new version of a piece, for example the score edited and exported again. Both files stay in
/// `pieces/`.
struct PieceRevised: Codable, Equatable {
    /// The id the piece was first added with (`PieceAdded.piece`).
    var piece: String
    /// The new file's SHA-256: its name in `pieces/`.
    var file: String
    var title: String
}

/// The piece left the library. Its files and its runs stay; a `pieceAdded` brings it back.
struct PieceRemoved: Codable, Equatable {
    /// The id the piece was first added with.
    var piece: String
}

/// A button or menu item used, for questions like "does anyone press Play again?".
struct UIAction: Codable, Equatable {
    var name: String
    var detail: String?
}

/// The per-note history kept before the usage log existed, recorded once so the log starts from
/// everything the app knew.
struct StatsSnapshot: Codable, Equatable {
    var reason: String
    var noteStats: [String: NoteStat]
    /// The best 60-second sprint scores, in snapshots recorded by versions until 2026-11-07. Kept
    /// so an old snapshot reads, and is copied into a journal, as it is; nothing uses it now.
    var bestScores: [String: Int]? = nil
}

enum StartSource: String, Codable, Equatable {
    case button, key, playAgain
}

enum PauseSource: String, Codable, Equatable {
    /// The Pause/Resume button; Space; switching to another app mid-round (pauses only).
    case button, key, appSwitch
}

enum AnswerSource: String, Codable, Equatable {
    /// Note buttons clicked; keyboard shortcuts (letters, 1–7) for them; typed names; piano keys.
    case click, shortcut, typing, piano
}

enum KeystrokeResult: String, Codable, Equatable {
    /// Kept as part of a name; refused (the box shook); Backspace; Return or a completed name
    /// submitting; ♯/♭ armed or disarmed on the note buttons; pressed but not part of answering.
    case typed, rejected, deleted, submitted, armed, other
}

enum RoundEndReason: String, Codable, Equatable {
    /// A timed round's clock ran out (or, until 2026-11-07, a sprint's); Stop/Esc; the last note of
    /// a piece; the last of a round's set number of notes; replaced by opening or closing a piece or
    /// starting over; the app quit mid-round; the round couldn't be brought back after a crash
    /// (ended at a later launch, with `RoundEnded.recordedAt`).
    case timeUp, stopped, pieceComplete, notesDone, abandoned, appQuit, interrupted
}

enum PieceOpenSource: String, Codable, Equatable {
    /// File ▸ Open Piece…, the start panel's button, a dropped file, the piece panel's Open
    /// another…, reopening last session's piece at launch, picking one from the piece library, or
    /// reopening the piece a journal last had open when the app switches to it.
    case menu, button, drop, openAnother, launch, library, journalSwitch
}

// MARK: - Envelope

/// An event as stored: when and in which app session it happened, plus the event itself.
struct LoggedEvent: Codable, Equatable {
    static let schemaVersion = 1

    let schema: Int
    let id: UUID
    let time: Date
    /// One per app launch.
    let session: UUID
    /// Order within the session, from 0.
    let sequence: Int
    let event: UsageEvent

    init(_ event: UsageEvent, session: UUID, sequence: Int, time: Date = Date()) {
        schema = Self.schemaVersion
        id = UUID()
        self.time = time
        self.session = session
        self.sequence = sequence
        self.event = event
    }

    private enum CodingKeys: String, CodingKey {
        case schema, type, id, time, session, sequence
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(event.type, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(time, forKey: .time)
        try container.encode(session, forKey: .session)
        try container.encode(sequence, forKey: .sequence)
        try event.payload.encode(to: encoder)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Int.self, forKey: .schema)
        id = try container.decode(UUID.self, forKey: .id)
        time = try container.decode(Date.self, forKey: .time)
        session = try container.decode(UUID.self, forKey: .session)
        sequence = try container.decode(Int.self, forKey: .sequence)
        event = try UsageEvent(type: try container.decode(String.self, forKey: .type), from: decoder)
    }

    /// The event as one usage-log line: its JSON and a line feed, exactly as the log writes it.
    func encodedLine() throws -> Data {
        var line = try Self.encoder.encode(self)
        line.append(0x0A)
        return line
    }

    /// The one encoder for log lines: ISO 8601 times with milliseconds, keys sorted.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestampStyle.format(date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            do {
                return try timestampStyle.parse(text)
            } catch {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad time \(text)"))
            }
        }
        return decoder
    }()

    /// UTC with milliseconds, "2026-10-30T17:02:11.348Z". The format style is much faster to parse
    /// than `ISO8601DateFormatter`, which matters when reading years of log.
    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}

extension UsageEvent {
    /// The "type" written to the log: the case name.
    var type: String {
        switch self {
        case .appLaunched: "appLaunched"
        case .appTerminated: "appTerminated"
        case .appActivity: "appActivity"
        case .windowResized: "windowResized"
        case .settingChanged: "settingChanged"
        case .roundStarted: "roundStarted"
        case .questionShown: "questionShown"
        case .answerGiven: "answerGiven"
        case .inputIgnored: "inputIgnored"
        case .roundPaused: "roundPaused"
        case .roundResumed: "roundResumed"
        case .roundRestored: "roundRestored"
        case .roundEnded: "roundEnded"
        case .pieceOpened: "pieceOpened"
        case .pieceOpenFailed: "pieceOpenFailed"
        case .pieceClosed: "pieceClosed"
        case .pieceAdded: "pieceAdded"
        case .pieceRevised: "pieceRevised"
        case .pieceRemoved: "pieceRemoved"
        case .uiAction: "uiAction"
        case .statsSnapshot: "statsSnapshot"
        }
    }

    var payload: any Encodable {
        switch self {
        case .appLaunched(let payload): payload
        case .appTerminated(let payload): payload
        case .appActivity(let payload): payload
        case .windowResized(let payload): payload
        case .settingChanged(let payload): payload
        case .roundStarted(let payload): payload
        case .questionShown(let payload): payload
        case .answerGiven(let payload): payload
        case .inputIgnored(let payload): payload
        case .roundPaused(let payload): payload
        case .roundResumed(let payload): payload
        case .roundRestored(let payload): payload
        case .roundEnded(let payload): payload
        case .pieceOpened(let payload): payload
        case .pieceOpenFailed(let payload): payload
        case .pieceClosed(let payload): payload
        case .pieceAdded(let payload): payload
        case .pieceRevised(let payload): payload
        case .pieceRemoved(let payload): payload
        case .uiAction(let payload): payload
        case .statsSnapshot(let payload): payload
        }
    }

    init(type: String, from decoder: Decoder) throws {
        switch type {
        case "appLaunched": self = .appLaunched(try AppLaunched(from: decoder))
        case "appTerminated": self = .appTerminated(try AppTerminated(from: decoder))
        case "appActivity": self = .appActivity(try AppActivity(from: decoder))
        case "windowResized": self = .windowResized(try WindowResized(from: decoder))
        case "settingChanged": self = .settingChanged(try SettingChanged(from: decoder))
        case "roundStarted": self = .roundStarted(try RoundStarted(from: decoder))
        case "questionShown": self = .questionShown(try QuestionShown(from: decoder))
        case "answerGiven": self = .answerGiven(try AnswerGiven(from: decoder))
        case "inputIgnored": self = .inputIgnored(try InputIgnored(from: decoder))
        case "roundPaused": self = .roundPaused(try RoundPaused(from: decoder))
        case "roundResumed": self = .roundResumed(try RoundResumed(from: decoder))
        case "roundRestored": self = .roundRestored(try RoundRestored(from: decoder))
        case "roundEnded": self = .roundEnded(try RoundEnded(from: decoder))
        case "pieceOpened": self = .pieceOpened(try PieceOpened(from: decoder))
        case "pieceOpenFailed": self = .pieceOpenFailed(try PieceOpenFailed(from: decoder))
        case "pieceClosed": self = .pieceClosed(try PieceClosed(from: decoder))
        case "pieceAdded": self = .pieceAdded(try PieceAdded(from: decoder))
        case "pieceRevised": self = .pieceRevised(try PieceRevised(from: decoder))
        case "pieceRemoved": self = .pieceRemoved(try PieceRemoved(from: decoder))
        case "uiAction": self = .uiAction(try UIAction(from: decoder))
        case "statsSnapshot": self = .statsSnapshot(try StatsSnapshot(from: decoder))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown event type \(type)"))
        }
    }
}

// MARK: - Helpers

/// Any JSON value, for logging settings without tying old log lines to today's Swift types.
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// `value` as it encodes to JSON (e.g. the saved settings).
    init<T: Encodable>(encoding value: T) {
        guard let data = try? JSONEncoder().encode(value),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            self = .null
            return
        }
        self = decoded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// Keeps events in memory: for tests, and anywhere a log on disk isn't wanted.
final class MemoryUsageRecorder: UsageRecorder {
    private(set) var events: [LoggedEvent] = []
    let session = UUID()

    func record(_ event: UsageEvent) {
        record(event, at: Date())
    }

    func record(_ event: UsageEvent, at time: Date) {
        events.append(LoggedEvent(event, session: session, sequence: events.count, time: time))
    }
}
