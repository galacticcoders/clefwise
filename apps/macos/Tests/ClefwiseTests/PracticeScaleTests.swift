import AppKit
import Testing
@testable import Clefwise

@Suite struct PracticeScaleTests {
    @Test func boundsFollowTheBusiestPlace() {
        // The user's practice by 2026-11-03: the staff 270–650 answers, ledger notes 3–225.
        #expect(PracticeScale(maximum: 647).thresholds == [25, 50, 100, 250])
        #expect(PracticeScale(maximum: 500).thresholds == [25, 50, 100, 250])
        #expect(PracticeScale(maximum: 499).thresholds == [10, 25, 50, 100])
        #expect(PracticeScale(maximum: 6_000).thresholds == [250, 500, 1_000, 2_500])
        #expect(PracticeScale(maximum: 20_000).thresholds == [1_000, 2_500, 5_000, 10_000])
        // However little practice, the classes never start below 2, 5, 10, 25.
        for maximum in [0, 1, 4, 49] {
            #expect(PracticeScale(maximum: maximum).thresholds == [2, 5, 10, 25])
        }
    }

    @Test func eachCountHasItsClass() {
        let scale = PracticeScale(maximum: 647)
        #expect(scale.level(answers: 0) == nil)
        #expect([1, 24, 25, 49, 50, 99, 100, 249, 250, 647, 10_000].map { scale.level(answers: $0) }
                == [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 4])
    }

    @Test func classesAreLabelledLowestFirst() {
        #expect(PracticeScale(maximum: 647).classLabels == ["1–24", "25–49", "50–99", "100–249", "250 or more"])
        // A class of one count shows just that count.
        #expect(PracticeScale(maximum: 10).classLabels == ["1", "2–4", "5–9", "10–24", "25 or more"])
    }

    @Test func classesSitOnTheOrangeRampAsTheAccuracyClassesOnTheBlue() {
        // Light: steps 250, 350, 500, 600, 700; dark: 550, 450, 300, 200, 100 (more is lighter there).
        #expect((0..<5).map { PracticeScale.fill(level: $0).hex(in: .aqua) }
                == [0xEB9C7F, 0xDF7249, 0xB44005, 0x8A2E00, 0x611E00])
        #expect((0..<5).map { PracticeScale.fill(level: $0).hex(in: .darkAqua) }
                == [0x9F3600, 0xC94908, 0xE68764, 0xF2B098, 0xFBD7CA])
        // The orange ramp's own ends, like the blue one's.
        #expect(DashboardTheme.orangeRampColor(0).hex(in: .aqua) == 0xFBD7CA)
        #expect(DashboardTheme.orangeRampColor(1).hex(in: .aqua) == 0x611E00)
        #expect(DashboardTheme.orangeRampColor(0, fromStep: 3).hex(in: .darkAqua) == 0x9F3600)
    }

    @Test func labelsTakeTheInkThatReadsBetter() {
        // By APCA on each class: ink only on the palest light class, and on the three lightest dark ones.
        #expect((0..<5).map { PracticeScale.labelColor(level: $0).hex(in: .aqua) }
                == [0x0B0B0B, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF])
        #expect((0..<5).map { PracticeScale.labelColor(level: $0).hex(in: .darkAqua) }
                == [0xF0EFEC, 0xF0EFEC, 0x0B0B0B, 0x0B0B0B, 0x0B0B0B])
        #expect(PracticeScale.labelColor(level: nil).hex(in: .aqua) == DashboardTheme.textSecondary.hex(in: .aqua))
    }
}
