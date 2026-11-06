import Foundation
import Observation

/// Per-note history used to bring up notes you struggle with more often.
struct NoteStat: Codable, Equatable {
    var attempts = 0
    var correct = 0
    /// Most recent results, oldest first.
    var recent: [Bool] = []

    mutating func record(_ wasCorrect: Bool) {
        attempts += 1
        if wasCorrect { correct += 1 }
        recent.append(wasCorrect)
        if recent.count > 8 { recent.removeFirst(recent.count - 8) }
    }

    /// Smoothed error rate over recent attempts; a note you've never seen counts as 50%.
    var recentErrorRate: Double {
        Double(recent.filter { !$0 }.count + 1) / Double(recent.count + 2)
    }
}

struct StaffNote: Hashable {
    let clef: Clef
    let pitch: Pitch
}

struct RoundSummary {
    let mode: Game.Mode
    let score: Int
    let attempts: Int
    let bestStreak: Int
    let averageSeconds: Double?
    let bestScore: Int?
    let isNewBest: Bool
    let timeRanOut: Bool
    let notesToReview: [StaffNote]
    /// Whether the round mixed clefs, so review notes need their clef spelled out.
    let mixedClefs: Bool
    /// Set for rounds on a loaded piece.
    let pieceTitle: String?
    /// The round ended because the piece (from the start bar) was played through.
    let finishedPiece: Bool
    /// The round was a practice round with a limit, reached or not.
    var hadLimit = false
    /// The round ended on the last of its set number of notes.
    var finishedNotes = false
    /// How long a round of a set number of notes took, pauses left out; nil for other rounds.
    var noteRoundSeconds: TimeInterval? = nil

    var accuracy: Double? { attempts > 0 ? Double(score) / Double(attempts) : nil }
}

@MainActor
@Observable
final class Game {
    enum Mode: String, CaseIterable, Identifiable, Codable {
        case sprint, practice

        var id: Self { self }
        var label: String { self == .sprint ? "60s Sprint" : "Practice" }
    }

    /// How a practice round of random notes ends. A sprint has its own clock, and a piece ends with
    /// its last note, so neither takes a limit.
    enum PracticeLimit: String, CaseIterable, Identifiable, Codable {
        /// Only when stopped.
        case endless
        /// When `Settings.practiceMinutes` are up.
        case time
        /// Once `Settings.practiceNotes` notes are answered, right or wrong.
        case notes

        var id: Self { self }
        var label: String {
            switch self {
            case .endless: "No limit"
            case .time: "Time"
            case .notes: "Notes"
            }
        }
    }

    /// The lengths to choose from. Fixed rather than typed, so that two rounds of one length can be
    /// compared fairly.
    static let practiceMinuteChoices = [2, 5, 10, 15, 30]
    static let practiceNoteChoices = [50, 100, 250, 500, 1000]

    enum AnswerInput: String, CaseIterable, Identifiable, Codable {
        case buttons, piano, keyboard

        var id: Self { self }
        var label: String {
            switch self {
            case .buttons: "Note buttons"
            case .piano: "Piano"
            case .keyboard: "Keyboard"
            }
        }
        var symbol: String {
            switch self {
            case .buttons: "rectangle.split.3x1"
            case .piano: "pianokeys"
            case .keyboard: "keyboard"
            }
        }
    }

    enum Phase { case idle, playing, finished }

    /// Brief highlight on the answer that was just given.
    struct Flash: Equatable {
        let letter: NoteLetter
        let accidental: Accidental
        /// The exact key, when answered on the piano. Compare keys by `midiNumber`: a black key
        /// may be spelled C♯ on the piano and D♭ in the question.
        let pitch: Pitch?
        let isCorrect: Bool
        let id = UUID()
    }

    struct Settings: Codable {
        var clefChoice = ClefChoice.treble
        var range = NoteRange.staff
        var mode = Mode.sprint
        var practiceLimit = PracticeLimit.endless
        /// Each kind of limit keeps its own length, so switching between them loses neither.
        var practiceMinutes = 5
        var practiceNotes = 100
        var naming = NamingSystem.letters
        var answerInput = AnswerInput.buttons
        var showHints = false
        /// Write note names on the piano keys.
        var showKeyNames = false
        var isMuted = false
        var key = KeyChoice.fixed(.cMajor)
        /// Now and then print a ♯, ♭ or ♮ in front of a note, on top of the key signature.
        var addsAccidentals = false
        /// How the open piece is practised. Each piece in the library keeps its own copy, which
        /// comes back when it's opened again; with no piece open, the last piece's.
        var piece = PieceSettings()
        /// Where the open piece was first opened from (its library entry's `originalPath`), the
        /// path the log knows it by. Versions before the library reopened it at launch; this one
        /// does when `pieceID` isn't set.
        var piecePath: String?
        /// Light or dark, or as macOS is set (View ▸ Appearance).
        var appearance = Appearance.system
        /// The library entry of the open piece, reopened at launch from its copy.
        var pieceID: UUID?

        init() {}

