import Foundation

/// The plain-language lines under the "Becoming automatic" panels, and the labels they share with
/// the charts. Pure functions of the report's numbers, with every threshold named, so they can be
/// tested and tuned. Each returns nil when there's too little to say anything.
enum AutomaticInsight {
    // MARK: - How long your answers take

    /// Fewer right answers than this in either window and the two middle halves aren't compared:
    /// quartiles of a handful of times jump about.
    static let minimumRightAnswersToCompare = 20
    /// The smallest change in the middle half's width called narrower or wider: at least 0.1 s, and
    /// at least a tenth of what it was.
    static let spreadChangeMs = 100
    static let spreadChangeFraction = 0.1

    enum SpreadChange: Equatable {
        case narrower, wider, same
    }

    /// How the middle half's width changed since the window before; nil when there's nothing to
    /// compare (no window before, or too few right answers in either).
    static func spreadChange(current: TimeSpread, previous: TimeSpread?) -> SpreadChange? {
        guard let previous, current.rightAnswers >= minimumRightAnswersToCompare,
              previous.rightAnswers >= minimumRightAnswersToCompare,
              let now = current.spreadMs, let before = previous.spreadMs else { return nil }
        let threshold = max(spreadChangeMs, Int((Double(before) * spreadChangeFraction).rounded()))
        let change = now - before
        if change <= -threshold { return .narrower }
        if change >= threshold { return .wider }
        return .same
    }

    /// "Middle half: 0,9–1,5 s (was 1,2–2,8 s). Your times are closer together than before."
    static func spreadLine(current: TimeSpread, previous: TimeSpread?, locale: Locale = .current) -> String? {
        guard let lower = current.lowerQuartileMs, let upper = current.upperQuartileMs else { return nil }
        let now = "Middle half: \(secondsRange(lower, upper, locale: locale))"
        guard let change = spreadChange(current: current, previous: previous),
              let before = previous, let beforeLower = before.lowerQuartileMs,
              let beforeUpper = before.upperQuartileMs else { return now }
        let verdict = switch change {
        case .narrower: "Your times are closer together than before."
        case .wider: "Your times vary more than before."
        case .same: "About as spread out as before."
        }
        return "\(now) (was \(secondsRange(beforeLower, beforeUpper, locale: locale))). \(verdict)"
    }

    // MARK: - Mistakes by speed

    /// Answers under this time are the fast ones…
    static let fastUnderMs = 1000
    /// …and answers taking at least this long the slow ones.
    static let slowFromMs = 3000
    /// A group's mistake rate stands out when it's at least this many times the overall rate (and
    /// the highest of the three groups).
    static let standsOutRatio = 1.5
    /// Fewer answers than this in all and nothing is said.
    static let minimumAnswers = 50
    /// Fewer mistakes than this in all, and there's no pattern to see (none at all is said, though).
    static let minimumMistakes = 5
    /// A group (fast, middle, slow) needs this many answers for its rate to count…
    static let minimumGroupAnswers = 20
    /// …and this many mistakes to stand out.
    static let minimumGroupMistakes = 3

    enum SpeedPattern: Equatable {
        /// The fastest answers have clearly the most mistakes.
        case rushing
        /// The slowest answers have clearly the most mistakes.
        case slowOnes
        /// No group stands out.
        case even
        /// Not one mistake.
        case noMistakes
    }

    static func speedPattern(_ bins: [SpeedBin]) -> SpeedPattern? {
        let answers = bins.map(\.answers).reduce(0, +)
        let wrong = bins.map(\.wrong).reduce(0, +)
        guard answers >= minimumAnswers else { return nil }
        guard wrong > 0 else { return .noMistakes }
        guard wrong >= minimumMistakes else { return nil }
        let overall = Double(wrong) / Double(answers)

        struct Group {
            var answers = 0
            var wrong = 0
            var rate: Double? {
                answers >= AutomaticInsight.minimumGroupAnswers ? Double(wrong) / Double(answers) : nil
            }
        }
        var fast = Group(), middle = Group(), slow = Group()
        for bin in bins {
            if let upper = bin.upperMs, upper <= fastUnderMs {
                fast.answers += bin.answers
                fast.wrong += bin.wrong
            } else if bin.lowerMs >= slowFromMs {
                slow.answers += bin.answers
                slow.wrong += bin.wrong
            } else {
                middle.answers += bin.answers
                middle.wrong += bin.wrong
            }
        }
        func standsOut(_ group: Group, over others: [Group]) -> Bool {
            guard let rate = group.rate, group.wrong >= minimumGroupMistakes, rate >= standsOutRatio * overall else {
                return false
            }
            return others.allSatisfy { other in other.rate.map { $0 < rate } ?? true }
        }
        if standsOut(fast, over: [middle, slow]) { return .rushing }
        if standsOut(slow, over: [fast, middle]) { return .slowOnes }
        // "Evenly" needs at least two speeds to compare.
        return [fast, middle, slow].filter { $0.rate != nil }.count >= 2 ? .even : nil
    }

