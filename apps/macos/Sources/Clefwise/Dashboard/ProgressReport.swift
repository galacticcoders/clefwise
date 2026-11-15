import Foundation

/// What the dashboard shows: a time window, which clef's notes count, and which answer method's.
/// Every number on the dashboard is computed for the same filter, so they always agree.
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

    /// Raw values are `Clef`'s: `treble8vb` is the guitar clef, offered only once there are answers
    /// in it (`choices`).
    enum ClefFilter: String, CaseIterable, Identifiable, Codable {
        case all, treble, bass, treble8vb

        var id: Self { self }
        var label: String {
            switch self {
            case .all: "All clefs"
            case .treble: "Treble"
            case .bass: "Bass"
            case .treble8vb: Clef.treble8vb.name
            }
        }

        /// The choices to offer: All, Treble and Bass as always, and Guitar once `report` has answers
        /// in the guitar clef, or when it's the one `selected`.
        static func choices(for report: ProgressReport, selected: ClefFilter) -> [ClefFilter] {
            let hasGuitar = report.clefsPractised.contains(.treble8vb) || report.positions.contains { $0.clef == .treble8vb }
            return hasGuitar || selected == .treble8vb ? [.all, .treble, .bass, .treble8vb] : [.all, .treble, .bass]
        }
    }

    var range = Range.month
    var clef = ClefFilter.all
    /// Only answers given this way; nil for every method (the default).
    var method: AnswerMethod? = nil

    /// The methods to offer besides All: every one with an answer in the journal
    /// (`ProgressReport.methodsPractised`), and the one `selected`, in `AnswerMethod` order.
    static func methodChoices(for report: ProgressReport, selected: AnswerMethod?) -> [AnswerMethod] {
        AnswerMethod.allCases.filter { report.methodsPractised.contains($0) || $0 == selected }
    }
}

extension ProgressFilter {
    /// Tolerant: a range or clef this version doesn't know (saved by a later one) falls back to its
    /// default alone.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = (try? container.decodeIfPresent(Range.self, forKey: .range)) ?? .month
        clef = (try? container.decodeIfPresent(ClefFilter.self, forKey: .clef)) ?? .all
        method = (try? container.decodeIfPresent(AnswerMethod.self, forKey: .method)) ?? nil
    }
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
    /// By answer method and by naming system ("letters"…): keys are `AnswerMethod` and
    /// `NamingSystem` raw values (answers on a real piano under `midi`, `BreakdownRow.realPianoKey`).
    var byInput: [BreakdownRow]
    var byNaming: [BreakdownRow]
    /// `byInput` for the same-length window just before this one, for each method's change; nil
    /// for all time.
    var previousByInput: [BreakdownRow]? = nil
    /// Pieces practised in the window, most recently practised first.
    var pieces: [PieceProgressSummary]
    /// Rounds in the window, newest first, at most 50.
    var recentRounds: [RecentRound]
    /// Response times beyond the median: spread, shape, mistakes by speed, the previous note's pull.
    var responseTimes = ResponseTimes()
    /// Answers from before detailed tracking began (the stats snapshots, one per device, added up):
    /// counted in the all-time note map and pitch lists only, as they have no dates or times.
    var answersBeforeTracking: Int
    /// Lines in the practice journal's files (or, read the old way, the usage log) that couldn't be
    /// read, and so are left out.
    var unreadableLines: Int
    /// Every clef with an answer anywhere in the journal, whatever the filter (all time, every
    /// clef): it decides which clef filters to offer, so the Guitar one shows once there are answers
    /// in the guitar clef.
    var clefsPractised: Set<Clef> = []
    /// Every answer method with an answer anywhere in the journal, whatever the filter: it decides
    /// which methods the filter offers (`ProgressFilter.methodChoices`).
    var methodsPractised: Set<AnswerMethod> = []

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
    /// The lower and upper quartiles of the day's right answers to single notes (`ResponseTimes`
    /// says which answers): the middle half of its times lies between them. Nil without any.
    var lowerQuartileMs: Int? = nil
    var upperQuartileMs: Int? = nil
    /// The day's answers by method, in `AnswerMethod` order, only methods with an answer that day.
    /// Their answers add up to `answers` but for answers in an input this version doesn't know.
    var methods: [MethodDay] = []

    var id: Date { day }
    var accuracy: Double? { answers > 0 ? Double(correct) / Double(answers) : nil }
    /// How far apart the middle half of the day's times are: upper minus lower quartile.
    var spreadMs: Int? { lowerQuartileMs.flatMap { lower in upperQuartileMs.map { $0 - lower } } }
}

