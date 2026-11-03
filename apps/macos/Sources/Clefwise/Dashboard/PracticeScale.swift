import SwiftUI

/// The orange scale of the practice map: how many answers a line or space has had, in five classes.
/// Practice is very uneven (the staff gets ten times the answers of far ledger notes), so the class
/// bounds step 2, 5, 10, 25, 50, 100, 250, 500, 1 000, 2 500… rather than evenly, and they follow
/// the busiest place, so the top class starts at no more than half its count. A place with no
/// answers is drawn hollow.
struct PracticeScale: Equatable {
    /// Lower bounds of classes 1 to 4; class 0 runs from 1 to just under the first.
    let thresholds: [Int]

    /// 2, 5, 10, 25, 50, 100, 250, 500, 1 000, 2 500, …
    private static let bounds: [Int] = {
        var bounds = [2, 5]
        var decade = 10
        while decade <= 100_000_000 {
            bounds += [decade, decade * 5 / 2, decade * 5]
            decade *= 10
        }
        return bounds
    }()

    /// The scale for places whose busiest has `maximum` answers. However little practice there is,
    /// the bounds start at 2, 5, 10, 25.
    init(maximum: Int) {
        let top = Self.bounds.lastIndex { $0 <= maximum / 2 } ?? 0
        let last = max(top, 3)
        thresholds = Array(Self.bounds[(last - 3)...last])
    }

    /// The class of `answers`; nil for none.
    func level(answers: Int) -> Int? {
        guard answers > 0 else { return nil }
        return thresholds.filter { answers >= $0 }.count
    }

    /// Lowest first: "1–24", "25–49", "50–99", "100–249", "250 or more".
    var classLabels: [String] {
        let lows = [1] + thresholds
        return lows.indices.map { index in
            let low = lows[index]
            guard index + 1 < lows.count else { return "\(ReportFormat.count(low)) or more" }
            let high = lows[index + 1] - 1
            return low == high ? ReportFormat.count(low) : "\(ReportFormat.count(low))–\(ReportFormat.count(high))"
        }
    }

    /// Where each class sits on the orange ramp from step 250: steps 250, 350, 500, 600 and 700 in
    /// light, 550, 450, 300, 200 and 100 in dark, as the accuracy classes sit on the blue ramp.
    private static let rampFractions: [Double] = [0, 2.0 / 9, 5.0 / 9, 7.0 / 9, 1]

    static func fill(level: Int) -> Color { DashboardTheme.orangeRampColor(rampFractions[level], fromStep: 3) }

    /// Ink or white for a label inside the mark, whichever reads better by APCA on that class
    /// (checked with the data-viz skill's `apca`); secondary ink inside a hollow one. Unlike the blue
    /// classes, light class 1 takes white: the orange step is darker for its lightness.
    static func labelColor(level: Int?) -> Color {
        guard let level else { return DashboardTheme.textSecondary }
        let ink = NSColor(hex: 0x0B0B0B)
        let lightUsesInk = [true, false, false, false, false][level]
        let darkUsesInk = [false, false, true, true, true][level]
        return Color(light: lightUsesInk ? ink : .white, dark: darkUsesInk ? ink : NSColor(hex: 0xF0EFEC))
    }
}
