import Charts
import SwiftUI

/// "Reading a new bar": a piece's practice days (`PieceProgressSummary.days`), evenly spaced, one slot
/// each and oldest first (a piece is practised now and then, so a calendar would be mostly gaps), with
/// two lines: the median time to the start of a bar, and to the rest of the bar as the context. As the
/// first comes down towards the second, bars are being read ahead rather than worked out on arrival.
struct PieceDayChart: View {
    let days: [PieceDay]
    /// The width it's laid out at, to space the date labels.
    let width: CGFloat

    /// The practice day under the pointer (its slot).
    @State private var hovered: Int?

    /// About what the y labels take beside the plot: near enough to space the date labels.
    private static let yAxisWidth: CGFloat = 30

    var body: some View {
        let points = PieceDayLine.points(in: days)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Reading a new bar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashboardTheme.textPrimary)
                Text(days.count == 1 ? "Median time to a right answer, on the day you practised it"
                                     : "Median time to a right answer, each day you practised it")
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PieceDayLegend()
            if points.isEmpty {
                NothingYetText("No day has enough right answers to judge yet: \(MethodDay.minimumForTrend) are needed for a time.")
            } else {
                chart(points)
            }
            Text("The start of a bar is the first note after you move into a new bar. As it comes down towards the rest of the bar, you're reading ahead.")
                .font(.caption)
                .foregroundStyle(DashboardTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chart(_ points: [PieceDayPoint]) -> some View {
        let ticks = NiceScale.ticks(for: points.map(\.seconds).max() ?? 1)
        let plotWidth = max(1, width - Self.yAxisWidth)
        let labelled = PieceDayLine.labelledSlots(count: days.count, plotWidth: plotWidth)
        let edgePadding = PieceDayLine.edgePadding(count: days.count, plotWidth: plotWidth)
        return Chart {
            RuleMark(y: .value("Baseline", 0))
                .foregroundStyle(DashboardTheme.baseline)
                .lineStyle(StrokeStyle(lineWidth: 1))
            // The rest of the bar first, so the start of a bar is drawn over it where they meet.
            ForEach(points) { point in
                LineMark(x: .value("Day", Double(point.slot)), y: .value("Seconds", point.seconds),
                         series: .value("Line", point.series))
                    .foregroundStyle(point.line.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .accessibilityLabel("\(point.line.label), \(DashboardFormat.day(days[point.slot].day))")
                    .accessibilityValue(DashboardFormat.seconds(point.seconds))
            }
            // The lines carry the trend; a point with no neighbour needs a marker to show at all.
            ForEach(points.filter(\.isAlone)) { point in
                PointMark(x: .value("Day", Double(point.slot)), y: .value("Seconds", point.seconds))
                    .symbol { DayMarker(size: 8, color: point.line.color) }
                    .accessibilityHidden(true)
            }
            if let hovered {
                RuleMark(x: .value("Day", Double(hovered)))
                    .foregroundStyle(DashboardTheme.textMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(points.filter { $0.slot == hovered }) { point in
                    PointMark(x: .value("Day", Double(point.slot)), y: .value("Seconds", point.seconds))
                        .symbol { DayMarker(size: 10, color: point.line.color) }
                        .accessibilityHidden(true)
                }
            }
        }
        // One slot per day, its point in the middle; room at the ends when the slots are too narrow
        // for the first and last dates to centre under them.
        .chartXScale(domain: -0.5...(Double(days.count) - 0.5),
                     range: .plotDimension(startPadding: edgePadding, endPadding: edgePadding))
        .chartYScale(domain: 0...(ticks.last ?? 1))
        .chartXAxis {
            // A short tick under every practice day, so the slots read as days, not as a calendar.
            AxisMarks(values: days.indices.map(Double.init)) { _ in
                AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(DashboardTheme.baseline)
            }
            AxisMarks(values: labelled.map(Double.init)) { mark in
                let slot = mark.as(Double.self).map { Int($0.rounded()) } ?? -1
                // Centred under its day (a number axis would start it there); the edge padding keeps
                // the first and last whole.
                AxisValueLabel(anchor: .top, collisionResolution: .disabled) {
                    if days.indices.contains(slot) {
                        Text(PieceDayLine.shortDate(days[slot].day))
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
                        Text("\(tick.formatted(.number.precision(.fractionLength(0...2)))) s")
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
                                hovered = proxy.value(atX: location.x - plot.minX, as: Double.self)
                                    .map { PieceDayLine.slot(nearest: $0, count: days.count) }
                            case .ended:
                                hovered = nil
                            }
                        }
                        .tooltip(tooltip,
                                 beside: hovered.flatMap { proxy.position(forX: Double($0)) }.map { plot.minX + $0 } ?? 0,
                                 top: plot.minY + 4, in: geometry.size.width)
                }
            }
        }
        .frame(height: 170)
    }

    @ViewBuilder private var tooltip: some View {
        if let hovered, days.indices.contains(hovered) {
            PieceDayTooltip(day: days[hovered])
        }
    }
}

/// The chart's two lines, in drawing order: the rest of the bar (the context) under the start of a bar.
enum PieceDayLine: CaseIterable, Identifiable {
    case restOfBar, barStart

    /// Legend, tooltip and table: the start of a bar (the point of the chart) first.
    static let legendOrder: [PieceDayLine] = [.barStart, .restOfBar]

    var id: Self { self }

    var label: String {
        switch self {
        case .barStart: "Start of a bar"
        case .restOfBar: "Rest of the bar"
        }
    }

    var color: Color {
        switch self {
        case .barStart: DashboardTheme.accent
        case .restOfBar: DashboardTheme.deemphasis
        }
    }

    func medianMs(of day: PieceDay) -> Int? {
        switch self {
        case .barStart: day.barStartMs
        case .restOfBar: day.restOfBarMs
        }
    }

    /// The right answers its median comes from.
    func count(of day: PieceDay) -> Int {
        switch self {
        case .barStart: day.barStarts
        case .restOfBar: day.restOfBar
        }
    }

    /// The day's point in seconds; nil, a gap, under `MethodDay.minimumForTrend` right answers.
    func seconds(of day: PieceDay) -> Double? {
        guard count(of: day) >= MethodDay.minimumForTrend, let ms = medianMs(of: day) else { return nil }
        return Double(ms) / 1000
    }

    /// Both lines' points, the rest of the bar first; each line numbered by unbroken run (consecutive
    /// days with a point), so a day without one breaks it.
    static func points(in days: [PieceDay]) -> [PieceDayPoint] {
        allCases.flatMap { line -> [PieceDayPoint] in
            let values = days.map(line.seconds(of:))
            var points: [PieceDayPoint] = []
            var run = 0
            for (slot, value) in values.enumerated() {
                guard let value else {
                    run += 1
                    continue
                }
                let before = slot > 0 ? values[slot - 1] : nil
                let after = slot + 1 < values.count ? values[slot + 1] : nil
                points.append(PieceDayPoint(line: line, slot: slot, seconds: value, run: run,
                                            isAlone: before == nil && after == nil))
            }
            return points
        }
    }

    /// About the widest a short date gets ("Nov 21", "28 Oct") in the axis font.
    static let labelWidth: CGFloat = 38
    /// The least room between two date labels.
    static let labelGap: CGFloat = 10

    /// Room inside either end of the plot so the first and last slots' middles are at least half a
    /// label in, and their dates centre under them uncut; none when the slots are wide enough.
    static func edgePadding(count: Int, plotWidth: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        // The padding p with p + (plotWidth − 2p) / count / 2 = labelWidth / 2.
        let n = CGFloat(count)
        return max(0, (n * labelWidth - plotWidth) / (2 * (n - 1)))
    }

    /// The slots that get a date, each centred under its slot: every day when the labels fit, else
    /// every so many counted back from the latest, so it's always labelled.
    static func labelledSlots(count: Int, plotWidth: CGFloat) -> [Int] {
        guard count > 0 else { return [] }
        let padding = edgePadding(count: count, plotWidth: plotWidth)
        let slotWidth = max(plotWidth - 2 * padding, 1) / CGFloat(count)
        let step = max(1, Int(((labelWidth + labelGap) / slotWidth).rounded(.up)))
        return stride(from: count - 1, through: 0, by: -step).reversed()
    }

    /// The slot nearest an x value on the chart's scale.
    static func slot(nearest x: Double, count: Int) -> Int {
        min(max(Int(x.rounded()), 0), max(count - 1, 0))
    }

    /// "14 Oct" (or as the locale writes it): short enough to sit under a day's slot.
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// "Keyboard", "Keyboard and Real piano"; nil when the day's answers came in no method this version
    /// knows.
    static func methods(of day: PieceDay) -> String? {
        day.methods.isEmpty ? nil : MixedMethodsNote.list(day.methods)
    }

    /// Under the day in its tooltip: "Real piano · 90 notes · 87% right".
    static func summary(of day: PieceDay) -> String {
        let notes = "\(DashboardFormat.notes(day.answers)) · \(ReportFormat.percent(day.correct, of: day.answers)) right"
        return methods(of: day).map { "\($0) · \(notes)" } ?? notes
    }
}

/// One day's point on one line of the chart.
struct PieceDayPoint: Identifiable, Equatable {
    let line: PieceDayLine
    /// The day's place among the piece's days, oldest first.
    let slot: Int
    let seconds: Double
    /// Unbroken runs of the line are numbered apart, so a gap breaks it.
    let run: Int
    /// No neighbour with a point on either side: the line alone wouldn't show it.
    let isAlone: Bool

    var id: String { "\(line.label) \(slot)" }
    /// The line it belongs to: one per line and run.
    var series: String { "\(line.label) \(run)" }
}

/// The two lines, each with a short line of its colour.
private struct PieceDayLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(PieceDayLine.legendOrder) { line in
                HStack(spacing: 6) {
                    LineKey(color: line.color)
                    Text(line.label)
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.textPrimary)
                }
                .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A short line in a line's colour, for keys beside its name.
private struct LineKey: View {
    let color: Color

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: 14, height: 3)
    }
}

