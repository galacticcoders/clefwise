import Foundation

enum ProgressAnalyzer {
    /// Works out the dashboard for `filter` from `events` (in time order, as `UsageLog.readEvents`
    /// gives them). Pure and thread-safe: call it off the main thread for a long log. One pass over
    /// the events, then over the rounds, so years of log take well under a second.
    ///
    /// The window runs from the start of its first local day through `now` (all time: the whole
    /// log). An answer counts when it was given in the window and its question is in the filter's
    /// clef; answers whose `questionShown` isn't in the log are left out everywhere. A round counts
    /// (rounds, practice time, days, pieces, recent rounds) when it started in the window and, with
    /// one clef chosen, has at least one answer in that clef; its time, score and attempts are then
    /// the whole round's, both clefs included. Streaks ignore the filter.
    static func report(from events: [LoggedEvent], filter: ProgressFilter, unreadableLines: Int = 0,
                       now: Date = Date(), calendar: Calendar = .current) -> ProgressReport {
        var analysis = Analysis(filter: filter, now: now, calendar: calendar)
        for event in events { analysis.add(event) }
        var report = analysis.report()
        report.unreadableLines = unreadableLines
        return report
    }

    /// "treble.F♯5", as note stats are keyed: the clef and the pitch; nil for anything else.
    static func parseStatKey(_ key: String) -> (clef: Clef, pitch: Pitch)? {
        guard let dot = key.firstIndex(of: "."), let clef = Clef(rawValue: String(key[..<dot])) else { return nil }
        var rest = key[key.index(after: dot)...]
        guard let first = rest.popFirst(), let letter = NoteLetter(character: first) else { return nil }
        var accidental = Accidental.natural
        if let sign = rest.first, let signed = [Accidental.sharp, .flat].first(where: { $0.symbol == String(sign) }) {
            accidental = signed
            rest = rest.dropFirst()
        }
        guard rest.first?.isNumber == true || rest.first == "-", let octave = Int(rest) else { return nil }
        return (clef, Pitch(letter, octave, accidental))
    }

    /// The middle value, or the mean of the middle two (rounded); nil when there are none.
    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return Int((Double(sorted[middle - 1] + sorted[middle]) / 2).rounded())
    }

    /// The `p` quantile (0…1) of `values`, between the two nearest ranks as spreadsheets'
    /// PERCENTILE does, rounded; nil when there are none. `quantile(values, 0.5)` is `median`.
    static func quantile(_ values: [Int], _ p: Double) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = min(max(p, 0), 1) * Double(sorted.count - 1)
        let below = Int(rank.rounded(.down)), above = Int(rank.rounded(.up))
        let value = Double(sorted[below]) + (Double(sorted[above]) - Double(sorted[below])) * (rank - Double(below))
        return Int(value.rounded())
    }

    fileprivate static func pitch(_ logged: LoggedPitch) -> Pitch? {
        guard logged.letter.count == 1, let letter = logged.letter.first.flatMap(NoteLetter.init(character:)),
              let accidental = Accidental(rawValue: logged.accidental) else { return nil }
        return Pitch(letter, logged.octave, accidental)
    }
}

// MARK: - Gathering

/// Everything gathered in the one pass over the log, then turned into the report.
private struct Analysis {
    let filter: ProgressFilter
    let now: Date
    let calendar: Calendar
    /// Starts of the window and of the same-length one before it; nil for all time.
    let periodStart: Date?
    let previousStart: Date?
    private var days: LocalDays

    /// Questions waiting for their answer.
    private var questions: [UUID: QuestionShown] = [:]
    private var rounds: [RoundRecord] = []
    private var roundIndex: [UUID: Int] = [:]
    /// Staves in each part of each piece as last opened, so single-staff parts don't name a hand.
    private var partStaves: [String: [Int]] = [:]
    private var snapshot: StatsSnapshot?