/// One answer method's part of a day (`DayProgress.methods`), counted as the day is.
struct MethodDay: Equatable, Identifiable {
    var method: AnswerMethod
    var answers: Int
    var correct: Int
    /// Median time of its right answers (notes named together included, as the day's).
    var medianResponseMs: Int?
    /// Quartiles of its right answers to single notes, as the day's.
    var lowerQuartileMs: Int? = nil
    var upperQuartileMs: Int? = nil
    /// Its right answers to single notes: how many times the quartiles come from.
    var rightSingleNotes = 0

    /// A method's point on a trend needs at least this many: answers for its accuracy, right
    /// answers for its typical time, right single notes for its spread. Fewer is a gap.
    static let minimumForTrend = 5

    var id: AnswerMethod { method }
    var accuracy: Double? { answers > 0 ? Double(correct) / Double(answers) : nil }
    var spreadMs: Int? { lowerQuartileMs.flatMap { lower in upperQuartileMs.map { $0 - lower } } }
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
    /// How fast it's named now: the median time of its last `recentWindow` right answers to single
    /// notes in the window (fewer when there aren't that many), and how many that is. Nil and 0
    /// without any.
    var recentMedianResponseMs: Int? = nil
    var recentRightAnswers = 0

    /// How many of the latest right answers make "now" for a place.
    static let recentWindow = 20

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

    /// The `byInput` key for answers on a real piano (source `midi`): they count apart from the
    /// piano on screen.
    static let realPianoKey = AnswerMethod.realPiano.rawValue

    /// What an answer method is called on the dashboard: "Note buttons", "Real piano".
    static func inputLabel(_ key: String) -> String {
        AnswerMethod(rawValue: key)?.label ?? key.capitalized
    }
}

struct PieceProgressSummary: Equatable, Identifiable {
    /// From the round practised last.
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
    /// The piece's id in the practice journal (the SHA-256 of the file it was first added with),
    /// whatever path each Mac practised it from; nil for a piece known only by its path.
    var pieceID: String? = nil

    /// The journal's id for the piece, or failing that its path.
    var id: String { pieceID ?? path }
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
    /// The round was a 60-second sprint, which versions until 2026-11-07 had beside practice
    /// rounds (`RoundStarted.wasSprint`); every other round is a practice round.
    var wasSprint = false
    /// `Game.AnswerInput` and `NamingSystem` raw values.
    var input: String
    var naming: String
    /// What was practised: "Treble · On the staff · G major", or a piece's title and hand.
    var description: String
    var score: Int
    var attempts: Int
    /// Nil when the round never ended (the app crashed): only when read the old way, from the usage
    /// log. Every run in the journal has its end, `interrupted` after a crash it didn't come back from.
    var endReason: RoundEndReason?
    /// A practice round's limit: "5 min", "100 notes"; nil without one.
    var practiceLength: String? = nil
    /// Its answers on a real piano (source `midi`), every answer of the round counted, whatever the
    /// filter: with `input` `piano`, Recent Rounds says which piano it was played on.
    var realPianoAnswers = 0

    var accuracy: Double? { attempts > 0 ? Double(score) / Double(attempts) : nil }

