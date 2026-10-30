import Foundation
@testable import Clefwise

/// A made-up but realistic usage log, the same for a given seed, for tests and for trying the
/// dashboard on months or years of practice. Most days have an evening session and some a morning
/// one too; rounds use both clefs, every answer input and naming system, C, G major and random
/// keys, added sharps, and a piece practised by bar with an 8va passage. Answers get righter and
/// faster over the days. The stats snapshot comes first, and now and then the app crashes,
/// leaving a round without an end and a session without a quit.
enum SyntheticUsage {
    static let pieceTitle = "Minuet in G"
    static let piecePath = "/Users/me/Music/Minuet in G.musicxml"
    static let pieceBars = 32
    /// What the snapshot holds from before the log.
    static let snapshot = StatsSnapshot(reason: "beforeUsageLog", noteStats: [
        "treble.E4": NoteStat(attempts: 42, correct: 35, recent: [true, true, false, true, true, true, true, true]),
        "treble.F5": NoteStat(attempts: 30, correct: 22, recent: [true, false, true, true, true, false, true, true]),
        "treble.F♯5": NoteStat(attempts: 12, correct: 6, recent: [false, true, false, true, true, false, true, false]),
        "treble.C4": NoteStat(attempts: 18, correct: 11, recent: [true, false, true, false, true, true, true, false]),
        "bass.G2": NoteStat(attempts: 20, correct: 13, recent: [true, true, false, true, false, true, true, true]),
        "bass.D3": NoteStat(attempts: 16, correct: 12, recent: [true, true, true, false, true, true, true, true]),
    ], bestScores: ["treble.staff": 21, "bass.staff": 14])

    /// Practice on `days` local days up to and including today, none of it after `now`.
    static func events(days: Int = 90, seed: UInt64 = 1, now: Date, calendar: Calendar) -> [LoggedEvent] {
        var writer = Writer(seed: seed, now: now)
        let today = calendar.startOfDay(for: now)
        var practisedDays = 0
        for back in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let progress = days > 1 ? Double(days - 1 - back) / Double(days - 1) : 1
            // About one day in four off, and a few days away a third of the way in.
            let away = days >= 30 && (days / 3..<days / 3 + 4).contains(days - 1 - back)
            guard !away, writer.random.next() > 0.25 else { continue }
            practisedDays += 1
            if writer.chance(0.35), let morning = calendar.date(bySettingHour: 7 + writer.number(below: 3),
                                                                   minute: writer.number(below: 60), second: 0, of: day) {
                writer.session(at: morning, progress: progress, crashes: false)
            }
            if let evening = calendar.date(bySettingHour: 18 + writer.number(below: 3), minute: writer.number(below: 60),
                                           second: 0, of: day) {
                writer.session(at: evening, progress: progress, crashes: practisedDays % 60 == 3)
            }
        }
        return writer.events
    }

    /// The piece: three notes a bar in G major, bars 13–14 and 29–30 under an 8va line.
    fileprivate static let pieceNotes: [(bar: Int, written: Pitch, octaveShift: Int)] = {
        let tune = [Pitch(.d, 5), Pitch(.g, 4), Pitch(.a, 4), Pitch(.b, 4), Pitch(.c, 5), Pitch(.d, 5),
                    Pitch(.g, 4), Pitch(.g, 4), Pitch(.e, 5), Pitch(.c, 5), Pitch(.d, 5), Pitch(.e, 5),
                    Pitch(.f, 5, .sharp), Pitch(.g, 5), Pitch(.g, 4), Pitch(.a, 4), Pitch(.f, 4, .sharp), Pitch(.g, 4)]
        return (0..<pieceBars * 3).map { index in
            let bar = index / 3 + 1
            return (bar, tune[index % tune.count], [13, 14, 29, 30].contains(bar) ? 1 : 0)
        }
    }()
}

/// Writes the log a session at a time, dropping a session that would run past `now`.
private struct Writer {
    var random: SeededRandom
    private let seed: UInt64
    private let now: Date
    private var ids: UInt64 = 0
    private(set) var events: [LoggedEvent] = []
    private var session: [LoggedEvent] = []
    private var sessionID = UUID()
    private var time = Date()
    private var settings = Game.Settings()
    private var bestScores: [String: Int] = [:]
    private var loggedSnapshot = false

    init(seed: UInt64, now: Date) {
        random = SeededRandom(seed: seed)
        self.seed = seed
        self.now = now
    }