    /// Every day with an answer, by its start, with its end: for the streaks.
    private var practised: [Date: Date] = [:]
    private var current = TotalsTally(), previous = TotalsTally()
    private var dayTallies: [Date: DayTally] = [:]
    /// First and last days with an answer in the window, for the all-time day list.
    private var firstDay: Date?, lastDay: Date?
    private var positions: [ClefKey<Int>: PositionTally] = [:]
    private var pitches: [ClefKey<Pitch>: Tally] = [:]
    private var inputs: [String: Tally] = [:], namings: [String: Tally] = [:]
    private var pieces: [String: PieceTally] = [:]

    init(filter: ProgressFilter, now: Date, calendar: Calendar) {
        self.filter = filter
        self.now = now
        self.calendar = calendar
        days = LocalDays(calendar)
        if let count = filter.range.days {
            let today = calendar.startOfDay(for: now)
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1 - count, to: today) ?? today)
            periodStart = start
            previousStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -count, to: start) ?? start)
        } else {
            periodStart = nil
            previousStart = nil
        }
    }

    private func inWindow(_ time: Date) -> Bool {
        guard let periodStart else { return true }
        return time >= periodStart && time <= now
    }

    private func inPreviousWindow(_ time: Date) -> Bool {
        guard let periodStart, let previousStart else { return false }
        return time >= previousStart && time < periodStart
    }

    private func inClef(_ clef: String) -> Bool {
        filter.clef == .all || clef == filter.clef.rawValue
    }

    private mutating func round(_ id: UUID) -> Int {
        if let index = roundIndex[id] { return index }
        roundIndex[id] = rounds.count
        rounds.append(RoundRecord(id: id))
        return rounds.count - 1
    }

    mutating func add(_ logged: LoggedEvent) {
        switch logged.event {
        case .roundStarted(let start):
            let index = round(start.round)
            rounds[index].started = logged.time
            rounds[index].start = start
            if let piece = start.piece, let staves = partStaves[piece.path], staves.indices.contains(piece.partIndex) {
                rounds[index].singleStaff = staves[piece.partIndex] == 1
            }
        case .questionShown(let question):
            questions[question.question] = question
        case .answerGiven(let answer):
            add(answer, at: logged.time)
        case .roundEnded(let end):
            rounds[round(end.round)].end = end
        case .pieceOpened(let opened):
            partStaves[opened.path] = opened.parts.map(\.staves)
        case .statsSnapshot(let snapshot):
            self.snapshot = snapshot
        default:
            break
        }
    }

    private mutating func add(_ answer: AnswerGiven, at time: Date) {
        let index = round(answer.round)
        rounds[index].answers += 1
        if answer.correct { rounds[index].correct += 1 }
        rounds[index].lastAnswer = max(rounds[index].lastAnswer ?? time, time)

        // A question has one answer, so it can go.
        guard let question = questions.removeValue(forKey: answer.question) else { return }
        let day = days.day(of: time)
        practised[day.start] = day.end
        guard inClef(question.clef) else { return }
        rounds[index].hasAnswerInClef = true
        if inPreviousWindow(time) { previous.add(answer, on: day.start) }
        guard inWindow(time) else { return }

        current.add(answer, on: day.start)
        dayTallies[day.start, default: DayTally()].tally.add(answer)
        firstDay = min(firstDay ?? day.start, day.start)
        lastDay = max(lastDay ?? day.start, day.start)
        inputs[question.input, default: Tally()].add(answer)
        namings[question.naming, default: Tally()].add(answer)
        if let clef = Clef(rawValue: question.clef) {
            positions[ClefKey(clef: clef, value: question.position), default: PositionTally()].tally.add(answer)
            if let pitch = ProgressAnalyzer.pitch(question.written) {
                pitches[ClefKey(clef: clef, value: pitch), default: Tally()].add(answer)
            }
        }
        if let started = rounds[index].started, let piece = rounds[index].start?.piece {
            pieces[piece.path, default: PieceTally()].add(answer, at: time, bar: question.pieceNote?.measure,
                                                          in: piece, startedAt: started)
        }
    }

    // MARK: - The report

    mutating func report() -> ProgressReport {
        // Rounds once all their answers are in, as the clef filter needs them.
        var roundDays = LocalDays(calendar)
        var recent: [Int] = []
        for (index, round) in rounds.enumerated() {
            guard let started = round.started, filter.clef == .all || round.hasAnswerInClef else { continue }
            let seconds = Double(round.durationMs ?? 0) / 1000
            if inPreviousWindow(started) {
                previous.rounds += 1
                previous.practiceSeconds += seconds
            }
            guard inWindow(started) else { continue }
            current.rounds += 1
            current.practiceSeconds += seconds
            dayTallies[roundDays.day(of: started).start, default: DayTally()].practiceSeconds += seconds
            recent.append(index)
            if let piece = round.start?.piece {
                pieces[piece.path, default: PieceTally()].addRound(piece, startedAt: started)
            }
        }
        recent.sort { (rounds[$0].started!, $0) > (rounds[$1].started!, $1) }

        let answersBeforeTracking = filter.range == .all ? addSnapshot() : 0
        let streaks = self.streaks()
        return ProgressReport(
            filter: filter, generatedAt: now, periodStart: periodStart,
            totals: current.totals, previousTotals: periodStart == nil ? nil : previous.totals,
            currentStreakDays: streaks.current, longestStreakDays: streaks.longest,
            days: dayList(),
            positions: positions
                .map { key, tally in
                    PositionProgress(clef: key.clef, position: key.value, natural: key.clef.pitch(atPosition: key.value),
                                     attempts: tally.tally.answers, correct: tally.tally.correct,
                                     medianResponseMs: tally.tally.medianMs, attemptsBeforeTracking: tally.beforeTracking)
                }
                .sorted { ($0.clef.order, $0.position) < ($1.clef.order, $1.position) },
            pitches: pitches
                .map { PitchProgress(clef: $0.clef, pitch: $0.value, attempts: $1.answers, correct: $1.correct, medianResponseMs: $1.medianMs) }
                .sorted {
                    ($0.clef.order, $0.pitch.diatonicIndex, $0.pitch.accidental.rawValue)
                        < ($1.clef.order, $1.pitch.diatonicIndex, $1.pitch.accidental.rawValue)
                },
            byInput: Self.breakdown(inputs), byNaming: Self.breakdown(namings),
            pieces: pieces
                .compactMap { path, piece in piece.summary(path: path) }
                .sorted { ($0.lastPractised, $1.path) > ($1.lastPractised, $0.path) },
            recentRounds: recent.prefix(50).map { Self.recentRound(rounds[$0]) },
            answersBeforeTracking: answersBeforeTracking, unreadableLines: 0)
    }

    /// Adds the stats kept before the log to the note map and pitch lists; returns how many answers
    /// they hold. The snapshot keys notes as played, so an 8va note lands an octave up.
    private mutating func addSnapshot() -> Int {
        guard let snapshot else { return 0 }
        var total = 0
        for (key, stat) in snapshot.noteStats where stat.attempts > 0 {
            guard let (clef, pitch) = ProgressAnalyzer.parseStatKey(key), inClef(clef.rawValue) else { continue }
            let correct = max(0, min(stat.correct, stat.attempts))
            positions[ClefKey(clef: clef, value: clef.position(of: pitch)), default: PositionTally()]
                .addBeforeTracking(attempts: stat.attempts, correct: correct)
            pitches[ClefKey(clef: clef, value: pitch), default: Tally()].addBeforeTracking(attempts: stat.attempts, correct: correct)
            total += stat.attempts
        }
        return total
    }

    /// The run of days ending today (or yesterday), and the longest run.
    private func streaks() -> (current: Int, longest: Int) {
        let today = calendar.startOfDay(for: now)
        var run = 0, longest = 0, previousEnd: Date?
        var endingToday: Int?, endingYesterday: Int?
        for (start, end) in practised.sorted(by: { $0.key < $1.key }) {
            run = start == previousEnd ? run + 1 : 1
            longest = max(longest, run)
            if start == today { endingToday = run }
            if end == today { endingYesterday = run }
            previousEnd = end
        }
        return (endingToday ?? endingYesterday ?? 0, longest)
    }

    /// Every day of the window; all time, from the first day with an answer through today.
    private func dayList() -> [DayProgress] {
        let today = calendar.startOfDay(for: now)
        let first: Date, last: Date
        if let periodStart {
            (first, last) = (periodStart, today)
        } else if let firstDay, let lastDay {
            // A clock set wrong can put answers after today.
            (first, last) = (firstDay, max(today, lastDay))
        } else {
            return []
        }
        var list: [DayProgress] = []
        var day = first
        while day <= last {
            let tally = dayTallies[day]
            list.append(DayProgress(day: day, answers: tally?.tally.answers ?? 0, correct: tally?.tally.correct ?? 0,
                                    practiceSeconds: tally?.practiceSeconds ?? 0, medianResponseMs: tally?.tally.medianMs))
            guard let next = calendar.dateInterval(of: .day, for: day)?.end, next > day else { break }
            day = next
        }
        return list
    }

    /// Most answers first.
    private static func breakdown(_ tallies: [String: Tally]) -> [BreakdownRow] {
        tallies
            .map { BreakdownRow(key: $0, answers: $1.answers, correct: $1.correct, medianResponseMs: $1.medianMs) }
            .sorted { ($0.answers, $1.key) > ($1.answers, $0.key) }
    }

    private static func recentRound(_ round: RoundRecord) -> RecentRound {
        let settings = SavedSettings(round.start?.settings)
        let defaults = Game.Settings()
        return RecentRound(
            id: round.id, started: round.started!, durationMs: round.durationMs,
            mode: settings.string("mode") ?? defaults.mode.rawValue,
            input: settings.string("answerInput") ?? defaults.answerInput.rawValue,
            naming: settings.string("naming") ?? defaults.naming.rawValue,
            description: description(of: round, settings),
            score: round.end?.score ?? round.correct, attempts: round.end?.attempts ?? round.answers,
            endReason: round.end?.reason)
    }

    /// "Treble · On the staff · G major", or for a piece "Minuet in G · Right hand".
    private static func description(of round: RoundRecord, _ settings: SavedSettings) -> String {
        if let piece = round.start?.piece {
            let hand = round.singleStaff ? nil : Game.PieceSettings.Hand(rawValue: piece.hand)?.label
            return [piece.title, hand].compactMap { $0 }.joined(separator: " · ")
        }
        let defaults = Game.Settings()
        let key: String?
        switch settings.decode("key") ?? defaults.key {
        case .fixed(let signature):
            key = majorKey(signature.fifths)
        case .random:
            // The key it landed on is in the round's start.
            key = KeyChoice.random.label + (round.start.flatMap { majorKey($0.keyFifths) }.map { " (\($0))" } ?? "")
        }
        let clefs: ClefChoice = settings.decode("clefChoice") ?? defaults.clefChoice
        let range: NoteRange = settings.decode("range") ?? defaults.range
        return [clefs.label, range.label, key].compactMap { $0 }.joined(separator: " · ")
    }

    /// "G major"; nil for a signature that can't be one.
    private static func majorKey(_ fifths: Int) -> String? {
        (-7...7).contains(fifths) ? "\(KeySignature(fifths: fifths).majorKey) major" : nil
    }
}

