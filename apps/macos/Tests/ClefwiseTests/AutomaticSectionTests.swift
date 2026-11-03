import Foundation
import Testing
@testable import Clefwise

/// The "Becoming automatic" lines and labels: what each says, from which numbers, at which thresholds.
@Suite struct AutomaticSectionTests {
    private let swedish = Locale(identifier: "sv_SE")
    private let english = Locale(identifier: "en_US")

    // MARK: - How long your answers take

    private func spread(_ lower: Int, _ upper: Int, answers: Int = 500) -> TimeSpread {
        TimeSpread(rightAnswers: answers, lowerQuartileMs: lower, medianMs: (lower + upper) / 2, upperQuartileMs: upper)
    }

    @Test func theMiddleHalfIsSaidWithWhatItWas() {
        let times = ProgressReport.sample().responseTimes
        #expect(AutomaticInsight.spreadLine(current: times.current, previous: times.previous, locale: swedish)
                == "Middle half: 0,9–1,5 s (was 1,2–2,8 s). Your times are closer together than before.")
        #expect(AutomaticInsight.spreadLine(current: spread(800, 1600), previous: spread(900, 1300), locale: english)
                == "Middle half: 0.8–1.6 s (was 0.9–1.3 s). Your times vary more than before.")
        #expect(AutomaticInsight.spreadLine(current: spread(900, 1400), previous: spread(900, 1460), locale: english)
                == "Middle half: 0.9–1.4 s (was 0.9–1.5 s). About as spread out as before.")
    }

    @Test func withNothingToCompareOnlyTheMiddleHalfIsSaid() {
        // All time has no window before; a window before with few right answers isn't compared.
        #expect(AutomaticInsight.spreadLine(current: spread(860, 1480), previous: nil, locale: swedish) == "Middle half: 0,9–1,5 s")
        let few = spread(1000, 2000, answers: AutomaticInsight.minimumRightAnswersToCompare - 1)
        #expect(AutomaticInsight.spreadChange(current: spread(860, 1480), previous: few) == nil)
        #expect(AutomaticInsight.spreadChange(current: few, previous: spread(860, 1480)) == nil)
        #expect(AutomaticInsight.spreadLine(current: TimeSpread(), previous: spread(860, 1480)) == nil)
    }

    @Test func aChangeInSpreadCountsFromATenthOfASecondAndATenthOfWhatItWas() {
        // Was 0.6 s wide: the threshold is 0.1 s.
        #expect(AutomaticInsight.spreadChange(current: spread(1000, 1500), previous: spread(1000, 1600)) == .narrower)
        #expect(AutomaticInsight.spreadChange(current: spread(1000, 1510), previous: spread(1000, 1600)) == .same)
        #expect(AutomaticInsight.spreadChange(current: spread(1000, 1700), previous: spread(1000, 1600)) == .wider)
        // Was 2 s wide: a tenth of it, 0.2 s.
        #expect(AutomaticInsight.spreadChange(current: spread(1000, 2850), previous: spread(1000, 3000)) == .same)
        #expect(AutomaticInsight.spreadChange(current: spread(1000, 2800), previous: spread(1000, 3000)) == .narrower)
    }

    // MARK: - Mistakes by speed

    /// Bins on the contract's edges with these answers and mistakes.
    private func bins(_ answers: [Int], _ wrong: [Int]) -> [SpeedBin] {
        let edges = [0] + ResponseTimes.speedEdgesMs
        return edges.indices.map { index in
            SpeedBin(lowerMs: edges[index], upperMs: index + 1 < edges.count ? edges[index + 1] : nil,
                     answers: answers[index], wrong: wrong[index])
        }
    }

    @Test func mistakesWithSlowAnswersAreNotRushing() {
        let sample = ProgressReport.sample().responseTimes.bySpeed
        #expect(AutomaticInsight.speedPattern(sample) == .slowOnes)
        #expect(AutomaticInsight.speedLine(sample) == "Mistakes come with slow answers, not fast ones: you're not rushing.")
    }

    @Test func mistakesWithTheFastestAnswersMayBeRushing() {
        let rushed = bins([180, 310, 620, 420, 260, 120, 60], [30, 25, 14, 12, 8, 3, 2])
        #expect(AutomaticInsight.speedPattern(rushed) == .rushing)
        #expect(AutomaticInsight.speedLine(rushed) == "Your fastest answers have the most mistakes: you may be rushing.")
    }

    @Test func noGroupStandingOutIsEven() {
        let even = bins([200, 200, 200, 200, 200, 100, 100], [10, 10, 10, 10, 10, 5, 5])
        #expect(AutomaticInsight.speedPattern(even) == .even)
        #expect(AutomaticInsight.speedLine(even) == "Mistakes are spread evenly across speeds.")
        // The fastest highest, but not by half again over the overall rate: still even.
        let slightly = bins([100, 100, 400, 0, 0, 0, 0], [7, 6, 20, 0, 0, 0, 0])
        #expect(AutomaticInsight.speedPattern(slightly) == .even)
    }

    @Test func standingOutTakesHalfAgainTheOverallRate() {
        // 1 000 answers, 50 wrong (5%): the line is 7.5%. Fast at 8% stands out, at 7% it doesn't.
        #expect(AutomaticInsight.speedPattern(bins([200, 0, 800, 0, 0, 0, 0], [16, 0, 34, 0, 0, 0, 0])) == .rushing)
        #expect(AutomaticInsight.speedPattern(bins([200, 0, 800, 0, 0, 0, 0], [14, 0, 36, 0, 0, 0, 0])) == .even)
    }

    @Test func groupsNeedEnoughAnswersAndMistakes() {
        // The fastest answers are all wrong, but there are only 10 of them.
        let fewFast = bins([10, 0, 400, 200, 100, 50, 0], [10, 0, 10, 5, 3, 1, 0])
        #expect(AutomaticInsight.speedPattern(fewFast) == .even)
        // Slow answers at 10%, but only two mistakes there.
        let fewSlowMistakes = bins([100, 100, 400, 200, 100, 20, 0], [3, 3, 10, 5, 3, 2, 0])
        #expect(AutomaticInsight.speedPattern(fewSlowMistakes) == .even)
    }

    @Test func tooLittleSaysNothing() {
        // Under 50 answers, or under 5 mistakes, or only one speed group to compare.
        #expect(AutomaticInsight.speedPattern(bins([5, 8, 15, 10, 6, 3, 1], [1, 1, 2, 2, 2, 1, 1])) == nil)
        #expect(AutomaticInsight.speedPattern(bins([100, 100, 400, 200, 100, 20, 10], [1, 0, 1, 1, 0, 0, 0])) == nil)
        #expect(AutomaticInsight.speedPattern(bins([0, 0, 300, 300, 0, 0, 0], [0, 0, 9, 9, 0, 0, 0])) == nil)
        #expect(AutomaticInsight.speedLine([]) == nil)
        #expect(AutomaticInsight.speedLine(bins([5, 8, 15, 10, 6, 3, 1], [1, 1, 2, 2, 2, 1, 1])) == nil)
    }

    @Test func noMistakesAtAllIsSaid() {
        #expect(AutomaticInsight.speedLine(bins([100, 100, 400, 200, 100, 20, 10], [0, 0, 0, 0, 0, 0, 0]))
                == "No mistakes at any speed.")
    }

    // MARK: - After the note before

    private func rows(step: (correct: Int, ms: Int?), far: (correct: Int, ms: Int?)) -> [PreviousNoteRow] {
        [PreviousNoteRow(distance: .samePlace, answers: 3, correct: 3, medianMs: 900),
         PreviousNoteRow(distance: .oneStep, answers: step.correct + 5, correct: step.correct, medianMs: step.ms),
         PreviousNoteRow(distance: .twoOrThreeSteps, answers: 500, correct: 480, medianMs: 1100),
         PreviousNoteRow(distance: .fourOrMoreSteps, answers: far.correct + 5, correct: far.correct, medianMs: far.ms)]
    }

    @Test func notesAStepAwayNamedQuickerAreStillReadFromTheOneBefore() {
        let sample = ProgressReport.sample().responseTimes.byPreviousNote
        #expect(AutomaticInsight.previousNotePattern(sample) == .stepsQuicker(ms: 310))
        #expect(AutomaticInsight.previousNoteLine(sample, locale: swedish)
                == "Notes a step from the last are named 0,3 s quicker than far jumps: you still read partly from the note before.")
    }

    @Test func aDifferenceCountsPastAHundredAndFiftyMilliseconds() {
        #expect(AutomaticInsight.previousNotePattern(rows(step: (100, 1000), far: (100, 1150))) == .noDifference)
        #expect(AutomaticInsight.previousNotePattern(rows(step: (100, 1000), far: (100, 1151))) == .stepsQuicker(ms: 151))
        #expect(AutomaticInsight.previousNotePattern(rows(step: (100, 1150), far: (100, 1000))) == .noDifference)
        #expect(AutomaticInsight.previousNotePattern(rows(step: (100, 1300), far: (100, 1000))) == .jumpsQuicker(ms: 300))
        #expect(AutomaticInsight.previousNoteLine(rows(step: (100, 1000), far: (100, 1100)))
                == "How far a note is from the last one makes no difference: each is read on its own.")
        #expect(AutomaticInsight.previousNoteLine(rows(step: (100, 1300), far: (100, 1000)), locale: english)
                == "Notes a step from the last are named 0.3 s slower than far jumps: you're not leaning on the note before.")
    }

    @Test func bothDistancesNeedEnoughRightAnswers() {
        let enough = AutomaticInsight.minimumRightAnswersPerDistance
        #expect(AutomaticInsight.previousNotePattern(rows(step: (enough - 1, 900), far: (100, 1300))) == nil)
        #expect(AutomaticInsight.previousNotePattern(rows(step: (100, 900), far: (enough - 1, 1300))) == nil)
        #expect(AutomaticInsight.previousNotePattern(rows(step: (enough, 900), far: (enough, 1300))) == .stepsQuicker(ms: 400))
        #expect(AutomaticInsight.previousNotePattern(rows(step: (100, nil), far: (100, 1300))) == nil)
        #expect(AutomaticInsight.previousNoteLine([]) == nil)
    }

    // MARK: - Labels

    @Test func histogramBinsAreLabelledInSeconds() {
        #expect([0, 3, 4, 5, 23].map { AutomaticInsight.histogramBinLabel($0, locale: swedish) }
                == ["0–0,25 s", "0,75–1 s", "1–1,25 s", "1,25–1,5 s", "5,75–6 s"])
        #expect(AutomaticInsight.histogramBinLabel(ResponseTimes.histogramBins, locale: swedish) == "6 s or more")
    }

    @Test func speedBinsAreLabelledInFullAndOnTheAxis() {
        let speeds = ProgressReport.sample().responseTimes.bySpeed
        #expect(speeds.map { AutomaticInsight.speedBinLabel($0, locale: swedish) }
                == ["Under 0,75 s", "0,75–1 s", "1–1,5 s", "1,5–2 s", "2–3 s", "3–5 s", "5 s or more"])
        #expect(speeds.map { AutomaticInsight.speedAxisLabel($0, locale: swedish) }
                == ["<0,75", "0,75–1", "1–1,5", "1,5–2", "2–3", "3–5", "5+"])
        #expect(AutomaticInsight.speedAxisLabel(speeds[1], locale: english) == "0.75–1")
    }

    @Test func periodsAreNamedFromTheRange() {
        #expect(AutomaticInsight.periodNames(.month) == ("Last 30 days", "The 30 days before"))
        #expect(AutomaticInsight.periodNames(.week) == ("Last 7 days", "The 7 days before"))
        #expect(AutomaticInsight.periodNames(.all) == ("All time", nil))
        #expect(AutomaticInsight.distanceDescription(.oneStep) == "One step from the note before")
        #expect(AutomaticInsight.distanceDescription(.samePlace) == "Same line or space as the note before")
    }
}