    mutating func chance(_ probability: Double) -> Bool { random.next() < probability }
    mutating func number(below count: Int) -> Int { min(count - 1, Int(random.next() * Double(count))) }
    mutating func pick<T>(_ options: [T]) -> T { options[number(below: options.count)] }

    /// Ids from the seed and a counter, so they're the same every run.
    private mutating func id() -> UUID {
        ids += 1
        return withUnsafeBytes(of: (seed.bigEndian, ids.bigEndian)) { UUID(uuid: $0.load(as: uuid_t.self)) }
    }

    private mutating func log(_ event: UsageEvent) {
        session.append(LoggedEvent(event, session: sessionID, sequence: session.count, time: time))
    }

    private mutating func wait(ms: Int) { time = time.addingTimeInterval(Double(ms) / 1000) }

    mutating func session(at start: Date, progress: Double, crashes: Bool) {
        sessionID = id()
        session = []
        time = start
        log(.appLaunched(AppLaunched(appVersion: "0.1.0", build: "7", osVersion: "26.5", model: "Mac15,12",
                                     locale: "en_GB", timeZone: "Europe/Stockholm", screen: Size(width: 1728, height: 1117))))
        let withSnapshot = !loggedSnapshot
        if withSnapshot { log(.statsSnapshot(SyntheticUsage.snapshot)) }
        log(.windowResized(WindowResized(size: Size(width: 1100, height: 760))))
        log(.appActivity(AppActivity(active: true)))
        wait(ms: 4000 + number(below: 20_000))
        var pieceOpen = false
        let rounds = 1 + number(below: 4)
        for index in 0..<rounds {
            let isLast = index == rounds - 1
            round(progress: progress, pieceOpen: &pieceOpen, crashes: crashes && isLast)
            if crashes && isLast { break }
            wait(ms: 5000 + number(below: 40_000))
        }
        if !crashes {
            log(.appActivity(AppActivity(active: false)))
            log(.appTerminated(AppTerminated(sessionSeconds: time.timeIntervalSince(start))))
        }
        guard time <= now else { return }
        events += session
        if withSnapshot { loggedSnapshot = true }
    }