// MARK: - Tallies

/// Answers, how many were right, and the right ones' response times for the median.
private struct Tally {
    var answers = 0, correct = 0
    var correctMs: [Int] = []

    var medianMs: Int? { ProgressAnalyzer.median(correctMs) }

    mutating func add(_ answer: AnswerGiven) {
        answers += 1
        guard answer.correct else { return }
        correct += 1
        correctMs.append(answer.responseMs)
    }

    /// From the stats snapshot, which has no times.
    mutating func addBeforeTracking(attempts: Int, correct: Int) {
        answers += attempts
        self.correct += correct
    }
}

private struct TotalsTally {
    var tally = Tally()
    var rounds = 0
    var practiceSeconds = 0.0
    var days: Set<Date> = []

    var totals: ProgressTotals {
        ProgressTotals(answers: tally.answers, correct: tally.correct, rounds: rounds, practiceSeconds: practiceSeconds,
                       daysPractised: days.count, medianResponseMs: tally.medianMs)
    }

    mutating func add(_ answer: AnswerGiven, on day: Date) {
        tally.add(answer)
        days.insert(day)
    }
}

private struct DayTally {
    var tally = Tally()
    var practiceSeconds = 0.0
}

private struct PositionTally {
    var tally = Tally()
    var beforeTracking = 0

