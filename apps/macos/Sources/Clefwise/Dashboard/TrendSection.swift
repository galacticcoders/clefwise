import Charts
import SwiftUI

/// Accuracy, response time and how much the times vary, per day, as three charts side by side
/// (never one chart with two scales).
struct TrendSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    /// The period under the pointer in any chart (its start); all show it, so they read across.
    @State private var hovered: Date?

    /// Past about six weeks a point a day breaks into fragments wherever a day is skipped and
    /// swings with small days: the charts go by week instead (so "Last 90 days" reads as a trend).
    private var isWeekly: Bool { report.days.count > 45 }

    private var periods: [TrendPeriod] {
        isWeekly ? TrendPeriod.weeks(of: report.days) : report.days.map(TrendPeriod.init(day:))
    }

    var body: some View {
        DashboardCard(title: "Over time",
                      subtitle: isWeekly ? "Per week; weeks without practice are gaps" : "Per day; days without practice are gaps") {
            if report.days.contains(where: { $0.answers > 0 }) {
                let periods = periods
                // Three across when they fit; else the third under the first two; else one above another.
                ThreeAcross(spacing: 28, rowSpacing: 24) {
                    accuracyChart(periods)
                } second: {
                    timeChart(periods)
                } third: {
                    spreadChart(periods)
                }
            } else {
                Text("No dated practice in this range yet.")
                    .foregroundStyle(DashboardTheme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        } table: {
            // Always by day, newest first: the numbers behind the points.
            DashboardTable(
                columns: [.init(title: "Day", isNumeric: false), .init(title: "Notes"), .init(title: "Accuracy"),
                          .init(title: "Typical response"), .init(title: "Middle half"), .init(title: "Spread"),
                          .init(title: "Practice time")],
                rows: report.days.reversed().map { day in
                    [DashboardFormat.day(day.day), day.answers > 0 ? day.answers.formatted() : "–",
                     day.accuracy.map(DashboardFormat.percent) ?? "–",
                     day.medianResponseMs.map { DashboardFormat.seconds(milliseconds: $0) } ?? "–",
                     day.lowerQuartileMs.flatMap { lower in
                         day.upperQuartileMs.map { AutomaticInsight.secondsRange(lower, $0) }
                     } ?? "–",
                     day.spreadMs.map { DashboardFormat.seconds(milliseconds: $0) } ?? "–",
                     day.answers > 0 ? DashboardFormat.duration(day.practiceSeconds) : "–"]
                })
        }
    }

    private func accuracyChart(_ periods: [TrendPeriod]) -> some View {
        TrendChart(title: "Accuracy", subtitle: "Share of notes named right",
                   periods: periods, hovered: $hovered,
                   value: { $0.accuracy.map { $0 * 100 } },
                   ticks: [0, 25, 50, 75, 100],
                   tickLabel: { "\(Int($0))%" },
                   readout: { $0.accuracy.map(DashboardFormat.percent) })
            .frame(minWidth: 280)
    }

    private func timeChart(_ periods: [TrendPeriod]) -> some View {
        TrendChart(title: "Typical response time", subtitle: "Median time to a right answer",
                   periods: periods, hovered: $hovered,
                   value: { $0.medianResponseMs.map { Double($0) / 1000 } },
                   ticks: NiceScale.ticks(for: periods.compactMap(\.medianResponseMs).max().map { Double($0) / 1000 } ?? 1),
                   tickLabel: { "\($0.formatted(.number.precision(.fractionLength(0...1)))) s" },
                   readout: { $0.medianResponseMs.map { DashboardFormat.seconds(milliseconds: $0) } })
            .frame(minWidth: 280)
    }

    /// How far apart the middle half of the times is: it often draws together before the median
    /// falls much.
    private func spreadChart(_ periods: [TrendPeriod]) -> some View {
        TrendChart(title: "How much your times vary", subtitle: "Spread of the middle half of right answers",
                   periods: periods, hovered: $hovered,
                   value: { $0.spreadMs.map { Double($0) / 1000 } },
                   ticks: NiceScale.ticks(for: periods.compactMap(\.spreadMs).max().map { Double($0) / 1000 } ?? 1),
                   // Spreads are small, so steps of 0.25 s come up: "0,25 s", not "0,2 s".
                   tickLabel: { "\($0.formatted(.number.precision(.fractionLength(0...2)))) s" },
                   readout: { $0.spreadMs.map { DashboardFormat.seconds(milliseconds: $0) } },
                   detail: { period in
                       // A day's own middle half; a week's spread is the middle of its days', so it has none.
                       guard let lower = period.lowerQuartileMs, let upper = period.upperQuartileMs else { return nil }
                       return "Middle half \(AutomaticInsight.secondsRange(lower, upper)) · \(DashboardFormat.notes(period.answers))"
                   })
            .frame(minWidth: 280)
    }
}

/// One point on the trend charts: a day, or a week for long ranges.
private struct TrendPeriod: Identifiable {
    let start: Date
    /// The day after the period's last.
    let end: Date
    let isWeek: Bool
    let answers: Int
    let correct: Int
    let medianResponseMs: Int?
    /// A day's quartiles of its right answers; nil for a week.
    let lowerQuartileMs: Int?
    let upperQuartileMs: Int?
    /// How far apart the middle half of the times is: a day's own, or the middle of a week's days'.
    let spreadMs: Int?

    var id: Date { start }
    var accuracy: Double? { answers > 0 ? Double(correct) / Double(answers) : nil }
    /// Where its point sits: the middle, so each period owns the space either side of it.
    var middle: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    /// "Wed, Oct 21", "Week of Oct 19"
    var label: String {
        isWeek ? "Week of \(start.formatted(.dateTime.day().month(.abbreviated)))" : DashboardFormat.day(start)
    }

    init(day: DayProgress) {
        let calendar = Calendar.current
        start = calendar.startOfDay(for: day.day)
        end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        isWeek = false
        answers = day.answers
        correct = day.correct
        medianResponseMs = day.medianResponseMs
        lowerQuartileMs = day.lowerQuartileMs
        upperQuartileMs = day.upperQuartileMs
        spreadMs = day.spreadMs
    }

    private init(week days: ArraySlice<DayProgress>) {
        let calendar = Calendar.current
        start = calendar.startOfDay(for: days.first!.day)
        let last = calendar.startOfDay(for: days.last!.day)
        end = calendar.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86_400)
        isWeek = true
        answers = days.map(\.answers).reduce(0, +)
        correct = days.map(\.correct).reduce(0, +)
        // The middle of the week's daily medians: the report has no finer times, and a trend needs no more.
        let medians = days.compactMap(\.medianResponseMs).sorted()
        medianResponseMs = medians.isEmpty ? nil : medians[medians.count / 2]
        // Likewise the middle of its daily spreads; a week's own quartiles would need its times.
        lowerQuartileMs = nil
        upperQuartileMs = nil
        let spreads = days.compactMap(\.spreadMs).sorted()
        spreadMs = spreads.isEmpty ? nil : spreads[spreads.count / 2]
    }

    /// `days` in calendar weeks; the first and last may be part weeks.
    static func weeks(of days: [DayProgress]) -> [TrendPeriod] {
        let calendar = Calendar.current
        var weeks: [TrendPeriod] = []
        var index = days.startIndex
        while index < days.endIndex {
            let weekEnd = calendar.dateInterval(of: .weekOfYear, for: days[index].day)?.end ?? days[index].day
            var end = index + 1
            while end < days.endIndex, days[end].day < weekEnd { end += 1 }
            weeks.append(TrendPeriod(week: days[index..<end]))
            index = end
        }
        return weeks
    }
}

