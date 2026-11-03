import SwiftUI

/// The aqua scale of the speed map: how fast a line or space is named now (the median time of its
/// last `PositionProgress.recentWindow` right answers), in five classes. A time means the same
/// whatever else was practised, so the bounds are fixed seconds: 3 s or more, 2–3 s, 1.5–2 s,
/// 1–1.5 s and under 1 s. Faster is darker in light mode and lighter in dark, as better and more
/// are on the other two maps. A place with too few right answers to judge is drawn hollow.
enum SpeedScale {
    /// Fewer right answers than this and a place is drawn hollow, as the note map does with answers.
    static let minimumRightAnswers = AccuracyScale.minimumAnswers
    /// The class bounds in milliseconds, slowest first: 3 000 ms or more is class 0, 2 000 up to
    /// 3 000 class 1, … under 1 000 class 4. A time on a bound belongs to the slower class.
    static let boundsMs = [3000, 2000, 1500, 1000]

    /// The class of a median of `medianMs` over `rightAnswers` right answers; nil when that's too
    /// few to judge.
    static func level(medianMs: Int?, rightAnswers: Int) -> Int? {
        guard let medianMs, rightAnswers >= minimumRightAnswers else { return nil }
        return boundsMs.filter { medianMs < $0 }.count
    }

    /// Slowest class first, as `ScaleLegend` takes them: "3 s or more", "2–3 s", "1.5–2 s",
    /// "1–1.5 s", "Under 1 s", with the locale's decimal mark ("1,5–2 s" in Swedish).
    static func classLabels(locale: Locale = .autoupdatingCurrent) -> [String] {
        let bound = boundsMs.map { (Double($0) / 1000).formatted(.number.precision(.fractionLength(0...1)).locale(locale)) }
        return ["\(bound[0]) s or more", "\(bound[1])–\(bound[0]) s", "\(bound[2])–\(bound[1]) s",
                "\(bound[3])–\(bound[2]) s", "Under \(bound[3]) s"]
    }

    /// A time as `ReportFormat.seconds` writes it ("1.2 s"), but never rounded up onto a class bound:
    /// 960 ms is "0.9 s", as it's under 1 s, so a cell's time always reads as inside its class (as
    /// `ReportFormat.percent` never rounds up to 100%). Times further from a bound print as everywhere.
    static func seconds(_ ms: Int?) -> String {
        guard let ms else { return ReportFormat.seconds(nil) }
        let bound = boundsMs.first { ($0 - 50)..<$0 ~= ms }
        return ReportFormat.seconds(bound.map { $0 - 100 } ?? ms)
    }

    /// Where each class sits on the aqua ramp from step 250: steps 250, 350, 500, 600 and 700 in
    /// light, 550, 450, 300, 200 and 100 in dark, as the accuracy classes sit on the blue ramp.
    private static let rampFractions: [Double] = [0, 2.0 / 9, 5.0 / 9, 7.0 / 9, 1]

    static func fill(level: Int) -> Color { DashboardTheme.aquaRampColor(rampFractions[level], fromStep: 3) }

    /// Ink or white for a label inside the mark, whichever reads better by APCA on that class
    /// (checked with the data-viz skill's `apca`); secondary ink inside a hollow one. As on the orange
    /// classes, light class 1 takes white.
    static func labelColor(level: Int?) -> Color {
        guard let level else { return DashboardTheme.textSecondary }
        let ink = NSColor(hex: 0x0B0B0B)
        let lightUsesInk = [true, false, false, false, false][level]
        let darkUsesInk = [false, false, true, true, true][level]
        return Color(light: lightUsesInk ? ink : .white, dark: darkUsesInk ? ink : NSColor(hex: 0xF0EFEC))
    }
}
