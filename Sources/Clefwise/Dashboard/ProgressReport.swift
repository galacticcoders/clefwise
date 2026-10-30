import Foundation

/// What the dashboard shows: a time window, and which clef's notes count. Every number on the
/// dashboard is computed for the same filter, so they always agree.
struct ProgressFilter: Equatable, Codable {
    enum Range: String, CaseIterable, Identifiable, Codable {
        case week, month, quarter, all

        var id: Self { self }
        var label: String {
            switch self {
            case .week: "Last 7 days"
            case .month: "Last 30 days"
            case .quarter: "Last 90 days"
            case .all: "All time"
            }
        }
        /// Local days in the window, today included; nil for all time.
        var days: Int? {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            case .all: nil
            }
        }
    }

    enum ClefFilter: String, CaseIterable, Identifiable, Codable {
        case all, treble, bass

        var id: Self { self }
        var label: String {
            switch self {
            case .all: "All clefs"
            case .treble: "Treble"
            case .bass: "Bass"
            }
        }
    }

    var range = Range.month
    var clef = ClefFilter.all
}

/// Everything the dashboard draws, worked out from the usage log for one filter.
struct ProgressReport: Equatable {
    var filter: ProgressFilter
    var generatedAt: Date
    /// Start of the window's first local day; nil for all time.
    var periodStart: Date?
    var totals: ProgressTotals
    /// The same-length window just before this one, for "vs previous period"; nil for all time.
    var previousTotals: ProgressTotals?
    /// Local days in a row with at least one answer, ending today (or yesterday, so a streak isn't
    /// broken before today's practice), and the longest run ever. Not limited by the filter.
    var currentStreakDays: Int
    var longestStreakDays: Int
    /// Every local day in the window, practised or not, oldest first. All time: from the first
    /// day with an answer.
    var days: [DayProgress]
    /// The note map: one per clef and written staff position answered at least once.
    var positions: [PositionProgress]
    /// One per clef and spelled pitch (F♯5 apart from F5), for "most missed" and "slowest".
    var pitches: [PitchProgress]
    /// By answer method ("buttons", "piano", "keyboard") and by naming system ("letters"…),
    /// as `Game.AnswerInput` / `NamingSystem` raw values.
    var byInput: [BreakdownRow]
    var byNaming: [BreakdownRow]
    /// Pieces practised in the window, most recently practised first.
    var pieces: [PieceProgressSummary]
    /// Rounds in the window, newest first, at most 50.
    var recentRounds: [RecentRound]
    /// Answers from before detailed tracking began (the one-off stats snapshot): counted in the
    /// all-time note map and pitch lists only, as they have no dates or times.
    var answersBeforeTracking: Int
    /// Usage log lines that couldn't be read.
    var unreadableLines: Int

    var isEmpty: Bool { totals.answers == 0 && answersBeforeTracking == 0 }

    static func empty(_ filter: ProgressFilter, at now: Date = Date()) -> ProgressReport {
        ProgressReport(filter: filter, generatedAt: now, periodStart: nil, totals: ProgressTotals(),
                       previousTotals: nil, currentStreakDays: 0, longestStreakDays: 0, days: [], positions: [],
                       pitches: [], byInput: [], byNaming: [], pieces: [], recentRounds: [],
                       answersBeforeTracking: 0, unreadableLines: 0)
    }
}

struct ProgressTotals: Equatable {
    var answers = 0
    var correct = 0
    var rounds = 0
    /// Time spent in rounds.
    var practiceSeconds: Double = 0
    var daysPractised = 0
    /// Median time to a correct answer; nil without any.
    var medianResponseMs: Int?

    var accuracy: Double? { answers > 0 ? Double(correct) / Double(answers) : nil }
}

struct DayProgress: Equatable, Identifiable {
    /// Start of the local day.
    var day: Date
    var answers: Int
    var correct: Int
    var practiceSeconds: Double
    var medianResponseMs: Int?

    var id: Date { day }
    var accuracy: Double? { answers > 0 ? Double(correct) / Double(answers) : nil }
}

