import Foundation
import Observation

/// Per-note history used to bring up notes you struggle with more often.
struct NoteStat: Codable {
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

        init() {}

        /// Missing keys fall back to defaults, like `Settings`.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            part = try container.decodeIfPresent(Int.self, forKey: .part) ?? part
            hand = try container.decodeIfPresent(Hand.self, forKey: .hand) ?? hand
            order = try container.decodeIfPresent(Order.self, forKey: .order) ?? order
            startBar = try container.decodeIfPresent(Int.self, forKey: .startBar) ?? startBar
            oneNotePerChord = try container.decodeIfPresent(Bool.self, forKey: .oneNotePerChord) ?? oneNotePerChord
        }
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
        }
    }

    private(set) var phase = Phase.idle
    private(set) var question: Question?
    /// True while a missed note is shown in red with its name before moving on.
    private(set) var isShowingMiss = false
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
    /// The round in progress when it's on a piece; nil between rounds and in random rounds.
    private var pieceRound: PieceRound?

    /// A round on a piece, fixed at `start()`: later changes to the piece settings wait for the next one.
    private struct PieceRound {
        let title: String
        let notes: [ScoreNote]
        let bars: Int
        let order: PieceSettings.Order
        /// Shuffled rounds draw a note (as stats count them: clef and pitch), then one of its places
        /// in `notes`, so a note the piece repeats often isn't asked any more often for it.
        let places: [(statKey: String, indices: [Int])]
        /// Index in `notes` of the note being asked.
        var index = 0

        init(title: String, notes: [ScoreNote], bars: Int, order: PieceSettings.Order) {
            self.title = title
            self.notes = notes
            self.bars = bars
            self.order = order
            guard order == .shuffled else {
                places = []
                return
            }
            places = Dictionary(grouping: notes.indices) { Game.statKey(notes[$0].clef, notes[$0].pitch) }
                .map { ($0.key, $0.value) }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var noteStats: [String: NoteStat]
    @ObservationIgnored private var bestStreak = 0
    @ObservationIgnored private var roundMisses: [StaffNote: Int] = [:]
    @ObservationIgnored private var responseTimes: [TimeInterval] = []
    @ObservationIgnored private var roundStart = Date()
    @ObservationIgnored private var questionStart = Date()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pendingAdvance: Task<Void, Never>?
    @ObservationIgnored private let synth = Synth()

    /// `defaults` is where settings, note stats and best scores are kept; tests pass their own.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.load(Settings.self, from: Keys.settings, in: defaults) ?? Settings()
        noteStats = Self.load([String: NoteStat].self, from: Keys.noteStats, in: defaults) ?? [:]
        bestScores = Self.load([String: Int].self, from: Keys.bestScores, in: defaults) ?? [:]
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
        return PieceProgress(bar: pieceRound.notes[pieceRound.index].measure, bars: pieceRound.bars,
                             done: pieceRound.order == .inOrder ? pieceRound.index : attempts,
                             total: pieceRound.notes.count)
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

    /// Reads a MusicXML file and switches to practising it, or sets `pieceError`.
    func openPiece(at url: URL) {
        do {
            open(try MusicXMLImporter.load(from: url), from: url)
        } catch {
            pieceError = error.localizedDescription
        }
    }

    /// Switches to practising `score` (also how tests and previews load one without a file).
    /// A round in progress is dropped without a summary. Reopening the same file keeps its
    /// piece settings; another file starts from bar 1.
    func open(_ score: Score, from url: URL) {
        guard !score.parts.isEmpty else {
            pieceError = "There are no notes to practise in this file."
            return
        }
        abandonRound()
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
        piece = nil
        pieceURL = nil
        pieceError = nil
        settings.piecePath = nil
        updateSelection()
    }

    /// At launch, picks up last session's piece. One that's gone or no longer reads is quietly
    /// forgotten: nobody just asked to open it.
    private func reopenLastPiece() {
        guard let path = settings.piecePath else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.isReadableFile(atPath: path),
           let score = try? MusicXMLImporter.load(from: url), !score.parts.isEmpty {
            open(score, from: url)
        } else {
            settings.piecePath = nil
        }
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
    /// settings leave no notes), otherwise on random notes from the toolbar settings.
    func start() {
        if let piece, let part = piecePart {
            guard !selectedNotes.isEmpty else {
                pieceError = emptySelectionMessage
                return
            }
            pieceError = nil
            pieceRound = PieceRound(title: piece.title, notes: selectedNotes, bars: part.measureCount,
                                    order: settings.piece.order)
        } else {
            pieceRound = nil
            roundKey = pickRoundKey()
        }
        stopClock()
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
        roundStart = Date()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        nextQuestion()
    }

    func stop() {
        guard phase == .playing else { return }
        finish(timeRanOut: false)
    }

    func dismissSummary() {
        summary = nil
        phase = .idle
    }

    /// Note-button press: the letter plus whichever ♯/♭ is armed. Presses that can't count (during
    /// the pause after a miss, or a combination with no name like komal Sa) leave the armed sign alone.
    func answer(_ letter: NoteLetter) {
        guard phase == .playing, !isShowingMiss, settings.naming.hasName(letter, armedAccidental) else { return }
        let accidental = armedAccidental
        armedAccidental = .natural
        answer(letter, accidental)
    }

    /// Answers with a note name (buttons and typing); any octave counts. Combinations with no name
    /// of their own are ignored rather than judged by sound, so "komal Sa" never passes for Ni.
    func answer(_ letter: NoteLetter, _ accidental: Accidental) {
        guard let question, settings.naming.hasName(letter, accidental) else { return }
        submit(Flash(letter: letter, accidental: accidental, pitch: nil,
                     isCorrect: settings.naming.accepts(letter, accidental, for: question.pitch)))
    }

    /// Answers with a piano key, so the octave has to be right too. Compared by sound, so the
    /// black key counts whether the question spells it C♯ or D♭.
    func answer(_ pitch: Pitch) {
        guard let question else { return }
        submit(Flash(letter: pitch.letter, accidental: pitch.accidental, pitch: pitch,
                     isCorrect: question.pitch.midiNumber == pitch.midiNumber))
    }

    /// Arms ♯ or ♭ for the next note button; choosing the armed one again disarms it.
    func toggleArmedAccidental(_ accidental: Accidental) {
        armedAccidental = armedAccidental == accidental ? .natural : accidental
    }

    private func submit(_ response: Flash) {
        guard phase == .playing, !isShowingMiss, let question else { return }
        let isCorrect = response.isCorrect
        attempts += 1
        noteStats[statKey(for: question), default: NoteStat()].record(isCorrect)
        save(noteStats, as: Keys.noteStats)
        showFlash(response, for: isCorrect ? Self.correctFlash : Self.missPause)

        if isCorrect {
            score += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            responseTimes.append(Date().timeIntervalSince(questionStart))
            if !settings.isMuted { synth.play(question.pitch) }
            nextQuestion()
        } else {
            streak = 0
            roundMisses[StaffNote(clef: question.clef, pitch: question.pitch), default: 0] += 1
            if !settings.isMuted { synth.playMiss() }
            isShowingMiss = true
            pendingAdvance = Task { [weak self] in
                try? await Task.sleep(for: Self.missPause)
                guard let self, !Task.isCancelled, self.phase == .playing else { return }
                self.isShowingMiss = false
                self.nextQuestion()
            }
        }
    }

    /// Handles a key press; returns false to let the system handle it instead.
    func handleKey(characters: String, keyCode: UInt16) -> Bool {
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
                start()
            } else if keyCode != 49, settings.answerInput == .keyboard, accidentalsPossible {
                confirmTyping()
            }
            return true
        case 51 where settings.answerInput == .keyboard: // Delete (backspace)
            if !typedText.isEmpty { typedText.removeLast() }
            return true
        default:
            break
        }
        guard let character = characters.lowercased().first else { return false }
        // In keyboard mode every letter typed during a round goes towards a note name, and so
        // does a ♯/♭ sign when notes can have one ("b" is a letter already).
        if settings.answerInput == .keyboard, phase == .playing,
           character.isLetter || (accidentalsPossible && "#♯♭".contains(character)) {
            type(character)
            return true
        }
        // Typing can't pick an octave, so these shortcuts only answer in button mode.
        // 1–7 answer by button position; typed letters only make sense with letter names.
        // # or = arms a sharp and - a flat: "b" has to stay the note B.
        if settings.answerInput == .buttons {
            if accidentalsPossible, let accidental = Self.armingKeys[character] {
                if phase == .playing { toggleArmedAccidental(accidental) }
                return true
            }
            if let digit = character.wholeNumberValue, let letter = NoteLetter(rawValue: digit - 1) {
                answer(letter)
                return true
            }
            if settings.naming == .letters, let letter = NoteLetter(character: character) {
                answer(letter)
                return true
            }
        }
        switch character {
        case "h": settings.showHints.toggle()
        case "k" where settings.answerInput == .piano: settings.showKeyNames.toggle()
        case "m": settings.isMuted.toggle()
        default: return false
        }
        return true
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
        guard !isShowingMiss else { return }
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
            answer(match.letter, match.accidental)
        } else if !extensions.isEmpty {
            typedText = text
        } else {
            rejectedKeystrokes += 1
        }
    }

    /// Return in keyboard mode: answers with a whole name that was waiting for a possible ♯/♭.
    private func confirmTyping() {
        guard !isShowingMiss, !typedText.isEmpty else { return }
        if let match = typeableAnswers.first(where: { $0.text == typedText }) {
            typedText = ""
            answer(match.letter, match.accidental)
        } else {
            rejectedKeystrokes += 1
        }
    }

    private func tick() {
        let now = Date().timeIntervalSince(roundStart)
        // Only publish whole-second changes so the UI doesn't redraw ten times a second.
        if Int(now) != Int(elapsed) { elapsed = now }
        if settings.mode == .sprint, now >= Self.sprintLength {
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
        guard attempts > 0 || settings.mode == .sprint else {
            phase = .idle
            return
        }

        var isNewBest = false
        if pieceRound == nil, settings.mode == .sprint, score > (bestScores[bestScoreKey] ?? 0) {
            bestScores[bestScoreKey] = score
            save(bestScores, as: Keys.bestScores)
            isNewBest = true
        }
        // F and F♯ share a staff position, so pitch height breaks the tie.
        let review = roundMisses
            .sorted {
                $0.value != $1.value ? $0.value > $1.value
                    : ($0.key.pitch.diatonicIndex, $0.key.pitch.midiNumber) < ($1.key.pitch.diatonicIndex, $1.key.pitch.midiNumber)
            }
            .prefix(4)
            .map(\.key)
        summary = RoundSummary(
            mode: settings.mode,
            score: score,
            attempts: attempts,
            bestStreak: bestStreak,
            averageSeconds: responseTimes.isEmpty ? nil : responseTimes.reduce(0, +) / Double(responseTimes.count),
            bestScore: pieceRound == nil && settings.mode == .sprint ? bestScores[bestScoreKey] : nil,
            isNewBest: isNewBest,
            timeRanOut: timeRanOut,
            notesToReview: review,
            mixedClefs: pieceRound.map { round in round.notes.contains { $0.clef != round.notes[0].clef } }
                ?? (settings.clefChoice == .both),
            pieceTitle: pieceRound?.title,
            finishedPiece: finishedPiece
        )
        phase = .finished
    }

    /// Drops the round in progress, or the last one's summary, without scoring it: for when the
    /// piece it's on is closed or replaced.
    private func abandonRound() {
        stopClock()
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
            question = randomQuestion()
            questionStart = Date()
            return
        }
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
            pieceRound.index = shuffledIndex(in: pieceRound)
        }
        self.pieceRound = pieceRound
        question = pieceRound.notes[pieceRound.index].question
        questionStart = Date()
    }

    /// A shuffled round's next note, weighted like random rounds and never the one just asked
    /// unless the round has no other.
    private func shuffledIndex(in round: PieceRound) -> Int {
        let previous = question.map { Self.statKey($0.clef, $0.pitch) }
        let others = round.places.filter { $0.statKey != previous }
        let candidates = others.isEmpty ? round.places : others
        let choice = candidates[Self.weightedIndex(candidates.map { weight(forStatKey: $0.statKey) })]
        return choice.indices.randomElement()!
    }

    private func randomQuestion() -> Question {
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
        return candidates[Self.weightedIndex(weights)].question
    }

    /// Notes you've been missing lately come up more often (up to ~5x a mastered note).
    private func weight(forStatKey key: String) -> Double {
        0.4 + 2.5 * (noteStats[key] ?? NoteStat()).recentErrorRate
    }

    /// An index into `weights`, each as likely as its weight.
    private static func weightedIndex(_ weights: [Double]) -> Int {
        var roll = Double.random(in: 0..<weights.reduce(0, +))
        for (index, weight) in weights.enumerated() {
            if roll < weight { return index }
            roll -= weight
        }
        return weights.count - 1
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

    // MARK: - Persistence

    private enum Keys {
        static let settings = "settings"
        static let noteStats = "noteStats"
        static let bestScores = "bestScores"
    }

    private static func load<T: Decodable>(_ type: T.Type, from key: String, in defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func save<T: Encodable>(_ value: T, as key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