/// One measure over time as a line: 2 px with round joins, gaps where there's no value, a
/// crosshair that snaps to the nearest day (or week), and a tooltip with its numbers.
private struct TrendChart: View {
    let title: String
    let subtitle: String
    let periods: [TrendPeriod]
    @Binding var hovered: Date?
    /// The period's value on the chart's scale, nil for a gap.
    let value: (TrendPeriod) -> Double?
    /// The y-axis from 0 to the last tick.
    let ticks: [Double]
    let tickLabel: (Double) -> String
    /// The tooltip's lead value, nil when there's none.
    let readout: (TrendPeriod) -> String?
    /// The tooltip's line under the period, when there's more to say than the number of notes.
    var detail: ((TrendPeriod) -> String?)? = nil

    private let calendar = Calendar.current

    /// One per period with a value, numbered by unbroken run so gaps break the line.
    private struct Point: Identifiable {
        let start: Date
        let x: Date
        let value: Double
        let run: Int
        /// No neighbour with a value on either side: the line alone wouldn't show it.
        let isAlone: Bool
        var id: Date { start }
    }

    private var points: [Point] {
        var points: [Point] = []
        var run = 0
        let values = periods.map(value)
        for (index, period) in periods.enumerated() {
            guard let value = values[index] else {
                run += 1
                continue
            }
            let before = index > 0 ? values[index - 1] : nil
            let after = index + 1 < values.count ? values[index + 1] : nil
            points.append(Point(start: period.start, x: period.middle, value: value, run: run,
                                isAlone: before == nil && after == nil))
        }
        return points
    }