    /// What Recent Rounds calls it: "Practice", "Practice · 5 min", or for a sprint from before
    /// 2026-11-07 "60s Sprint", as the app called it then.
    var modeLabel: String {
        let label = wasSprint ? "60s Sprint" : "Practice"
        return practiceLength.map { "\(label) · \($0)" } ?? label
    }
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
            // The spread draws together faster than the median falls.
            let median = Int(2400 - 1300 * progress + (random.next() - 0.5) * 300)
            let halfSpread = Int(900 - 700 * progress + (random.next() - 0.5) * 120)
            return DayProgress(day: day, answers: answers, correct: Int(Double(answers) * accuracy),
                               practiceSeconds: Double(answers) * (2.4 - progress), medianResponseMs: median,
                               lowerQuartileMs: max(250, median - halfSpread * 2 / 3), upperQuartileMs: median + halfSpread)
        }
        .enumerated().map { sampleMethods($1, daysAgo: 59 - $0) }
        let window = Array(days.suffix(30))
        func totals(_ days: ArraySlice<DayProgress>) -> ProgressTotals {
            let practised = days.filter { $0.answers > 0 }
            return ProgressTotals(answers: practised.map(\.answers).reduce(0, +), correct: practised.map(\.correct).reduce(0, +),
                                  rounds: practised.count * 2, practiceSeconds: practised.map(\.practiceSeconds).reduce(0, +),
                                  daysPractised: practised.count,
                                  medianResponseMs: practised.compactMap(\.medianResponseMs).sorted().dropFirst(practised.count / 2).first)
        }
        // Treble and bass only, as before the guitar clef, so the demo stays the same.
        let positions: [PositionProgress] = [Clef.treble, .bass].flatMap { clef in
            (-6...14).compactMap { position -> PositionProgress? in
                // Ledger notes are seen less and known less well.
                let ledger = position < 0 || position > 8
                guard !ledger || random.next() > 0.3 else { return nil }
                let attempts = ledger ? 3 + Int(random.next() * 20) : 30 + Int(random.next() * 90)
                let accuracy = ledger ? 0.45 + random.next() * 0.35 : 0.75 + random.next() * 0.23
                let median = Int(ledger ? 1800 + random.next() * 1500 : 700 + random.next() * 900)
                let correct = Int(Double(attempts) * accuracy)
                return PositionProgress(clef: clef, position: position, natural: clef.pitch(atPosition: position),
                                        attempts: attempts, correct: correct, medianResponseMs: median,
                                        attemptsBeforeTracking: 0,
                                        // Faster now than over the whole window.
                                        recentMedianResponseMs: correct > 0 ? Int(Double(median) * (0.6 + random.next() * 0.3)) : nil,
                                        recentRightAnswers: min(correct, PositionProgress.recentWindow))
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
            let isPiece = index % 5 == 0
            // Some rounds of random notes are timed; pieces end with their last note.
            let isTimed = !isPiece && index % 3 != 0
            return RecentRound(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!, started: now.addingTimeInterval(-Double(index) * 5400),
                            durationMs: isTimed ? 120_000 : 60_000, input: ["buttons", "piano", "keyboard"][index % 3],
                            naming: index % 4 == 0 ? "solfege" : "letters",
                            description: isPiece ? "Minuet in G · Right hand" : "Treble · On the staff · G major",
                            score: Int(Double(attempts) * (0.7 + random.next() * 0.28)), attempts: attempts,
                            endReason: isTimed ? .timeUp : isPiece ? .pieceComplete : .stopped,
                            practiceLength: isTimed ? "2 min" : nil,
                            // The latest piano rounds were played on a real piano.
                            realPianoAnswers: index % 3 == 1 && index < 9 ? attempts : 0)
        }
        let bars = (1...16).map { BarProgress(bar: $0, attempts: 6 + Int(random.next() * 10), correct: 0) }
            .map { BarProgress(bar: $0.bar, attempts: $0.attempts, correct: Int(Double($0.attempts) * (0.55 + random.next() * 0.45))) }
        return ProgressReport(
            filter: ProgressFilter(), generatedAt: now, periodStart: window.first?.day,
            totals: totals(window[...]), previousTotals: totals(days.dropLast(30).suffix(30)),
            currentStreakDays: 4, longestStreakDays: 11, days: window, positions: positions, pitches: pitches,
            byInput: sampleBreakdown(window[...]),
            byNaming: [BreakdownRow(key: "letters", answers: 1700, correct: 1520, medianResponseMs: 1100),
                       BreakdownRow(key: "solfege", answers: 470, correct: 380, medianResponseMs: 1500)],
            previousByInput: sampleBreakdown(days.dropLast(30).suffix(30)),
            pieces: [PieceProgressSummary(title: "Minuet in G", path: "/tmp/minuet.mxl", lastPractised: now.addingTimeInterval(-7200),
                                          rounds: 6, answers: bars.map(\.attempts).reduce(0, +),
                                          correct: bars.map(\.correct).reduce(0, +), measureCount: 16, bars: bars)],
            recentRounds: rounds, responseTimes: sampleResponseTimes(), answersBeforeTracking: 0, unreadableLines: 0,
            methodsPractised: Set(days.flatMap { $0.methods.map(\.method) }))
    }

    /// Splits a sample day's answers by method, with a random sequence of its own so the rest of
    /// the sample stays as it was: mostly the keyboard; note buttons now and then in the middle
    /// weeks; the piano on screen for a few days, then a real piano over the last two weeks, slower
    /// than typing and getting faster; the guitar on two days, much slower.
    private static func sampleMethods(_ day: DayProgress, daysAgo back: Int) -> DayProgress {
        guard day.answers > 0, let median = day.medianResponseMs else { return day }
        var random = SeededRandom(seed: 1000 + UInt64(back))
        func part(_ method: AnswerMethod, _ answers: Int, accuracy: Double, medianMs: Int) -> MethodDay {
            let correct = Int((Double(answers) * min(1, accuracy)).rounded())
            let half = medianMs / 3
            return MethodDay(method: method, answers: answers, correct: correct, medianResponseMs: medianMs,
                             lowerQuartileMs: medianMs - half * 2 / 3, upperQuartileMs: medianMs + half,
                             rightSingleNotes: correct)
        }
        var others: [MethodDay] = []
        if (25...40).contains(back), random.next() < 0.4 {
            others.append(part(.buttons, 8 + Int(random.next() * 12), accuracy: 0.85, medianMs: median * 6 / 5))
        }
        if back <= 12 {
            let speed = Double(12 - back) / 12
            others.append(part(.realPiano, 20 + Int(random.next() * 40), accuracy: 0.9 + 0.07 * speed,
                               medianMs: Int(5200 - 1800 * speed)))
        } else if (13...18).contains(back) {
            others.append(part(.piano, 10 + Int(random.next() * 15), accuracy: 0.8, medianMs: 3800))
        }
        if back == 3 || back == 1 {
            others.append(part(.guitar, 25 + Int(random.next() * 10), accuracy: back == 1 ? 0.62 : 0.5,
                               medianMs: back == 1 ? 12_500 : 16_000))
        }
        let keyboardAnswers = max(5, day.answers - others.map(\.answers).reduce(0, +))
        let keyboard = MethodDay(method: .keyboard, answers: keyboardAnswers, correct: Int(Double(keyboardAnswers) * (day.accuracy ?? 0.9)),
                                 medianResponseMs: median, lowerQuartileMs: day.lowerQuartileMs, upperQuartileMs: day.upperQuartileMs,
                                 rightSingleNotes: Int(Double(keyboardAnswers) * (day.accuracy ?? 0.9)))
        var day = day
        day.methods = ([keyboard] + others).sorted { AnswerMethod.allCases.firstIndex(of: $0.method)! < AnswerMethod.allCases.firstIndex(of: $1.method)! }
        day.answers = day.methods.map(\.answers).reduce(0, +)
        day.correct = day.methods.map(\.correct).reduce(0, +)
        return day
    }

    /// The sample's "How you answer" rows for some days: each method's answers added up, its time the
    /// middle of its days' medians.
    private static func sampleBreakdown(_ days: ArraySlice<DayProgress>) -> [BreakdownRow] {
        AnswerMethod.allCases.compactMap { method in
            let parts = days.flatMap(\.methods).filter { $0.method == method }
            guard !parts.isEmpty else { return nil }
            let medians = parts.compactMap(\.medianResponseMs).sorted()
            return BreakdownRow(key: method.rawValue, answers: parts.map(\.answers).reduce(0, +),
                                correct: parts.map(\.correct).reduce(0, +), medianResponseMs: medians[medians.count / 2])
        }
        .sorted { ($0.answers, $1.key) > ($1.answers, $0.key) }
    }

    /// Times bunched around 1.1 s now, spread out around 1.8 s the window before; mistakes rising
    /// with slow answers; notes a step from the last named faster than far jumps.
    private static func sampleResponseTimes() -> ResponseTimes {
        func histogram(peak: Double, width: Double, total: Double) -> [Int] {
            (0...ResponseTimes.histogramBins).map { bin in
                let seconds = (Double(bin) + 0.5) * Double(ResponseTimes.histogramBinMs) / 1000
                // Log-normal-ish: a quick rise, a long tail.
                let z = log(seconds / peak) / width
                return Int(total * exp(-z * z / 2) / 10)
            }
        }
        var times = ResponseTimes()
        times.current = TimeSpread(rightAnswers: 1960, lowerQuartileMs: 860, medianMs: 1120, upperQuartileMs: 1480)
        times.previous = TimeSpread(rightAnswers: 1410, lowerQuartileMs: 1150, medianMs: 1790, upperQuartileMs: 2760)
        times.histogram = histogram(peak: 1.05, width: 0.35, total: 1960)
        times.previousHistogram = histogram(peak: 1.6, width: 0.6, total: 1410)
        let edges = [0] + ResponseTimes.speedEdgesMs
        let answers = [180, 310, 620, 420, 260, 120, 60]
        let wrong = [3, 6, 14, 12, 11, 8, 7]
        times.bySpeed = edges.indices.map { index in
            SpeedBin(lowerMs: edges[index], upperMs: index + 1 < edges.count ? edges[index + 1] : nil,
                     answers: answers[index], wrong: wrong[index])
        }
        times.byPreviousNote = [
            PreviousNoteRow(distance: .samePlace, answers: 3, correct: 3, medianMs: 1300),
            PreviousNoteRow(distance: .oneStep, answers: 480, correct: 470, medianMs: 980),
            PreviousNoteRow(distance: .twoOrThreeSteps, answers: 760, correct: 735, medianMs: 1150),
            PreviousNoteRow(distance: .fourOrMoreSteps, answers: 920, correct: 880, medianMs: 1290),
        ]
        return times
    }
}

