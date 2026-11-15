import Charts
import SwiftUI

/// "What you practised": notes answered per day (per week past 45 days, as "Over time" goes), as
/// columns stacked by answer method in `AnswerMethod` order, bottom to top, each in its colour. The
/// column's height is the whole; its parts show whether a period was naming, playing or both.
struct PracticeMixSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    /// The period under the pointer (its start).
    @State private var hovered: Date?

    var body: some View {
        let isWeekly = TrendPeriod.isWeekly(report.days)
        DashboardCard(title: "What you practised",
                      subtitle: "Notes answered per \(isWeekly ? "week" : "day"), by answer method") {
            if report.days.contains(where: { $0.answers > 0 }) {
                let periods = TrendPeriod.periods(for: report.days)
                let methods = TrendPeriod.methods(in: report.days)
                let hasOther = periods.contains { $0.otherAnswers > 0 }
                VStack(alignment: .leading, spacing: 14) {
                    if methods.count + (hasOther ? 1 : 0) > 1 {
                        MethodLegend(methods: methods, includesOther: hasOther)
                    }
                    PracticeMixChart(periods: periods, hovered: $hovered)
                }
            } else {
                Text("No dated practice in this range yet.")
                    .foregroundStyle(DashboardTheme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        } table: {
            table
        }
    }

    /// Days with answers, newest first: each method's notes, the total and the time spent.
    private var table: some View {
        let methods = TrendPeriod.methods(in: report.days)
        let days = report.days.reversed().filter { $0.answers > 0 }.map(TrendPeriod.init(day:))
        let hasOther = days.contains { $0.otherAnswers > 0 }
        let columns: [DashboardTable.Column] = [.init(title: "Day", isNumeric: false)]
            + methods.map { .init(title: $0.label) }
            + (hasOther ? [.init(title: MethodLegend.otherLabel)] : [])
            + [.init(title: "Total"), .init(title: "Practice time")]
        return DashboardTable(columns: columns, rows: days.map { day in
            [DashboardFormat.day(day.start)]
                + methods.map { method in day.part(method).map { $0.answers.formatted() } ?? "–" }
                + (hasOther ? [day.otherAnswers > 0 ? day.otherAnswers.formatted() : "–"] : [])
                + [day.answers.formatted(), DashboardFormat.duration(day.practiceSeconds)]
        })
    }
}

/// The stacked columns: one per period with answers, from the baseline, rounded at the top, its
/// methods apart by a 2 pt gap of the card; the whole plot is the hover target.
private struct PracticeMixChart: View {
    let periods: [TrendPeriod]
    @Binding var hovered: Date?

    /// The plot's own height (`chartPlotStyle`), so a point is a known number of notes.
    private static let plotHeight: CGFloat = 150
    /// Under the plot, for the dates.
    private static let labelBand: CGFloat = 22
    /// About what the y labels take beside the plot: near enough to size the columns.
    private static let yAxisWidth: CGFloat = 36

    var body: some View {
        GeometryReader { geometry in
            chart(plotWidth: geometry.size.width - Self.yAxisWidth)
        }
        .frame(height: Self.plotHeight + Self.labelBand)
    }

    private func chart(plotWidth: CGFloat) -> some View {
        let columnWidth = MixColumn.width(for: periods, plotWidth: plotWidth)
        let segments = periods.flatMap(MixColumn.segments(of:))
        let ticks = NiceScale.ticks(for: segments.map(\.upper).max() ?? 0)
        let top = ticks.last ?? 1
        let notesPerPoint = top / Self.plotHeight
        let hoveredPeriod = hovered.flatMap { start in periods.first { $0.start == start } }
        return Chart {
            // The hovered period's slot, lightly: it shows which day the tip is about, practised or not.
            if let hoveredPeriod {
                RectangleMark(xStart: .value("Day", hoveredPeriod.start), xEnd: .value("Day", hoveredPeriod.end),
                              yStart: .value("Notes", 0), yEnd: .value("Notes", top))
                    .foregroundStyle(DashboardTheme.textMuted.opacity(0.1))
                    .accessibilityHidden(true)
            }
            RuleMark(y: .value("Baseline", 0))
                .foregroundStyle(DashboardTheme.baseline)
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(segments) { segment in
                let drawn = segment.drawn(gap: MixColumn.gap * notesPerPoint, minimum: notesPerPoint)
                // The column's top is rounded: a rounded mark, its lower corners covered by a square one.
                let radius = segment.isTop ? min(4, columnWidth / 3, (drawn.upperBound - drawn.lowerBound) / notesPerPoint / 2) : 0
                BarMark(x: .value("Day", segment.x), yStart: .value("Notes", drawn.lowerBound),
                        yEnd: .value("Notes", drawn.upperBound), width: .fixed(columnWidth))
                    .foregroundStyle(segment.color)
                    .cornerRadius(radius)
                    .accessibilityLabel("\(segment.periodLabel), \(segment.name)")
                    .accessibilityValue(DashboardFormat.notes(segment.answers))
                if radius > 0 {
                    BarMark(x: .value("Day", segment.x), yStart: .value("Notes", drawn.lowerBound),
                            yEnd: .value("Notes", drawn.upperBound - radius * notesPerPoint), width: .fixed(columnWidth))
                        .foregroundStyle(segment.color)
                        .accessibilityHidden(true)
                }
            }
        }
        .chartXScale(domain: TrendPeriod.axisDomain(periods))
        .chartYScale(domain: 0...top)
        .chartPlotStyle { $0.frame(height: Self.plotHeight) }
        .chartXAxis {
            AxisMarks(values: TrendPeriod.axisTicks(periods)) { mark in
                // Labels by either edge hang inwards instead of being cut.
                AxisValueLabel(anchor: TrendPeriod.axisAnchor(mark.as(Date.self), in: periods, plotWidth: plotWidth)) {
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
                        Text(Int(tick).formatted())
                            .font(.caption)
                            .monospacedDigit()
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
    }

    /// The period's notes, each method's part, and the time spent.
    @ViewBuilder
    private func tooltip(_ period: TrendPeriod?) -> some View {
        if let period {
            if period.answers > 0 {
                MethodTooltip(value: DashboardFormat.notes(period.answers), label: period.label,
                              rows: MixColumn.segments(of: period).map { MethodTooltip.Row(method: $0.method, value: $0.answers.formatted()) },
                              detail: "\(DashboardFormat.duration(period.practiceSeconds)) of practice")
            } else {
                ChartTooltip(value: "No practice", label: period.label)
            }
        }
    }
}

/// A period's column in "What you practised", worked out apart from drawing it.
enum MixColumn {
    /// Columns are never wider than this, and stand this far apart (as their parts do).
    static let maxWidth: CGFloat = 24
    static let gap: CGFloat = 2

    /// Its parts bottom to top: each method with answers in `AnswerMethod` order, then any answers
    /// in a way this version doesn't know. None for a period without practice.
    static func segments(of period: TrendPeriod) -> [MixSegment] {
        var parts: [(method: AnswerMethod?, answers: Int)] = period.methods.map { ($0.method, $0.answers) }
        if period.otherAnswers > 0 { parts.append((nil, period.otherAnswers)) }
        var below = 0
        return parts.enumerated().map { index, part in
            defer { below += part.answers }
            return MixSegment(periodStart: period.start, periodLabel: period.label, x: period.middle, method: part.method,
                              answers: part.answers, lower: Double(below), upper: Double(below + part.answers),
                              isTop: index == parts.count - 1)
        }
    }

    /// As wide as the two closest periods leave room for with a `gap` between, up to `maxWidth`.
    static func width(for periods: [TrendPeriod], plotWidth: CGFloat) -> CGFloat {
        let domain = TrendPeriod.axisDomain(periods)
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0, plotWidth > 0 else { return maxWidth }
        let closest = zip(periods, periods.dropFirst()).map { $1.middle.timeIntervalSince($0.middle) }.min() ?? span
        return max(1, min(maxWidth, CGFloat(closest / span) * plotWidth - gap))
    }
}

/// One method's part of a column, in notes from the baseline.
struct MixSegment: Identifiable, Equatable {
    let periodStart: Date
    let periodLabel: String
    let x: Date
    /// Nil: answers in a way this version doesn't know ("Other").
    let method: AnswerMethod?
    let answers: Int
    /// Notes below it in the column, and up to its top.
    let lower: Double
    let upper: Double
    /// The column's last part, rounded at the top.
    let isTop: Bool

    var id: String { "\(periodStart.timeIntervalSinceReferenceDate) \(method?.rawValue ?? "other")" }
    var name: String { method?.label ?? MethodLegend.otherLabel }
    var color: Color { method?.color ?? DashboardTheme.deemphasis }

    /// Where it's drawn, in notes: half a `gap` in from each neighbour, so parts stand `gap` apart;
    /// the foot on the baseline and the column's top where its total is. A part too small for the
    /// gaps still shows, `minimum` tall (at the top for the column's last part).
    func drawn(gap: Double, minimum: Double) -> ClosedRange<Double> {
        let low = lower > 0 ? lower + gap / 2 : lower
        let high = isTop ? upper : upper - gap / 2
        if high - low >= minimum { return low...high }
        let thinHigh = isTop ? upper : (lower + upper) / 2 + minimum / 2
        return max(0, thinHigh - minimum)...thinHigh
    }
}

/// The answer methods' key, shared by every chart that colours by method: a swatch and the name of
/// each of `methods`, under "Naming" and "Playing" (`AnswerMethod.byFamily`), in `AnswerMethod`
/// order, on as many lines as the width needs.
struct MethodLegend: View {
    let methods: [AnswerMethod]
    /// Adds "Other", in the de-emphasis grey, for answers in a way this version doesn't know (a later
    /// version's, on another Mac).
    var includesOther = false

    static let otherLabel = "Other"
    /// More room between the families than between the methods in one.
    private static let familyGap: CGFloat = 10

    var body: some View {
        LegendFlow(spacing: 12, lineSpacing: 6) {
            ForEach(Array(AnswerMethod.byFamily(methods).enumerated()), id: \.offset) { index, group in
                // The family's name stays on the line of its first method.
                HStack(spacing: 8) {
                    Text(group.family.label)
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.textSecondary)
                    item(group.methods[0].label, color: group.methods[0].color)
                }
                .layoutValue(key: GroupGap.self, value: index > 0 ? Self.familyGap : 0)
                ForEach(group.methods.dropFirst()) { method in
                    item(method.label, color: method.color)
                }
            }
            if includesOther {
                item(Self.otherLabel, color: DashboardTheme.deemphasis)
                    .layoutValue(key: GroupGap.self, value: methods.isEmpty ? 0 : Self.familyGap)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func item(_ label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundStyle(DashboardTheme.textPrimary)
        }
        .fixedSize()
    }
}

/// Extra room before a legend entry that starts a group, unless it starts a line.
private struct GroupGap: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

/// Entries left to right, wrapping onto a new line when the next one doesn't fit.
private struct LegendFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(subviews, width: bounds.width).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let gap = x > 0 ? spacing + subview[GroupGap.self] : 0
            if x > 0, x + gap + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
                frames.append(CGRect(origin: CGPoint(x: 0, y: y), size: size))
                x = size.width
            } else {
                frames.append(CGRect(origin: CGPoint(x: x + gap, y: y), size: size))
                x += gap + size.width
            }
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x)
        }
        return (frames, CGSize(width: widest, height: y + lineHeight))
    }
}