struct PositionProgress: Equatable, Identifiable {
    var clef: Clef
    /// Written staff position: 0 = bottom line, each step a line or space.
    var position: Int
    /// The natural note on that line or space (E4 on the treble bottom line); the counts include
    /// its sharps and flats.
    var natural: Pitch
    var attempts: Int
    var correct: Int
    var medianResponseMs: Int?
    /// Of `attempts`, how many come from before detailed tracking (no times, all-time only).
    var attemptsBeforeTracking: Int

    var id: String { "\(clef.rawValue)\(position)" }
    var accuracy: Double? { attempts > 0 ? Double(correct) / Double(attempts) : nil }
}

struct PitchProgress: Equatable, Identifiable {
    var clef: Clef
    var pitch: Pitch
    var attempts: Int
    var correct: Int
    var medianResponseMs: Int?

    var id: String { "\(clef.rawValue).\(pitch.name)" }
    var accuracy: Double? { attempts > 0 ? Double(correct) / Double(attempts) : nil }
}

struct BreakdownRow: Equatable, Identifiable {
    var key: String
    var answers: Int
    var correct: Int
    var medianResponseMs: Int?

    var id: String { key }
    var accuracy: Double? { answers > 0 ? Double(correct) / Double(answers) : nil }
}

struct PieceProgressSummary: Equatable, Identifiable {
    var title: String
    var path: String
    var lastPractised: Date
    var rounds: Int
    var answers: Int
    var correct: Int
    /// Bars in the part last practised, when known.
    var measureCount: Int?
    /// Bars with at least one answer, in order.
    var bars: [BarProgress]

    var id: String { path }
    var accuracy: Double? { answers > 0 ? Double(correct) / Double(answers) : nil }
}

struct BarProgress: Equatable, Identifiable {
    var bar: Int
    var attempts: Int
    var correct: Int

    var id: Int { bar }
    var accuracy: Double? { attempts > 0 ? Double(correct) / Double(attempts) : nil }
}

struct RecentRound: Equatable, Identifiable {
    var id: UUID
    var started: Date
    var durationMs: Int?
    /// `Game.Mode`, `Game.AnswerInput` and `NamingSystem` raw values.
    var mode: String
    var input: String
    var naming: String
    /// What was practised: "Treble · On the staff · G major", or a piece's title and hand.
    var description: String
    var score: Int
    var attempts: Int
    /// Nil when the round never ended in the log (the app crashed).
    var endReason: RoundEndReason?

    var accuracy: Double? { attempts > 0 ? Double(score) / Double(attempts) : nil }
}

// MARK: - Sample data

