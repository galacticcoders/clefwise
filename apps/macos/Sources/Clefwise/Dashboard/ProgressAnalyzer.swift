import Foundation

enum ProgressAnalyzer {
    /// Works out the dashboard for `filter` from `events` (in time order, as `UsageLog.readEvents`
    /// gives them). Pure and thread-safe: call it off the main thread for a long log. One pass over
    /// the events, then over the rounds, so years of log take well under a second.
    ///
    /// The window runs from the start of its first local day through `now` (all time: the whole
    /// log). An answer counts when it was given in the window, its question is in the filter's clef,
    /// and it was given in the filter's answer method (`AnswerMethod.of`: an input this version
    /// doesn't know counts only with every method); answers whose `questionShown` isn't in the log
    /// are left out everywhere. A round counts (rounds, practice time, days, pieces, recent rounds)
    /// when it started in the window and, with one clef or method chosen, has at least one answer
    /// that counts; its time, score and attempts are then the whole round's, every clef and method
    /// included. The stats snapshot, which has no method, counts only with every method. Streaks,
    /// `clefsPractised`, `methodsPractised`, `piecesPractised` and `hasRandomPractice` ignore the filter,
    /// and so does the note before a question (`ResponseTimes.byPreviousNote`, the start of a bar in
    /// `PieceDay`): it's the one shown before it in its round.
    ///
    /// Besides the rounds' own events, it uses two kinds from outside them: `statsSnapshot` (the
    /// opening balances: several, one per device, add up) and `pieceOpened` (each part's staves, for
    /// rounds that don't say). Pieces go by their journal id (`piece.id`) when a round has one,
    /// otherwise by path; the usage log has no `pieceAdded` to link the two.
    static func report(from events: [LoggedEvent], filter: ProgressFilter, unreadableLines: Int = 0,
                       now: Date = Date(), calendar: Calendar = .current) -> ProgressReport {
        var analysis = Analysis(filter: filter, now: now, calendar: calendar, pieceIDs: PieceIDs())
        for event in events { analysis.add(event) }
        var report = analysis.report()
        report.unreadableLines = unreadableLines
        return report
    }

    /// Works out the dashboard for `filter` from a practice journal, as `JournalReader.read()` gives
    /// it, by the rules of `report(from:filter:…)`: the opening balances (`journal.snapshots`, one per
    /// device, added up), then the runs by start time. `unreadableLines` is the journal's.
    ///
    /// Pieces go by their journal id, so a piece practised on several Macs, or before and after the
    /// journal began, is one piece: a round's `piece.id`; for a run brought in from the old usage log
    /// (which has none), the piece its `libraryID` was added as (`pieceAdded` in
    /// `journal.pieceEvents`), failing that the one whose `originalPath` is its path; failing both,
    /// its path stands in.
    ///
    /// `pieceOpenings` are this Mac's `pieceOpened` events from its usage log: they say how many
    /// staves each part has for runs that don't (those brought in from the log), so a single-staff
    /// piece isn't described with a hand. Each counts from its time on, as in the log, and for
    /// nothing else; any other event among them is ignored.
    static func report(from journal: JournalReader.Contents, pieceOpenings: [LoggedEvent] = [], filter: ProgressFilter,
                       now: Date = Date(), calendar: Calendar = .current) -> ProgressReport {
        var analysis = Analysis(filter: filter, now: now, calendar: calendar, pieceIDs: PieceIDs(journal.pieceEvents))
        for snapshot in journal.snapshots { analysis.add(snapshot) }
        let openings = pieceOpenings
            .filter { if case .pieceOpened = $0.event { true } else { false } }
            .enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
        var nextOpening = openings.startIndex
        for run in journal.runs {
            while nextOpening < openings.endIndex, openings[nextOpening].time <= run.startedAt {
                analysis.add(openings[nextOpening])
                nextOpening += 1
            }
            for event in run.events { analysis.add(event) }
        }
        var report = analysis.report()
        report.unreadableLines = journal.unreadableLines
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
        quantile(sorted: values.sorted(), p)
    }

