import Foundation

/// A practice round as its run file tells it: what `Game` needs to bring the round back after a
/// crash, or to end it as `interrupted` when it can't (spec/practice-journal.md, "After a crash").
/// Worked out from the events alone, in the order they were written. They may span several app
/// sessions: each crash ends one, and the next starts with its `appLaunched`.
struct RoundReplay: Equatable {
    /// The round's start; nil when its line isn't there.
    private(set) var started: RoundStarted?
    /// When the run's last event was logged; nil without events. An `interrupted` end takes this time.
    private(set) var lastEventTime: Date?
    /// As after the last answer: its `scoreAfter` and `streakAfter`.
    private(set) var score = 0
    private(set) var streak = 0
    /// One per `answerGiven`: notes asked together are answered one each, as `Game` counts them.
    private(set) var attempts = 0
    /// The highest `streakAfter`.
    private(set) var bestStreak = 0
    /// Wrong answers by note, each joined to its `questionShown`, as `Game` keeps them for the
    /// notes to review.
    private(set) var misses: [StaffNote: Int] = [:]
    /// As `Game` keeps them for the average, in seconds: one per note answered right on its own,
    /// and one per set of notes asked together that were all named right.
    private(set) var responseTimes: [TimeInterval] = []
    /// `questionShown` events, one per note: the next question's index.
    private(set) var questionsShown = 0
    /// The round time used, pauses left out: exact as of the last `roundPaused` or `roundRestored`,
    /// plus the time it then ran, up to the last event of its session. The time between a crash
    /// and the round coming back counts for nothing.
    private(set) var activeMs = 0
    /// Time paused: each `roundResumed`'s `pausedMs`, and a pause still going when a session
    /// stopped, up to that session's last event.
    private(set) var pausedMs = 0
    /// The latest question: one note, or the notes asked together, in the order logged.
    private(set) var lastQuestion: [QuestionShown] = []
    /// `lastQuestion` was answered.
    private(set) var lastQuestionAnswered = false
    /// Round time and paused time since `lastQuestion` appeared, as `Game` measures a question
    /// left unanswered.
    private(set) var lastQuestionShownMs = 0
    private(set) var lastQuestionPausedMs = 0
    /// The round came back after a crash and carried on, then stopped again before another answer
    /// (after its last `roundRestored` comes a `roundResumed` and no `answerGiven`). Its note may be
    /// what crashed the app, so it isn't brought back again.
    private(set) var resumedAfterRestoreWithoutAnswer = false
    /// The run already has its `roundEnded`.
    private(set) var hasEnded = false

    /// The question on screen when the app stopped: `lastQuestion`, unless it was answered.
    var unansweredQuestion: [QuestionShown] { lastQuestionAnswered ? [] : lastQuestion }

    /// The average response time as `Game` logs it, in milliseconds; nil with nothing to average.
    var averageResponseMs: Int? {
        responseTimes.isEmpty ? nil : Int((responseTimes.reduce(0, +) / Double(responseTimes.count) * 1000).rounded())
    }

