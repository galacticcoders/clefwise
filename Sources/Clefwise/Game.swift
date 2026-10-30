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

    enum Phase { case idle, playing, finished }

    /// Brief highlight on the answer key that was just pressed.
    struct Flash: Equatable {
        let letter: NoteLetter
        let isCorrect: Bool
        let id = UUID()
    }

    struct Settings: Codable {
        var clefChoice = ClefChoice.treble
        var range = NoteRange.staff
        var mode = Mode.sprint
        var naming = NamingSystem.letters
        var showHints = false
        var isMuted = false

        init() {}

        /// Missing keys fall back to defaults, so settings saved by older versions still load.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            clefChoice = try container.decodeIfPresent(ClefChoice.self, forKey: .clefChoice) ?? clefChoice
            range = try container.decodeIfPresent(NoteRange.self, forKey: .range) ?? range
            mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? mode
            naming = try container.decodeIfPresent(NamingSystem.self, forKey: .naming) ?? naming
            showHints = try container.decodeIfPresent(Bool.self, forKey: .showHints) ?? showHints
            isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? isMuted
        }
    }

    static let sprintLength: TimeInterval = 60
    private static let missPause: Duration = .milliseconds(1200)
    private static let correctFlash: Duration = .milliseconds(250)

    var settings: Settings {
        didSet { Self.save(settings, as: Keys.settings) }
    }

    private(set) var phase = Phase.idle
    private(set) var question: Question?
    /// True while a missed note is shown in red with its name before moving on.
    private(set) var isShowingMiss = false
    private(set) var flash: Flash?
    private(set) var score = 0
    private(set) var attempts = 0
    private(set) var streak = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var summary: RoundSummary?
    private var bestScores: [String: Int]

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
    private var bestScoreKey: String { "\(settings.clefChoice.rawValue).\(settings.range.rawValue)" }

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

    func answer(_ letter: NoteLetter) {
        guard phase == .playing, !isShowingMiss, let question else { return }
        let isCorrect = question.pitch.letter == letter
        attempts += 1
        noteStats[statKey(for: question), default: NoteStat()].record(isCorrect)
        Self.save(noteStats, as: Keys.noteStats)
        showFlash(Flash(letter: letter, isCorrect: isCorrect), for: isCorrect ? Self.correctFlash : Self.missPause)

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
            if phase != .playing { start() }
            return true
        default:
            break
        }
        guard let character = characters.lowercased().first else { return false }
        // 1–7 always answer by key position; typed letters only make sense with letter names.
        if let digit = character.wholeNumberValue, let letter = NoteLetter(rawValue: digit - 1) {
            answer(letter)
            return true
        }
        if settings.naming == .letters, let letter = NoteLetter(character: character) {
            answer(letter)
            return true
        }
        switch character {
        case "h": settings.showHints.toggle()
        case "m": settings.isMuted.toggle()
        default: return false
        }
        return true
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
        let review = roundMisses
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.pitch.diatonicIndex < $1.key.pitch.diatonicIndex }
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

    private func nextQuestion() {
        let previous = question
        let candidates = settings.clefChoice.clefs.flatMap { clef in
            settings.range.positions.map { Question(clef: clef, pitch: clef.pitch(atPosition: $0)) }
        }.filter { $0.clef != previous?.clef || $0.pitch != previous?.pitch }

        // Notes you've been missing lately come up more often (up to ~5x a mastered note).
        let weights = candidates.map { 0.4 + 2.5 * (noteStats[statKey(for: $0)] ?? NoteStat()).recentErrorRate }
        var roll = Double.random(in: 0..<weights.reduce(0, +))
        var choice = candidates[candidates.count - 1]
        for (candidate, weight) in zip(candidates, weights) {
            if roll < weight {
                choice = candidate
                break
            }
            roll -= weight
        }
        question = choice
        questionStart = Date()
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