    /// `quantile` of values already sorted, so several quantiles of a long list sort it only once.
    fileprivate static func quantile(sorted: [Int], _ p: Double) -> Int? {
        guard !sorted.isEmpty else { return nil }
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

// MARK: - Pieces

/// Which piece in the journal a round practised, from the piece library's `pieceAdded` events:
/// runs brought in from the old usage log name their piece only by `libraryID` and path. When the
/// events disagree, the latest wins (they come in time order).
private struct PieceIDs {
    private var byLibraryID: [UUID: String] = [:]
    private var byOriginalPath: [String: String] = [:]

    init(_ pieceEvents: [LoggedEvent] = []) {
        for logged in pieceEvents {
            guard case .pieceAdded(let added) = logged.event else { continue }
            let id = added.piece.lowercased()
            if let libraryID = added.libraryID { byLibraryID[libraryID] = id }
            if let path = added.originalPath { byOriginalPath[path] = id }
        }
    }

    /// `piece.id`; failing that, the piece added with its `libraryID`, then the one first opened
    /// from its path; nil when none says (the path then stands in). Ids are hashes, kept in
    /// lowercase.
    func id(of piece: PieceContext) -> String? {
        if let id = piece.id { return id.lowercased() }
        if let libraryID = piece.libraryID, let id = byLibraryID[libraryID] { return id }
        return byOriginalPath[piece.path]
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
    private let pieceIDs: PieceIDs

    /// Questions waiting for their answer.
    private var questions: [UUID: WaitingQuestion] = [:]
    /// The latest question shown in each round, whatever the filter: for `ResponseTimes.byPreviousNote`
    /// and for the start of a bar (`PieceDay`).
    private var lastShown: [UUID: ShownNote] = [:]
    private var rounds: [RoundRecord] = []
    private var roundIndex: [UUID: Int] = [:]
    /// Staves in each part of each piece as last opened, so single-staff parts don't name a hand,
    /// for rounds that don't say themselves (`PieceContext.staves`).
    private var partStaves: [String: [Int]] = [:]
    /// The opening balances, added up as the journal's projection adds them.
    private var openingBalance = JournalProjection()

    /// Every day with an answer, by its start, with its end: for the streaks.
    private var practised: [Date: Date] = [:]
    private var current = TotalsTally(), previous = TotalsTally()
    private var dayTallies: [Date: DayTally] = [:]
    /// First and last days with an answer in the window, for the all-time day list.
    private var firstDay: Date?, lastDay: Date?
    private var positions: [ClefKey<Int>: PositionTally] = [:]
    private var pitches: [ClefKey<Pitch>: Tally] = [:]
    private var inputs: [String: Tally] = [:], namings: [String: Tally] = [:]
    /// `inputs` for the window before, for `previousByInput`.
    private var previousInputs: [String: Tally] = [:]
    private var pieces: [String: PieceTally] = [:]
    /// Every clef and answer method answered in, whatever the filter.
    private var clefsPractised: Set<Clef> = []
    private var methodsPractised: Set<AnswerMethod> = []
    /// Random notes against pieces, in the window; every piece answered and whether any random notes
    /// were, whatever the filter.
    private var practices: [String: Tally] = [:]
    private var piecesPractised: [String: PracticedPiece] = [:]
    private var hasRandomPractice = false
    /// Right answers to single notes in the window and in the one before, and the window's answers
    /// by speed and by the previous note: for `ResponseTimes`.
    private var times = TimesTally()
    private var previousTimes = SpreadTally()

    init(filter: ProgressFilter, now: Date, calendar: Calendar, pieceIDs: PieceIDs) {
        self.filter = filter
        self.now = now
        self.calendar = calendar
        self.pieceIDs = pieceIDs
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

    /// An answer in an input this version doesn't know (no method) counts only with every method.
    private func inMethod(_ method: AnswerMethod?) -> Bool {
        filter.method == nil || method == filter.method
    }

    /// Random notes are rounds without a piece; `pieceKey` is the round's piece's key in the report.
    private func inPractice(_ pieceKey: String?) -> Bool {
        switch filter.practice {
        case nil: true
        case .random: pieceKey == nil
        case .pieces: pieceKey != nil
        case .piece(let key): pieceKey == key
        }
    }

    /// One clef, method or practice chosen: only some answers count, and only the rounds with one of
    /// them.
    private var picksAnswers: Bool { filter.clef != .all || filter.method != nil || filter.practice != nil }

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
            rounds[index].clock = RoundClock(time: logged.time, activeMs: 0, running: true)
            if let piece = start.piece {
                let id = pieceIDs.id(of: piece)
                rounds[index].piece = (key: id ?? piece.path, id: id)
                rounds[index].inOrder = piece.order == Game.PieceSettings.Order.inOrder.rawValue
                if let staves = piece.staves {
                    rounds[index].singleStaff = staves == 1
                } else if let staves = partStaves[piece.path], staves.indices.contains(piece.partIndex) {
                    rounds[index].singleStaff = staves[piece.partIndex] == 1
                }
            }
        case .questionShown(let question):
            let shown = ShownNote(question)
            // The round's question shown before, whatever the filter: the note before, and moving
            // into another bar, are the round's.
            let before = lastShown.updateValue(shown, forKey: question.round)
            questions[question.question] = WaitingQuestion(shown: question, stepsFromPrevious: shown.steps(after: before),
                                                           place: place(of: shown, after: before, in: question.round))
        case .answerGiven(let answer):
            add(answer, at: logged.time)
        case .roundPaused(let pause):
            rounds[round(pause.round)].clock = RoundClock(time: logged.time, activeMs: pause.activeMs, running: false)
        case .roundResumed(let resume):
            let index = round(resume.round)
            rounds[index].clock = rounds[index].clock.map { RoundClock(time: logged.time, activeMs: $0.activeMs, running: true) }
        case .roundRestored(let restore):
            // Back after a crash, paused: the time since its last event counts for nothing. The
            // question left on screen is asked again as a new one, so it never gets an answer, and
            // the new one doesn't follow on from it: like a round's first question, it's neither the
            // start of a bar nor the rest of one (its time includes finding the place again).
            rounds[round(restore.round)].clock = RoundClock(time: logged.time, activeMs: restore.activeMs, running: false)
            if let question = restore.unansweredQuestion { questions[question] = nil }
            lastShown[restore.round] = nil
        case .roundEnded(let end):
            rounds[round(end.round)].end = end
        case .pieceOpened(let opened):
            partStaves[opened.path] = opened.parts.map(\.staves)
        case .statsSnapshot(let snapshot):
            openingBalance.apply(snapshot)
        default:
            break
        }
    }

    /// Where `shown` stands in its bar (`PieceDay`), from the question shown `before` it in its round.
    /// Only in a piece round going in order, and never its first question (nor the first after a
    /// restore): its time includes getting ready. Of notes named together, only the group's first
    /// question can start a bar; the rest of the bar is single notes.
    private func place(of shown: ShownNote, after before: ShownNote?, in round: UUID) -> BarPlace {
        guard let before, let bar = shown.bar, let barBefore = before.bar,
              let index = roundIndex[round], rounds[index].inOrder else { return .neither }
        if shown.isSingleNote { return bar == barBefore ? .rest : .start }
        let firstOfGroup = shown.group == nil || shown.group != before.group
        return firstOfGroup && bar != barBefore ? .start : .neither
    }

    private mutating func add(_ answer: AnswerGiven, at time: Date) {
        let index = round(answer.round)
        rounds[index].answers += 1
        if answer.correct { rounds[index].correct += 1 }
        if answer.source == .midi { rounds[index].realPianoAnswers += 1 }
        if let active = rounds[index].clock?.activeMs(at: time) {
            rounds[index].activeMsAtLastAnswer = max(rounds[index].activeMsAtLastAnswer ?? active, active)
        }

        // A question has one answer, so it can go.
        guard let waiting = questions.removeValue(forKey: answer.question) else { return }
        let question = waiting.shown
        let day = days.day(of: time)
        practised[day.start] = day.end
        if let clef = Clef(rawValue: question.clef) { clefsPractised.insert(clef) }
        let method = AnswerMethod.of(source: answer.source, input: question.input)
        if let method { methodsPractised.insert(method) }
        let pieceKey = rounds[index].piece?.key
        if let pieceKey {
            if piecesPractised[pieceKey].map({ $0.lastPractised <= time }) ?? true {
                let title = rounds[index].start?.piece?.title ?? piecesPractised[pieceKey]?.title ?? "A piece"
                piecesPractised[pieceKey] = PracticedPiece(id: pieceKey, title: title, lastPractised: time)
            }
        } else {
            hasRandomPractice = true
        }
        guard inClef(question.clef), inMethod(method), inPractice(pieceKey) else { return }
        rounds[index].hasAnswerInFilter = true
        // Notes named together share one time, so the time statistics leave them out.
        let isSingleNote = question.isSingleNote
        // The method's key (`midi` for a real piano), or the input this version doesn't know.
        let inputKey = method?.rawValue ?? question.input
        if inPreviousWindow(time) {
            previous.add(answer, on: day.start)
            if isSingleNote, answer.correct { previousTimes.add(answer.responseMs) }
            previousInputs[inputKey, default: Tally()].add(answer)
        }
        guard inWindow(time) else { return }

        current.add(answer, on: day.start)
        dayTallies[day.start, default: DayTally()].add(answer, singleNote: isSingleNote, method: method)
        if isSingleNote { times.add(answer, stepsFromPrevious: waiting.stepsFromPrevious) }
        firstDay = min(firstDay ?? day.start, day.start)
        lastDay = max(lastDay ?? day.start, day.start)
        inputs[inputKey, default: Tally()].add(answer)
        namings[question.naming, default: Tally()].add(answer)
        practices[pieceKey == nil ? PracticeFilter.randomKey : PracticeFilter.piecesKey, default: Tally()].add(answer)
        if let clef = Clef(rawValue: question.clef) {
            positions[ClefKey(clef: clef, value: question.position), default: PositionTally()].add(answer, singleNote: isSingleNote)
            if let pitch = ProgressAnalyzer.pitch(question.written) {
                pitches[ClefKey(clef: clef, value: pitch), default: Tally()].add(answer)
            }
        }
        if let started = rounds[index].started, let piece = rounds[index].start?.piece, let key = rounds[index].piece {
            pieces[key.key, default: PieceTally(id: key.id)].add(answer, at: time, on: day.start, bar: question.pieceNote?.measure,
                                                                 singleNote: isSingleNote, place: waiting.place,
                                                                 method: method, in: piece, startedAt: started)
        }
    }

    // MARK: - The report

    mutating func report() -> ProgressReport {
        // Rounds once all their answers are in, as the clef and method filters need them.
        var roundDays = LocalDays(calendar)
        var recent: [Int] = []
        for (index, round) in rounds.enumerated() {
            guard let started = round.started, !picksAnswers || round.hasAnswerInFilter else { continue }
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
            if let piece = round.start?.piece, let key = round.piece {
                pieces[key.key, default: PieceTally(id: key.id)].addRound(piece, startedAt: started)
            }
        }
        recent.sort { (rounds[$0].started!, $0) > (rounds[$1].started!, $1) }

        // The snapshot has no dates, and no methods.
        // The snapshot's answers have no method or practice: only with every one counted.
        let answersBeforeTracking = filter.range == .all && filter.method == nil && filter.practice == nil ? addSnapshot() : 0
        for (key, stat) in openingBalance.noteStats where stat.attempts > 0 {
            if let (clef, _) = ProgressAnalyzer.parseStatKey(key) { clefsPractised.insert(clef) }
        }
        let streaks = self.streaks()
        return ProgressReport(
            filter: filter, generatedAt: now, periodStart: periodStart,
            totals: current.totals, previousTotals: periodStart == nil ? nil : previous.totals,
            currentStreakDays: streaks.current, longestStreakDays: streaks.longest,
            days: dayList(),
            positions: positions
                .map { key, tally in
                    let recent = Array(tally.singleNoteMs.suffix(PositionProgress.recentWindow))
                    return PositionProgress(clef: key.clef, position: key.value, natural: key.clef.pitch(atPosition: key.value),
                                            attempts: tally.tally.answers, correct: tally.tally.correct,
                                            medianResponseMs: tally.tally.medianMs, attemptsBeforeTracking: tally.beforeTracking,
                                            recentMedianResponseMs: ProgressAnalyzer.median(recent),
                                            recentRightAnswers: recent.count)
                }
                .sorted { ($0.clef.order, $0.position) < ($1.clef.order, $1.position) },
            pitches: pitches
                .map { PitchProgress(clef: $0.clef, pitch: $0.value, attempts: $1.answers, correct: $1.correct, medianResponseMs: $1.medianMs) }
                .sorted {
                    ($0.clef.order, $0.pitch.diatonicIndex, $0.pitch.accidental.rawValue)
                        < ($1.clef.order, $1.pitch.diatonicIndex, $1.pitch.accidental.rawValue)
                },
            byInput: Self.breakdown(inputs), byNaming: Self.breakdown(namings),
            previousByInput: periodStart == nil ? nil : Self.breakdown(previousInputs),
            byPractice: Self.breakdown(practices),
            pieces: pieces.values
                .compactMap { $0.summary() }
                .sorted { ($0.lastPractised, $1.id) > ($1.lastPractised, $0.id) },
            recentRounds: recent.prefix(50).map { Self.recentRound(rounds[$0]) },
            responseTimes: times.responseTimes(previous: periodStart == nil ? nil : previousTimes),
            answersBeforeTracking: answersBeforeTracking, unreadableLines: 0, clefsPractised: clefsPractised,
            methodsPractised: methodsPractised,
            piecesPractised: piecesPractised.values.sorted { ($0.lastPractised, $1.id) > ($1.lastPractised, $0.id) },
            hasRandomPractice: hasRandomPractice)
    }

    /// Adds the stats kept before the log (every device's opening balance) to the note map and pitch
    /// lists; returns how many answers they hold. The snapshot keys notes as played, so an 8va note
    /// lands an octave up.
    private mutating func addSnapshot() -> Int {
        var total = 0
        for (key, stat) in openingBalance.noteStats where stat.attempts > 0 {
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
            let spread = TimeSpread(times: tally?.singleNoteMs ?? [])
            list.append(DayProgress(day: day, answers: tally?.tally.answers ?? 0, correct: tally?.tally.correct ?? 0,
                                    practiceSeconds: tally?.practiceSeconds ?? 0, medianResponseMs: tally?.tally.medianMs,
                                    lowerQuartileMs: spread.lowerQuartileMs, upperQuartileMs: spread.upperQuartileMs,
                                    methods: tally?.methodDays() ?? []))
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
            wasSprint: round.start?.wasSprint ?? false,
            input: settings.string("answerInput") ?? defaults.answerInput.rawValue,
            naming: settings.string("naming") ?? defaults.naming.rawValue,
            description: description(of: round, settings),
            score: round.end?.score ?? round.correct, attempts: round.end?.attempts ?? round.answers,
            endReason: round.end?.reason, practiceLength: practiceLength(of: round, settings),
            realPianoAnswers: round.realPianoAnswers)
    }

    /// "5 min" or "100 notes" for a round of random notes with a limit. An old sprint had none,
    /// whatever its saved settings say.
    private static func practiceLength(of round: RoundRecord, _ settings: SavedSettings) -> String? {
        guard let start = round.start, start.piece == nil, !start.wasSprint else { return nil }
        let defaults = Game.Settings()
        switch settings.string("practiceLimit").flatMap(Game.PracticeLimit.init(rawValue:)) {
        case .time:
            let minutes: Int = settings.decode("practiceMinutes") ?? defaults.practiceMinutes
            return "\(minutes.formatted()) min"
        case .notes:
            let notes: Int = settings.decode("practiceNotes") ?? defaults.practiceNotes
            return "\(notes.formatted()) notes"
        default:
            return nil
        }
    }

    /// "Treble · On the staff · G major", "Guitar · On the staff · G major" when answered on the
    /// guitar, or for a piece "Minuet in G · Right hand".
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
        // Answering on the guitar, random notes are guitar music, in the guitar clef (`Game.randomClefs`).
        let onGuitar = settings.string("answerInput") == Game.AnswerInput.guitar.rawValue
        let range: NoteRange = settings.decode("range") ?? defaults.range
        return [onGuitar ? Clef.treble8vb.name : clefs.label, range.label, key].compactMap { $0 }.joined(separator: " · ")
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
    /// Times of the right answers to single notes, for the quartiles.
    var singleNoteMs: [Int] = []
    /// The same by answer method; answers in an input this version doesn't know are in none.
    private var methods: [AnswerMethod: MethodTally] = [:]

    mutating func add(_ answer: AnswerGiven, singleNote: Bool, method: AnswerMethod?) {
        tally.add(answer)
        if singleNote, answer.correct { singleNoteMs.append(answer.responseMs) }
        if let method { methods[method, default: MethodTally()].add(answer, singleNote: singleNote) }
    }

    /// One per method answered in, in `AnswerMethod` order, worked out as the day's own numbers are.
    func methodDays() -> [MethodDay] {
        guard !methods.isEmpty else { return [] }
        return AnswerMethod.allCases.compactMap { method in
            guard let part = methods[method] else { return nil }
            let spread = TimeSpread(times: part.singleNoteMs)
            return MethodDay(method: method, answers: part.tally.answers, correct: part.tally.correct,
                             medianResponseMs: part.tally.medianMs, lowerQuartileMs: spread.lowerQuartileMs,
                             upperQuartileMs: spread.upperQuartileMs, rightSingleNotes: spread.rightAnswers)
        }
    }
}

/// One answer method's part of a day: its answers, and its right single notes' times.
private struct MethodTally {
    var tally = Tally()
    var singleNoteMs: [Int] = []

    mutating func add(_ answer: AnswerGiven, singleNote: Bool) {
        tally.add(answer)
        if singleNote, answer.correct { singleNoteMs.append(answer.responseMs) }
    }
}

private struct PositionTally {
    var tally = Tally()
    var beforeTracking = 0
    /// Times of the right answers to single notes, in log order, for how fast it's named now.
    var singleNoteMs: [Int] = []

    mutating func add(_ answer: AnswerGiven, singleNote: Bool) {
        tally.add(answer)
        if singleNote, answer.correct { singleNoteMs.append(answer.responseMs) }
    }

    mutating func addBeforeTracking(attempts: Int, correct: Int) {
        tally.addBeforeTracking(attempts: attempts, correct: correct)
        beforeTracking += attempts
    }
}

/// Right answers' times, for their quartiles and histogram.
private struct SpreadTally {
    var rightMs: [Int] = []
    var histogram = [Int](repeating: 0, count: ResponseTimes.histogramBins + 1)
    private let binMs = ResponseTimes.histogramBinMs, lastBin = ResponseTimes.histogramBins

    mutating func add(_ ms: Int) {
        rightMs.append(ms)
        histogram[min(max(ms, 0) / binMs, lastBin)] += 1
    }
}

/// The window's answers to single notes, for `ResponseTimes`.
private struct TimesTally {
    var right = SpreadTally()
    /// Answers, and wrong ones, per `bySpeed` bin.
    private var speedAnswers = [Int](repeating: 0, count: ResponseTimes.speedEdgesMs.count + 1)
    private var speedWrong = [Int](repeating: 0, count: ResponseTimes.speedEdgesMs.count + 1)
    private let speedEdges = ResponseTimes.speedEdgesMs
    /// One per `PreviousNoteDistance`, in its order.
    private var byPreviousNote = [Tally](repeating: Tally(), count: PreviousNoteDistance.allCases.count)

    mutating func add(_ answer: AnswerGiven, stepsFromPrevious steps: Int?) {
        let ms = answer.responseMs
        if answer.correct { right.add(ms) }
        var bin = 0
        while bin < speedEdges.count, ms >= speedEdges[bin] { bin += 1 }
        speedAnswers[bin] += 1
        if !answer.correct { speedWrong[bin] += 1 }
        if let steps { byPreviousNote[PreviousNoteDistance(steps: steps).order].add(answer) }
    }

    /// `previous`: the right answers of the window before; nil for all time.
    func responseTimes(previous: SpreadTally?) -> ResponseTimes {
        var times = ResponseTimes()
        times.current = TimeSpread(times: right.rightMs)
        times.histogram = right.histogram
        times.previous = previous.map { TimeSpread(times: $0.rightMs) }
        times.previousHistogram = previous?.histogram
        let edges = [0] + ResponseTimes.speedEdgesMs
        times.bySpeed = edges.indices.map { index in
            SpeedBin(lowerMs: edges[index], upperMs: index + 1 < edges.count ? edges[index + 1] : nil,
                     answers: speedAnswers[index], wrong: speedWrong[index])
        }
        times.byPreviousNote = PreviousNoteDistance.allCases.map { distance in
            let tally = byPreviousNote[distance.order]
            return PreviousNoteRow(distance: distance, answers: tally.answers, correct: tally.correct, medianMs: tally.medianMs)
        }
        return times
    }
}

private extension PreviousNoteDistance {
    /// Its index in `allCases`, without searching for it.
    var order: Int {
        switch self {
        case .samePlace: 0
        case .oneStep: 1
        case .twoOrThreeSteps: 2
        case .fourOrMoreSteps: 3
        }
    }
}

private extension TimeSpread {
    /// The quartiles of `times` (`ProgressAnalyzer.quantile`), sorting them once.
    init(times: [Int]) {
        let sorted = times.sorted()
        self.init(rightAnswers: sorted.count, lowerQuartileMs: ProgressAnalyzer.quantile(sorted: sorted, 0.25),
                  medianMs: ProgressAnalyzer.quantile(sorted: sorted, 0.5),
                  upperQuartileMs: ProgressAnalyzer.quantile(sorted: sorted, 0.75))
    }
}

private extension QuestionShown {
    /// Asked on its own, not with others as one chord.
    var isSingleNote: Bool { group == nil && groupSize == nil }
}

/// A question waiting for its answer, how far it is from the one before (`ShownNote.steps(after:)`)
/// and where it stands in its bar (`Analysis.place(of:after:in:)`), both decided when it was shown.
private struct WaitingQuestion {
    let shown: QuestionShown
    let stepsFromPrevious: Int?
    let place: BarPlace
}

/// A question's place for `PieceDay`: the first question shown after an in-order round moves into
/// another bar, another single note of such a round, or neither (anything else).
private enum BarPlace {
    case start, rest, neither
}

/// What the previous-note statistics and the start of a bar need of a question once the next one
/// is shown.
private struct ShownNote {
    let index: Int
    let clef: String
    /// A piece's staff (nil for random notes), so two treble staves of a grand staff stay apart.
    let staff: Int?
    /// A piece's bar (nil for random notes).
    let bar: Int?
    let position: Int
    let isSingleNote: Bool
    /// Notes named together share one; nil for a note asked on its own.
    let group: UUID?

    init(_ question: QuestionShown) {
        index = question.index
        clef = question.clef
        staff = question.pieceNote?.staff
        bar = question.pieceNote?.measure
        position = question.position
        isSingleNote = question.isSingleNote
        group = question.group
    }

    /// Staff steps from `before`, the question shown just before it in its round, when both are
    /// single notes on the same staff; nil otherwise.
    func steps(after before: ShownNote?) -> Int? {
        guard isSingleNote, let before, before.index == index - 1, before.isSingleNote,
              before.clef == clef, before.staff == staff else { return nil }
        return position - before.position
    }
}

private struct ClefKey<Value: Hashable>: Hashable {
    let clef: Clef
    let value: Value
}

private struct PieceTally {
    /// The piece's journal id; nil when its path stands in.
    let id: String?
    /// From the latest round, for its title, path and bar count.
    var context: PieceContext?
    var contextStart = Date.distantPast
    var rounds = 0, answers = 0, correct = 0
    var lastAnswer: Date?, lastRoundStart: Date?
    var bars: [Int: BarTally] = [:]
    /// By the start of the local day answered on.
    var days: [Date: PieceDayTally] = [:]

    mutating func addRound(_ piece: PieceContext, startedAt start: Date) {
        rounds += 1
        lastRoundStart = max(lastRoundStart ?? start, start)
        note(piece, startedAt: start)
    }

    /// An answer that counts, given at `time` on the local day starting `day`.
    mutating func add(_ answer: AnswerGiven, at time: Date, on day: Date, bar: Int?, singleNote: Bool, place: BarPlace,
                      method: AnswerMethod?, in piece: PieceContext, startedAt start: Date) {
        answers += 1
        if answer.correct { correct += 1 }
        lastAnswer = max(lastAnswer ?? time, time)
        if let bar { bars[bar, default: BarTally()].add(answer, singleNote: singleNote) }
        days[day, default: PieceDayTally()].add(answer, place: place, method: method)
        note(piece, startedAt: start)
    }

    private mutating func note(_ piece: PieceContext, startedAt start: Date) {
        guard start >= contextStart else { return }
        context = piece
        contextStart = start
    }

    func summary() -> PieceProgressSummary? {
        guard let context, let lastPractised = lastAnswer ?? lastRoundStart else { return nil }
        return PieceProgressSummary(title: context.title, path: context.path, lastPractised: lastPractised, rounds: rounds,
                                    answers: answers, correct: correct, measureCount: context.measureCount,
                                    bars: bars.map { $1.progress(bar: $0) }.sorted { $0.bar < $1.bar },
                                    days: days.map { $1.progress(day: $0) }.sorted { $0.day < $1.day }, pieceID: id)
    }
}

/// A bar's answers, and the times of its right answers to single notes, whatever the round's order.
private struct BarTally {
    var attempts = 0, correct = 0
    var singleNoteMs: [Int] = []

    mutating func add(_ answer: AnswerGiven, singleNote: Bool) {
        attempts += 1
        guard answer.correct else { return }
        correct += 1
        if singleNote { singleNoteMs.append(answer.responseMs) }
    }

    func progress(bar: Int) -> BarProgress {
        BarProgress(bar: bar, attempts: attempts, correct: correct, medianResponseMs: ProgressAnalyzer.median(singleNoteMs),
                    rightSingleNotes: singleNoteMs.count)
    }
}

/// One day of a piece: its answers, the right ones' times at the start of a bar and in the rest of
/// it, and the methods answered in.
private struct PieceDayTally {
    var answers = 0, correct = 0
    var barStartMs: [Int] = [], restOfBarMs: [Int] = []
    var methods: Set<AnswerMethod> = []

    mutating func add(_ answer: AnswerGiven, place: BarPlace, method: AnswerMethod?) {
        answers += 1
        if let method { methods.insert(method) }
        guard answer.correct else { return }
        correct += 1
        switch place {
        case .start: barStartMs.append(answer.responseMs)
        case .rest: restOfBarMs.append(answer.responseMs)
        case .neither: break
        }
    }

    func progress(day: Date) -> PieceDay {
        PieceDay(day: day, answers: answers, correct: correct,
                 barStartMs: ProgressAnalyzer.median(barStartMs), barStarts: barStartMs.count,
                 restOfBarMs: ProgressAnalyzer.median(restOfBarMs), restOfBar: restOfBarMs.count,
                 methods: AnswerMethod.allCases.filter(methods.contains))
    }
}

/// A round as the log tells it: its start and end (either may be missing) and its answers. A round
/// that came back after a crash spans two sessions; it belongs to the one it started in.
private struct RoundRecord {
    let id: UUID
    var started: Date?
    var start: RoundStarted?
    var end: RoundEnded?
    /// Every `answerGiven` for it, for a round that never ended.
    var answers = 0, correct = 0
    /// Of them, those on a real piano (source `midi`), whatever the filter.
    var realPianoAnswers = 0
    /// The round time as of its latest start, pause, resume or restore; nil before its start.
    var clock: RoundClock?
    /// The round time at its last answer, for a round that never ended.
    var activeMsAtLastAnswer: Int?
    /// It has an answer the filter's clef and method let through.
    var hasAnswerInFilter = false
    var singleStaff = false
    /// A piece round asking its notes in order (`PieceContext.order` `inOrder`), so its bars come one
    /// after another: the start of a bar is told apart from the rest (`PieceDay`).
    var inOrder = false
    /// A piece round's piece: its key in the report (its journal id, or failing that its path),
    /// and its journal id.
    var piece: (key: String, id: String?)?

    /// From `roundEnded`; a round that never ended (the app crashed, or it's still going) runs to
    /// its last answer, pauses left out, and the time before it came back after a crash too.
    var durationMs: Int? {
        if let end { return end.durationMs }
        guard started != nil else { return nil }
        return activeMsAtLastAnswer
    }
}

/// A round's time as of one of its events: the round time then, and whether it ran on from there.
private struct RoundClock {
    let time: Date
    let activeMs: Int
    let running: Bool

    /// The round time at `later`.
    func activeMs(at later: Date) -> Int {
        guard running else { return activeMs }
        return activeMs + max(0, Int((later.timeIntervalSince(time) * 1000).rounded()))
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
    /// Treble first, then bass, then the guitar clef.
    var order: Int {
        switch self {
        case .treble: 0
        case .bass: 1
        case .treble8vb: 2
        }
    }
}