    mutating func addBeforeTracking(attempts: Int, correct: Int) {
        tally.addBeforeTracking(attempts: attempts, correct: correct)
        beforeTracking += attempts
    }
}

private struct ClefKey<Value: Hashable>: Hashable {
    let clef: Clef
    let value: Value
}

private struct PieceTally {
    /// From the latest round, for its title and bar count.
    var context: PieceContext?
    var contextStart = Date.distantPast
    var rounds = 0, answers = 0, correct = 0
    var lastAnswer: Date?, lastRoundStart: Date?
    var bars: [Int: BarProgress] = [:]

    mutating func addRound(_ piece: PieceContext, startedAt start: Date) {
        rounds += 1
        lastRoundStart = max(lastRoundStart ?? start, start)
        note(piece, startedAt: start)
    }

    mutating func add(_ answer: AnswerGiven, at time: Date, bar: Int?, in piece: PieceContext, startedAt start: Date) {
        answers += 1
        if answer.correct { correct += 1 }
        lastAnswer = max(lastAnswer ?? time, time)
        if let bar {
            bars[bar, default: BarProgress(bar: bar, attempts: 0, correct: 0)].attempts += 1
            if answer.correct { bars[bar]!.correct += 1 }
        }
        note(piece, startedAt: start)
    }