/// The hover readout of a chart by method: the lead value (when there's one) and the period, then
/// a row per method, keyed by a short stroke of its colour (the text stays in text colours): its
/// name, its value or "too few to judge", and a detail; then any line about the whole period.
struct MethodTooltip: View {
    struct Row: Identifiable {
        /// Nil: answers in a way this version doesn't know ("Other").
        let method: AnswerMethod?
        /// Nil: too few to judge.
        let value: String?
        var detail: String? = nil

        var id: String { method?.rawValue ?? "other" }
    }

    var value: String? = nil
    let label: String
    let rows: [Row]
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 2) {
                if let value {
                    Text(value)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DashboardTheme.textPrimary)
                }
                Text(label)
                    .font(value == nil ? .caption.weight(.semibold) : .caption)
                    .foregroundStyle(DashboardTheme.textSecondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                ForEach(rows) { row in
                    GridRow(alignment: .firstTextBaseline) {
                        Capsule()
                            .fill(row.method?.color ?? DashboardTheme.deemphasis)
                            .frame(width: 12, height: 3)
                            .alignmentGuide(.firstTextBaseline) { $0.height / 2 + 3.5 }
                        Text(row.method?.label ?? MethodLegend.otherLabel)
                            .font(.caption)
                            .foregroundStyle(DashboardTheme.textSecondary)
                        if let value = row.value {
                            // Numbers line up on the right, unless a row says why it has none.
                            Text(value)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(DashboardTheme.textPrimary)
                                .gridColumnAlignment(rows.allSatisfy { $0.value != nil } ? .trailing : .leading)
                        } else {
                            Text("too few to judge")
                                .font(.caption)
                                .foregroundStyle(DashboardTheme.textMuted)
                        }
                        if let detail = row.detail {
                            Text(detail)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(DashboardTheme.textMuted)
                        }
                    }
                }
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textMuted)
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
