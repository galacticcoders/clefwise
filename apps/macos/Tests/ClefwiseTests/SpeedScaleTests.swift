import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Clefwise

@Suite struct SpeedScaleTests {
    @Test func eachTimeHasItsClass() {
        // A time on a bound belongs to the slower class.
        let times = [0, 999, 1000, 1499, 1500, 1999, 2000, 2999, 3000, 12_000]
        #expect(times.map { SpeedScale.level(medianMs: $0, rightAnswers: PositionProgress.recentWindow) }
                == [4, 4, 3, 3, 2, 2, 1, 1, 0, 0])
    }

    @Test func tooFewRightAnswersIsHollow() {
        #expect(SpeedScale.minimumRightAnswers == AccuracyScale.minimumAnswers)
        #expect(SpeedScale.level(medianMs: 1200, rightAnswers: 0) == nil)
        #expect(SpeedScale.level(medianMs: 1200, rightAnswers: 4) == nil)
        #expect(SpeedScale.level(medianMs: 1200, rightAnswers: 5) == 3)
        #expect(SpeedScale.level(medianMs: nil, rightAnswers: 20) == nil)
    }

    @Test func classesAreLabelledSlowestFirstInTheLocale() {
        #expect(SpeedScale.classLabels(locale: Locale(identifier: "sv_SE"))
                == ["3 s or more", "2–3 s", "1,5–2 s", "1–1,5 s", "Under 1 s"])
        #expect(SpeedScale.classLabels(locale: Locale(identifier: "en_US"))
                == ["3 s or more", "2–3 s", "1.5–2 s", "1–1.5 s", "Under 1 s"])
    }

    @Test func timesNeverRoundUpOntoAClassBound() {
        // Within 50 ms under a bound, the time reads as the tenth under it, so it stays in its class.
        #expect(SpeedScale.seconds(999) == ReportFormat.seconds(900))
        #expect(SpeedScale.seconds(950) == ReportFormat.seconds(900))
        #expect(SpeedScale.seconds(1460) == ReportFormat.seconds(1400))
        #expect(SpeedScale.seconds(1999) == ReportFormat.seconds(1900))
        #expect(SpeedScale.seconds(2960) == ReportFormat.seconds(2900))
        // Anywhere else, as every other time on the dashboard.
        for ms in [0, 949, 1000, 1049, 1234, 1500, 2000, 2949, 3000, 3049, 4567] {
            #expect(SpeedScale.seconds(ms) == ReportFormat.seconds(ms))
        }
        #expect(SpeedScale.seconds(nil) == "—")
    }

    @Test func classesSitOnTheAquaRampAsTheAccuracyClassesOnTheBlue() {
        // Light: steps 250, 350, 500, 600, 700; dark: 550, 450, 300, 200, 100 (faster is lighter there).
        #expect((0..<5).map { SpeedScale.fill(level: $0).hex(in: .aqua) }
                == [0x80C3A2, 0x43AC7F, 0x037F56, 0x026040, 0x00432B])
        #expect((0..<5).map { SpeedScale.fill(level: $0).hex(in: .darkAqua) }
                == [0x016F4B, 0x018F62, 0x62B890, 0x9AD0B4, 0xCCE8D9])
    }

    @Test func labelsTakeTheInkThatReadsBetter() {
        // By APCA on each class: ink only on the palest light class, and on the three lightest dark ones.
        #expect((0..<5).map { SpeedScale.labelColor(level: $0).hex(in: .aqua) }
                == [0x0B0B0B, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF])
        #expect((0..<5).map { SpeedScale.labelColor(level: $0).hex(in: .darkAqua) }
                == [0xF0EFEC, 0xF0EFEC, 0x0B0B0B, 0x0B0B0B, 0x0B0B0B])
        #expect(SpeedScale.labelColor(level: nil).hex(in: .aqua) == DashboardTheme.textSecondary.hex(in: .aqua))
        #expect(SpeedScale.labelColor(level: nil).hex(in: .darkAqua) == DashboardTheme.textSecondary.hex(in: .darkAqua))
    }

    @Test func everyRampStepLightAndDark() {
        // All 13 steps of each ramp (100…700): adding aqua must leave blue and orange as they were.
        let blue = [0xCDE2FB, 0xB7D3F6, 0x9EC5F4, 0x86B6EF, 0x6DA7EC, 0x5598E7, 0x3987E5,
                    0x2A78D6, 0x256ABF, 0x1C5CAB, 0x184F95, 0x104281, 0x0D366B]
        let orange = [0xFBD7CA, 0xF5C4B2, 0xF2B098, 0xEB9C7F, 0xE68764, 0xDF7249, 0xD95923,
                      0xC94908, 0xB44005, 0x9F3600, 0x8A2E00, 0x752600, 0x611E00]
        let aqua = [0xCCE8D9, 0xB4DBC6, 0x9AD0B4, 0x80C3A2, 0x62B890, 0x43AC7F, 0x039F6D,
                    0x018F62, 0x037F56, 0x016F4B, 0x026040, 0x025136, 0x00432B]
        let steps = (0...12).map { Double($0) / 12 }
        for (ramp, color) in [(blue, DashboardTheme.rampColor), (orange, DashboardTheme.orangeRampColor),
                              (aqua, DashboardTheme.aquaRampColor)] as [([Int], (Double, Int) -> Color)] {
            #expect(steps.map { color($0, 0).hex(in: .aqua) } == ramp)
            #expect(steps.map { color($0, 0).hex(in: .darkAqua) } == ramp.reversed())
        }
    }
}