    private mutating func round(progress: Double, pieceOpen: inout Bool, crashes: Bool) {
        let onPiece = chance(0.15)
        var next = Game.Settings()
        next.clefChoice = pick([.treble, .treble, .treble, .bass, .bass, .both])
        next.range = pick([.staff, .staff, .staff, .oneLedgerLine, .oneLedgerLine, .threeLedgerLines])
        next.mode = onPiece || chance(0.3) ? .practice : .sprint
        next.naming = pick([.letters, .letters, .letters, .letters, .letters, .letters, .letters, .solfege, .solfege, .sargam])
        next.answerInput = pick([.buttons, .buttons, .buttons, .piano, .piano, .keyboard])
        next.key = chance(0.6) ? .fixed(.cMajor) : chance(0.6) ? .fixed(KeySignature(fifths: 1)) : .random
        next.addsAccidentals = chance(0.15)
        if onPiece {
            next.piece.startBar = pick([1, 17])
            next.piecePath = SyntheticUsage.piecePath
            if !pieceOpen {
                log(.pieceOpened(PieceOpened(path: SyntheticUsage.piecePath, title: SyntheticUsage.pieceTitle, via: .menu,
                                             parts: [PartInfo(name: "Piano", notes: 190, measures: SyntheticUsage.pieceBars,
                                                              staves: 2, skipped: 0)])))
                pieceOpen = true
            }
        }
        logChanges(to: next)
        settings = next

        let notes = SyntheticUsage.pieceNotes.filter { $0.bar >= settings.piece.startBar }
        let piece = onPiece ? PieceContext(title: SyntheticUsage.pieceTitle, path: SyntheticUsage.piecePath, part: "Piano",
                                           partIndex: 0, hand: "right", order: "inOrder", startBar: settings.piece.startBar,
                                           oneNotePerChord: false, noteCount: notes.count, measureCount: SyntheticUsage.pieceBars)
            : nil
        let key: KeySignature
        switch settings.key {
        case .fixed(let fixed): key = onPiece ? KeySignature(fifths: 1) : fixed
        case .random: key = onPiece ? KeySignature(fifths: 1) : pick(KeySignature.all.filter { $0 != .cMajor })
        }
        let round = id(), start = time
        log(.roundStarted(RoundStarted(round: round, via: pick([.button, .key, .key, .playAgain]),
                                       settings: JSONValue(encoding: settings), keyFifths: key.fifths, piece: piece)))

        var score = 0, attempts = 0, streak = 0, bestStreak = 0, correctMs: [Int] = [], missed: [String] = []
        let questions = onPiece ? notes.count : settings.mode == .practice ? 12 + number(below: 20) : Int.max
        // A crash comes some way into the round, before a practice round would end.
        let crashAfter = crashes ? 3 + number(below: 8) : Int.max
        var index = 0
        while index < questions {
            // The sprint clock can run out in the pause after a miss.
            if settings.mode == .sprint, time.timeIntervalSince(start) >= 60 {
                time = max(start.addingTimeInterval(60), session.last?.time ?? time)
                end(round, .timeUp, start: start, score: score, attempts: attempts, bestStreak: bestStreak, correctMs: correctMs,
                    missed: missed, unanswered: nil)
                return
            }
            let question = id()
            let (shown, pitch) = makeQuestion(round: round, id: question, index: index, key: key,
                                              piece: onPiece ? notes[index] : nil)
            var response = answer(to: shown, pitch: pitch, progress: progress)
            if settings.mode == .sprint, time.timeIntervalSince(start) * 1000 + Double(response.responseMs) > 60_000 {
                log(.questionShown(shown))
                let shownMs = 60_000 - Int((time.timeIntervalSince(start) * 1000).rounded())
                time = start.addingTimeInterval(60)
                end(round, .timeUp, start: start, score: score, attempts: attempts, bestStreak: bestStreak, correctMs: correctMs,
                    missed: missed, unanswered: UnansweredQuestion(question: question, shownMs: shownMs, keystrokes: []))
                return
            }
            log(.questionShown(shown))
            wait(ms: response.responseMs)
            attempts += 1
            if response.correct {
                score += 1
                streak += 1
                bestStreak = max(bestStreak, streak)
                correctMs.append(response.responseMs)
            } else {
                streak = 0
                if !missed.contains("\(shown.clef).\(pitch.name)") { missed.append("\(shown.clef).\(pitch.name)") }
            }
            response.scoreAfter = score
            response.streakAfter = streak
            log(.answerGiven(response))
            if attempts == crashAfter { return }
            if !response.correct {
                if chance(0.1) {
                    wait(ms: 300)
                    log(.inputIgnored(InputIgnored(round: round, reason: "missPause", source: response.source, detail: response.letter)))
                }
                wait(ms: 1200)
            }
            index += 1
        }
        end(round, onPiece ? .pieceComplete : .stopped, start: start, score: score, attempts: attempts, bestStreak: bestStreak,
            correctMs: correctMs, missed: missed, unanswered: nil)
    }

    private mutating func makeQuestion(round: UUID, id: UUID, index: Int, key: KeySignature,
                                       piece note: (bar: Int, written: Pitch, octaveShift: Int)?) -> (QuestionShown, Pitch) {
        let clef: Clef, written: Pitch, octaveShift: Int, printed: Int?
        if let note {
            clef = .treble
            written = note.written
            octaveShift = note.octaveShift
            printed = nil
        } else {
            clef = pick(settings.clefChoice.clefs)
            let positions = settings.range.positions
            let natural = clef.pitch(atPosition: positions.lowerBound + number(below: positions.count))
            let fromKey = key.accidental(for: natural.letter)
            // Added accidentals: now and then a printed sharp on a note the key leaves natural.
            let sharpened = settings.addsAccidentals && fromKey == .natural && ![.e, .b].contains(natural.letter) && chance(0.3)
            written = natural.with(sharpened ? .sharp : fromKey)
            octaveShift = 0
            printed = sharpened ? 1 : nil
        }
        let pitch = Pitch(written.letter, written.octave + octaveShift, written.accidental)
        return (QuestionShown(
            round: round, question: id, index: index, clef: clef.rawValue, pitch: LoggedPitch(pitch),
            written: LoggedPitch(written), position: clef.position(of: written), keyFifths: key.fifths,
            printedAccidental: printed, octaveShift: octaveShift,
            pieceNote: note.map { PieceNoteRef(measure: $0.bar, staff: 1, onset: Double(index), chord: index) },
            pickChance: note == nil ? 0.02 + random.next() * 0.1 : nil, naming: settings.naming.rawValue,
            input: settings.answerInput.rawValue, hintsVisible: settings.showHints,
            keyNamesVisible: settings.answerInput == .piano && settings.showKeyNames), pitch)
    }

