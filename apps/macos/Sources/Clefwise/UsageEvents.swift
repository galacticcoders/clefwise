import Foundation

// The usage log: everything that happens in the app, kept so progress can be analysed later.
// Each event is one JSON object per line, its payload flattened next to the envelope fields:
//   {"schema":1,"type":"answerGiven","id":"…","time":"2026-10-30T17:02:11.348Z","session":"…",
//    "sequence":42,"round":"…","question":"…","correct":true,"responseMs":1820,…}
// Payload fields must not reuse the envelope names (schema, type, id, time, session, sequence).
// Add fields freely; bump `LoggedEvent.schemaVersion` only when a field changes meaning.

/// Where events go. The app writes them to disk (`UsageLog`); tests keep them in memory.
protocol UsageRecorder: AnyObject {
    func record(_ event: UsageEvent)
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
    case roundEnded(RoundEnded)
    case pieceOpened(PieceOpened)
    case pieceOpenFailed(PieceOpenFailed)
    case pieceClosed(PieceClosed)
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
}

struct PieceContext: Codable, Equatable {
    var title: String
    var path: String
    var part: String
    var partIndex: Int
    var hand: String
    var order: String
    var startBar: Int
    var oneNotePerChord: Bool
    /// Notes this round asks, and bars in the part.
    var noteCount: Int
    var measureCount: Int
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
}

struct Keystroke: Codable, Equatable {
    /// The character typed, a key name ("Return", "Delete"…), or "click ♯" / "click ♭" for the
    /// note buttons' sign buttons.
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
    /// How long this pause lasted.
    var pausedMs: Int
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
    var bestScore: Int?
    var isNewBest: Bool
    var notesToReview: [String]
    /// The question still on screen when the round ended (time up, stopped, quit…), if any.
    var unansweredQuestion: UnansweredQuestion? = nil
}

/// A question left without an answer: how long it was up and the keys pressed meanwhile.
struct UnansweredQuestion: Codable, Equatable {
    var question: UUID
    /// How long it was up, pauses left out.
    var shownMs: Int
    var keystrokes: [Keystroke]
    /// How long the round was paused while it was up; nil when it wasn't.
    var pausedMs: Int? = nil
}

struct PieceOpened: Codable, Equatable {
    var path: String
    var title: String
    var via: PieceOpenSource
    var parts: [PartInfo]
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
}

struct PieceClosed: Codable, Equatable {
    var path: String?
}

/// A button or menu item used, for questions like "does anyone press Play again?".
struct UIAction: Codable, Equatable {
    var name: String
    var detail: String?
}

/// The per-note history and best scores kept before the usage log existed, recorded once so the
/// log starts from everything the app knew.
struct StatsSnapshot: Codable, Equatable {
    var reason: String
    var noteStats: [String: NoteStat]
    var bestScores: [String: Int]
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
    /// Sprint clock ran out; Stop/Esc; the last note of a piece; replaced by opening or closing a
    /// piece or starting over; the app quit mid-round.
    case timeUp, stopped, pieceComplete, abandoned, appQuit
}

enum PieceOpenSource: String, Codable, Equatable {
    case menu, button, drop, openAnother, launch
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
        case .roundEnded: "roundEnded"
        case .pieceOpened: "pieceOpened"
        case .pieceOpenFailed: "pieceOpenFailed"
        case .pieceClosed: "pieceClosed"
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
        case .roundEnded(let payload): payload
        case .pieceOpened(let payload): payload
        case .pieceOpenFailed(let payload): payload
        case .pieceClosed(let payload): payload
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
        case "roundEnded": self = .roundEnded(try RoundEnded(from: decoder))
        case "pieceOpened": self = .pieceOpened(try PieceOpened(from: decoder))
        case "pieceOpenFailed": self = .pieceOpenFailed(try PieceOpenFailed(from: decoder))
        case "pieceClosed": self = .pieceClosed(try PieceClosed(from: decoder))
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
        events.append(LoggedEvent(event, session: session, sequence: events.count))
    }
}
