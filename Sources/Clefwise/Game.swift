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
        }
    }

    static let sprintLength: TimeInterval = 60
    private static let missPause: Duration = .milliseconds(1200)
    private static let correctFlash: Duration = .milliseconds(250)

    var settings: Settings {
        didSet {
            if settings.naming != oldValue.naming { typedText = "" }
            // Between rounds the staff shows the newly chosen key instead of the last round's.
            if settings.key != oldValue.key, phase != .playing { roundKey = nil }
            Self.save(settings, as: Keys.settings)
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

    @ObservationIgnored private var noteStats: [String: NoteStat]
    @ObservationIgnored private var bestStreak = 0
    @ObservationIgnored private var roundMisses: [StaffNote: Int] = [:]
    @ObservationIgnored private var responseTimes: [TimeInterval] = []
    @ObservationIgnored private var roundStart = Date()
    @ObservationIgnored private var questionStart = Date()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pendingAdvance: Task<Void, Never>?
    @ObservationIgnored private let synth = Synth()

    init() {
        settings = Self.load(Settings.self, from: Keys.settings) ?? Settings()
        noteStats = Self.load([String: NoteStat].self, from: Keys.noteStats) ?? [:]
        bestScores = Self.load([String: Int].self, from: Keys.bestScores) ?? [:]
    }

    /// The clef on screen: the current question's, or the first selected clef between rounds.
    var displayedClef: Clef { question?.clef ?? settings.clefChoice.clefs[0] }
    var timeRemaining: TimeInterval { max(0, Self.sprintLength - elapsed) }
    var accuracy: Double? { attempts > 0 ? Double(score) / Double(attempts) : nil }
    var bestScore: Int? { bestScores[bestScoreKey] }
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
    /// round (C major when the choice is random).
    var currentKeySignature: KeySignature {
        if let question { return question.keySignature }
        if let roundKey { return roundKey }
        if case .fixed(let key) = settings.key { return key }
        return .cMajor
    }

    /// Whether questions can be sharp or flat, so the answer inputs need a way to say so.
    var accidentalsPossible: Bool {
        settings.addsAccidentals || settings.key != .fixed(.cMajor)
    }

    /// In keyboard mode: the typed text is a whole name but could still get a ♯/♭, so it waits for Return.
    var typingNeedsReturn: Bool {
        let answers = typeableAnswers
        return answers.contains { $0.text == typedText }
            && answers.contains { $0.text != typedText && $0.text.hasPrefix(typedText) }
    }

    /// White keys (as diatonic indices) for the piano: whole octaves covering every note the settings can ask.
    var pianoKeys: ClosedRange<Int> {
        let indices = settings.clefChoice.clefs.flatMap { clef in
            [settings.range.positions.lowerBound, settings.range.positions.upperBound]
                .map { clef.pitch(atPosition: $0).diatonicIndex }
        }
        return (indices.min()! / 7 * 7)...(indices.max()! / 7 * 7 + 6)
    }

    // MARK: - Round flow

    func start() {
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
        roundKey = pickRoundKey()
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
    /// the pause after a miss) leave the armed sign alone.
    func answer(_ letter: NoteLetter) {
        guard phase == .playing, !isShowingMiss else { return }
        let accidental = armedAccidental
        armedAccidental = .natural
        answer(letter, accidental)
    }

    /// Answers with a note name (buttons and typing); any octave counts.
    func answer(_ letter: NoteLetter, _ accidental: Accidental) {
        guard let question else { return }
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
        Self.save(noteStats, as: Keys.noteStats)
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
            return accidentals.map { (name + ($0 == .natural ? "" : $0.symbol), letter, $0) }
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

    private func finish(timeRanOut: Bool) {
        stopClock()
        isShowingMiss = false
        flash = nil
        typedText = ""
        armedAccidental = .natural
        question = nil
        guard attempts > 0 || settings.mode == .sprint else {
            phase = .idle
            return
        }

        var isNewBest = false
        if settings.mode == .sprint, score > (bestScores[bestScoreKey] ?? 0) {
            bestScores[bestScoreKey] = score
            Self.save(bestScores, as: Keys.bestScores)
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
            bestScore: settings.mode == .sprint ? bestScores[bestScoreKey] : nil,
            isNewBest: isNewBest,
            timeRanOut: timeRanOut,
            notesToReview: review,
            mixedClefs: settings.clefChoice == .both
        )
        phase = .finished
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

    private func nextQuestion() {
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

        // Notes you've been missing lately come up more often (up to ~5x a mastered note).
        let weights = candidates.map {
            $0.share * (0.4 + 2.5 * (noteStats[statKey(for: $0.question)] ?? NoteStat()).recentErrorRate)
        }
        var roll = Double.random(in: 0..<weights.reduce(0, +))
        var choice = candidates[candidates.count - 1].question
        for (candidate, weight) in zip(candidates, weights) {
            if roll < weight {
                choice = candidate.question
                break
            }
            roll -= weight
        }
        question = choice
        questionStart = Date()
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
        "\(question.clef.rawValue).\(question.pitch.name)"
    }

    // MARK: - Persistence

    private enum Keys {
        static let settings = "settings"
        static let noteStats = "noteStats"
        static let bestScores = "bestScores"
    }

    private static func load<T: Decodable>(_ type: T.Type, from key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, as key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
