import Foundation
import Testing
@testable import Clefwise

@Suite struct ProgressReportTests {
    private let now = Date(timeIntervalSince1970: 1_793_390_400) // a fixed afternoon

    @Test func sampleIsDeterministic() {
        #expect(ProgressReport.sample(seed: 3, now: now) == ProgressReport.sample(seed: 3, now: now))
        #expect(ProgressReport.sample(seed: 3, now: now) != ProgressReport.sample(seed: 4, now: now))
    }

    @Test func sampleLooksLikeAMonthOfPractice() {
        let sample = ProgressReport.sample(now: now)
        #expect(sample.days.count == 30)
        #expect(!sample.isEmpty)
        #expect(Set(sample.positions.map(\.clef)) == [.treble, .bass])
        #expect(sample.pitches.contains { $0.pitch.accidental == .sharp })
        #expect(sample.totals.accuracy.map { $0 > 0.5 && $0 < 1 } == true)
        #expect(sample.previousTotals != nil)
    }

    @Test func emptyReportIsEmpty() {
        #expect(ProgressReport.empty(ProgressFilter(), at: now).isEmpty)
    }

    @Test func rampEndsLightAndDark() {
        #expect(DashboardTheme.rampColor(0) == DashboardTheme.ramp.first)
        #expect(DashboardTheme.rampColor(1) == DashboardTheme.ramp.last)
        #expect(DashboardTheme.rampColor(0, fromStep: 3) == DashboardTheme.ramp[3])
    }
}
