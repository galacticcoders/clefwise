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
        var naming = NamingSystem.letters
        var answerInput = AnswerInput.buttons
        var showHints = false
        /// Write note names on the piano keys.
        var showKeyNames = false
        var isMuted = false
        var key = KeyChoice.fixed(.cMajor)
        /// Now and then print a ♯, ♭ or ♮ in front of a note, on top of the key signature.
        var addsAccidentals = false
        var piece = PieceSettings()
        /// The last piece opened, reopened at launch.
        var piecePath: String?

        init() {}

        /// Missing keys fall back to defaults, so settings saved by older versions still load.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            clefChoice = try container.decodeIfPresent(ClefChoice.self, forKey: .clefChoice) ?? clefChoice
            range = try container.decodeIfPresent(NoteRange.self, forKey: .range) ?? range
            mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? mode
            naming = try container.decodeIfPresent(NamingSystem.self, forKey: .naming) ?? naming
            answerInput = try container.decodeIfPresent(AnswerInput.self, forKey: .answerInput) ?? answerInput
            showHints = try container.decodeIfPresent(Bool.self, forKey: .showHints) ?? showHints
            showKeyNames = try container.decodeIfPresent(Bool.self, forKey: .showKeyNames) ?? showKeyNames
            isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? isMuted
            key = try container.decodeIfPresent(KeyChoice.self, forKey: .key) ?? key
            addsAccidentals = try container.decodeIfPresent(Bool.self, forKey: .addsAccidentals) ?? addsAccidentals
            piece = try container.decodeIfPresent(PieceSettings.self, forKey: .piece) ?? piece
            piecePath = try container.decodeIfPresent(String.self, forKey: .piecePath) ?? piecePath
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

        /// Index into the score's parts.
        var part = 0
        /// Right hand = upper staff, left hand = lower; ignored for single-staff parts.
        var hand = Hand.right
        var order = Order.inOrder
        /// Bar to start from (1-based), so a long piece can be practised a section at a time.
        var startBar = 1
        /// Only the top note of right-hand chords and the bottom note of left-hand ones.
        var oneNotePerChord = false
        /// Draw the whole bar the note is in, as the score has it, rather than the note on its own.
        var showsWholeBar = true

        init() {}

        /// Missing keys fall back to defaults, like `Settings`.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            part = try container.decodeIfPresent(Int.self, forKey: .part) ?? part
            hand = try container.decodeIfPresent(Hand.self, forKey: .hand) ?? hand
            order = try container.decodeIfPresent(Order.self, forKey: .order) ?? order
            startBar = try container.decodeIfPresent(Int.self, forKey: .startBar) ?? startBar
            oneNotePerChord = try container.decodeIfPresent(Bool.self, forKey: .oneNotePerChord) ?? oneNotePerChord
            showsWholeBar = try container.decodeIfPresent(Bool.self, forKey: .showsWholeBar) ?? showsWholeBar
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
    /// What's been typed so far towards a note name, in keyboard mode.
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
    private(set) var pieceURL: URL?
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
        /// Shuffled rounds draw a note (as stats count them: clef and pitch), then one of its places
        /// in `notes`, so a note the piece repeats often isn't asked any more often for it.
        let places: [(statKey: String, indices: [Int])]
        /// Index in `notes` of the note being asked.
        var index = 0

        init(title: String, part: ScorePart, notes: [ScoreNote], order: PieceSettings.Order, barLayout: BarLayout?) {
            self.title = title
            self.part = part
            self.notes = notes
            bars = part.measureCount
            self.order = order
            self.barLayout = barLayout
            guard order == .shuffled else {
                places = []
                return
            }
            places = Dictionary(grouping: notes.indices) { Game.statKey(notes[$0].clef, notes[$0].pitch) }
                .map { ($0.key, $0.value) }
        }

        /// The note being asked.
        var note: ScoreNote { notes[index] }

        /// The bar the note being asked is in, as the bar view draws it; nil when it's shown on its own.
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
            return Game.barDisplay(for: note, in: part, layout: barLayout, isAsked: true, answered: answered)
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
    @ObservationIgnored private var advancesOnResume = false
    @ObservationIgnored private let synth = Synth()
    /// Where usage events go (the usage log on disk in the app; memory in tests).
    @ObservationIgnored let recorder: UsageRecorder
    /// The saved settings as last logged, to tell which ones a change touched.
    @ObservationIgnored private var settingsAsLogged = JSONValue.null
    /// The round being logged, from `roundStarted` to `roundEnded`.
    @ObservationIgnored private var roundLog: RoundLog?
    /// The question on screen, from `questionShown` until it's answered.
    @ObservationIgnored private var questionLog: QuestionLog?

    /// `defaults` is where settings, note stats and best scores are kept, `recorder` where usage
    /// events go; tests pass their own.
    init(defaults: UserDefaults = .standard, recorder: UsageRecorder = UsageLog.shared) {
        self.defaults = defaults
        self.recorder = recorder
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
    var timeRemaining: TimeInterval { max(0, Self.sprintLength - elapsed) }
    var accuracy: Double? { attempts > 0 ? Double(score) / Double(attempts) : nil }
    /// Pieces don't keep best scores: a score on one piece says little about another.
    var bestScore: Int? { isPractisingPiece ? nil : bestScores[bestScoreKey] }
    /// Each answer method plays differently (the piano needs the octave, typing takes keystrokes),
    /// and so do key signatures and printed accidentals, so each setup keeps its own best scores.
    /// Plain C major adds nothing, so scores saved before keys existed still count.
    private var bestScoreKey: String {
        var key = "\(settings.clefChoice.rawValue).\(settings.range.rawValue)"
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

    /// In keyboard mode: the typed text is a whole name but could still get a ♯/♭, so it waits for Return.
    var typingNeedsReturn: Bool {
        let answers = typeableAnswers
        return answers.contains { $0.text == typedText }
            && answers.contains { $0.text != typedText && $0.text.hasPrefix(typedText) }
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
    /// being asked, between rounds the bar the next one starts in. Nil shows one note at a time:
    /// for random notes, with the setting off (as it was when the round started), when the part
    /// has no bar layout, or when a staff to draw has a clef that can't be drawn there.
    var barDisplay: BarDisplay? {
        if let pieceRound { return pieceRound.barDisplay }
        guard piece != nil, settings.piece.showsWholeBar, let part = piecePart, let selectedBarLayout,
              let first = selectedNotes.first else { return nil }
        return Self.barDisplay(for: first, in: part, layout: selectedBarLayout, isAsked: false, answered: [])
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

    /// The question for a piece note: in the bar view it prints the sign the bar prints (a sign
    /// earlier in the bar carries on), on its own the note's `printedAccidental`.
    private static func question(for note: ScoreNote, in bar: BarDisplay?) -> Question {
        guard let bar, let current = bar.current else { return note.question }
        return Question(clef: note.clef, pitch: note.pitch, keySignature: note.keySignature,
                        printedAccidental: bar.measure.symbols[current].accidental, octaveShift: note.octaveShift)
    }

    /// Staff positions the staff has to fit for the round's notes (both clefs), so it doesn't
    /// rescale from note to note; nil when they fit the usual layout (three ledger lines either
    /// side), and for random rounds.
    var staffPositionsToFit: ClosedRange<Int>? {
        let positions = pieceNotes.map(\.question.position)
        guard let low = positions.min(), let high = positions.max() else { return nil }
        let usual = NoteRange.threeLedgerLines.positions
        return low < usual.lowerBound || high > usual.upperBound ? low...high : nil
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

    /// Reads a MusicXML file and switches to practising it, or sets `pieceError`. `source` says
    /// how the file was picked, for the usage log.
    func openPiece(at url: URL, via source: PieceOpenSource = .menu) {
        do {
            open(try MusicXMLImporter.load(from: url), from: url, via: source)
        } catch {
            pieceError = error.localizedDescription
            recordPieceOpenFailed(url.path, via: source, error.localizedDescription)
        }
    }

    /// Switches to practising `score` (also how tests and previews load one without a file).
    /// A round in progress is dropped without a summary. Reopening the same file keeps its
    /// piece settings; another file starts from bar 1.
    func open(_ score: Score, from url: URL, via source: PieceOpenSource = .menu) {
        guard !score.parts.isEmpty else {
            pieceError = Self.noNotesMessage
            recordPieceOpenFailed(url.path, via: source, Self.noNotesMessage)
            return
        }
        abandonRound()
        recordPieceOpened(score, from: url, via: source)
        piece = score
        pieceURL = url
        pieceError = nil
        var newSettings = settings
        if url.path != settings.piecePath { newSettings.piece.startBar = 1 }
        newSettings.piece = Self.fitting(newSettings.piece, to: score)
        newSettings.piecePath = url.path
        settings = newSettings
        updateSelection()
    }

    /// Back to random notes; a round in progress is dropped without a summary.
    func closePiece() {
        abandonRound()
        recorder.record(.pieceClosed(PieceClosed(path: pieceURL?.path)))
        piece = nil
        pieceURL = nil
        pieceError = nil
        settings.piecePath = nil
        updateSelection()
    }

    private static let noNotesMessage = "There are no notes to practise in this file."

    /// At launch, picks up last session's piece. One that's gone or no longer reads is quietly
    /// forgotten (only the log hears why): nobody just asked to open it.
    private func reopenLastPiece() {
        guard let path = settings.piecePath else { return }
        let url = URL(fileURLWithPath: path)
        let failure: String
        if !FileManager.default.isReadableFile(atPath: path) {
            failure = "The file is gone or can't be read."
        } else {
            do {
                let score = try MusicXMLImporter.load(from: url)
                if !score.parts.isEmpty {
                    open(score, from: url, via: .launch)
                    return
                }
                failure = Self.noNotesMessage
            } catch {
                failure = error.localizedDescription
            }
        }
        recordPieceOpenFailed(path, via: .launch, failure)
        settings.piecePath = nil
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
    /// staff, and with one note per chord only its top note on the upper staff (the melody)
    /// and its bottom one on the lower (the bass).
    private static func notes(of part: ScorePart, with options: PieceSettings) -> [ScoreNote] {
        var notes = part.notes.filter { $0.measure >= options.startBar }
        if part.staffCount > 1 {
            switch options.hand {
            case .right: notes = notes.filter { $0.staff == 1 }
            case .left: notes = notes.filter { $0.staff == 2 }
            case .both: break
            }
        }
        guard options.oneNotePerChord else { return notes }
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
            [settings.range.positions.lowerBound, settings.range.positions.upperBound]
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
                                    barLayout: settings.piece.showsWholeBar ? selectedBarLayout : nil)
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
        typedText = ""
        armedAccidental = .natural
        isShowingMiss = false
        question = nil
        phase = .playing
        roundStart = .now
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        recordRoundStart(via: source)
        nextQuestion()
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
    }

    func dismissSummary() {
        summary = nil
        phase = .idle
    }

    /// Note-button click: the letter plus whichever ♯/♭ is armed.
    func answer(_ letter: NoteLetter) {
        pressNoteButton(letter, via: .click)
    }

    /// Answers with a note name, as if clicked; any octave counts.
    func answer(_ letter: NoteLetter, _ accidental: Accidental) {
        answerName(letter, accidental, via: .click)
    }

    /// Answers with a piano key, so the octave has to be right too. Compared by sound, so the
    /// black key counts whether the question spells it C♯ or D♭.
    func answer(_ pitch: Pitch) {
        guard let question = questionTakingAnswers(from: .piano, detail: pitch.name) else { return }
        submit(Flash(letter: pitch.letter, accidental: pitch.accidental, pitch: pitch,
                     isCorrect: question.pitch.midiNumber == pitch.midiNumber),
               to: question, via: .piano)
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
            } else if settings.answerInput == .keyboard, accidentalsPossible {
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

    /// Adds a typed character; answers as soon as the text is a whole answer nothing longer starts
    /// with (a bare "f" might still become "f♯", so that one waits for Return). Keystrokes that
    /// can't lead to any answer are dropped rather than counted as wrong, so typos aren't punished.
    private func type(_ character: Character) {
        guard !isPaused, !isShowingMiss else {
            recordIgnored(isPaused ? "paused" : "missPause", from: .typing, detail: String(character))
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
        if extensions.count == 1, let match = extensions.first, match.text == text {
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

    /// Return in keyboard mode: answers with a whole name that was waiting for a possible ♯/♭.
    private func confirmTyping() {
        guard !isShowingMiss, !typedText.isEmpty else { return }
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
        if settings.mode == .sprint, seconds >= Self.sprintLength {
            elapsed = Self.sprintLength
            finish(timeRanOut: true)
        }
    }

    /// `finishedPiece`: an in-order practice round got past the piece's last note.
    private func finish(timeRanOut: Bool, finishedPiece: Bool = false) {
        stopClock()
        isShowingMiss = false
        flash = nil
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
        recordRoundEnd(timeRanOut ? .timeUp : finishedPiece ? .pieceComplete : .stopped, isNewBest: isNewBest)
        clearPause()
        // A practice round stopped before any answer has nothing to sum up.
        guard attempts > 0 || settings.mode == .sprint else {
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
            finishedPiece: finishedPiece
        )
        phase = .finished
    }

    private var averageResponseTime: TimeInterval? {
        responseTimes.isEmpty ? nil : responseTimes.reduce(0, +) / Double(responseTimes.count)
    }

    /// The round's most missed notes, at most four. F and F♯ share a staff position, so pitch
    /// height breaks the tie.
    private var notesToReview: [StaffNote] {
        roundMisses
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

    // MARK: - Picking notes

    /// The chosen key, or for "random" any key but C major, other than last round's.
    private func pickRoundKey() -> KeySignature {
        switch settings.key {
        case .fixed(let key): key
        case .random: KeySignature.all.filter { $0 != .cMajor && $0 != roundKey }.randomElement()!
        }
    }

    /// Moves on to the next note, or ends an in-order practice round on a piece after its last note.
    private func nextQuestion() {
        guard var pieceRound else {
            let pick = randomQuestion()
            show(pick.question, pickChance: pick.chance)
            return
        }
        var pickChance: Double?
        switch pieceRound.order {
        case .inOrder:
            // No question yet means the round is just starting.
            let next = question == nil ? 0 : pieceRound.index + 1
            if next == pieceRound.notes.count, settings.mode == .practice {
                finish(timeRanOut: false, finishedPiece: true)
                return
            }
            // A sprint goes round again from the start bar until time's up.
            pieceRound.index = next % pieceRound.notes.count
        case .shuffled:
            let pick = shuffledIndex(in: pieceRound)
            pieceRound.index = pick.index
            pickChance = pick.chance
        }
        self.pieceRound = pieceRound
        show(Self.question(for: pieceRound.note, in: pieceRound.barDisplay), pickChance: pickChance)
    }

    /// `pickChance`: how likely the weighted pick was to choose this note, for the log.
    private func show(_ question: Question, pickChance: Double?) {
        self.question = question
        questionStart = .now
        questionPaused = .zero
        recordQuestionShown(pickChance: pickChance)
    }

    /// A shuffled round's next note, weighted like random rounds and never the one just asked
    /// unless the round has no other; and the chance the note had (any of its places).
    private func shuffledIndex(in round: PieceRound) -> (index: Int, chance: Double) {
        let previous = question.map { Self.statKey($0.clef, $0.pitch) }
        let others = round.places.filter { $0.statKey != previous }
        let candidates = others.isEmpty ? round.places : others
        let pick = Self.weightedIndex(candidates.map { weight(forStatKey: $0.statKey) })
        return (candidates[pick.index].indices.randomElement()!, pick.chance)
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
        let id = UUID()
        var questionsShown = 0
    }

    /// Kept for the question's `answerGiven`.
    private struct QuestionLog {
        let id: UUID
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
                            measureCount: part.measureCount)
    }

    private func recordQuestionShown(pickChance: Double?) {
        guard let question, let roundLog else { return }
        questionLog = QuestionLog(id: question.id)
        self.roundLog?.questionsShown += 1
        let note = pieceRound?.note
        let bar = pieceRound?.barDisplay
        recorder.record(.questionShown(QuestionShown(
            round: roundLog.id, question: question.id, index: roundLog.questionsShown,
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
            barView: pieceRound.map { _ in bar != nil }, barStaves: bar?.staves.map(\.number))))
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
                               pausedMs: pausedMilliseconds(questionPaused))
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

    private func recordPieceOpened(_ score: Score, from url: URL, via source: PieceOpenSource) {
        recorder.record(.pieceOpened(PieceOpened(
            path: url.path, title: score.title, via: source,
            parts: score.parts.map {
                PartInfo(name: $0.name, notes: $0.notes.count, measures: $0.measureCount, staves: $0.staffCount,
                         skipped: $0.skippedNoteCount)
            })))
    }

    private func recordPieceOpenFailed(_ path: String, via source: PieceOpenSource, _ error: String) {
        recorder.record(.pieceOpenFailed(PieceOpenFailed(path: path, via: source, error: error)))
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
    }

    private static func load<T: Decodable>(_ type: T.Type, from key: String, in defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func save<T: Encodable>(_ value: T, as key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
