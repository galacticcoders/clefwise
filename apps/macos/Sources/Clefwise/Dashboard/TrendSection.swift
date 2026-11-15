import Charts
import SwiftUI

/// Accuracy, response time and how much the times vary, per day, as three charts side by side
/// (never one chart with two scales), each with one line per answer method. Naming a note and
/// playing it take very different times, so a line for every answer together would jump whenever
/// the mix changed; there is none.
struct TrendSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    /// The period under the pointer in any chart (its start); all show it, so they read across.
    @State private var hovered: Date?

    var body: some View {
        let isWeekly = TrendPeriod.isWeekly(report.days)
        DashboardCard(title: "Over time",
                      subtitle: "\(isWeekly ? "Per week" : "Per day"), one line per answer method; gaps where there are too few notes to judge") {
            if report.days.contains(where: { $0.answers > 0 }) {
                let periods = TrendPeriod.periods(for: report.days)
                let methods = TrendPeriod.methods(in: report.days)
                VStack(alignment: .leading, spacing: 16) {
                    if methods.count > 1 {
                        MethodLegend(methods: methods)
                    }
                    // Three across when they fit; else the third under the first two; else one above another.
                    ThreeAcross(spacing: 28, rowSpacing: 24) {
                        accuracyChart(periods)
                    } second: {
                        timeChart(periods)
                    } third: {
                        spreadChart(periods)
                    }
                }
            } else {
                Text("No dated practice in this range yet.")
                    .foregroundStyle(DashboardTheme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        } table: {
            // Always by day, newest first: the numbers behind the points, every method with answers,
            // under the minimum too. Practice time is in "What you practised".
            DashboardTable(
                columns: [.init(title: "Day", isNumeric: false), .init(title: "Method", isNumeric: false),
                          .init(title: "Notes"), .init(title: "Accuracy"), .init(title: "Typical response"),
                          .init(title: "Middle half"), .init(title: "Spread")],
                rows: report.days.reversed().flatMap { day in
                    day.methods.filter { $0.answers > 0 }.map { part in
                        [DashboardFormat.day(day.day), part.method.label, part.answers.formatted(),
                         part.accuracy.map(DashboardFormat.percent) ?? "–",
                         part.medianResponseMs.map { DashboardFormat.seconds(milliseconds: $0) } ?? "–",
                         part.lowerQuartileMs.flatMap { lower in
                             part.upperQuartileMs.map { AutomaticInsight.secondsRange(lower, $0) }
                         } ?? "–",
                         part.spreadMs.map { DashboardFormat.seconds(milliseconds: $0) } ?? "–"]
                    }
                })
        }
    }

    private func accuracyChart(_ periods: [TrendPeriod]) -> some View {
        let points = TrendMeasure.accuracy.points(in: periods)
        return TrendChart(title: "Accuracy", subtitle: "Share of notes answered right", measure: .accuracy,
                          periods: periods, points: points, hovered: $hovered,
                          // Focused on where the accuracy is (near the top, mostly), not always 0–100%.
                          ticks: NiceScale.ticks(covering: points.map(\.value), minimumSpan: 10, within: 0...100),
                          tickLabel: { "\(Int($0))%" })
            .frame(minWidth: 280)
    }

    private func timeChart(_ periods: [TrendPeriod]) -> some View {
        let points = TrendMeasure.responseTime.points(in: periods)
        return TrendChart(title: "Typical response time", subtitle: "Median time to a right answer",
                          measure: .responseTime, periods: periods, points: points, hovered: $hovered,
                          ticks: NiceScale.ticks(for: points.map(\.value).max() ?? 1),
                          tickLabel: { "\($0.formatted(.number.precision(.fractionLength(0...1)))) s" })
            .frame(minWidth: 280)
    }

    /// How far apart the middle half of the times is: it often draws together before the median
    /// falls much.
    private func spreadChart(_ periods: [TrendPeriod]) -> some View {
        let points = TrendMeasure.spread.points(in: periods)
        return TrendChart(title: "How much your times vary", subtitle: "Spread of the middle half of right answers",
                          measure: .spread, periods: periods, points: points, hovered: $hovered,
                          ticks: NiceScale.ticks(for: points.map(\.value).max() ?? 1),
                          // Spreads are small, so steps of 0.25 s come up: "0,25 s", not "0,2 s".
                          tickLabel: { "\($0.formatted(.number.precision(.fractionLength(0...2)))) s" })
            .frame(minWidth: 280)
    }
}

/// One step of the charts over time: a day, or a week for long ranges. "Over time" and "What you
/// practised" share it, so they go by day or by week together.
struct TrendPeriod: Identifiable {
    let start: Date
    /// The day after the period's last.
    let end: Date
    let isWeek: Bool
    let answers: Int
    let correct: Int
    let practiceSeconds: Double
    let medianResponseMs: Int?
    /// A day's quartiles of its right answers; nil for a week.
    let lowerQuartileMs: Int?
    let upperQuartileMs: Int?
    /// How far apart the middle half of the times is: a day's own, or the middle of a week's days'.
    let spreadMs: Int?
    /// Each answer method's part, in `AnswerMethod` order, only those with answers.
    let methods: [MethodPeriod]

    /// Past about six weeks a point a day breaks into fragments wherever a day is skipped and
    /// swings with small days: the charts go by week instead (so "Last 90 days" reads as a trend).
    static let weeklyAfterDays = 45

    var id: Date { start }
    var accuracy: Double? { answers > 0 ? Double(correct) / Double(answers) : nil }
    /// Where its point sits: the middle, so each period owns the space either side of it.
    var middle: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    /// "Wed, Oct 21", "Week of Oct 19"
    var label: String {
        isWeek ? "Week of \(start.formatted(.dateTime.day().month(.abbreviated)))" : DashboardFormat.day(start)
    }
    /// Answers in a way this version doesn't know (written by a later one): in `answers`, in no method.
    var otherAnswers: Int { max(0, answers - methods.map(\.answers).reduce(0, +)) }

    func part(_ method: AnswerMethod) -> MethodPeriod? { methods.first { $0.method == method } }

    init(day: DayProgress) {
        let calendar = Calendar.current
        start = calendar.startOfDay(for: day.day)
        end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        isWeek = false
        answers = day.answers
        correct = day.correct
        practiceSeconds = day.practiceSeconds
        medianResponseMs = day.medianResponseMs
        lowerQuartileMs = day.lowerQuartileMs
        upperQuartileMs = day.upperQuartileMs
        spreadMs = day.spreadMs
        methods = day.methods.filter { $0.answers > 0 }.map(MethodPeriod.init(day:))
    }

    private init(week days: ArraySlice<DayProgress>) {
        let calendar = Calendar.current
        start = calendar.startOfDay(for: days.first!.day)
        let last = calendar.startOfDay(for: days.last!.day)
        end = calendar.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86_400)
        isWeek = true
        answers = days.map(\.answers).reduce(0, +)
        correct = days.map(\.correct).reduce(0, +)
        practiceSeconds = days.map(\.practiceSeconds).reduce(0, +)
        // The middle of the week's daily medians: the report has no finer times, and a trend needs no more.
        medianResponseMs = Self.middle(days.compactMap(\.medianResponseMs))
        // Likewise the middle of its daily spreads; a week's own quartiles would need its times.
        lowerQuartileMs = nil
        upperQuartileMs = nil
        spreadMs = Self.middle(days.compactMap(\.spreadMs))
        let parts = days.flatMap(\.methods).filter { $0.answers > 0 }
        methods = AnswerMethod.allCases.compactMap { method in
            let days = parts.filter { $0.method == method }
            return days.isEmpty ? nil : MethodPeriod(week: days)
        }
    }

    /// The middle value (the upper one of an even count), nil for none.
    static func middle(_ values: [Int]) -> Int? {
        values.isEmpty ? nil : values.sorted()[values.count / 2]
    }

    static func isWeekly(_ days: [DayProgress]) -> Bool { days.count > weeklyAfterDays }

    /// The charts' periods for a report's days: one a day, or calendar weeks past `weeklyAfterDays`.
    static func periods(for days: [DayProgress]) -> [TrendPeriod] {
        isWeekly(days) ? weeks(of: days) : days.map(TrendPeriod.init(day:))
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

    /// The answer methods with answers on any of `days`, in `AnswerMethod` order.
    static func methods(in days: [DayProgress]) -> [AnswerMethod] {
        let present = Set(days.flatMap { $0.methods.filter { $0.answers > 0 }.map(\.method) })
        return AnswerMethod.allCases.filter(present.contains)
    }

    // MARK: - The x axis, shared by the charts over time

    /// Long ranges label months. Otherwise a label every day for a week, then every week or
    /// fortnight, counted back from today so the latest day is always labelled.
    static func axisTicks(_ periods: [TrendPeriod]) -> [Date] {
        let calendar = Calendar.current
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

    static func axisLabel(_ date: Date, in periods: [TrendPeriod]) -> String {
        let calendar = Calendar.current
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

    /// Where a date label hangs from its tick: centred under it, but the latest period's ends at its
    /// tick by the right edge, and one within half a label ("Oct 18") of the left edge starts at its
    /// tick, so neither is cut. `plotWidth` is the plot's, or the narrowest it gets.
    static func axisAnchor(_ date: Date?, in periods: [TrendPeriod], plotWidth: CGFloat = 280) -> UnitPoint {
        guard let date, let last = periods.last else { return .top }
        if date == last.middle { return .topTrailing }
        let domain = axisDomain(periods)
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return .top }
        return CGFloat(date.timeIntervalSince(domain.lowerBound) / span) * plotWidth < 20 ? .topLeading : .top
    }

    /// The x domain: from the first period's start to the last one's end.
    static func axisDomain(_ periods: [TrendPeriod]) -> ClosedRange<Date> {
        guard let first = periods.first, let last = periods.last else { return Date()...Date() }
        return first.start...last.end
    }

    /// The period under the pointer's x, or the nearest one at either end.
    static func period(at date: Date, in periods: [TrendPeriod]) -> TrendPeriod? {
        guard let first = periods.first, let last = periods.last else { return nil }
        if date < first.start { return first }
        return periods.first { date < $0.end } ?? last
    }
}

/// One answer method's part of a trend period: a day's `MethodDay` as it is, or a week's days added
/// up as the period is (answers summed, the time and spread the middle of its days').
struct MethodPeriod: Equatable, Identifiable {
    let method: AnswerMethod
    let answers: Int
    let correct: Int
    let medianResponseMs: Int?
    /// A day's quartiles; nil for a week.
    let lowerQuartileMs: Int?
    let upperQuartileMs: Int?
    let spreadMs: Int?
    let rightSingleNotes: Int

    var id: AnswerMethod { method }
    var accuracy: Double? { answers > 0 ? Double(correct) / Double(answers) : nil }

    init(day: MethodDay) {
        method = day.method
        answers = day.answers
        correct = day.correct
        medianResponseMs = day.medianResponseMs
        lowerQuartileMs = day.lowerQuartileMs
        upperQuartileMs = day.upperQuartileMs
        spreadMs = day.spreadMs
        rightSingleNotes = day.rightSingleNotes
    }

    /// `days` are one method's, at least one.
    init(week days: [MethodDay]) {
        method = days[0].method
        answers = days.map(\.answers).reduce(0, +)
        correct = days.map(\.correct).reduce(0, +)
        medianResponseMs = TrendPeriod.middle(days.compactMap(\.medianResponseMs))
        lowerQuartileMs = nil
        upperQuartileMs = nil
        spreadMs = TrendPeriod.middle(days.compactMap(\.spreadMs))
        rightSingleNotes = days.map(\.rightSingleNotes).reduce(0, +)
    }
}

/// What a chart over time shows of each method, and when it has enough to show it.
enum TrendMeasure {
    case accuracy, responseTime, spread

    /// What `MethodDay.minimumForTrend` counts for it: answers for the accuracy, right answers for
    /// the typical time, right single notes for the spread.
    func evidence(_ part: MethodPeriod) -> Int {
        switch self {
        case .accuracy: part.answers
        case .responseTime: part.correct
        case .spread: part.rightSingleNotes
        }
    }

    /// The method's point in the chart's unit (percent, seconds); nil, a gap, under the minimum.
    func value(_ part: MethodPeriod) -> Double? {
        guard evidence(part) >= MethodDay.minimumForTrend else { return nil }
        return switch self {
        case .accuracy: part.accuracy.map { $0 * 100 }
        case .responseTime: part.medianResponseMs.map { Double($0) / 1000 }
        case .spread: part.spreadMs.map { Double($0) / 1000 }
        }
    }

    /// "94%", "1.4 s"; nil under the minimum.
    func readout(_ part: MethodPeriod) -> String? {
        guard value(part) != nil else { return nil }
        return switch self {
        case .accuracy: part.accuracy.map(DashboardFormat.percent)
        case .responseTime: part.medianResponseMs.map { DashboardFormat.seconds(milliseconds: $0) }
        case .spread: part.spreadMs.map { DashboardFormat.seconds(milliseconds: $0) }
        }
    }

    /// Every method's points, in `AnswerMethod` order, each line numbered by unbroken run so its
    /// own gaps break it.
    func points(in periods: [TrendPeriod]) -> [TrendPoint] {
        AnswerMethod.allCases.flatMap { method -> [TrendPoint] in
            let values = periods.map { $0.part(method).flatMap(value) }
            var points: [TrendPoint] = []
            var run = 0
            for (index, period) in periods.enumerated() {
                guard let value = values[index], let part = period.part(method) else {
                    run += 1
                    continue
                }
                let before = index > 0 ? values[index - 1] : nil
                let after = index + 1 < values.count ? values[index + 1] : nil
                points.append(TrendPoint(method: method, start: period.start, x: period.middle, value: value, run: run,
                                         isAlone: before == nil && after == nil,
                                         label: period.label, readout: readout(part) ?? ""))
            }
            return points
        }
    }
}

/// One method's point on a chart over time.
struct TrendPoint: Identifiable, Equatable {
    let method: AnswerMethod
    /// Its period's start.
    let start: Date
    let x: Date
    let value: Double
    /// Unbroken runs of the method's line are numbered apart, so a gap breaks it.
    let run: Int
    /// No neighbour with a value on either side: the line alone wouldn't show it.
    let isAlone: Bool
    /// The period's label and the value as the tooltip says them, for VoiceOver.
    let label: String
    let readout: String

    var id: String { "\(method.rawValue) \(start.timeIntervalSinceReferenceDate)" }
    /// The line it belongs to: one per method and run.
    var series: String { "\(method.rawValue) \(run)" }
}

/// One measure over time as a line per method: 2 px with round joins, each breaking at its own
/// gaps, a crosshair that snaps to the nearest day (or week), and a tooltip with every method.
private struct TrendChart: View {
    let title: String
    let subtitle: String
    let measure: TrendMeasure
    let periods: [TrendPeriod]
    let points: [TrendPoint]
    @Binding var hovered: Date?
    /// The y-axis from 0 to the last tick.
    let ticks: [Double]
    let tickLabel: (Double) -> String

    var body: some View {
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
                // The bottom of the scale: zero, or the lowest tick on a focused one.
                RuleMark(y: .value("Baseline", ticks.first ?? 0))
                    .foregroundStyle(DashboardTheme.baseline)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(points) { point in
                    LineMark(x: .value("Day", point.x), y: .value(title, point.value), series: .value("Line", point.series))
                        .foregroundStyle(point.method.color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .accessibilityLabel("\(point.method.label), \(point.label)")
                        .accessibilityValue(point.readout)
                }
                // The line carries the trend; a point on its own between gaps needs a marker to show.
                ForEach(points.filter(\.isAlone)) { point in
                    PointMark(x: .value("Day", point.x), y: .value(title, point.value))
                        .symbol { Marker(size: 8, color: point.method.color) }
                        .accessibilityHidden(true)
                }
                if let hoveredPeriod {
                    RuleMark(x: .value("Day", hoveredPeriod.middle))
                        .foregroundStyle(DashboardTheme.textMuted)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    ForEach(points.filter { $0.start == hoveredPeriod.start }) { point in
                        PointMark(x: .value("Day", point.x), y: .value(title, point.value))
                            .symbol { Marker(size: 10, color: point.method.color) }
                            .accessibilityHidden(true)
                    }
                }
            }
            .chartXScale(domain: TrendPeriod.axisDomain(periods))
            .chartYScale(domain: (ticks.first ?? 0)...(ticks.last ?? 1))
            .chartXAxis {
                AxisMarks(values: TrendPeriod.axisTicks(periods)) { mark in
                    // Labels by either edge hang inwards instead of being cut.
                    AxisValueLabel(anchor: TrendPeriod.axisAnchor(mark.as(Date.self), in: periods)) {
                        if let date = mark.as(Date.self) {
                            Text(TrendPeriod.axisLabel(date, in: periods))
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
                                    hovered = proxy.value(atX: location.x - plot.minX)
                                        .flatMap { TrendPeriod.period(at: $0, in: periods) }?.start
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

    /// Every method answered with that period: its value, or why it has none, and its notes.
    @ViewBuilder
    private func tooltip(_ period: TrendPeriod?) -> some View {
        if let period {
            if period.answers == 0 {
                ChartTooltip(value: "No practice", label: period.label)
            } else if period.methods.isEmpty {
                ChartTooltip(value: DashboardFormat.notes(period.answers), label: period.label)
            } else {
                MethodTooltip(label: period.label, rows: period.methods.map { part in
                    MethodTooltip.Row(method: part.method, value: measure.readout(part), detail: DashboardFormat.notes(part.answers))
                })
            }
        }
    }
}

/// A data point: its line's colour with a 2 px ring of the card's surface, so it stands off the line.
private struct Marker: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .padding(2)
            .background(Circle().fill(DashboardTheme.surface))
    }
}
