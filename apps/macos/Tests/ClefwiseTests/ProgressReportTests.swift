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
        // Light: from the palest step to the darkest, starting at step 250 for ordered marks.
        #expect(DashboardTheme.rampColor(0).hex(in: .aqua) == 0xCDE2FB)
        #expect(DashboardTheme.rampColor(1).hex(in: .aqua) == 0x0D366B)
        #expect(DashboardTheme.rampColor(0, fromStep: 3).hex(in: .aqua) == 0x86B6EF)
        // Dark: the other way, so more stands out further from the dark card; from step 550.
        #expect(DashboardTheme.rampColor(0).hex(in: .darkAqua) == 0x0D366B)
        #expect(DashboardTheme.rampColor(1).hex(in: .darkAqua) == 0xCDE2FB)
        #expect(DashboardTheme.rampColor(0, fromStep: 3).hex(in: .darkAqua) == 0x1C5CAB)
        // Text on the darker half is light in both.
        #expect(DashboardTheme.textOnRamp(0.2).hex(in: .aqua) == 0x0B0B0B && DashboardTheme.textOnRamp(0.8).hex(in: .aqua) == 0xFFFFFF)
        #expect(DashboardTheme.textOnRamp(0.2).hex(in: .darkAqua) == 0xF0EFEC && DashboardTheme.textOnRamp(0.8).hex(in: .darkAqua) == 0x0B0B0B)
    }
}