    var body: some View {
        let points = points
        let hoveredPeriod = hovered.flatMap { start in periods.first { $0.start == start } }
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashboardTheme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textSecondary)
            }
            Chart {
                RuleMark(y: .value("Baseline", 0))
                    .foregroundStyle(DashboardTheme.baseline)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(points) { point in
                    LineMark(x: .value("Day", point.x), y: .value(title, point.value), series: .value("Run", point.run))
                        .foregroundStyle(DashboardTheme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                // The line carries the trend; a point on its own between gaps needs a marker to show.
                ForEach(points.filter(\.isAlone)) { point in
                    PointMark(x: .value("Day", point.x), y: .value(title, point.value))
                        .symbol { Marker(size: 8) }
                }
                if let hoveredPeriod {
                    RuleMark(x: .value("Day", hoveredPeriod.middle))
                        .foregroundStyle(DashboardTheme.textMuted)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    if let point = points.first(where: { $0.start == hoveredPeriod.start }) {
                        PointMark(x: .value("Day", point.x), y: .value(title, point.value))
                            .symbol { Marker(size: 10) }
                    }
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: 0...(ticks.last ?? 1))
            .chartXAxis {
                AxisMarks(values: xTicks) { mark in
                    // The latest point sits by the right edge: its label ends there instead of being cut.
                    AxisValueLabel(anchor: mark.as(Date.self) == periods.last?.middle ? .topTrailing : .top) {
                        if let date = mark.as(Date.self) {
                            Text(xLabel(date))
                                .font(.caption)
                                .foregroundStyle(DashboardTheme.textMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: ticks) { mark in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(DashboardTheme.gridline)
                    AxisValueLabel {
                        if let tick = mark.as(Double.self) {
                            Text(tickLabel(tick))
                                .font(.caption)
                                .foregroundStyle(DashboardTheme.textMuted)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plot = proxy.plotFrame.map({ geometry[$0] }) {
                        // The whole plot is the hit target: the pointer only has to be nearest a day.
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    hovered = period(at: location.x - plot.minX, proxy: proxy)?.start
                                case .ended:
                                    hovered = nil
                                }
                            }
                            .tooltip(tooltip(hoveredPeriod),
                                     beside: hoveredPeriod.flatMap { proxy.position(forX: $0.middle) }.map { plot.minX + $0 } ?? 0,
                                     top: plot.minY + 4, in: geometry.size.width)
                    }
                }
            }
            .frame(height: 190)
        }
    }

    // MARK: - Hover

    /// The period under the pointer's x, or the nearest one at either end.
    private func period(at x: CGFloat, proxy: ChartProxy) -> TrendPeriod? {
        guard let date: Date = proxy.value(atX: x), let first = periods.first, let last = periods.last else { return nil }
        if date < first.start { return first }
        return periods.first { date < $0.end } ?? last
    }

    @ViewBuilder
    private func tooltip(_ period: TrendPeriod?) -> some View {
        if let period {
            if let readout = readout(period) {
                ChartTooltip(value: readout, label: period.label,
                             detail: detail?(period) ?? DashboardFormat.notes(period.answers))
            } else {
                ChartTooltip(value: period.answers > 0 ? "No right answers" : "No practice", label: period.label)
            }
        }
    }

    // MARK: - Axes

    private var xDomain: ClosedRange<Date> {
        guard let first = periods.first, let last = periods.last else { return Date()...Date() }
        return first.start...last.end
    }

    /// Long ranges label months. Otherwise a label every day for a week, then every week or
    /// fortnight, counted back from today so the latest day is always labelled.
    private var xTicks: [Date] {
        guard let first = periods.first?.start, let last = periods.last?.start else { return [] }
        if periods.first?.isWeek == true {
            let months = calendar.dateComponents([.month], from: first, to: last).month ?? 0
            var ticks: [Date] = []
            var month = calendar.date(from: calendar.dateComponents([.year, .month], from: first)) ?? first
            while month <= last {
                if month >= first { ticks.append(month) }
                month = calendar.date(byAdding: .month, value: months > 14 ? 3 : 1, to: month) ?? last.addingTimeInterval(1)
            }
            return ticks
        }
        let count = periods.count
        let step = count <= 8 ? 1 : count <= 35 ? 7 : 14
        return stride(from: count - 1, through: 0, by: -step).map { periods[$0].middle }
    }

    private func xLabel(_ date: Date) -> String {
        guard let first = periods.first else { return "" }
        if first.isWeek {
            let span = calendar.dateComponents([.month], from: first.start, to: periods.last?.start ?? first.start).month ?? 0
            // "Oct 2025": a two-digit year reads as a day of the month.
            return span > 11 ? date.formatted(.dateTime.month(.abbreviated).year())
                : date.formatted(.dateTime.month(.abbreviated))
        }
        return periods.count <= 8 ? date.formatted(.dateTime.weekday(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// A data point: the accent with a 2 px ring of the card's white, so it stands off the line.
private struct Marker: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(DashboardTheme.accent)
            .frame(width: size, height: size)
            .padding(2)
            .background(Circle().fill(DashboardTheme.surface))
    }
}