extension ProgressReport {
    /// A plausible two months of practice, for building and checking the dashboard without a
    /// real log. Deterministic for a given seed.
    static func sample(seed: UInt64 = 7, now: Date = Date(), calendar: Calendar = .current) -> ProgressReport {
        var random = SeededRandom(seed: seed)
        let today = calendar.startOfDay(for: now)
        // Accuracy and speed improve over the weeks; some days are skipped.
        let days: [DayProgress] = (0..<60).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            guard random.next() > 0.25 else { return DayProgress(day: day, answers: 0, correct: 0, practiceSeconds: 0, medianResponseMs: nil) }
            let progress = Double(60 - back) / 60
            let answers = 20 + Int(random.next() * 120)
            let accuracy = min(0.98, 0.62 + 0.3 * progress + (random.next() - 0.5) * 0.08)
            return DayProgress(day: day, answers: answers, correct: Int(Double(answers) * accuracy),
                               practiceSeconds: Double(answers) * (2.4 - progress),
                               medianResponseMs: Int(2400 - 1300 * progress + (random.next() - 0.5) * 300))
        }
        let window = Array(days.suffix(30))
        func totals(_ days: ArraySlice<DayProgress>) -> ProgressTotals {
            let practised = days.filter { $0.answers > 0 }
            return ProgressTotals(answers: practised.map(\.answers).reduce(0, +), correct: practised.map(\.correct).reduce(0, +),
                                  rounds: practised.count * 2, practiceSeconds: practised.map(\.practiceSeconds).reduce(0, +),
                                  daysPractised: practised.count,
                                  medianResponseMs: practised.compactMap(\.medianResponseMs).sorted().dropFirst(practised.count / 2).first)
        }
        let positions: [PositionProgress] = Clef.allCases.flatMap { clef in
            (-6...14).compactMap { position -> PositionProgress? in
                // Ledger notes are seen less and known less well.
                let ledger = position < 0 || position > 8
                guard !ledger || random.next() > 0.3 else { return nil }
                let attempts = ledger ? 3 + Int(random.next() * 20) : 30 + Int(random.next() * 90)
                let accuracy = ledger ? 0.45 + random.next() * 0.35 : 0.75 + random.next() * 0.23
                return PositionProgress(clef: clef, position: position, natural: clef.pitch(atPosition: position),
                                        attempts: attempts, correct: Int(Double(attempts) * accuracy),
                                        medianResponseMs: Int(ledger ? 1800 + random.next() * 1500 : 700 + random.next() * 900),
                                        attemptsBeforeTracking: 0)
            }
        }
        let pitches: [PitchProgress] = positions.flatMap { position -> [PitchProgress] in
            var spelled = [PitchProgress(clef: position.clef, pitch: position.natural, attempts: position.attempts,
                                         correct: position.correct, medianResponseMs: position.medianResponseMs)]
            if position.natural.letter == .f {
                spelled.append(PitchProgress(clef: position.clef, pitch: position.natural.with(.sharp), attempts: 25,
                                             correct: 14, medianResponseMs: 2100))
            }
            return spelled
        }
        let rounds: [RecentRound] = (0..<24).map { index in
            let attempts = 15 + Int(random.next() * 30)
            return RecentRound(id: UUID(), started: now.addingTimeInterval(-Double(index) * 5400), durationMs: 60_000,
                            mode: index % 3 == 0 ? "practice" : "sprint", input: ["buttons", "piano", "keyboard"][index % 3],
                            naming: index % 4 == 0 ? "solfege" : "letters",
                            description: index % 5 == 0 ? "Minuet in G · Right hand" : "Treble · On the staff · G major",
                            score: Int(Double(attempts) * (0.7 + random.next() * 0.28)), attempts: attempts,
                            endReason: index % 3 == 0 ? .stopped : .timeUp)
        }
        let bars = (1...16).map { BarProgress(bar: $0, attempts: 6 + Int(random.next() * 10), correct: 0) }
            .map { BarProgress(bar: $0.bar, attempts: $0.attempts, correct: Int(Double($0.attempts) * (0.55 + random.next() * 0.45))) }
        return ProgressReport(
            filter: ProgressFilter(), generatedAt: now, periodStart: window.first?.day,
            totals: totals(window[...]), previousTotals: totals(days.dropLast(30).suffix(30)),
            currentStreakDays: 4, longestStreakDays: 11, days: window, positions: positions, pitches: pitches,
            byInput: [BreakdownRow(key: "buttons", answers: 1240, correct: 1130, medianResponseMs: 980),
                      BreakdownRow(key: "piano", answers: 610, correct: 480, medianResponseMs: 1650),
                      BreakdownRow(key: "keyboard", answers: 320, correct: 290, medianResponseMs: 1420)],
            byNaming: [BreakdownRow(key: "letters", answers: 1700, correct: 1520, medianResponseMs: 1100),
                       BreakdownRow(key: "solfege", answers: 470, correct: 380, medianResponseMs: 1500)],
            pieces: [PieceProgressSummary(title: "Minuet in G", path: "/tmp/minuet.mxl", lastPractised: now.addingTimeInterval(-7200),
                                          rounds: 6, answers: bars.map(\.attempts).reduce(0, +),
                                          correct: bars.map(\.correct).reduce(0, +), measureCount: 16, bars: bars)],
            recentRounds: rounds, answersBeforeTracking: 0, unreadableLines: 0)
    }
}

/// A small deterministic generator (SplitMix64), so sample data is the same every run.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// Uniform in 0..<1.
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}