    static func speedLine(_ bins: [SpeedBin]) -> String? {
        switch speedPattern(bins) {
        case .rushing: "Your fastest answers have the most mistakes: you may be rushing."
        case .slowOnes: "Mistakes come with slow answers, not fast ones: you're not rushing."
        case .even: "Mistakes are spread evenly across speeds."
        case .noMistakes: "No mistakes at any speed."
        case nil: nil
        }
    }

    // MARK: - After the note before

    /// Fewer right answers than this a step away, or 4 or more steps away, and the two aren't compared.
    static let minimumRightAnswersPerDistance = 20
    /// A difference in median time between a step and a far jump smaller than this makes no difference.
    static let distanceDifferenceMs = 150

    enum PreviousNotePattern: Equatable {
        /// Notes a step from the last are named this much quicker than far jumps.
        case stepsQuicker(ms: Int)
        /// Far jumps are named this much quicker than steps.
        case jumpsQuicker(ms: Int)
        /// Within `distanceDifferenceMs` either way.
        case noDifference
    }

    static func previousNotePattern(_ rows: [PreviousNoteRow]) -> PreviousNotePattern? {
        guard let step = rows.first(where: { $0.distance == .oneStep }),
              let jump = rows.first(where: { $0.distance == .fourOrMoreSteps }),
              step.correct >= minimumRightAnswersPerDistance, jump.correct >= minimumRightAnswersPerDistance,
              let stepMs = step.medianMs, let jumpMs = jump.medianMs else { return nil }
        let difference = jumpMs - stepMs
        if difference > distanceDifferenceMs { return .stepsQuicker(ms: difference) }
        if difference < -distanceDifferenceMs { return .jumpsQuicker(ms: -difference) }
        return .noDifference
    }

    static func previousNoteLine(_ rows: [PreviousNoteRow], locale: Locale = .current) -> String? {
        switch previousNotePattern(rows) {
        case .stepsQuicker(let ms):
            "Notes a step from the last are named \(seconds(ms, locale: locale)) quicker than far jumps: you still read partly from the note before."
        case .jumpsQuicker(let ms):
            "Notes a step from the last are named \(seconds(ms, locale: locale)) slower than far jumps: you're not leaning on the note before."
        case .noDifference:
            "How far a note is from the last one makes no difference: each is read on its own."
        case nil:
            nil
        }
    }

    // MARK: - Words and numbers

    /// "Last 30 days" and "The 30 days before"; all time has nothing before it.
    static func periodNames(_ range: ProgressFilter.Range) -> (current: String, previous: String?) {
        (range.label, range.days.map { "The \($0) days before" })
    }

    /// "0,3 s" (to a tenth, in the locale's decimals).
    static func seconds(_ ms: Int, locale: Locale = .current) -> String {
        "\(tenths(ms, locale: locale)) s"
    }

    /// "0,9–1,5 s"
    static func secondsRange(_ lowerMs: Int, _ upperMs: Int, locale: Locale = .current) -> String {
        "\(tenths(lowerMs, locale: locale))–\(tenths(upperMs, locale: locale)) s"
    }

    private static func tenths(_ ms: Int, locale: Locale) -> String {
        (Double(ms) / 1000).formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// A time in seconds with as few decimals as it needs: "1", "1,5", "0,75".
    static func plainSeconds(_ ms: Int, locale: Locale = .current) -> String {
        (Double(ms) / 1000).formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// A histogram bin: "1–1,25 s", the last "6 s or more".
    static func histogramBinLabel(_ index: Int, locale: Locale = .current) -> String {
        let width = ResponseTimes.histogramBinMs
        guard index < ResponseTimes.histogramBins else {
            return "\(plainSeconds(index * width, locale: locale)) s or more"
        }
        return "\(plainSeconds(index * width, locale: locale))–\(plainSeconds((index + 1) * width, locale: locale)) s"
    }

    /// A speed bin in full: "Under 0,75 s", "0,75–1 s", "5 s or more".
    static func speedBinLabel(_ bin: SpeedBin, locale: Locale = .current) -> String {
        guard let upper = bin.upperMs else { return "\(plainSeconds(bin.lowerMs, locale: locale)) s or more" }
        guard bin.lowerMs > 0 else { return "Under \(plainSeconds(upper, locale: locale)) s" }
        return "\(plainSeconds(bin.lowerMs, locale: locale))–\(plainSeconds(upper, locale: locale)) s"
    }

    /// A speed bin on the axis, in seconds without the unit: "<0,75", "0,75–1", "5+".
    static func speedAxisLabel(_ bin: SpeedBin, locale: Locale = .current) -> String {
        guard let upper = bin.upperMs else { return "\(plainSeconds(bin.lowerMs, locale: locale))+" }
        guard bin.lowerMs > 0 else { return "<\(plainSeconds(upper, locale: locale))" }
        return "\(plainSeconds(bin.lowerMs, locale: locale))–\(plainSeconds(upper, locale: locale))"
    }

    /// "One step from the note before", "Same line or space as the note before".
    static func distanceDescription(_ distance: PreviousNoteDistance) -> String {
        distance == .samePlace ? "Same line or space as the note before" : "\(distance.label) from the note before"
    }
}