    /// Replays the events of `round`; events of other rounds are left out, but every event's time
    /// and session count (an `appActivity` is still the round's last event).
    init(round: UUID, events: [LoggedEvent]) {
        var clock = Clock()
        var shown: [UUID: QuestionShown] = [:]
        /// Answers for the response times, notes asked together as one.
        var timed: [(group: UUID?, seconds: TimeInterval, right: Bool)] = []
        var lastQuestionAt: (activeMs: Int, pausedMs: Int)?
        var restored = false, resumedSinceRestore = false, answeredSinceRestore = false

        for logged in events {
            clock.enter(logged.session)
            switch logged.event {
            case .roundStarted(let start) where start.round == round && started == nil:
                started = start
                clock.start(at: logged.time)
            case .questionShown(let question) where question.round == round:
                questionsShown += 1
                shown[question.question] = question
                if let group = question.group, lastQuestion.last?.group == group, !lastQuestionAnswered {
                    lastQuestion.append(question)
                } else {
                    lastQuestion = [question]
                    lastQuestionAnswered = false
                    lastQuestionAt = (clock.active(at: logged.time), clock.paused(at: logged.time))
                }
            case .answerGiven(let answer) where answer.round == round:
                attempts += 1
                score = answer.scoreAfter
                streak = answer.streakAfter
                bestStreak = max(bestStreak, answer.streakAfter)
                if !answer.correct, let question = shown[answer.question], let note = Self.staffNote(of: question) {
                    misses[note, default: 0] += 1
                }
                // Notes asked together are answered at once, one after the other.
                if let group = answer.group, timed.last?.group == group {
                    timed[timed.count - 1].right = timed[timed.count - 1].right && answer.correct
                } else {
                    timed.append((answer.group, Double(answer.responseMs) / 1000, answer.correct))
                }
                if lastQuestion.contains(where: { $0.question == answer.question }) { lastQuestionAnswered = true }
                answeredSinceRestore = true
            case .roundPaused(let pause) where pause.round == round:
                clock.pause(activeMs: pause.activeMs, at: logged.time)
            case .roundResumed(let resume) where resume.round == round:
                clock.resume(pausedMs: resume.pausedMs, at: logged.time)
                resumedSinceRestore = restored
            case .roundRestored(let restore) where restore.round == round:
                clock.restore(activeMs: restore.activeMs, at: logged.time)
                restored = true
                resumedSinceRestore = false
                answeredSinceRestore = false
            case .roundEnded(let end) where end.round == round:
                hasEnded = true
            default:
                break
            }
            clock.lastTime = logged.time
            lastEventTime = logged.time
        }
        clock.stop()

        activeMs = clock.activeMs
        pausedMs = clock.pausedMs
        responseTimes = timed.filter(\.right).map(\.seconds)
        if let lastQuestionAt {
            lastQuestionShownMs = max(0, activeMs - lastQuestionAt.activeMs)
            lastQuestionPausedMs = max(0, pausedMs - lastQuestionAt.pausedMs)
        }
        resumedAfterRestoreWithoutAnswer = restored && resumedSinceRestore && !answeredSinceRestore
    }

    /// The note `question` asked, as stats and misses know it; nil when its clef or pitch doesn't read.
    static func staffNote(of question: QuestionShown) -> StaffNote? {
        guard let clef = Clef(rawValue: question.clef), let pitch = pitch(question.pitch) else { return nil }
        return StaffNote(clef: clef, pitch: pitch)
    }

    /// The pitch a log line names; nil when it doesn't read.
    static func pitch(_ logged: LoggedPitch) -> Pitch? {
        guard logged.letter.count == 1, let letter = logged.letter.first.flatMap(NoteLetter.init(character:)),
              let accidental = Accidental(rawValue: logged.accidental) else { return nil }
        return Pitch(letter, logged.octave, accidental)
    }

    /// The round's clock as the events tell it: running or paused since an event, or stopped
    /// because the app stopped (a new session began) and the round hasn't come back yet.
    private struct Clock {
        private enum State {
            case running(since: Date), paused(since: Date), stopped
        }

        private(set) var activeMs = 0
        private(set) var pausedMs = 0
        private var state = State.stopped
        private var session: UUID?
        /// The latest event's time so far.
        var lastTime: Date?

        /// Before each event: one from another session means the app stopped after the last one,
        /// so the clock stops there.
        mutating func enter(_ session: UUID) {
            if let current = self.session, current != session { stop() }
            self.session = session
        }

        mutating func start(at time: Date) {
            activeMs = 0
            pausedMs = 0
            state = .running(since: time)
        }

        /// `roundPaused` says the round time exactly.
        mutating func pause(activeMs: Int, at time: Date) {
            self.activeMs = activeMs
            state = .paused(since: time)
        }

        /// `roundResumed` says how long the pause lasted.
        mutating func resume(pausedMs: Int, at time: Date) {
            self.pausedMs += pausedMs
            state = .running(since: time)
        }

        /// `roundRestored` says the round time brought back; the round is paused from then on.
        mutating func restore(activeMs: Int, at time: Date) {
            self.activeMs = activeMs
            state = .paused(since: time)
        }

        /// Stops the clock at the latest event, adding the time since it last started or paused.
        mutating func stop() {
            if let lastTime {
                activeMs = active(at: lastTime)
                pausedMs = paused(at: lastTime)
            }
            state = .stopped
        }

        func active(at time: Date) -> Int {
            guard case .running(let since) = state else { return activeMs }
            return activeMs + Self.milliseconds(from: since, to: time)
        }

        func paused(at time: Date) -> Int {
            guard case .paused(let since) = state else { return pausedMs }
            return pausedMs + Self.milliseconds(from: since, to: time)
        }

        private static func milliseconds(from start: Date, to end: Date) -> Int {
            max(0, Int((end.timeIntervalSince(start) * 1000).rounded()))
        }
    }
}