/// Response times beyond the median: the signs that naming a note is becoming automatic rather
/// than worked out.
/// - **Spread:** the middle half of the times draws together, often before the median falls much.
/// - **Shape:** the times bunch up instead of trailing off into slow ones.
/// - **Speed and mistakes come apart:** mistakes no longer come with the fastest answers.
/// - **The previous note stops mattering:** a note is named as fast after a far jump as after a
///   step, so it's read on its own, not worked out from the one before.
///
/// **Which answers:** single notes only, in the filter's window and clef. Chords named together are
/// left out everywhere here (their one time covers several notes), and so are answers without a
/// time (from before detailed tracking). Times leave out pauses, as everywhere.
struct ResponseTimes: Equatable {
    /// `histogram` has `histogramBins` bins of `histogramBinMs` from 0 (0–0.25 s … 5.75–6 s), then
    /// one more for 6 s or longer.
    static let histogramBinMs = 250
    static let histogramBins = 24
    /// Upper edges of `bySpeed`'s bins: under 0.75 s, 0.75–1 s, 1–1.5 s, 1.5–2 s, 2–3 s, 3–5 s, then
    /// 5 s or longer.
    static let speedEdgesMs = [750, 1000, 1500, 2000, 3000, 5000]

    /// The window's right answers.
    var current = TimeSpread()
    /// The same-length window before; nil for all time.
    var previous: TimeSpread?
    /// The window's right answers by time: `histogramBins + 1` counts (see `histogramBinMs`).
    var histogram = [Int](repeating: 0, count: histogramBins + 1)
    /// The same for the window before; nil for all time.
    var previousHistogram: [Int]?
    /// Every answer in the window, right or wrong, by its time: one bin per `speedEdgesMs` gap,
    /// seven in all, empty ones included.
    var bySpeed: [SpeedBin] = []
    /// Answers in the window by how far the note is from the one asked just before it in the same
    /// round: one row per `PreviousNoteDistance`, empty ones included. Counted only when that
    /// question (index − 1) was a single note on the same clef; a round's first note, a note after
    /// a chord, and one after a note on the other staff are left out.
    var byPreviousNote: [PreviousNoteRow] = []
}

