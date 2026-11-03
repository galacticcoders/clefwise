import Foundation
import Testing
@testable import Clefwise

/// The contract for the response-time statistics: the helpers and shapes every part relies on.
@Suite struct ResponseTimesContractTests {
    @Test func quantilesInterpolateBetweenRanks() {
        #expect(ProgressAnalyzer.quantile([], 0.5) == nil)
        #expect(ProgressAnalyzer.quantile([700], 0.25) == 700)
        let times = [400, 1000, 600, 800, 1200] // sorted: 400 600 800 1000 1200
        #expect(ProgressAnalyzer.quantile(times, 0) == 400)
        #expect(ProgressAnalyzer.quantile(times, 0.25) == 600)
        #expect(ProgressAnalyzer.quantile(times, 0.5) == 800)
        #expect(ProgressAnalyzer.quantile(times, 0.75) == 1000)
        #expect(ProgressAnalyzer.quantile(times, 1) == 1200)
        // Between ranks: 0.25 of 4 values sits at rank 0.75, between 100 and 200.
        #expect(ProgressAnalyzer.quantile([100, 200, 300, 400], 0.25) == 175)
        // The median agrees with `median`, the mean of the middle two included.
        for values in [[1, 2], [5, 9, 1, 3], [10, 20, 31, 40, 50, 60]] {
            #expect(ProgressAnalyzer.quantile(values, 0.5) == ProgressAnalyzer.median(values))
        }
    }

    @Test func spreadsAreUpperMinusLowerQuartile() {
        #expect(TimeSpread(rightAnswers: 4, lowerQuartileMs: 800, medianMs: 1000, upperQuartileMs: 1500).spreadMs == 700)
        #expect(TimeSpread().spreadMs == nil)
        let day = DayProgress(day: .now, answers: 10, correct: 9, practiceSeconds: 60, medianResponseMs: 1000,
                              lowerQuartileMs: 900, upperQuartileMs: 1300)
        #expect(day.spreadMs == 400)
    }

    @Test func distancesFromThePreviousNote() {
        #expect([0, 1, -1, 2, -3, 4, 12].map(PreviousNoteDistance.init(steps:))
                == [.samePlace, .oneStep, .oneStep, .twoOrThreeSteps, .twoOrThreeSteps, .fourOrMoreSteps, .fourOrMoreSteps])
    }

    @Test func theSampleHasEveryShape() {
        let times = ProgressReport.sample().responseTimes
        #expect(times.histogram.count == ResponseTimes.histogramBins + 1)
        #expect(times.previousHistogram?.count == ResponseTimes.histogramBins + 1)
        #expect(times.bySpeed.count == ResponseTimes.speedEdgesMs.count + 1)
        #expect(times.bySpeed.first?.lowerMs == 0 && times.bySpeed.last?.upperMs == nil)
        #expect(times.byPreviousNote.map(\.distance) == PreviousNoteDistance.allCases)
        let sample = ProgressReport.sample()
        #expect(sample.days.contains { $0.spreadMs != nil })
        #expect(sample.positions.contains { $0.recentMedianResponseMs != nil })
    }

    @Test func anEmptyReportHasEmptyTimes() {
        let times = ProgressReport.empty(ProgressFilter()).responseTimes
        #expect(times.current.rightAnswers == 0 && times.previous == nil)
        #expect(times.histogram == [Int](repeating: 0, count: ResponseTimes.histogramBins + 1))
        #expect(times.bySpeed.isEmpty && times.byPreviousNote.isEmpty)
    }
}