    private mutating func note(_ piece: PieceContext, startedAt start: Date) {
        guard start >= contextStart else { return }
        context = piece
        contextStart = start
    }

    func summary(path: String) -> PieceProgressSummary? {
        guard let context, let lastPractised = lastAnswer ?? lastRoundStart else { return nil }
        return PieceProgressSummary(title: context.title, path: path, lastPractised: lastPractised, rounds: rounds,
                                    answers: answers, correct: correct, measureCount: context.measureCount,
                                    bars: bars.values.sorted { $0.bar < $1.bar })
    }
}

/// A round as the log tells it: its start and end (either may be missing) and its answers.
private struct RoundRecord {
    let id: UUID
    var started: Date?
    var start: RoundStarted?
    var end: RoundEnded?
    /// Every `answerGiven` for it, for a round that never ended.
    var answers = 0, correct = 0
    var lastAnswer: Date?
    var hasAnswerInClef = false
    var singleStaff = false

    /// From `roundEnded`; a round that never ended (the app crashed) runs to its last answer.
    var durationMs: Int? {
        if let end { return end.durationMs }
        guard let started, let lastAnswer else { return nil }
        return max(0, Int((lastAnswer.timeIntervalSince(started) * 1000).rounded()))
    }
}

/// Local days by start and end, asking the calendar once a day rather than once an event, as
/// events come in time order.
private struct LocalDays {
    let calendar: Calendar
    private var last: (start: Date, end: Date)?

    init(_ calendar: Calendar) { self.calendar = calendar }

    mutating func day(of time: Date) -> (start: Date, end: Date) {
        if let last, time >= last.start, time < last.end { return last }
        let day = calendar.dateInterval(of: .day, for: time).map { ($0.start, $0.end) }
            ?? (calendar.startOfDay(for: time), calendar.startOfDay(for: time).addingTimeInterval(86_400))
        last = day
        return day
    }
}

/// A round's saved settings, read a key at a time so a value this version can't read (or a key
/// older versions didn't save) only falls back to the app's default for that key.
private struct SavedSettings {
    private let values: [String: JSONValue]

    init(_ settings: JSONValue?) {
        if case .object(let values)? = settings { self.values = values } else { values = [:] }
    }

    func string(_ key: String) -> String? {
        if case .string(let text)? = values[key] { return text }
        return nil
    }

    /// Through JSON into the app's own type, e.g. `{"fixed":{"_0":{"fifths":1}}}` into `KeyChoice`.
    func decode<T: Decodable>(_ key: String) -> T? {
        guard let value = values[key], let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

private extension Clef {
    /// Treble first.
    var order: Int { self == .treble ? 0 : 1 }
}