/// The quartiles of a set of right answers' times (`ProgressAnalyzer.quantile`).
struct TimeSpread: Equatable {
    var rightAnswers = 0
    var lowerQuartileMs: Int?
    var medianMs: Int?
    var upperQuartileMs: Int?

    /// How far apart the middle half is: upper minus lower quartile.
    var spreadMs: Int? { lowerQuartileMs.flatMap { lower in upperQuartileMs.map { $0 - lower } } }
}

/// Answers whose time falls in `lowerMs..<upperMs` (no upper edge for the last bin).
struct SpeedBin: Equatable, Identifiable {
    var lowerMs: Int
    var upperMs: Int?
    var answers: Int
    var wrong: Int

    var id: Int { lowerMs }
    var mistakeRate: Double? { answers > 0 ? Double(wrong) / Double(answers) : nil }
}

/// How far a note is from the one before it, in staff steps (a line to the next space is one).
enum PreviousNoteDistance: String, CaseIterable, Identifiable {
    /// The same line or space: a repeated note, or its sharp or flat. Random rounds never repeat a
    /// note, so this comes almost only from pieces.
    case samePlace
    case oneStep
    case twoOrThreeSteps
    case fourOrMoreSteps

    var id: Self { self }
    var label: String {
        switch self {
        case .samePlace: "Same line or space"
        case .oneStep: "One step"
        case .twoOrThreeSteps: "2–3 steps"
        case .fourOrMoreSteps: "4 or more steps"
        }
    }

    init(steps: Int) {
        switch abs(steps) {
        case 0: self = .samePlace
        case 1: self = .oneStep
        case 2...3: self = .twoOrThreeSteps
        default: self = .fourOrMoreSteps
        }
    }
}

struct PreviousNoteRow: Equatable, Identifiable {
    var distance: PreviousNoteDistance
    var answers: Int
    var correct: Int
    /// Median time of the right ones.
    var medianMs: Int?

    var id: PreviousNoteDistance { distance }
    var accuracy: Double? { answers > 0 ? Double(correct) / Double(answers) : nil }
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