    /// Righter and faster as `progress` goes from 0 to 1; ledger lines, sharps and the bass clef are harder.
    /// Score and streak are the caller's to fill in.
    private mutating func answer(to question: QuestionShown, pitch: Pitch, progress: Double) -> AnswerGiven {
        let ledger = question.position < 0 || question.position > 8
        let difficulty = (ledger ? 0.12 : 0) + (pitch.accidental == .natural ? 0 : 0.06) + (question.clef == "bass" ? 0.05 : 0)
        let correct = chance(min(0.98, 0.6 + 0.35 * progress - difficulty))
        let input = settings.answerInput
        let slower = input == .piano ? 1.2 : input == .keyboard ? 1.3 : 1
        let ms = max(300, Int((2600 - 1600 * progress) * (0.55 + random.next() * 0.9) * slower * (1 + difficulty)) + (correct ? 0 : 400))

        // Misses are mostly a neighbouring letter, or on the piano now and then the right note an octave off.
        let wrongOctave = !correct && input == .piano && chance(0.2)
        let letter = correct || wrongOctave ? pitch.letter : NoteLetter(rawValue: (pitch.letter.rawValue + pick([1, 6, 2, 5])) % 7)!
        let accidental = correct || wrongOctave ? pitch.accidental : .natural
        let played = input == .piano ? Pitch(letter, pitch.octave + (wrongOctave ? 1 : 0), accidental) : nil
        let source: AnswerSource = switch input {
        case .buttons: chance(0.6) ? .click : .shortcut
        case .piano: .piano
        case .keyboard: .typing
        }
        let keystrokes: [Keystroke] = switch source {
        case .typing: [Keystroke(key: letter.name.lowercased(), ms: ms * 2 / 3, result: .typed)]
            + (accidental == .sharp ? [Keystroke(key: "#", ms: ms * 5 / 6, result: .typed)] : [])
            + [Keystroke(key: "Return", ms: ms, result: .submitted)]
        case .shortcut: [Keystroke(key: letter.name.lowercased(), ms: ms, result: .submitted)]
        case .click, .piano: []
        }
        return AnswerGiven(round: question.round, question: question.question, responseMs: ms, source: source,
                           letter: letter.name, accidental: accidental.rawValue,
                           name: settings.naming.name(of: played ?? Pitch(letter, 4, accidental)),
                           pitch: played.map(LoggedPitch.init), correct: correct,
                           wrongOctave: played.map { _ in wrongOctave }, keystrokes: keystrokes,
                           scoreAfter: 0, streakAfter: 0)
    }

    private mutating func end(_ round: UUID, _ reason: RoundEndReason, start: Date, score: Int, attempts: Int, bestStreak: Int,
                              correctMs: [Int], missed: [String], unanswered: UnansweredQuestion?) {
        var bestScore: Int?, isNewBest = false
        if settings.mode == .sprint, settings.piecePath == nil {
            let key = "\(settings.clefChoice.rawValue).\(settings.range.rawValue)"
            isNewBest = score > (bestScores[key] ?? 0)
            bestScores[key] = max(bestScores[key] ?? 0, score)
            bestScore = bestScores[key]
        }
        log(.roundEnded(RoundEnded(
            round: round, reason: reason,
            durationMs: reason == .timeUp ? 60_000 : Int((time.timeIntervalSince(start) * 1000).rounded()), score: score,
            attempts: attempts, bestStreak: bestStreak,
            averageResponseMs: correctMs.isEmpty ? nil : correctMs.reduce(0, +) / correctMs.count,
            bestScore: bestScore, isNewBest: isNewBest, notesToReview: Array(missed.prefix(4)),
            unansweredQuestion: unanswered)))
    }

    /// One `settingChanged` per setting the toolbar changed since the last round.
    private mutating func logChanges(to next: Game.Settings) {
        let pairs: [(String, String, String)] = [
            ("clefChoice", settings.clefChoice.rawValue, next.clefChoice.rawValue),
            ("range", settings.range.rawValue, next.range.rawValue),
            ("mode", settings.mode.rawValue, next.mode.rawValue),
            ("naming", settings.naming.rawValue, next.naming.rawValue),
            ("answerInput", settings.answerInput.rawValue, next.answerInput.rawValue),
        ]
        for (setting, from, to) in pairs where from != to {
            log(.settingChanged(SettingChanged(setting: setting, from: .string(from), to: .string(to))))
        }
    }
}