/// A day's tip: the date, how it was answered, its notes and accuracy, then both times with how many
/// right answers each comes from, or "too few to judge".
private struct PieceDayTooltip: View {
    let day: PieceDay

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DashboardFormat.day(day.day))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(DashboardTheme.textPrimary)
                Text(PieceDayLine.summary(of: day))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DashboardTheme.textSecondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                ForEach(PieceDayLine.legendOrder) { line in
                    GridRow(alignment: .firstTextBaseline) {
                        LineKey(color: line.color)
                            .alignmentGuide(.firstTextBaseline) { $0.height / 2 + 3.5 }
                        Text(line.label)
                            .font(.caption)
                            .foregroundStyle(DashboardTheme.textSecondary)
                        if let seconds = line.seconds(of: day) {
                            Text(DashboardFormat.seconds(seconds))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(DashboardTheme.textPrimary)
                        } else {
                            Text("too few to judge")
                                .font(.caption)
                                .foregroundStyle(DashboardTheme.textMuted)
                        }
                        Text(PieceSection.rightAnswers(line.count(of: day)))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(DashboardTheme.textMuted)
                    }
                }
            }
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DashboardTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DashboardTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .allowsHitTesting(false)
    }
}

/// A data point: its line's colour with a 2 px ring of the card's surface, so it stands off the line.
private struct DayMarker: View {
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