        /// Missing keys fall back to defaults, so settings saved by older versions still load.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            clefChoice = try container.decodeIfPresent(ClefChoice.self, forKey: .clefChoice) ?? clefChoice
            range = try container.decodeIfPresent(NoteRange.self, forKey: .range) ?? range
            mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? mode
            practiceLimit = try container.decodeIfPresent(PracticeLimit.self, forKey: .practiceLimit) ?? practiceLimit
            practiceMinutes = try container.decodeIfPresent(Int.self, forKey: .practiceMinutes) ?? practiceMinutes
            practiceNotes = try container.decodeIfPresent(Int.self, forKey: .practiceNotes) ?? practiceNotes
            naming = try container.decodeIfPresent(NamingSystem.self, forKey: .naming) ?? naming
            answerInput = try container.decodeIfPresent(AnswerInput.self, forKey: .answerInput) ?? answerInput
            showHints = try container.decodeIfPresent(Bool.self, forKey: .showHints) ?? showHints
            showKeyNames = try container.decodeIfPresent(Bool.self, forKey: .showKeyNames) ?? showKeyNames
            isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? isMuted
            key = try container.decodeIfPresent(KeyChoice.self, forKey: .key) ?? key
            addsAccidentals = try container.decodeIfPresent(Bool.self, forKey: .addsAccidentals) ?? addsAccidentals
            piece = try container.decodeIfPresent(PieceSettings.self, forKey: .piece) ?? piece
            piecePath = try container.decodeIfPresent(String.self, forKey: .piecePath) ?? piecePath
            appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? appearance
            // An id that doesn't read only loses the piece to reopen, not every setting.
            pieceID = (try? container.decodeIfPresent(UUID.self, forKey: .pieceID)) ?? nil
        }
    }

    /// How a loaded piece is practised.
    struct PieceSettings: Codable, Equatable {
        enum Hand: String, CaseIterable, Identifiable, Codable {
            case right, left, both

            var id: Self { self }
            var label: String {
                switch self {
                case .right: "Right hand"
                case .left: "Left hand"
                case .both: "Both hands"
                }
            }
        }

        enum Order: String, CaseIterable, Identifiable, Codable {
            case inOrder, shuffled

            var id: Self { self }
            var label: String { self == .inOrder ? "In order" : "Shuffled" }
        }

        /// How the notes of a chord, and notes struck together, are asked.
        enum Chords: String, CaseIterable, Identifiable, Codable {
            /// Each note on its own, in reading order: lower staff first, then low to high.
            case eachNote
            /// Only the top note of right-hand chords and the bottom note of left-hand ones.
            case topOrBottom
            /// Every note struck at one moment, on the staves read, named as one answer in the bar view.
            case together

            var id: Self { self }
            var label: String {
                switch self {
                case .eachNote: "Note by note"
                case .topOrBottom: "Top / bottom note"
                case .together: "All together"
                }
            }
        }

        /// Index into the score's parts.
        var part = 0
        /// Right hand = upper staff, left hand = lower; ignored for single-staff parts.
        var hand = Hand.right
        var order = Order.inOrder
        /// Bar to start from (1-based), so a long piece can be practised a section at a time.
        var startBar = 1
        var chords = Chords.eachNote
        /// Draw the whole bar the note is in, as the score has it, rather than the note on its own.
        /// Naming chords together always draws it, whatever this says (see `usesWholeBar`).
        var showsWholeBar = true

        /// The old "One note per chord" checkbox, now `chords == .topOrBottom`. Switching it off
        /// goes back to note by note only from `topOrBottom`.
        var oneNotePerChord: Bool {
            get { chords == .topOrBottom }
            set {
                if newValue {
                    chords = .topOrBottom
                } else if chords == .topOrBottom {
                    chords = .eachNote
                }
            }
        }

        /// Rounds use the whole-bar view: when it's switched on, and always when chords are named
        /// together, which needs it.
        var usesWholeBar: Bool { showsWholeBar || chords == .together }

        init() {}

        /// Missing keys fall back to defaults, like `Settings`. Settings saved before `chords`
        /// existed have `oneNotePerChord` instead: on means `topOrBottom`.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            part = try container.decodeIfPresent(Int.self, forKey: .part) ?? part
            hand = try container.decodeIfPresent(Hand.self, forKey: .hand) ?? hand
            order = try container.decodeIfPresent(Order.self, forKey: .order) ?? order
            startBar = try container.decodeIfPresent(Int.self, forKey: .startBar) ?? startBar
            // A choice this version doesn't know (from a later one) falls back rather than losing every setting.
            if let chords = (try? container.decodeIfPresent(Chords.self, forKey: .chords)) ?? nil {
                self.chords = chords
            } else if try decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(Bool.self, forKey: .oneNotePerChord) == true {
                chords = .topOrBottom
            }
            showsWholeBar = try container.decodeIfPresent(Bool.self, forKey: .showsWholeBar) ?? showsWholeBar
        }

        private enum LegacyKeys: String, CodingKey {
            case oneNotePerChord
        }
    }

    /// Where a piece round in the bar view is, bar by bar, for the strip along the staff card.
    struct BarStrip: Equatable {
        /// The bars the round goes through, first to last.
        let bars: ClosedRange<Int>
        /// Bar of the note being asked.
        let current: Int
        /// The part's last bar, as in "Bar 9 of 32".
        let pieceBars: Int
        /// In order, the bars before `current` are done (on this pass); shuffled rounds jump about,
        /// so only the current bar is marked.
        let showsDone: Bool
    }

    /// Where a piece round is up to.
    struct PieceProgress: Equatable {
        /// Bar of the current note, and the piece's last bar.
        let bar: Int
        let bars: Int
        /// Notes answered so far this round, and how many the round has.
        let done: Int
        let total: Int
    }

    /// Notes asked together as one question, in "All together" piece rounds when two or more
    /// notes start at the same moment, and the answer being put together for them.
    ///
    /// The answer is one entry per note, in any order: a note name (note buttons, typing), which
    /// counts in any octave, or a piano key, which must be exact. Once there are
    /// `entriesNeeded(on:)` entries they're judged: matched to the notes so that the most notes
    /// are right, each note right or wrong on its own.
    struct NoteGroup: Equatable {
        /// Shared by the notes' `questionShown` and `answerGiven` events.
        let id = UUID()
        /// One per note, in reading order: lower staff first, then low to high. The first is
        /// `Game.question` and the bar view's `current`.
        let questions: [Question]
        /// Entered so far, in order.
        fileprivate(set) var entries: [GroupEntry] = []
        /// How the entries were judged; nil until they are.
        fileprivate(set) var result: GroupResult?

        init(questions: [Question]) {
            self.questions = questions
        }

        /// How many entries make an answer: one name per note, so two Cs an octave apart are named
        /// twice; on the piano one key per note, but notes that sound the same key share it.
        func entriesNeeded(on input: AnswerInput) -> Int {
            input == .piano ? Set(questions.map(\.pitch.midiNumber)).count : questions.count
        }
    }

    /// One entry towards the notes asked together.
    struct GroupEntry: Equatable, Identifiable {
        let id = UUID()
        let letter: NoteLetter
        let accidental: Accidental
        /// The key, for piano entries; nil for names, which count in any octave. The piano calls
        /// black keys sharps: C♯, never D♭.
        let pitch: Pitch?
    }

    /// How the entries for notes asked together were judged.
    struct GroupResult: Equatable {
        /// By question: whether that note was named right.
        let isRight: [Bool]
        /// By question: the index in `entries` of the entry it's judged with: the one matched to
        /// it, or for a note named wrong one of the entries left over, paired in order (notes that
        /// sound the same key share a piano key).
        let entryIndices: [Int]
        /// By entry: whether it named one of the notes.
        let entryIsRight: [Bool]

        var rightCount: Int { isRight.filter { $0 }.count }
        var isAllRight: Bool { !isRight.contains(false) }
    }

    /// A note name without an octave, as typed.
    struct NoteName: Hashable {
        let letter: NoteLetter
        let accidental: Accidental
    }

    static let sprintLength: TimeInterval = 60
    private static let missPause: Duration = .milliseconds(1200)
    private static let correctFlash: Duration = .milliseconds(250)

    var settings: Settings {
        didSet {
            if settings.naming != oldValue.naming { typedText = "" }
            // Between rounds the staff shows the newly chosen key instead of the last round's.
            if settings.key != oldValue.key, phase != .playing { roundKey = nil }
            if settings.piece != oldValue.piece {
                // Keeps the start bar within the piece, e.g. after switching to a shorter part.
                // (The assignment runs didSet again, which then finds nothing to fit.)
                if let piece {
                    let fitted = Self.fitting(settings.piece, to: piece)
                    if fitted != settings.piece { settings.piece = fitted }
                }
                updateSelection()
                // The open piece keeps its own settings, as fitted, for the next time it's opened.
                if let pieceEntryID { library.save(settings: settings.piece, for: pieceEntryID) }
            }
            save(settings, as: Keys.settings)
            recordSettingChanges()
        }
    }

    private(set) var phase = Phase.idle
    private(set) var question: Question?
    /// True while a missed note is shown in red with its name before moving on.
    private(set) var isShowingMiss = false
    /// True while a round is paused: its clock is stopped and answers don't count.
    private(set) var isPaused = false
    /// What paused the round, while it's paused.
    private(set) var pausedVia: PauseSource?
    private(set) var flash: Flash?
    /// While notes struck together are asked as one question (an "All together" piece round),
    /// those notes, the entries so far and, once judged, the result: it stays up through the
    /// pause after a mistake, alongside `isShowingMiss`. Nil while one note is asked at a time,
    /// a lone note in an "All together" round included: that's asked as usual.
    private(set) var group: NoteGroup?
    /// The notes just named together, all of them right, with their result: shown on the answer
    /// pads for a moment like `flash`, while the next question is already up.
    private(set) var groupFlash: NoteGroup?
    /// What's been typed so far towards a note name, in keyboard mode. While a `group` is asked,
    /// names back to back as typed ("sisol", "ebg"; # kept as ♯, b as typed); `typedNames` reads them.
    private(set) var typedText = ""
    /// Bumped when a keystroke can't lead to any note name, so the input box can shake.
    private(set) var rejectedKeystrokes = 0
    /// ♯ or ♭ chosen on the note buttons for the next letter pressed; back to natural after each answer.
    private(set) var armedAccidental = Accidental.natural
    private(set) var score = 0
    private(set) var attempts = 0
    private(set) var streak = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var summary: RoundSummary?
    private var bestScores: [String: Int]
    /// Key signature every question of the round is written in, picked at `start()`. Kept after
    /// the round so the staff still shows it, until the key setting changes.
    private var roundKey: KeySignature?
    /// The piece being practised; nil means random notes from the toolbar settings.
    private(set) var piece: Score?
    /// Where the piece was first opened from: for one opened from the library, its original file,
    /// which may have moved or gone since (the piece itself is read from the library's copy).
    private(set) var pieceURL: URL?
    /// The piece's entry in `library`; nil without a piece, and for one that couldn't be kept there.
    private(set) var pieceEntryID: UUID?
    /// Why the last file couldn't be opened, or a piece round couldn't start, for the UI to show (and clear).
    var pieceError: String?
    /// The notes of the loaded piece the next round asks, kept up to date with the piece settings.
    private var selectedNotes: [ScoreNote] = []
    /// The bar view's layout for `selectedNotes`, worked out with them; nil without a bar layout.
    private var selectedBarLayout: BarLayout?
    /// How many notes the next piece round asks with the current hand, start bar and chord settings.
    var pieceRoundNoteCount: Int { selectedNotes.count }
    /// The round in progress when it's on a piece; nil between rounds and in random rounds.
    private var pieceRound: PieceRound?

    /// A round on a piece, fixed at `start()`: later changes to the piece settings wait for the next one.
    private struct PieceRound {
        let title: String
        /// The part the notes come from, kept so the round never mixes up parts.
        let part: ScorePart
        let notes: [ScoreNote]
        let bars: Int
        let order: PieceSettings.Order
        /// The bar view's layout for `notes`; nil when the round shows one note at a time (the
        /// setting is off, or the part has no bar layout).
        let barLayout: BarLayout?
        /// The round names the notes struck at one moment together ("All together").
        let namesTogether: Bool
        /// The questions, in reading order, as runs of `notes`: one note each, except that when
        /// notes are named together each run is the notes that start at the same moment (only
        /// where the bar view can draw their bar; elsewhere they're asked one at a time).
        let groups: [Range<Int>]
        /// By group: what shuffled rounds tell questions apart by, its notes as stats count them
        /// (clef and pitch), so a chord counts as itself whichever voice has which note.
        let groupKeys: [String]
        /// Shuffled rounds draw a question (by its key: a note, or the notes of a chord), then one of
        /// its places, so one the piece repeats often isn't asked any more often for it.
        let places: [(key: String, statKeys: [String], groups: [Int])]
        /// Index in `groups` of the question being asked.
        var groupIndex = 0

        init(title: String, part: ScorePart, notes: [ScoreNote], order: PieceSettings.Order, barLayout: BarLayout?,
             namesTogether: Bool = false) {
            self.title = title
            self.part = part
            self.notes = notes
            bars = part.measureCount
            self.order = order
            self.barLayout = barLayout
            self.namesTogether = namesTogether
            let groups = namesTogether ? Self.groups(of: notes, in: part, layout: barLayout) : notes.indices.map { $0..<($0 + 1) }
            self.groups = groups
            let statKeys = groups.map { notes[$0].map { Game.statKey($0.clef, $0.pitch) } }
            let keys = statKeys.map { $0.sorted().joined(separator: " ") }
            groupKeys = keys
            guard order == .shuffled else {
                places = []
                return
            }
            places = Dictionary(grouping: groups.indices) { keys[$0] }
                .map { ($0.key, statKeys[$0.value[0]], $0.value) }
        }

        /// Runs of `notes` (in reading order) that start at the same moment in one bar, each to be
        /// asked as one question. Runs whose bar the bar view can't draw are split into single notes.
        private static func groups(of notes: [ScoreNote], in part: ScorePart, layout: BarLayout?) -> [Range<Int>] {
            var groups: [Range<Int>] = []
            var start = 0
            while start < notes.count {
                var end = start + 1
                while end < notes.count, notes[end].measure == notes[start].measure,
                      abs(notes[end].onset - notes[start].onset) < 1e-6 {
                    end += 1
                }
                let drawn = layout.flatMap { Game.barDisplay(for: notes[start], in: part, layout: $0, isAsked: true, answered: []) } != nil
                    && notes[start..<end].allSatisfy { part.symbol(for: $0) != nil }
                if drawn {
                    groups.append(start..<end)
                } else {
                    groups += (start..<end).map { $0..<($0 + 1) }
                }
                start = end
            }
            return groups
        }

        /// Index in `notes` of the note being asked: the first of its group.
        var index: Int { groups[groupIndex].lowerBound }
        /// The note being asked: the first of the notes asked together.
        var note: ScoreNote { notes[index] }
        /// The notes asked together now, in reading order; one note when they're asked one at a time.
        var groupNotes: ArraySlice<ScoreNote> { notes[groups[groupIndex]] }

        /// The bar the note being asked is in, as the bar view draws it, with the other notes asked
        /// with it as `together`; nil when it's shown on its own.
        var barDisplay: BarDisplay? {
            guard let barLayout else { return nil }
            let note = note
            // In order, the notes before this one in its bar on this pass: they come just before it.
            var answered = Set<Int>()
            if order == .inOrder {
                for earlier in notes[..<index].reversed() {
                    guard earlier.measure == note.measure else { break }
                    if let symbol = earlier.symbolIndex { answered.insert(symbol) }
                }
            }
            var display = Game.barDisplay(for: note, in: part, layout: barLayout, isAsked: true, answered: answered)
            display?.together = Set(groupNotes.dropFirst().compactMap { $0.measure == note.measure ? $0.symbolIndex : nil })
            return display
        }
    }

    /// What the bar view needs that takes a scan through the piece, worked out once per selection
    /// (and so once per round) rather than for every note.
    private struct BarLayout: Equatable {
        /// The bars the notes are in, first to last.
        let bars: ClosedRange<Int>
        /// The notes are on both staves of a grand staff, so both are drawn.
        let isGrandStaff: Bool
        /// By staff number: lowest to highest position of the notes drawn on it in `bars`, and at
        /// least the staff itself (0…8).
        let positions: [Int: ClosedRange<Int>]
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var noteStats: [String: NoteStat]
    @ObservationIgnored private var bestStreak = 0
    @ObservationIgnored private var roundMisses: [StaffNote: Int] = [:]
    @ObservationIgnored private var responseTimes: [TimeInterval] = []
    /// Monotonic, so round and answer times don't jump when the Mac's clock is set.
    @ObservationIgnored private var roundStart = ContinuousClock.now
    @ObservationIgnored private var questionStart = ContinuousClock.now
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pendingAdvance: Task<Void, Never>?
    /// When the pause in progress began; nil when the round isn't paused.
    @ObservationIgnored private var pausedAt: ContinuousClock.Instant?
    /// Time paused so far this round, and while the question on screen was up.
    @ObservationIgnored private var roundPaused = Duration.zero
    @ObservationIgnored private var questionPaused = Duration.zero
    /// The pause after a miss ran out during a pause: the next note comes when the round resumes.
    @ObservationIgnored private(set) var advancesOnResume = false
    /// The round came back after a crash with a question on screen: it's asked again, as a new
    /// question, when the round resumes.
    @ObservationIgnored private var asksAgainOnResume = false
    @ObservationIgnored private let synth = Synth()
    /// Where usage events go (the usage log on disk in the app; memory in tests).
    @ObservationIgnored let recorder: UsageRecorder
    /// The pieces opened before, kept to practise again (the app's own folder; tests pass a
    /// throwaway one).
    let library: PieceLibrary
    /// The saved settings as last logged, to tell which ones a change touched.
    @ObservationIgnored private var settingsAsLogged = JSONValue.null
    /// The round being logged, from `roundStarted` to `roundEnded`.
    @ObservationIgnored private var roundLog: RoundLog?
    /// The question on screen, from `questionShown` until it's answered.
    @ObservationIgnored private var questionLog: QuestionLog?

    /// `defaults` is where settings, note stats and best scores are kept, `recorder` where usage
    /// events go, `library` where opened pieces are kept; tests pass their own. The library has no
    /// default, so nothing can reach the real one by accident.
    init(defaults: UserDefaults = .standard, recorder: UsageRecorder = UsageLog.shared, library: PieceLibrary) {
        self.defaults = defaults
        self.recorder = recorder
        self.library = library
        settings = Self.load(Settings.self, from: Keys.settings, in: defaults) ?? Settings()
        noteStats = Self.load([String: NoteStat].self, from: Keys.noteStats, in: defaults) ?? [:]
        bestScores = Self.load([String: Int].self, from: Keys.bestScores, in: defaults) ?? [:]
        settingsAsLogged = JSONValue(encoding: settings)
        recordStatsSnapshotOnce()
        reopenLastPiece()
    }

    /// The clef on screen: the current question's, or between rounds the first selected clef
    /// (with a piece, the clef of the note the next round starts on).
    var displayedClef: Clef { question?.clef ?? leadingPieceNote?.clef ?? settings.clefChoice.clefs[0] }
    var timeRemaining: TimeInterval { max(0, (roundTimeLimit ?? 0) - elapsed) }

    /// The limit on a round started now: only practice rounds of random notes take one.
    private var practiceRoundLimit: PracticeLimit {
        settings.mode == .practice && !isPractisingPiece ? settings.practiceLimit : .endless
    }

    /// How long a round may run; nil when its clock only counts up.
    var roundTimeLimit: TimeInterval? {
        if settings.mode == .sprint { return Self.sprintLength }
        return practiceRoundLimit == .time ? TimeInterval(settings.practiceMinutes * 60) : nil
    }

    /// How many notes a round asks; nil when it isn't a set number.
    var roundNoteLimit: Int? { practiceRoundLimit == .notes ? settings.practiceNotes : nil }

    /// Notes still to answer in a round of a set number, while it runs.
    var notesLeft: Int? {
        guard phase == .playing, let limit = roundNoteLimit else { return nil }
        return max(0, limit - attempts)
    }
    var accuracy: Double? { attempts > 0 ? Double(score) / Double(attempts) : nil }
    /// Pieces don't keep best scores: a score on one piece says little about another.
    var bestScore: Int? { isPractisingPiece ? nil : bestScores[bestScoreKey] }
    /// The current settings' best-score key.
    private var bestScoreKey: String { Self.bestScoreKey(for: settings) }

    /// The key `settings` keep their best sprint score under. Each answer method plays differently
    /// (the piano needs the octave, typing takes keystrokes), and so do key signatures and printed
    /// accidentals, so each setup keeps its own best scores. Plain C major adds nothing, so scores
    /// saved before keys existed still count.
    nonisolated static func bestScoreKey(for settings: Settings) -> String {
        var key = "\(settings.clefChoice.rawValue).\(settings.range.key)"
            + (settings.answerInput == .buttons ? "" : ".\(settings.answerInput.rawValue)")
        switch settings.key {
        case .fixed(let signature) where signature != .cMajor: key += ".key\(signature.fifths)"
        case .fixed: break
        case .random: key += ".keyRandom"
        }
        if settings.addsAccidentals { key += ".acc" }
        return key
    }

    /// Key signature on the staff: the current or last round's, or the chosen one before any
    /// round (C major when the choice is random). With a piece, the key the next round starts in.
    var currentKeySignature: KeySignature {
        if let question { return question.keySignature }
        if let leadingPieceNote { return leadingPieceNote.keySignature }
        if let roundKey { return roundKey }
        if case .fixed(let key) = settings.key { return key }
        return .cMajor
    }

    /// Whether questions can be sharp or flat, so the answer inputs need a way to say so.
    /// A piece goes by its notes (a G major piece needs ♯), not the toolbar's key and accidentals.
    var accidentalsPossible: Bool {
        if isPractisingPiece { return pieceNotes.contains { $0.pitch.accidental != .natural } }
        return settings.addsAccidentals || settings.key != .fixed(.cMajor)
    }

    /// In keyboard mode, while notes are asked together: the typed text reads as all their names,
    /// but something longer still could, so it waits for Return. One note never asks for Return:
    /// the only name that waits is the right letter without its sign, where Return would answer it
    /// as typed (a miss), so the cue would mislead (see `type(_:)`).
    var typingNeedsReturn: Bool { typedNames?.needsReturn ?? false }

    /// How `typedText` reads while notes are asked together (`group`), for the typing box; nil
    /// while one note is asked at a time.
    var typedNames: TypedNames? {
        guard let group else { return nil }
        return TypedNames(typedText, count: group.questions.count, answers: typeableAnswers)
    }

    /// The round asks the notes struck at one moment as one answer ("All together"), or between
    /// rounds the next one will: the answer pads keep room for the entries.
    var namesTogether: Bool {
        if let pieceRound { return pieceRound.namesTogether }
        return phase != .playing && isPractisingPiece && settings.piece.chords == .together
    }

    /// How many entries make an answer to the notes asked together with the answer input in use;
    /// nil while one note is asked at a time.
    var groupEntriesNeeded: Int? {
        group?.entriesNeeded(on: settings.answerInput)
    }

    var isPractisingPiece: Bool { piece != nil }

    /// The chosen part of the loaded piece.
    var piecePart: ScorePart? {
        guard let piece, !piece.parts.isEmpty else { return nil }
        return piece.parts[min(max(settings.piece.part, 0), piece.parts.count - 1)]
    }

    /// Where a piece round is up to; nil outside piece rounds. In order, `done` counts the notes
    /// before the current one in this pass (a sprint starts again from 0 when it wraps); shuffled,
    /// it counts answers, so it can pass `total`.
    var pieceProgress: PieceProgress? {
        guard phase == .playing, let pieceRound else { return nil }
        return PieceProgress(bar: pieceRound.note.measure, bars: pieceRound.bars,
                             done: pieceRound.order == .inOrder ? pieceRound.index : attempts,
                             total: pieceRound.notes.count)
    }

    /// What the staff card draws in the whole-bar view: during a piece round the bar of the note
    /// being asked (with the notes asked together with it, and after they're judged wrong their
    /// marks), between rounds the bar the next one starts in. Nil shows one note at a time: for
    /// random notes, with the setting off (as it was when the round started) unless chords are
    /// named together, when the part has no bar layout, or when a staff to draw has a clef that
    /// can't be drawn there.
    var barDisplay: BarDisplay? {
        if let pieceRound {
            guard var display = pieceRound.barDisplay else { return nil }
            // Every note of a judged group is marked, right ones too.
            if let group, let result = group.result {
                for (offset, note) in pieceRound.groupNotes.enumerated() where offset < group.questions.count {
                    guard note.measure == display.measure.number, let symbol = note.symbolIndex else { continue }
                    display.marks[symbol] = result.isRight[offset] ? .right
                        : .wrong(name: missLabel(for: group.questions[offset].pitch,
                                                 answeredWith: group.entries[result.entryIndices[offset]].pitch))
                }
            }
            return display
        }
        guard piece != nil, settings.piece.usesWholeBar, let part = piecePart, let selectedBarLayout,
              let first = selectedNotes.first else { return nil }
        return Self.barDisplay(for: first, in: part, layout: selectedBarLayout, isAsked: false, answered: [])
    }

    /// What a missed note is labelled with on the staff: its name in the naming system in use
    /// ("Fa♯", "Middle Do" for C4), and when it was answered with a piano `key` of the right name
    /// in another octave, "· wrong octave". The same for one note and for notes asked together.
    func missLabel(for pitch: Pitch, answeredWith key: Pitch?) -> String {
        let name = settings.naming.name(of: pitch)
        let label = pitch == Pitch(.c, 4) ? "Middle \(name)" : name
        if let key, key.pitchClass == pitch.pitchClass, key.midiNumber != pitch.midiNumber {
            return "\(label) · wrong octave"
        }
        return label
    }

    /// Where a piece round in the bar view is, bar by bar; nil outside one.
    var barStrip: BarStrip? {
        guard phase == .playing, let pieceRound, let layout = pieceRound.barLayout else { return nil }
        return BarStrip(bars: layout.bars, current: pieceRound.note.measure, pieceBars: pieceRound.bars,
                        showsDone: pieceRound.order == .inOrder)
    }

    /// `note`'s bar on its staff, or on both staves of a grand staff; nil when it has no bar or
    /// a staff to draw has no clef the bar view can draw. `isAsked`: `note` is being asked now.
    nonisolated private static func barDisplay(for note: ScoreNote, in part: ScorePart, layout: BarLayout,
                                               isAsked: Bool, answered: Set<Int>) -> BarDisplay? {
        guard let symbol = part.symbol(for: note) else { return nil }
        let measure = symbol.measure
        let numbers = layout.isGrandStaff && (1...2).contains(note.staff) ? [1, 2] : [note.staff]
        var staves: [BarDisplay.Staff] = []
        for number in numbers {
            guard measure.staves.indices.contains(number - 1), let clef = measure.staves[number - 1].clef else { return nil }
            staves.append(BarDisplay.Staff(number: number, clef: clef, keySignature: measure.staves[number - 1].keySignature,
                                           positions: layout.positions[number] ?? 0...8))
        }
        return BarDisplay(staves: staves, measure: measure, current: isAsked ? symbol.index : nil,
                          answered: answered.filter(measure.symbols.indices.contains),
                          isLastBar: measure.number == part.measureCount)
    }

    /// The bar view's layout for `notes` of `part`; nil when the part has no bar layout for them.
    private static func barLayout(of notes: [ScoreNote], in part: ScorePart) -> BarLayout? {
        guard let first = notes.map(\.measure).min(), let last = notes.map(\.measure).max(),
              first >= 1, first <= part.measures.count else { return nil }
        let staves = Set(notes.map(\.staff))
        var positions: [Int: ClosedRange<Int>] = [:]
        for measure in part.measures[(first - 1)..<min(last, part.measures.count)] {
            for symbol in measure.symbols where staves.contains(symbol.staff) {
                guard let position = symbol.position else { continue }
                let range = positions[symbol.staff] ?? 0...8
                positions[symbol.staff] = min(range.lowerBound, position)...max(range.upperBound, position)
            }
        }
        return BarLayout(bars: first...last, isGrandStaff: staves.contains(1) && staves.contains(2), positions: positions)
    }

    /// The question for a piece note asked in `bar` (the note being asked, or one asked with it):
    /// in the bar view it prints the sign the bar prints (a sign earlier in the bar carries on), on
    /// its own the note's `printedAccidental`.
    private static func question(for note: ScoreNote, in bar: BarDisplay?) -> Question {
        guard let bar, bar.current != nil, note.measure == bar.measure.number, let symbol = note.symbolIndex,
              bar.measure.symbols.indices.contains(symbol) else { return note.question }
        return Question(clef: note.clef, pitch: note.pitch, keySignature: note.keySignature,
                        printedAccidental: bar.measure.symbols[symbol].accidental, octaveShift: note.octaveShift)
    }

    /// Staff positions the staff has to fit (both clefs), so it doesn't rescale from note to note:
    /// a piece round's notes, or every note random rounds can ask. Nil when they fit the usual
    /// layout (three ledger lines either side).
    var staffPositionsToFit: ClosedRange<Int>? {
        let positions = pieceNotes.map(\.question.position)
        let fit: ClosedRange<Int>
        if let low = positions.min(), let high = positions.max() {
            fit = low...high
        } else if isPractisingPiece {
            return nil
        } else {
            fit = settings.range.span
        }
        let usual = NoteRange.threeLedgerLines.span
        return fit.lowerBound < usual.lowerBound || fit.upperBound > usual.upperBound ? fit : nil
    }

    /// The notes piece state describes: the round's during one, otherwise the next round's.
    /// Empty without a piece.
    private var pieceNotes: [ScoreNote] { pieceRound?.notes ?? selectedNotes }

    /// Whose clef and key the staff shows between piece rounds: the note the next round starts
    /// on, or the part's first note when the settings leave nothing to ask.
    private var leadingPieceNote: ScoreNote? { pieceNotes.first ?? piecePart?.notes.first }

    /// Called by the app as it quits, so a round still going is logged as ended (`.appQuit`).
    func appWillTerminate() {
        guard phase == .playing else { return }
        abandonRound(as: .appQuit)
    }

    /// Reads a MusicXML file and switches to practising it, or sets `pieceError`. Every piece
    /// opened is kept in `library`, so it can be opened again from there (the same file again is
    /// the same piece); one that can't be kept there (a disk error) is opened all the same.
    /// `source` says how the file was picked, for the usage log.
    func openPiece(at url: URL, via source: PieceOpenSource = .menu) {
        if let failure = openFile(at: url, via: source) { pieceError = failure }
    }

    /// Switches to practising `score` (also how tests and previews load one without a file),
    /// outside the library. A round in progress is dropped without a summary. Reopening the same
    /// file keeps the piece settings; another file starts from bar 1.
    func open(_ score: Score, from url: URL, via source: PieceOpenSource = .menu) {
        guard !score.parts.isEmpty else {
            pieceError = Self.noNotesMessage
            recordPieceOpenFailed(url.path, via: source, Self.noNotesMessage)
            return
        }
        switchTo(score, from: url, entry: nil, via: source)
    }

    /// Opens a piece from the library: its copy, with the settings it was last practised with.
    /// When the copy can no longer be read, sets `pieceError` and leaves the entry where it is.
    func open(_ entry: PieceLibrary.Entry, via source: PieceOpenSource = .library) {
        if let failure = openCopy(of: entry, via: source) { pieceError = failure }
    }

    /// Back to random notes; a round in progress is dropped without a summary. The piece stays in
    /// the library, with its settings.
    func closePiece() {
        abandonRound()
        recorder.record(.pieceClosed(PieceClosed(path: pieceURL?.path, libraryID: pieceEntryID)))
        piece = nil
        pieceURL = nil
        pieceEntryID = nil
        pieceError = nil
        forgetLastPiece()
        updateSelection()
    }

    private static let noNotesMessage = "There are no notes to practise in this file."

    /// Imports the file at `url`, keeps it in the library and switches to it; or logs why it
    /// can't and returns that.
    private func openFile(at url: URL, via source: PieceOpenSource) -> String? {
        // The library's own copy, picked in Finder, is that entry (and has its id for a name).
        if let entry = library.entries.first(where: {
            library.fileURL(for: $0).standardizedFileURL.path == url.standardizedFileURL.path
        }) {
            return openCopy(of: entry, via: source)
        }
        let score: Score
        do {
            score = try MusicXMLImporter.load(from: url)
        } catch {
            recordPieceOpenFailed(url.path, via: source, error.localizedDescription)
            return error.localizedDescription
        }
        guard !score.parts.isEmpty else {
            recordPieceOpenFailed(url.path, via: source, Self.noNotesMessage)
            return Self.noNotesMessage
        }
        do {
            let entry = try library.add(url, title: score.title)
            // Known by where it was first opened from, which may be another copy of the same file.
            switchTo(score, from: URL(fileURLWithPath: entry.originalPath), entry: entry, via: source)
        } catch {
            switchTo(score, from: url, entry: nil, libraryError: error.localizedDescription, via: source)
        }
        return nil
    }

    /// Imports the library's copy of `entry` and switches to it, marking it opened; or logs why it
    /// can't and returns what to tell. The entry stays in the library either way.
    private func openCopy(of entry: PieceLibrary.Entry, via source: PieceOpenSource) -> String? {
        let copy = library.fileURL(for: entry)
        var score: Score
        do {
            score = try MusicXMLImporter.load(from: copy)
        } catch {
            return copyFailed(entry, via: source, error.localizedDescription)
        }
        guard !score.parts.isEmpty else { return copyFailed(entry, via: source, Self.noNotesMessage) }
        // The copy is named after the entry's id: a score without a title goes by the original's name.
        if score.title == copy.deletingPathExtension().lastPathComponent {
            score = Score(title: URL(fileURLWithPath: entry.originalPath).deletingPathExtension().lastPathComponent,
                          parts: score.parts)
        }
        var opened = library.entry(id: entry.id) ?? entry
        var libraryError: String?
        do {
            opened = try library.add(copy, title: score.title)
        } catch {
            libraryError = error.localizedDescription
        }
        switchTo(score, from: URL(fileURLWithPath: opened.originalPath), entry: opened, libraryError: libraryError,
                 via: source)
        return nil
    }

    /// Logs why the copy of `entry` didn't open, and returns what to tell.
    private func copyFailed(_ entry: PieceLibrary.Entry, via source: PieceOpenSource, _ error: String) -> String {
        recordPieceOpenFailed(entry.originalPath, libraryID: entry.id, via: source, error)
        let original = (entry.originalPath as NSString).abbreviatingWithTildeInPath
        return "Clefwise's copy of “\(entry.title)” can no longer be read. "
            + "Open the original file again to practise it (\(original))."
    }

    /// Switches to practising `score`, known by `url`, where it was first opened from; a round in
    /// progress is dropped without a summary. A piece from the library comes back with its own
    /// settings when it has some; otherwise it takes the ones in use, from bar 1 when it's another
    /// piece than the last, and keeps them from then on. Either way they're fitted to the score.
    private func switchTo(_ score: Score, from url: URL, entry: PieceLibrary.Entry?, libraryError: String? = nil,
                          via source: PieceOpenSource) {
        abandonRound()
        let saved = entry?.settings
        var newSettings = settings
        if let saved {
            newSettings.piece = saved
        } else if url.path != settings.piecePath {
            newSettings.piece.startBar = 1
        }
        newSettings.piece = Self.fitting(newSettings.piece, to: score)
        newSettings.piecePath = url.path
        newSettings.pieceID = entry?.id
        recordPieceOpened(score, from: url, libraryID: entry?.id, restoredSettings: saved != nil,
                          pieceSettings: newSettings.piece, libraryError: libraryError, via: source)
        piece = score
        pieceURL = url
        // Before the settings change, so they're kept for this piece and not the last.
        pieceEntryID = entry?.id
        pieceError = nil
        if saved != nil {
            // `pieceOpened` holds the restored settings: they aren't changes the user made.
            var asLogged = settings
            asLogged.piece = newSettings.piece
            settingsAsLogged = JSONValue(encoding: asLogged)
        }
        settings = newSettings
        updateSelection()
        // Also when they didn't change, so a piece new to the library has them from the start.
        if let id = entry?.id { library.save(settings: settings.piece, for: id) }
    }

    /// Nothing to reopen at launch: one change, so it's saved and logged once.
    private func forgetLastPiece() {
        var newSettings = settings
        newSettings.piecePath = nil
        newSettings.pieceID = nil
        settings = newSettings
    }

    /// At launch, picks up last session's piece: the library entry last open, from its copy (or,
    /// should the copy be gone, from the original file). Settings from before the library have
    /// only the file's path: that file if it still reads, which adds it to the library, otherwise
    /// the library's copy of it. A piece that can't be reopened, or was taken out of the library,
    /// is quietly forgotten (only the log hears why): nobody just asked to open it.
    private func reopenLastPiece() {
        if let id = settings.pieceID {
            if let entry = library.entry(id: id) {
                if openCopy(of: entry, via: .launch) == nil || reopenFile(at: entry.originalPath) { return }
            } else {
                recordPieceOpenFailed(settings.piecePath ?? "", libraryID: id, via: .launch,
                                      "The piece is no longer in the library.")
            }
        } else if let path = settings.piecePath {
            if reopenFile(at: path) { return }
            if let entry = library.entry(originalPath: path), openCopy(of: entry, via: .launch) == nil { return }
        } else {
            return
        }
        forgetLastPiece()
    }

    /// At launch, opens the file at `path` when it's still there and reads, and says whether it did.
    private func reopenFile(at path: String) -> Bool {
        guard FileManager.default.isReadableFile(atPath: path) else {
            recordPieceOpenFailed(path, via: .launch, "The file is gone or can't be read.")
            return false
        }
        return openFile(at: URL(fileURLWithPath: path), via: .launch) == nil
    }

    /// `options` with the part and start bar brought within what `score` has.
    private static func fitting(_ options: PieceSettings, to score: Score) -> PieceSettings {
        var options = options
        options.part = min(max(options.part, 0), score.parts.count - 1)
        options.startBar = min(max(options.startBar, 1), max(score.parts[options.part].measureCount, 1))
        return options
    }

    private func updateSelection() {
        selectedNotes = piecePart.map { Self.notes(of: $0, with: settings.piece) } ?? []
        selectedBarLayout = piecePart.flatMap { Self.barLayout(of: selectedNotes, in: $0) }
    }

    /// The notes a round on `part` asks, in reading order: from the start bar on, on the hand's
    /// staff, and with top or bottom notes of chords only its top note on the upper staff (the
    /// melody) and its bottom one on the lower (the bass). Named together, it's every note.
    private static func notes(of part: ScorePart, with options: PieceSettings) -> [ScoreNote] {
        var notes = part.notes.filter { $0.measure >= options.startBar }
        if part.staffCount > 1 {
            switch options.hand {
            case .right: notes = notes.filter { $0.staff == 1 }
            case .left: notes = notes.filter { $0.staff == 2 }
            case .both: break
            }
        }
        guard options.chords == .topOrBottom else { return notes }
        var kept: [Int: Int] = [:] // chord id: index in `notes`
        for (index, note) in notes.enumerated() {
            guard let keptIndex = kept[note.chord] else {
                kept[note.chord] = index
                continue
            }
            // By sound, then by spelling for the odd E♯ and F in one chord.
            let pitch = (note.pitch.midiNumber, note.pitch.diatonicIndex)
            let keptPitch = (notes[keptIndex].pitch.midiNumber, notes[keptIndex].pitch.diatonicIndex)
            if note.staff == 1 ? pitch > keptPitch : pitch < keptPitch { kept[note.chord] = index }
        }
        return notes.indices.filter { kept[notes[$0].chord] == $0 }.map { notes[$0] }
    }

    /// Why a piece round can't start: the piece settings leave no notes.
    private var emptySelectionMessage: String {
        let startBar = settings.piece.startBar
        guard piecePart?.notes.contains(where: { $0.measure >= startBar }) == true else {
            return "This part has no notes from bar \(startBar) on. Choose an earlier start bar."
        }
        // The part has notes there, so it's the hand that leaves none.
        let hand = settings.piece.hand == .left ? "left" : "right"
        return startBar > 1
            ? "There are no \(hand)-hand notes from bar \(startBar) on. Choose another hand or an earlier start bar."
            : "This part has no \(hand)-hand notes. Choose another hand."
    }

    /// White keys (as diatonic indices) for the piano: whole octaves covering every note the
    /// settings can ask, or a piece round's notes as they sound (an 8va note is played up the octave).
    var pianoKeys: ClosedRange<Int> {
        let midiNumbers = pieceNotes.map(\.pitch.midiNumber)
        if let low = midiNumbers.min(), let high = midiNumbers.max() {
            // By MIDI number rather than staff step, so a C♭ brings in the B below.
            return ((low / 12 - 1) * 7)...((high / 12 - 1) * 7 + 6)
        }
        let indices = settings.clefChoice.clefs.flatMap { clef in
            [settings.range.span.lowerBound, settings.range.span.upperBound]
                .map { clef.pitch(atPosition: $0).diatonicIndex }
        }
        return (indices.min()! / 7 * 7)...(indices.max()! / 7 * 7 + 6)
    }

    // MARK: - Round flow

    /// Starts a round: on the loaded piece if there is one (or sets `pieceError` when the piece
    /// settings leave no notes), otherwise on random notes from the toolbar settings. `source`
    /// says what started it, for the usage log.
    func start(via source: StartSource = .button) {
        if let piece, let part = piecePart {
            guard !selectedNotes.isEmpty else {
                pieceError = emptySelectionMessage
                return
            }
            pieceError = nil
            pieceRound = PieceRound(title: piece.title, part: part, notes: selectedNotes, order: settings.piece.order,
                                    barLayout: settings.piece.usesWholeBar ? selectedBarLayout : nil,
                                    namesTogether: settings.piece.chords == .together)
        } else {
            pieceRound = nil
            roundKey = pickRoundKey()
        }
        // Starting over mid-round drops the round in progress (only the log sees it end).
        recordRoundEnd(.abandoned)
        stopClock()
        clearPause()
        score = 0
        attempts = 0
        streak = 0
        bestStreak = 0
        elapsed = 0
        roundMisses = [:]
        responseTimes = []
        summary = nil
        flash = nil
        group = nil
        groupFlash = nil
        typedText = ""
        armedAccidental = .natural
        isShowingMiss = false
        question = nil
        phase = .playing
        roundStart = .now
        startClock()
        recordRoundStart(via: source)
        nextQuestion()
    }

    /// The round clock's timer, ten times a second (`tick`).
    private func startClock() {
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard phase == .playing else { return }
        finish(timeRanOut: false)
    }

    /// A round going and not paused: answers count.
    var isTakingAnswers: Bool { phase == .playing && !isPaused }

    /// Space and the Pause button: pauses the round in progress, or carries it on. Tests pass
    /// `now`, as with `tick(at:)`.
    func togglePause(via source: PauseSource = .button, at now: ContinuousClock.Instant = .now) {
        if isPaused {
            resume(via: source, at: now)
        } else {
            pause(via: source, at: now)
        }
    }

    /// Stops the round's clock. The time shown, the response time of the note on screen and the
    /// round's practice time all leave the pause out. Answers don't count until `resume`.
    func pause(via source: PauseSource = .button, at now: ContinuousClock.Instant = .now) {
        guard phase == .playing, !isPaused else { return }
        isPaused = true
        pausedVia = source
        pausedAt = now
        recordPause(via: source)
    }

    func resume(via source: PauseSource = .button, at now: ContinuousClock.Instant = .now) {
        guard phase == .playing, isPaused, let pausedAt else { return }
        let pause = max(now - pausedAt, .zero)
        // Times are measured from these starts, so moving them on by the pause leaves it out.
        roundStart += pause
        questionStart += pause
        roundPaused += pause
        questionPaused += pause
        self.pausedAt = nil
        isPaused = false
        pausedVia = nil
        recordResume(via: source, after: pause)
        if advancesOnResume {
            advancesOnResume = false
            isShowingMiss = false
            nextQuestion()
        } else if asksAgainOnResume {
            asksAgainOnResume = false
            askAgain()
        }
    }

    /// Called by the app when it stops being the active app: a round going pauses itself, and
    /// waits for Resume or Space when you come back.
    func appDidResignActive() {
        pause(via: .appSwitch)
    }

    private func clearPause() {
        isPaused = false
        pausedVia = nil
        pausedAt = nil
        roundPaused = .zero
        questionPaused = .zero
        advancesOnResume = false
        asksAgainOnResume = false
    }

    func dismissSummary() {
        summary = nil
        phase = .idle
    }

    /// Note-button click: the letter plus whichever ♯/♭ is armed. While a `group` is asked, it
    /// adds an entry instead (the last one needed submits them).
    func answer(_ letter: NoteLetter) {
        pressNoteButton(letter, via: .click)
    }

    /// Answers with a note name, as if clicked; any octave counts. While a `group` is asked, it
    /// adds an entry.
    func answer(_ letter: NoteLetter, _ accidental: Accidental) {
        answerName(letter, accidental, via: .click)
    }

    /// Answers with a piano key, so the octave has to be right too. Compared by sound, so the
    /// black key counts whether the question spells it C♯ or D♭. While a `group` is asked, the
    /// key is chosen, or taken back if it was chosen already; the last one needed submits them.
    func answer(_ pitch: Pitch) {
        guard let question = questionTakingAnswers(from: .piano, detail: pitch.name) else { return }
        if group != nil {
            toggleGroupKey(pitch)
            return
        }
        submit(Flash(letter: pitch.letter, accidental: pitch.accidental, pitch: pitch,
                     isCorrect: question.pitch.midiNumber == pitch.midiNumber),
               to: question, via: .piano)
    }

    /// Takes back an entry towards the notes asked together (a chip clicked), before they're judged.
    func removeGroupEntry(at index: Int) {
        guard let entries = group?.entries, entries.indices.contains(index) else { return }
        let key = "remove \(label(of: entries[index]))"
        guard questionTakingAnswers(from: .click, detail: key) != nil else { return }
        noteClick(key)
        group?.entries.remove(at: index)
        settleKeystroke(.deleted)
    }

    /// Delete with the note buttons or the piano: takes back the last entry towards the notes
    /// asked together. Paused, or once they're judged, nothing changes.
    private func removeLastGroupEntry() {
        guard isTakingAnswers, !isShowingMiss, let entries = group?.entries, !entries.isEmpty else { return }
        group?.entries.removeLast()
        settleKeystroke(.deleted)
    }

    /// A piano key while notes are asked together: chosen, or taken back if it's chosen already.
    private func toggleGroupKey(_ pitch: Pitch) {
        guard let entries = group?.entries else { return }
        if let index = entries.firstIndex(where: { $0.pitch?.midiNumber == pitch.midiNumber }) {
            noteClick("piano \(pitch.name)")
            group?.entries.remove(at: index)
            settleKeystroke(.deleted)
        } else {
            addGroupEntry(GroupEntry(letter: pitch.letter, accidental: pitch.accidental, pitch: pitch), via: .piano)
        }
    }

    /// Adds an entry towards the notes asked together; the last one needed submits them.
    private func addGroupEntry(_ entry: GroupEntry, via source: AnswerSource) {
        guard var group else { return }
        noteClick("\(source == .piano ? "piano" : "click") \(label(of: entry))")
        group.entries.append(entry)
        self.group = group
        if group.entries.count >= group.entriesNeeded(on: settings.answerInput) {
            judgeGroup(via: source)
        } else {
            settleKeystroke(.typed)
        }
    }

    /// A click towards the notes asked together joins the question's keystrokes as `key`, as the
    /// sign buttons' clicks do; a key pressed for it is noted already.
    private func noteClick(_ key: String) {
        if let questionLog, !questionLog.keyPending { noteKeystroke(key) }
    }

    /// "Sol♯" for a name, "G♯4" for a piano key.
    private func label(of entry: GroupEntry) -> String {
        entry.pitch?.name ?? settings.naming.name(of: Pitch(entry.letter, 4, entry.accidental))
    }

    /// Arms ♯ or ♭ for the next note button; choosing the armed one again disarms it.
    func toggleArmedAccidental(_ accidental: Accidental) {
        // A click on the sign button joins the question's keystrokes; a key arming it is already noted.
        if let questionLog, !questionLog.keyPending {
            noteKeystroke("click \(accidental.symbol)")
            settleKeystroke(.armed)
        }
        armedAccidental = armedAccidental == accidental ? .natural : accidental
    }

    /// A note button, clicked or by shortcut. Presses that can't count (during the pause after a
    /// miss, or a combination with no name like komal Sa) leave the armed sign alone.
    private func pressNoteButton(_ letter: NoteLetter, via source: AnswerSource) {
        if answerName(letter, armedAccidental, via: source) { armedAccidental = .natural }
    }

    /// Answers with a note name (buttons and typing); false when the answer can't count.
    /// Combinations with no name of their own are ignored rather than judged by sound, so
    /// "komal Sa" never passes for Ni.
    @discardableResult
    private func answerName(_ letter: NoteLetter, _ accidental: Accidental, via source: AnswerSource) -> Bool {
        let name = settings.naming.answerName(of: letter, accidental)
        guard let question = questionTakingAnswers(
            from: source, detail: name ?? settings.naming.name(of: letter) + accidental.symbol, hasName: name != nil
        ) else { return false }
        if group != nil {
            addGroupEntry(GroupEntry(letter: letter, accidental: accidental, pitch: nil), via: source)
            return true
        }
        submit(Flash(letter: letter, accidental: accidental, pitch: nil,
                     isCorrect: settings.naming.accepts(letter, accidental, for: question.pitch)),
               to: question, via: source)
        return true
    }

    /// The question an answer goes to, or nil when it can't count right now: no round, the pause
    /// after a miss, or (`hasName` false) a sign with no name. Those are logged as ignored.
    private func questionTakingAnswers(from source: AnswerSource, detail: String, hasName: Bool = true) -> Question? {
        let reason: String
        if phase != .playing || question == nil {
            reason = "noRound"
        } else if isPaused {
            reason = "paused"
        } else if isShowingMiss {
            reason = "missPause"
        } else if !hasName {
            reason = "noName"
        } else {
            return question
        }
        recordIgnored(reason, from: source, detail: detail)
        settleKeystroke(.rejected) // when a key sent it
        return nil
    }

    private func submit(_ response: Flash, to question: Question, via source: AnswerSource) {
        let isCorrect = response.isCorrect
        attempts += 1
        noteStats[statKey(for: question), default: NoteStat()].record(isCorrect)
        save(noteStats, as: Keys.noteStats)
        showFlash(response, for: isCorrect ? Self.correctFlash : Self.missPause)

        if isCorrect {
            score += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            responseTimes.append(Self.seconds(from: questionStart))
            recordAnswer(response, to: question, via: source)
            if !settings.isMuted { synth.play(question.pitch) }
            nextQuestion()
        } else {
            streak = 0
            roundMisses[StaffNote(clef: question.clef, pitch: question.pitch), default: 0] += 1
            recordAnswer(response, to: question, via: source)
            if !settings.isMuted { synth.playMiss() }
            showMiss()
        }
    }

    /// Judges the entries towards the notes asked together, each note right or wrong on its own.
    /// The score goes up by the notes named right and attempts by the notes asked; the streak
    /// grows by them all only when all are right. All right, the notes sound as a chord and the
    /// next question comes; otherwise the result stays up for the pause after a miss.
    private func judgeGroup(via source: AnswerSource) {
        guard var group, !group.entries.isEmpty else { return }
        let result = Self.judge(group.entries, against: group.questions, naming: settings.naming)
        group.result = result
        self.group = group
        attempts += group.questions.count
        score += result.rightCount
        for (question, isRight) in zip(group.questions, result.isRight) {
            noteStats[statKey(for: question), default: NoteStat()].record(isRight)
            if !isRight { roundMisses[StaffNote(clef: question.clef, pitch: question.pitch), default: 0] += 1 }
        }
        save(noteStats, as: Keys.noteStats)

        if result.isAllRight {
            streak += group.questions.count
            bestStreak = max(bestStreak, streak)
            // One time per question, as for a note on its own.
            responseTimes.append(Self.seconds(from: questionStart))
            recordGroupAnswer(group, via: source)
            showGroupFlash(group)
            if !settings.isMuted { synth.play(group.questions.map(\.pitch)) }
            nextQuestion()
        } else {
            streak = 0
            recordGroupAnswer(group, via: source)
            if !settings.isMuted { synth.playMiss() }
            showMiss()
        }
    }

    /// The pause after a miss: the note (or the notes asked together, marked) stays up, then the
    /// next question comes. Paused meanwhile, it comes when the round resumes.
    private func showMiss() {
        isShowingMiss = true
        pendingAdvance = Task { [weak self] in
            try? await Task.sleep(for: Self.missPause)
            guard let self, !Task.isCancelled, self.phase == .playing else { return }
            // Paused meanwhile: the miss stays up and the next note waits for the resume.
            guard !self.isPaused else {
                self.advancesOnResume = true
                return
            }
            self.isShowingMiss = false
            self.nextQuestion()
        }
    }

    private func showGroupFlash(_ judged: NoteGroup) {
        groupFlash = judged
        Task { [weak self] in
            try? await Task.sleep(for: Self.correctFlash)
            if self?.groupFlash?.id == judged.id { self?.groupFlash = nil }
        }
    }

    /// Matches `entries` to the notes asked together (`questions`) so that the most notes are
    /// right. A name names one note, in any octave (`NamingSystem.accepts`); a piano key names
    /// every note that sounds it. Notes left without a match are wrong, and each is paired with
    /// an entry left over, in order.
    nonisolated static func judge(_ entries: [GroupEntry], against questions: [Question],
                                  naming: NamingSystem) -> GroupResult {
        var matched = [Int?](repeating: nil, count: questions.count)
        for (entry, given) in entries.enumerated() {
            guard let key = given.pitch else { continue }
            for question in questions.indices
            where matched[question] == nil && questions[question].pitch.midiNumber == key.midiNumber {
                matched[question] = entry
            }
        }
        // Names, one note each: matched for the most right. A name takes the first note it fits
        // that's still free; failing that, an earlier name gives up its note if it can take
        // another instead (augmenting paths).
        let open = questions.indices.filter { matched[$0] == nil }
        var byName: [Int: Int] = [:] // question: entry
        func place(_ entry: Int, _ tried: inout Set<Int>) -> Bool {
            let name = entries[entry]
            let fitting = open.filter { naming.accepts(name.letter, name.accidental, for: questions[$0].pitch) }
            if let free = fitting.first(where: { byName[$0] == nil && !tried.contains($0) }) {
                byName[free] = entry
                return true
            }
            for question in fitting where !tried.contains(question) {
                tried.insert(question)
                if let holder = byName[question], place(holder, &tried) {
                    byName[question] = entry
                    return true
                }
            }
            return false
        }
        for entry in entries.indices where entries[entry].pitch == nil {
            var tried = Set<Int>()
            _ = place(entry, &tried)
        }
        for (question, entry) in byName { matched[question] = entry }

        let used = Set(matched.compactMap { $0 })
        var leftovers = ArraySlice(entries.indices.filter { !used.contains($0) })
        // Notes named wrong that sound the same key are paired with the same piano key.
        var sharedKeys: [Int: Int] = [:]
        let entryIndices = questions.indices.map { question -> Int in
            if let entry = matched[question] { return entry }
            let midi = questions[question].pitch.midiNumber
            if let entry = sharedKeys[midi] { return entry }
            let entry = leftovers.popFirst() ?? max(entries.count - 1, 0)
            if entries.indices.contains(entry), entries[entry].pitch != nil { sharedKeys[midi] = entry }
            return entry
        }
        return GroupResult(isRight: matched.map { $0 != nil }, entryIndices: entryIndices,
                           entryIsRight: entries.indices.map(used.contains))
    }

    /// Handles a key press; returns false to let the system handle it instead.
    func handleKey(characters: String, keyCode: UInt16) -> Bool {
        // The question's log takes the key now; what the key turns out to do settles its result,
        // and a key that does none of those things is `other`.
        noteKeystroke(Self.keyName(characters: characters, keyCode: keyCode))
        defer { settleKeystroke(.other) }
        switch keyCode {
        case 53: // Escape
            switch phase {
            case .playing: stop()
            case .finished: dismissSummary()
            case .idle: break
            }
            return true
        case 36, 76, 49: // Return, keypad Enter, Space
            if phase != .playing {
                start(via: .key)
            } else if keyCode == 49 {
                togglePause(via: .key)
            } else if settings.answerInput == .keyboard, accidentalsPossible || group != nil {
                confirmTyping()
            }
            return true
        case 51 where settings.answerInput == .keyboard: // Delete (backspace)
            // Paused, the answer box is left as it is.
            if !isPaused, !typedText.isEmpty {
                typedText.removeLast()
                settleKeystroke(.deleted)
            }
            return true
        case 51 where group != nil: // Delete with the note buttons or the piano: takes back an entry
            removeLastGroupEntry()
            return true
        default:
            break
        }
        guard let character = characters.lowercased().first else { return false }
        if settings.answerInput == .keyboard, phase == .playing, isTypeable(character) {
            type(character)
            return true
        }
        // Typing can't pick an octave, so these shortcuts only answer in button mode.
        // 1–7 answer by button position; typed letters only make sense with letter names.
        // # or = arms a sharp and - a flat: "b" has to stay the note B.
        if settings.answerInput == .buttons {
            if accidentalsPossible, let accidental = Self.armingKeys[character] {
                if isTakingAnswers {
                    toggleArmedAccidental(accidental)
                    settleKeystroke(.armed)
                } else {
                    recordIgnored(isPaused ? "paused" : "noRound", from: .shortcut, detail: String(character))
                }
                return true
            }
            if let digit = character.wholeNumberValue, let letter = NoteLetter(rawValue: digit - 1) {
                pressNoteButton(letter, via: .shortcut)
                return true
            }
            if settings.naming == .letters, let letter = NoteLetter(character: character) {
                pressNoteButton(letter, via: .shortcut)
                return true
            }
        }
        switch character {
        case "h": settings.showHints.toggle()
        case "k" where settings.answerInput == .piano: settings.showKeyNames.toggle()
        case "m": settings.isMuted.toggle()
        default:
            // Typing a name with no round going (during one it would have been typed above).
            if settings.answerInput == .keyboard, isTypeable(character) {
                recordIgnored("noRound", from: .typing, detail: String(character))
            }
            return false
        }
        return true
    }

    /// In keyboard mode every letter typed during a round goes towards a note name, and so does
    /// a ♯/♭ sign when notes can have one ("b" is a letter already).
    private func isTypeable(_ character: Character) -> Bool {
        character.isLetter || (accidentalsPossible && "#♯♭".contains(character))
    }

    private static let armingKeys: [Character: Accidental] = ["#": .sharp, "=": .sharp, "-": .flat]

    /// Everything that can be typed as an answer, lowercased: each name, and when notes can be
    /// sharp or flat also the name followed by ♯ or ♭.
    private var typeableAnswers: [(text: String, letter: NoteLetter, accidental: Accidental)] {
        let accidentals: [Accidental] = accidentalsPossible ? [.natural, .sharp, .flat] : [.natural]
        return NoteLetter.allCases.flatMap { letter in
            let name = settings.naming.name(of: letter).lowercased()
            return accidentals
                .filter { settings.naming.hasName(letter, $0) }
                .map { (name + ($0 == .natural ? "" : $0.symbol), letter, $0) }
        }
    }

    /// Adds a typed character; answers as soon as the text is a whole name, with no Return:
    /// - a right name at once, even when a ♯/♭ could follow ("fa" for Fa in G major);
    /// - a wrong name at once too, when no ♯/♭ could make it right ("mi" for Fa♯);
    /// - only the right letter without its sign ("fa" for Fa♯) waits for the ♯/♭, or for Return,
    ///   which answers it as typed.
    /// So a wrong name is always judged and can't be taken back and retyped. Keystrokes that can't
    /// lead to any answer are dropped rather than counted as wrong, so typos aren't punished.
    private func type(_ character: Character) {
        guard !isPaused, !isShowingMiss else {
            recordIgnored(isPaused ? "paused" : "missPause", from: .typing, detail: String(character))
            return
        }
        if let group {
            type(character, towards: group)
            return
        }
        let answers = typeableAnswers
        // # and a "b" after a whole name are stored as ♯ and ♭, so the text reads like the name.
        let followsName = answers.contains { $0.text == typedText }
        let addition = switch character {
        case "#", "♯": Accidental.sharp.symbol
        case "♭": Accidental.flat.symbol
        case "b" where followsName: Accidental.flat.symbol
        default: String(character)
        }
        let text = typedText + addition
        let extensions = answers.filter { $0.text.hasPrefix(text) }
        func isRight(_ answer: (text: String, letter: NoteLetter, accidental: Accidental)) -> Bool {
            guard let question else { return false }
            return settings.naming.accepts(answer.letter, answer.accidental, for: question.pitch)
        }
        if let match = extensions.first(where: { $0.text == text }),
           isRight(match) || !extensions.contains(where: { $0.text != text && isRight($0) }) {
            typedText = ""
            answerName(match.letter, match.accidental, via: .typing)
        } else if !extensions.isEmpty {
            typedText = text
            settleKeystroke(.typed)
        } else {
            rejectedKeystrokes += 1
            settleKeystroke(.rejected)
        }
    }

    /// Typing while notes are asked together: names back to back, read as that many names. A
    /// keystroke that can't lead to them is refused (the box shakes); the text submits by itself
    /// once it reads as all the names and nothing longer could follow, otherwise on Return.
    private func type(_ character: Character, towards group: NoteGroup) {
        // # is kept as ♯; a "b" stays as typed, since it's a flat or the note B depending on the reading.
        let text = typedText + (character == "#" ? Accidental.sharp.symbol : String(character))
        let names = TypedNames(text, count: group.questions.count, answers: typeableAnswers)
        guard names.isViable else {
            rejectedKeystrokes += 1
            settleKeystroke(.rejected)
            return
        }
        typedText = text
        if names.submitsAtOnce {
            submitTyped(names)
        } else {
            settleKeystroke(.typed)
        }
    }

    /// Answers the notes asked together with the typed names. Read more than one way, the text is
    /// judged with the reading that names the most notes right (the first such one).
    private func submitTyped(_ names: TypedNames) {
        guard var group else { return }
        let readings = names.readings.map { $0.map { GroupEntry(letter: $0.letter, accidental: $0.accidental, pitch: nil) } }
        guard let best = readings.max(by: { a, b in
            Self.judge(a, against: group.questions, naming: settings.naming).rightCount
                < Self.judge(b, against: group.questions, naming: settings.naming).rightCount
        }) else { return }
        typedText = ""
        group.entries = best
        self.group = group
        judgeGroup(via: .typing)
    }

    /// Return in keyboard mode: answers with a whole name that was waiting for a possible ♯/♭ (the
    /// right letter without its sign, so a miss).
    /// While notes are asked together, with the names typed if they read as all of them.
    private func confirmTyping() {
        guard !isShowingMiss, !typedText.isEmpty else { return }
        if let group {
            guard questionTakingAnswers(from: .typing, detail: typedText) != nil else { return }
            let names = TypedNames(typedText, count: group.questions.count, answers: typeableAnswers)
            if names.readings.isEmpty {
                rejectedKeystrokes += 1
                settleKeystroke(.rejected)
            } else {
                submitTyped(names)
            }
            return
        }
        if let match = typeableAnswers.first(where: { $0.text == typedText }) {
            typedText = ""
            answerName(match.letter, match.accidental, via: .typing)
        } else {
            rejectedKeystrokes += 1
            settleKeystroke(.rejected)
        }
    }

    /// The round clock, ten times a second. Tests pass a later `now` to run a sprint out.
    func tick(at now: ContinuousClock.Instant = .now) {
        guard phase == .playing, !isPaused else { return }
        let seconds = Self.seconds(from: roundStart, to: now)
        // Only publish whole-second changes so the UI doesn't redraw ten times a second.
        if Int(seconds) != Int(elapsed) { elapsed = seconds }
        if let limit = roundTimeLimit, seconds >= limit {
            elapsed = limit
            finish(timeRanOut: true)
        }
    }

    /// `finishedPiece`: an in-order practice round got past the piece's last note.
    /// `finishedNotes`: a round of a set number of notes answered its last.
    private func finish(timeRanOut: Bool, finishedPiece: Bool = false, finishedNotes: Bool = false) {
        stopClock()
        isShowingMiss = false
        flash = nil
        group = nil
        groupFlash = nil
        typedText = ""
        armedAccidental = .natural
        question = nil
        let pieceRound = pieceRound
        self.pieceRound = nil

        // Only sprints keep best scores and the guard below only turns away practice rounds, so
        // this can come first, and every round's end is logged with it.
        var isNewBest = false
        if pieceRound == nil, settings.mode == .sprint, score > (bestScores[bestScoreKey] ?? 0) {
            bestScores[bestScoreKey] = score
            save(bestScores, as: Keys.bestScores)
            isNewBest = true
        }
        // While a pause can still be left out of it.
        let seconds = Double(activeMilliseconds(since: roundStart)) / 1000
        recordRoundEnd(timeRanOut ? .timeUp : finishedPiece ? .pieceComplete : finishedNotes ? .notesDone : .stopped,
                       isNewBest: isNewBest)
        clearPause()
        // A practice round stopped before any answer has nothing to sum up; one that ran out of
        // time does: nothing named is a result.
        guard attempts > 0 || settings.mode == .sprint || timeRanOut else {
            phase = .idle
            return
        }

        summary = RoundSummary(
            mode: settings.mode,
            score: score,
            attempts: attempts,
            bestStreak: bestStreak,
            averageSeconds: averageResponseTime,
            bestScore: pieceRound == nil && settings.mode == .sprint ? bestScores[bestScoreKey] : nil,
            isNewBest: isNewBest,
            timeRanOut: timeRanOut,
            notesToReview: notesToReview,
            mixedClefs: pieceRound.map { round in round.notes.contains { $0.clef != round.notes[0].clef } }
                ?? (settings.clefChoice == .both),
            pieceTitle: pieceRound?.title,
            finishedPiece: finishedPiece,
            hadLimit: practiceRoundLimit != .endless,
            finishedNotes: finishedNotes,
            noteRoundSeconds: roundNoteLimit == nil ? nil : seconds
        )
        phase = .finished
    }

    private var averageResponseTime: TimeInterval? {
        responseTimes.isEmpty ? nil : responseTimes.reduce(0, +) / Double(responseTimes.count)
    }

    /// The round's most missed notes, at most four.
    private var notesToReview: [StaffNote] { Self.notesToReview(from: roundMisses) }

    /// The most missed of `misses`, at most four. F and F♯ share a staff position, so pitch height
    /// breaks the tie.
    private static func notesToReview(from misses: [StaffNote: Int]) -> [StaffNote] {
        misses
            .sorted {
                $0.value != $1.value ? $0.value > $1.value
                    : ($0.key.pitch.diatonicIndex, $0.key.pitch.midiNumber) < ($1.key.pitch.diatonicIndex, $1.key.pitch.midiNumber)
            }
            .prefix(4)
            .map(\.key)
    }

    /// Drops the round in progress, or the last one's summary, without scoring it: for when the
    /// piece it's on is closed or replaced, or the app quits. `reason` is what the log says ended it.
    private func abandonRound(as reason: RoundEndReason = .abandoned) {
        recordRoundEnd(reason)
        stopClock()
        clearPause()
        isShowingMiss = false
        flash = nil
        group = nil
        groupFlash = nil
        typedText = ""
        armedAccidental = .natural
        question = nil
        pieceRound = nil
        summary = nil
        score = 0
        attempts = 0
        streak = 0
        elapsed = 0
        phase = .idle
    }

    private func stopClock() {
        timer?.invalidate()
        timer = nil
        pendingAdvance?.cancel()
        pendingAdvance = nil
    }

    private func showFlash(_ newFlash: Flash, for duration: Duration) {
        flash = newFlash
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            if self?.flash == newFlash { self?.flash = nil }
        }
    }

    private static func seconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant = .now) -> TimeInterval {
        let elapsed = (end - start).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }

    /// Since `start`, to the nearest millisecond (how the log keeps times), up to the start of
    /// the pause in progress if there is one.
    private func activeMilliseconds(since start: ContinuousClock.Instant) -> Int {
        Int((Self.seconds(from: start, to: pausedAt ?? .now) * 1000).rounded())
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int((Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15).rounded())
    }

    /// Time paused so far, the pause in progress included; nil when there was none, as the log has it.
    private func pausedMilliseconds(_ paused: Duration) -> Int? {
        let total = paused + (pausedAt.map { .now - $0 } ?? .zero)
        return total > .zero ? Self.milliseconds(total) : nil
    }

    // MARK: - Coming back after a crash

    /// How long a round that came back keeps the device's note about it (`Keys.restoringRound`): a
    /// crash within that time is taken to be the restore's own doing.
    private static let restoreSettles: Duration = .seconds(2)

    /// Brings back the round a crash cut short (or a force quit, or the battery running out), from
    /// its run file's events: called at launch, right after `init` has reopened the round's piece.
    /// The round comes back paused, as it was at its last event: the score, attempts, streaks,
    /// misses and response times, the place in a piece, and the round time used. `roundRestored` is
    /// logged. When the round resumes, the note that was on screen is asked again as a new question;
    /// after a miss (or with no question left on screen) the next note comes instead.
    ///
    /// The round is ended instead, as `interrupted` and timed at its last event, when bringing it
    /// back last time crashed (the device's note says that restore never settled, or the round
    /// carried on and stopped before another answer), or when it can't be rebuilt: its piece is
    /// gone or different, the settings that shape it changed, or its events don't make a round.
    /// See spec/practice-journal.md, "After a crash".
    func restore(_ pending: PendingRun) {
        // Already back (called twice), it's left as it is.
        guard roundLog?.id != pending.round else { return }
        let replay = RoundReplay(round: pending.round, events: pending.events)
        // One that ended is the run-file writer's to place; one with no events has nothing to bring back.
        guard !replay.hasEnded, replay.lastEventTime != nil else { return }
        let id = pending.round.uuidString
        if defaults.object(forKey: Keys.restoringRound) as? String == id || replay.resumedAfterRestoreWithoutAnswer {
            endInterrupted(pending.round, replay)
            return
        }
        // Written before rebuilding, so that if rebuilding crashes the app, the next launch knows.
        defaults.set(id, forKey: Keys.restoringRound)
        guard let rebuilt = rebuild(from: replay) else {
            endInterrupted(pending.round, replay)
            return
        }

        pieceError = nil
        pieceRound = rebuilt.pieceRound
        if let key = rebuilt.roundKey { roundKey = key }
        stopClock()
        clearPause()
        score = replay.score
        attempts = replay.attempts
        streak = replay.streak
        bestStreak = replay.bestStreak
        roundMisses = replay.misses
        responseTimes = replay.responseTimes
        summary = nil
        flash = nil
        groupFlash = nil
        typedText = ""
        armedAccidental = .natural
        isShowingMiss = false
        // The question last shown, which the next one follows on from (or which is asked again).
        question = rebuilt.questions.first
        group = rebuilt.questions.count > 1 ? NoteGroup(questions: rebuilt.questions) : nil
        phase = .playing
        // Paused from now, with the round time used before the crash: the time since counts for nothing.
        let now = ContinuousClock.now
        roundStart = now - .milliseconds(replay.activeMs)
        questionStart = now
        pausedAt = now
        isPaused = true
        roundPaused = .milliseconds(replay.pausedMs)
        elapsed = Double(replay.activeMs) / 1000
        if replay.unansweredQuestion.isEmpty {
            advancesOnResume = true
        } else {
            asksAgainOnResume = true
        }
        startClock()
        roundLog = RoundLog(id: pending.round, questionsShown: replay.questionsShown)
        questionLog = nil
        recorder.record(.roundRestored(RoundRestored(round: pending.round, activeMs: replay.activeMs,
                                                     unansweredQuestion: replay.unansweredQuestion.first?.question)))
        Task { [weak self] in
            try? await Task.sleep(for: Self.restoreSettles)
            self?.forgetRestoring(pending.round)
        }
    }

    /// A round rebuilt from its events, ready to come back.
    private struct RebuiltRound {
        /// Nil for random notes.
        var pieceRound: PieceRound?
        /// Random notes' key.
        var roundKey: KeySignature?
        /// The question last shown (the notes asked together, if they were), as it was.
        var questions: [Question]
    }

    /// The round `replay` tells of, as `start()` set it up; nil when that can't be the same round:
    /// the settings that shape it changed, its piece isn't open or isn't the same, or the question
    /// last shown isn't one it asks. A piece round is rebuilt from the piece settings it started
    /// with, which may since have changed for the next round.
    private func rebuild(from replay: RoundReplay) -> RebuiltRound? {
        guard phase != .playing, let started = replay.started, !replay.lastQuestion.isEmpty,
              let saved = Self.settings(from: started.settings), Self.shapeRoundsAlike(saved, settings) else { return nil }
        guard let logged = started.piece else {
            // Random notes: their key, and the question rebuilt from its line.
            guard piece == nil, (-7...7).contains(started.keyFifths) else { return nil }
            let questions = replay.lastQuestion.compactMap(Self.question(from:))
            guard questions.count == replay.lastQuestion.count else { return nil }
            return RebuiltRound(pieceRound: nil, roundKey: KeySignature(fifths: started.keyFifths), questions: questions)
        }
        // As `start()` set it up, with the round's own piece settings: changes made to them during
        // the round wait for the next one, and stay.
        let options = saved.piece
        guard let piece, piece.parts.indices.contains(options.part) else { return nil }
        let part = piece.parts[options.part]
        let notes = Self.notes(of: part, with: options)
        guard !notes.isEmpty else { return nil }
        var round = PieceRound(title: piece.title, part: part, notes: notes, order: options.order,
                               barLayout: options.usesWholeBar ? Self.barLayout(of: notes, in: part) : nil,
                               namesTogether: options.chords == .together)
        guard let context = pieceContext(for: round), Self.isSamePiece(round, known: context, as: logged),
              let index = Self.groupIndex(of: replay.lastQuestion, in: round) else { return nil }
        round.groupIndex = index
        let bar = round.barDisplay
        let questions = round.groupNotes.map { Self.question(for: $0, in: bar) }
        guard questions.count == replay.lastQuestion.count,
              zip(questions, replay.lastQuestion).allSatisfy(Self.asks) else { return nil }
        return RebuiltRound(pieceRound: round, roundKey: nil, questions: questions)
    }

    /// Ends the round `replay` tells of as `interrupted`, at its last event, with what it had come
    /// to: it can't come back.
    private func endInterrupted(_ round: UUID, _ replay: RoundReplay) {
        forgetRestoring(round)
        guard let time = replay.lastEventTime else { return }
        let saved = replay.started.flatMap { Self.settings(from: $0.settings) }
        // As other ends have it: sprints on random notes say the best score for their settings.
        let bestScore = saved.flatMap { saved in
            saved.mode == .sprint && replay.started?.piece == nil ? bestScores[Self.bestScoreKey(for: saved)] : nil
        }
        let unanswered = replay.unansweredQuestion.first.map {
            UnansweredQuestion(question: $0.question, shownMs: replay.lastQuestionShownMs, keystrokes: [],
                               pausedMs: replay.lastQuestionPausedMs > 0 ? replay.lastQuestionPausedMs : nil,
                               group: $0.group)
        }
        recorder.record(.roundEnded(RoundEnded(
            round: round, reason: .interrupted, durationMs: replay.activeMs,
            pausedMs: replay.pausedMs > 0 ? replay.pausedMs : nil,
            score: replay.score, attempts: replay.attempts, bestStreak: replay.bestStreak,
            averageResponseMs: replay.averageResponseMs, bestScore: bestScore, isNewBest: false,
            notesToReview: Self.notesToReview(from: replay.misses).map { Self.statKey($0.clef, $0.pitch) },
            unansweredQuestion: unanswered, recordedAt: Date())), at: time)
    }

    /// Clears the device's note that `round` is being brought back, if it's still about that round.
    private func forgetRestoring(_ round: UUID) {
        guard defaults.object(forKey: Keys.restoringRound) as? String == round.uuidString else { return }
        defaults.removeObject(forKey: Keys.restoringRound)
    }

    /// After a crash, as the round resumes: the question that was on screen, asked again as a new
    /// one (the notes asked together, as a new group).
    private func askAgain() {
        guard let question else {
            nextQuestion()
            return
        }
        show((group?.questions ?? [question]).map {
            Question(clef: $0.clef, pitch: $0.pitch, keySignature: $0.keySignature,
                     printedAccidental: $0.printedAccidental, octaveShift: $0.octaveShift)
        }, pickChance: nil)
    }

    /// Settings as `roundStarted` logged them; nil when they don't read.
    private static func settings(from logged: JSONValue) -> Settings? {
        guard case .object = logged, let data = try? JSONEncoder().encode(logged) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: data)
    }

    /// `a` and `b` make the same round: what it asks, how it ends, and the piece open. Naming, the
    /// answer input, hints, sound and looks don't come into it, nor the piece settings: a piece
    /// round is rebuilt from its own.
    private static func shapeRoundsAlike(_ a: Settings, _ b: Settings) -> Bool {
        a.mode == b.mode && a.clefChoice == b.clefChoice && a.range == b.range && a.key == b.key
            && a.addsAccidentals == b.addsAccidentals && a.practiceLimit == b.practiceLimit
            && a.practiceMinutes == b.practiceMinutes && a.practiceNotes == b.practiceNotes
            && a.pieceID == b.pieceID && a.piecePath == b.piecePath
    }

    /// `round`, rebuilt on the piece open now (`current` says how the app knows it), is on the one
    /// the round started on (`logged`): as many notes and bars, and when the round knew the piece
    /// and its file by their hashes, the same ones.
    private static func isSamePiece(_ round: PieceRound, known current: PieceContext, as logged: PieceContext) -> Bool {
        round.notes.count == logged.noteCount && round.bars == logged.measureCount
            && (logged.id == nil || current.id == logged.id) && (logged.file == nil || current.file == logged.file)
    }

    /// Index in `round.groups` of the question `shown` logged (its notes, in order); nil when the
    /// round has no such question.
    private static func groupIndex(of shown: [QuestionShown], in round: PieceRound) -> Int? {
        guard let first = shown.first, let ref = first.pieceNote,
              let index = round.notes.firstIndex(where: { isNote($0, ref, pitch: first.pitch) }),
              let group = round.groups.firstIndex(where: { $0.lowerBound == index }) else { return nil }
        let notes = round.notes[round.groups[group]]
        guard notes.count == shown.count, zip(notes, shown).allSatisfy({ note, shown in
            shown.pieceNote.map { isNote(note, $0, pitch: shown.pitch) } ?? false
        }) else { return nil }
        return group
    }

    /// `note` is the one `ref` points to, with the pitch logged for it.
    private static func isNote(_ note: ScoreNote, _ ref: PieceNoteRef, pitch: LoggedPitch) -> Bool {
        note.measure == ref.measure && note.staff == ref.staff && abs(note.onset - ref.onset) < 1e-6
            && note.chord == ref.chord && note.symbolIndex == ref.symbolIndex && LoggedPitch(note.pitch) == pitch
    }

    /// `question` is the one `shown` logged: clef, pitch, key, printed sign and octave line.
    private static func asks(_ question: Question, as shown: QuestionShown) -> Bool {
        question.clef.rawValue == shown.clef && LoggedPitch(question.pitch) == shown.pitch
            && question.keySignature.fifths == shown.keyFifths
            && question.printedAccidental?.rawValue == shown.printedAccidental && question.octaveShift == shown.octaveShift
    }

    /// The question `shown` logged in a round of random notes; nil when it doesn't read.
    private static func question(from shown: QuestionShown) -> Question? {
        guard let note = RoundReplay.staffNote(of: shown) else { return nil }
        var printed: Accidental?
        if let sign = shown.printedAccidental {
            guard let accidental = Accidental(rawValue: sign) else { return nil }
            printed = accidental
        }
        return Question(clef: note.clef, pitch: note.pitch, keySignature: KeySignature(fifths: shown.keyFifths),
                        printedAccidental: printed, octaveShift: shown.octaveShift)
    }

    // MARK: - Picking notes

    /// The chosen key, or for "random" any key but C major, other than last round's.
    private func pickRoundKey() -> KeySignature {
        switch settings.key {
        case .fixed(let key): key
        case .random: KeySignature.all.filter { $0 != .cMajor && $0 != roundKey }.randomElement()!
        }
    }

    /// Moves on to the next note (or notes asked together), or ends an in-order practice round on
    /// a piece after its last one.
    private func nextQuestion() {
        guard var pieceRound else {
            if let limit = roundNoteLimit, attempts >= limit {
                finish(timeRanOut: false, finishedNotes: true)
                return
            }
            let pick = randomQuestion()
            show([pick.question], pickChance: pick.chance)
            return
        }
        var pickChance: Double?
        switch pieceRound.order {
        case .inOrder:
            // No question yet means the round is just starting.
            let next = question == nil ? 0 : pieceRound.groupIndex + 1
            if next == pieceRound.groups.count, settings.mode == .practice {
                finish(timeRanOut: false, finishedPiece: true)
                return
            }
            // A sprint goes round again from the start bar until time's up.
            pieceRound.groupIndex = next % pieceRound.groups.count
        case .shuffled:
            let pick = shuffledGroup(in: pieceRound)
            pieceRound.groupIndex = pick.index
            pickChance = pick.chance
        }
        self.pieceRound = pieceRound
        let bar = pieceRound.barDisplay
        show(pieceRound.groupNotes.map { Self.question(for: $0, in: bar) }, pickChance: pickChance)
    }

    /// Asks `questions`: one note, or notes asked together as a `group`. `pickChance`: how likely
    /// the weighted pick was to choose it, for the log.
    private func show(_ questions: [Question], pickChance: Double?) {
        question = questions[0]
        group = questions.count > 1 ? NoteGroup(questions: questions) : nil
        questionStart = .now
        questionPaused = .zero
        recordQuestionShown(pickChance: pickChance)
    }

    /// A shuffled round's next question (a note, or notes asked together), weighted like random
    /// rounds and never the one just asked unless the round has no other; and the chance it had
    /// (any of its places). Notes asked together weigh as much as the one that weighs most.
    private func shuffledGroup(in round: PieceRound) -> (index: Int, chance: Double) {
        let previous = question == nil ? nil : round.groupKeys[round.groupIndex]
        let others = round.places.filter { $0.key != previous }
        let candidates = others.isEmpty ? round.places : others
        let pick = Self.weightedIndex(candidates.map { $0.statKeys.map(weight(forStatKey:)).max() ?? 1 })
        return (candidates[pick.index].groups.randomElement()!, pick.chance)
    }

    /// A random note from the toolbar settings, and the chance it had of being picked.
    private func randomQuestion() -> (question: Question, chance: Double) {
        let previous = question
        let key = roundKey ?? .cMajor
        // With added accidentals on, about 30% of notes get a printed sign; the rest follow the key.
        let printsAccidental = settings.addsAccidentals && Double.random(in: 0..<1) < 0.3
        let candidates = settings.clefChoice.clefs.flatMap { clef in
            settings.range.positions.flatMap { position in
                let natural = clef.pitch(atPosition: position)
                let fromKey = key.accidental(for: natural.letter)
                let accidentals = printsAccidental ? Self.printableAccidentals(on: natural.letter, besides: fromKey) : [fromKey]
                // A position with two possible signs splits its share, so every position stays as likely.
                return accidentals.map {
                    (question: Question(clef: clef, pitch: natural.with($0), keySignature: key,
                                        printedAccidental: printsAccidental ? $0 : nil),
                     share: 1 / Double(accidentals.count))
                }
            }
        }.filter { $0.question.clef != previous?.clef || $0.question.pitch != previous?.pitch }

        let weights = candidates.map { $0.share * weight(forStatKey: statKey(for: $0.question)) }
        let pick = Self.weightedIndex(weights)
        return (candidates[pick.index].question, pick.chance)
    }

    /// Notes you've been missing lately come up more often (up to ~5x a mastered note).
    private func weight(forStatKey key: String) -> Double {
        0.4 + 2.5 * (noteStats[key] ?? NoteStat()).recentErrorRate
    }

    /// An index into `weights`, each as likely as its weight, and the chance it had.
    private static func weightedIndex(_ weights: [Double]) -> (index: Int, chance: Double) {
        let total = weights.reduce(0, +)
        var roll = Double.random(in: 0..<total)
        for (index, weight) in weights.enumerated() {
            if roll < weight { return (index, weight / total) }
            roll -= weight
        }
        return (weights.count - 1, weights[weights.count - 1] / total)
    }

    /// Signs that change what the key gives `letter`, short of spelling E♯, B♯, C♭ or F♭.
    private static func printableAccidentals(on letter: NoteLetter, besides fromKey: Accidental) -> [Accidental] {
        Accidental.allCases.filter { accidental in
            switch accidental {
            case fromKey: false
            case .sharp: letter != .e && letter != .b
            case .flat: letter != .c && letter != .f
            case .natural: true
            }
        }
    }

    private func statKey(for question: Question) -> String {
        Self.statKey(question.clef, question.pitch)
    }

    /// "treble.F♯4": what note stats are kept by, in random and piece rounds alike.
    nonisolated private static func statKey(_ clef: Clef, _ pitch: Pitch) -> String {
        "\(clef.rawValue).\(pitch.name)"
    }

    // MARK: - Usage log

    private struct RoundLog {
        let id: UUID
        var questionsShown: Int

        /// A new round; or, brought back after a crash, the round's own id and the questions it had shown.
        init(id: UUID = UUID(), questionsShown: Int = 0) {
            self.id = id
            self.questionsShown = questionsShown
        }
    }

    /// Kept for the question's `answerGiven`. Notes asked together keep one, under the first note.
    private struct QuestionLog {
        let id: UUID
        /// The notes asked together, if they were.
        var group: UUID?
        var keystrokes: [Keystroke] = []
        /// The last keystroke is the key `handleKey` is still handling: its result isn't known yet.
        var keyPending = false
    }

    /// Once per defaults store: the note stats and best scores kept from before there was a log.
    private func recordStatsSnapshotOnce() {
        guard defaults.object(forKey: Keys.usageLogStarted) == nil else { return }
        recorder.record(.statsSnapshot(StatsSnapshot(reason: "beforeUsageLog", noteStats: noteStats,
                                                     bestScores: bestScores)))
        defaults.set(Date(), forKey: Keys.usageLogStarted)
    }

    /// One `settingChanged` per saved value that differs from what was last logged, by its dotted
    /// path in the saved JSON ("naming", "piece.hand", "key.fixed._0.fifths"). Comparing with the
    /// last logged settings rather than `oldValue` logs a change once, already fitted to the piece,
    /// though fitting it re-runs `didSet` from inside.
    private func recordSettingChanges() {
        let saved = JSONValue(encoding: settings)
        guard saved != settingsAsLogged else { return }
        let old = Self.leaves(of: settingsAsLogged), new = Self.leaves(of: saved)
        settingsAsLogged = saved
        for setting in Set(old.keys).union(new.keys).sorted() where old[setting] != new[setting] {
            recorder.record(.settingChanged(SettingChanged(setting: setting, from: old[setting] ?? .null,
                                                           to: new[setting] ?? .null)))
        }
    }

    /// `value`'s leaves by dotted path. Arrays and empty objects are leaves; a key that's missing
    /// (an optional setting that's nil) has none.
    private static func leaves(of value: JSONValue, at path: String = "") -> [String: JSONValue] {
        guard case .object(let members) = value, !members.isEmpty else { return [path: value] }
        return members.reduce(into: [:]) { leaves, member in
            leaves.merge(Self.leaves(of: member.value, at: path.isEmpty ? member.key : "\(path).\(member.key)")) { $1 }
        }
    }

    private func recordRoundStart(via source: StartSource) {
        let roundLog = RoundLog()
        self.roundLog = roundLog
        recorder.record(.roundStarted(RoundStarted(
            round: roundLog.id, via: source, settings: JSONValue(encoding: settings),
            keyFifths: (pieceRound.map { $0.notes[0].keySignature } ?? roundKey ?? .cMajor).fifths,
            piece: pieceRound.flatMap(pieceContext(for:)))))
    }

    private func pieceContext(for round: PieceRound) -> PieceContext? {
        guard let piece, let part = piecePart else { return nil }
        let options = settings.piece
        return PieceContext(title: piece.title, path: pieceURL?.path ?? "", part: part.name, partIndex: options.part,
                            hand: options.hand.rawValue, order: options.order.rawValue, startBar: options.startBar,
                            oneNotePerChord: options.oneNotePerChord, noteCount: round.notes.count,
                            measureCount: part.measureCount, chords: options.chords.rawValue, libraryID: pieceEntryID)
    }

    /// One `questionShown` per note on screen: notes asked together are logged one by one, with
    /// their group's id and size. `pickChance` is the question's.
    private func recordQuestionShown(pickChance: Double?) {
        guard let question, let roundLog else { return }
        questionLog = QuestionLog(id: question.id, group: group?.id)
        let questions = group?.questions ?? [question]
        let notes = pieceRound.map { Array($0.groupNotes) }
        let bar = pieceRound?.barDisplay
        for (offset, question) in questions.enumerated() {
            let index = roundLog.questionsShown + offset
            let note = notes.flatMap { $0.indices.contains(offset) ? $0[offset] : nil }
            recorder.record(.questionShown(QuestionShown(
                round: roundLog.id, question: question.id, index: index,
                clef: question.clef.rawValue, pitch: LoggedPitch(question.pitch), written: LoggedPitch(question.writtenPitch),
                position: question.position, keyFifths: question.keySignature.fifths,
                // As drawn: in the bar view, the bar's sign.
                printedAccidental: question.printedAccidental?.rawValue, octaveShift: question.octaveShift,
                pieceNote: note.map {
                    PieceNoteRef(measure: $0.measure, staff: $0.staff, onset: $0.onset, chord: $0.chord, symbolIndex: $0.symbolIndex)
                },
                pickChance: pickChance, naming: settings.naming.rawValue, input: settings.answerInput.rawValue,
                hintsVisible: settings.showHints,
                // Key names are only drawn on the piano.
                keyNamesVisible: settings.answerInput == .piano && settings.showKeyNames,
                barView: pieceRound.map { _ in bar != nil }, barStaves: bar?.staves.map(\.number),
                group: group?.id, groupSize: group?.questions.count)))
        }
        self.roundLog?.questionsShown += questions.count
    }

    /// Adds a key to the keystrokes of the question on screen, if one is up and not yet answered;
    /// what the key does then settles its result.
    private func noteKeystroke(_ key: String) {
        questionLog?.keystrokes.append(Keystroke(key: key, ms: activeMilliseconds(since: questionStart), result: .other))
        questionLog?.keyPending = true
    }

    /// What the key being handled did; only the first call for a key counts.
    private func settleKeystroke(_ result: KeystrokeResult) {
        guard var log = questionLog, log.keyPending else { return }
        log.keystrokes[log.keystrokes.count - 1].result = result
        log.keyPending = false
        questionLog = log
    }

    private func recordAnswer(_ response: Flash, to question: Question, via source: AnswerSource) {
        settleKeystroke(.submitted) // when a key sent the answer
        guard let roundLog, let questionLog else { return }
        self.questionLog = nil
        recorder.record(.answerGiven(AnswerGiven(
            round: roundLog.id, question: questionLog.id, responseMs: activeMilliseconds(since: questionStart),
            source: source, letter: response.letter.name, accidental: response.accidental.rawValue,
            // Names leave the octave out, so any will do for a named answer.
            name: settings.naming.name(of: response.pitch ?? Pitch(response.letter, 4, response.accidental)),
            pitch: response.pitch.map(LoggedPitch.init), correct: response.isCorrect,
            wrongOctave: response.pitch.map {
                $0.pitchClass == question.pitch.pitchClass && $0.midiNumber != question.pitch.midiNumber
            },
            keystrokes: questionLog.keystrokes, scoreAfter: score, streakAfter: streak,
            pausedMs: pausedMilliseconds(questionPaused))))
    }

    /// One `answerGiven` per note asked together, each right or wrong on its own, with the entry
    /// judged with it. They share the response time, source, score and streak after the group;
    /// the keystrokes go with the first note.
    private func recordGroupAnswer(_ group: NoteGroup, via source: AnswerSource) {
        settleKeystroke(.submitted) // when a key sent the answer
        guard let roundLog, let questionLog, let result = group.result else { return }
        self.questionLog = nil
        let responseMs = activeMilliseconds(since: questionStart)
        let pausedMs = pausedMilliseconds(questionPaused)
        for (offset, question) in group.questions.enumerated() {
            let entry = group.entries[result.entryIndices[offset]]
            recorder.record(.answerGiven(AnswerGiven(
                round: roundLog.id, question: question.id, responseMs: responseMs, source: source,
                letter: entry.letter.name, accidental: entry.accidental.rawValue,
                name: settings.naming.name(of: entry.pitch ?? Pitch(entry.letter, 4, entry.accidental)),
                pitch: entry.pitch.map(LoggedPitch.init), correct: result.isRight[offset],
                wrongOctave: entry.pitch.map {
                    $0.pitchClass == question.pitch.pitchClass && $0.midiNumber != question.pitch.midiNumber
                },
                keystrokes: offset == 0 ? questionLog.keystrokes : [], scoreAfter: score, streakAfter: streak,
                pausedMs: pausedMs, group: group.id, groupSize: group.questions.count)))
        }
    }

    private func recordPause(via source: PauseSource) {
        guard let roundLog else { return }
        recorder.record(.roundPaused(RoundPaused(round: roundLog.id, question: questionLog?.id, via: source,
                                                 activeMs: activeMilliseconds(since: roundStart))))
    }

    private func recordResume(via source: PauseSource, after pause: Duration) {
        guard let roundLog else { return }
        recorder.record(.roundResumed(RoundResumed(round: roundLog.id, question: questionLog?.id, via: source,
                                                   pausedMs: Self.milliseconds(pause))))
    }

    private func recordIgnored(_ reason: String, from source: AnswerSource, detail: String) {
        recorder.record(.inputIgnored(InputIgnored(round: roundLog?.id, reason: reason, source: source, detail: detail)))
    }

    /// Ends the round being logged, if there is one. `isNewBest`: a finished sprint set a best score.
    private func recordRoundEnd(_ reason: RoundEndReason, isNewBest: Bool = false) {
        guard let roundLog else { return }
        let unanswered = questionLog.map {
            UnansweredQuestion(question: $0.id, shownMs: activeMilliseconds(since: questionStart), keystrokes: $0.keystrokes,
                               pausedMs: pausedMilliseconds(questionPaused), group: $0.group)
        }
        self.roundLog = nil
        questionLog = nil
        recorder.record(.roundEnded(RoundEnded(
            round: roundLog.id, reason: reason, durationMs: activeMilliseconds(since: roundStart), pausedMs: pausedMilliseconds(roundPaused),
            score: score, attempts: attempts, bestStreak: bestStreak,
            averageResponseMs: averageResponseTime.map { Int(($0 * 1000).rounded()) },
            bestScore: settings.mode == .sprint ? bestScore : nil, isNewBest: isNewBest,
            notesToReview: notesToReview.map { Self.statKey($0.clef, $0.pitch) },
            unansweredQuestion: unanswered)))
    }

    private func recordPieceOpened(_ score: Score, from url: URL, libraryID: UUID?, restoredSettings: Bool,
                                   pieceSettings: PieceSettings, libraryError: String?, via source: PieceOpenSource) {
        recorder.record(.pieceOpened(PieceOpened(
            path: url.path, title: score.title, via: source,
            parts: score.parts.map {
                PartInfo(name: $0.name, notes: $0.notes.count, measures: $0.measureCount, staves: $0.staffCount,
                         skipped: $0.skippedNoteCount)
            },
            libraryID: libraryID, restoredSettings: restoredSettings, pieceSettings: JSONValue(encoding: pieceSettings),
            libraryError: libraryError)))
    }

    private func recordPieceOpenFailed(_ path: String, libraryID: UUID? = nil, via source: PieceOpenSource, _ error: String) {
        recorder.record(.pieceOpenFailed(PieceOpenFailed(path: path, via: source, error: error, libraryID: libraryID)))
    }

    /// How the log writes a key: the character it types, or a name for keys that type none.
    private static func keyName(characters: String, keyCode: UInt16) -> String {
        switch keyCode {
        case 36: return "Return"
        case 76: return "Enter"
        case 49: return "Space"
        case 53: return "Escape"
        case 51: return "Delete"
        case 48: return "Tab"
        default:
            // Arrows and function keys come as private-use characters.
            let printable = !characters.isEmpty && characters.unicodeScalars.allSatisfy {
                ![.control, .privateUse].contains($0.properties.generalCategory)
            }
            return printable ? characters : "key \(keyCode)"
        }
    }

    // MARK: - Persistence

    private enum Keys {
        static let settings = "settings"
        static let noteStats = "noteStats"
        static let bestScores = "bestScores"
        /// When the usage log first saw this store (and took its stats snapshot).
        static let usageLogStarted = "usageLogStarted"
        /// The device's note that a round is being brought back after a crash: its id, from just
        /// before it's rebuilt until it has settled back in (`restoreSettles`).
        static let restoringRound = "restoringRound"
    }

    private static func load<T: Decodable>(_ type: T.Type, from key: String, in defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func save<T: Encodable>(_ value: T, as key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

// MARK: - Typing notes named together

extension Game {
    /// How typed text reads as the names of `count` notes asked together: names back to back in
    /// any order ("sisol", "fa♯do", "dodo"), each a name with an optional ♯ or ♭ after it.
    ///
    /// With letter names "b" is both the note B and a flat, so the text is read with the count in
    /// mind: for three notes "ebg" is E B G, for two it's E♭ G. Typed "#" is stored as ♯; a "b" (or
    /// ♭) after a name may be its flat.
    struct TypedNames: Equatable {
        /// Every way to read the whole text as exactly `count` names, in a fixed order (a "b" read
        /// as a flat before it's read as B).
        let readings: [[NoteName]]
        /// The text can lead to `count` names: some reading has at most that many whole names, or
        /// fewer and the start of one more. A keystroke that makes it false is refused.
        let isViable: Bool
        /// Something longer could still read as `count` names: another name, a longer name, or a
        /// ♯/♭ after the last one.
        let canGrow: Bool
        /// The reading the typing box shows: all the names if the text reads as them (the first
        /// such reading), otherwise the fewest whole names, then what's left of the text, the start
        /// of a name ("s" on the way to "sol").
        let shown: [NoteName]
        let rest: String

        /// The text reads as all the names and nothing longer could follow: it submits by itself.
        var submitsAtOnce: Bool { !readings.isEmpty && !canGrow }
        /// The text reads as all the names, but something longer could follow: Return submits it.
        var needsReturn: Bool { !readings.isEmpty && canGrow }

        /// `answers`: everything that can be typed as one name, lowercased, signs as ♯ and ♭
        /// (`Game.typeableAnswers`).
        init(_ text: String, count: Int, answers: [(text: String, letter: NoteLetter, accidental: Accidental)]) {
            let typed = Array(text.lowercased())
            let forms = answers.map { (form: Array($0.text), name: NoteName(letter: $0.letter, accidental: $0.accidental)) }
            // A ♭ in a name is typed as "b" or "♭".
            func same(_ form: Character, _ key: Character) -> Bool { form == key || (form == "♭" && key == "b") }
            func fits(_ form: [Character], at position: Int) -> Bool {
                position + form.count <= typed.count && form.indices.allSatisfy { same(form[$0], typed[position + $0]) }
            }
            // The text from `position` on is the start of a name, short of all of it.
            func starts(at position: Int) -> Bool {
                let rest = typed.count - position
                return forms.contains { candidate in
                    candidate.form.count > rest && (0..<rest).allSatisfy { same(candidate.form[$0], typed[position + $0]) }
                }
            }

            var whole: [[NoteName]] = []
            var partial: [(names: [NoteName], rest: String)] = []
            var canGrow = false
            func read(from position: Int, _ names: [NoteName]) {
                if position == typed.count { whole.append(names) }
                if names.count < count, starts(at: position) {
                    canGrow = true
                    if position < typed.count { partial.append((names, String(typed[position...]))) }
                }
                guard names.count < count else { return }
                for (form, name) in forms where fits(form, at: position) {
                    read(from: position + form.count, names + [name])
                }
            }
            read(from: 0, [])

            readings = whole.filter { $0.count == count }
            isViable = !whole.isEmpty || !partial.isEmpty
            self.canGrow = canGrow
            if let all = readings.first {
                (shown, rest) = (all, "")
            } else if let fewest = whole.min(by: { $0.count < $1.count }) {
                (shown, rest) = (fewest, "")
            } else if let fewest = partial.min(by: { $0.names.count < $1.names.count }) {
                (shown, rest) = fewest
            } else {
                (shown, rest) = ([], text)
            }
        }
    }
}
