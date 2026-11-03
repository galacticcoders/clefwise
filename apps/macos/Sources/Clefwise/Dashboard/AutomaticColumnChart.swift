import SwiftUI

/// A small column chart for the "Becoming automatic" panels: one hue; columns in slots of equal
/// width with a 2 px gap between them and never wider than 24 pt; hollow where there are too few
/// answers to judge; an optional step line for the window before, on the same scale; an optional
/// marked value with its label above the plot. Each column's whole slot is its hover target, and
/// the panel around the chart draws the tip (`hoverTip`).
struct AutomaticColumnChart: View {
    struct Column: Identifiable {
        let id: String
        /// On the y scale; nil draws nothing.
        let value: Double?
        var isHollow = false
        /// What VoiceOver reads for it.
        let label: String
        let accessibilityValue: String
    }

    /// A label under the plot, or a marked value above it, at `position` in columns from the left
    /// edge: 0 is the first column's left edge, 0.5 its middle.
    struct AxisLabel: Identifiable {
        let text: String
        let position: Double
        var id: Double { position }
    }

    let columns: [Column]
    /// The y-axis from 0 to the last tick, in the columns' unit.
    let ticks: [Double]
    let tickLabel: (Double) -> String
    let xLabels: [AxisLabel]
    /// The window before, one value per column, drawn as a quiet step line.
    var comparison: [Double]?
    /// A value marked with a rule across the plot and its label above it (the median).
    var marker: AxisLabel?
    /// Sets the last column a little apart, as it's open-ended ("6 s or more").
    var setsLastApart = false
    @Binding var hovered: String?

    static let plotHeight: CGFloat = 140
    /// Above the plot, for the marker's label.
    private static let markerBand: CGFloat = 18
    /// Under the plot, for the x labels.
    private static let labelBand: CGFloat = 18
    /// Room for the y labels ("100%") and a gap before the plot.
    private static let axisWidth: CGFloat = 40
    private static let apartGap: CGFloat = 5
    private static let gap: CGFloat = 2
    private static let maxColumnWidth: CGFloat = 24
    /// The window before: quieter than this window's columns.
    static let comparisonColor = DashboardTheme.deemphasis

    var body: some View {
        GeometryReader { proxy in
            let layout = Layout(plotWidth: max(0, proxy.size.width - Self.axisWidth), count: columns.count,
                                apart: setsLastApart ? Self.apartGap : 0)
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                grid(layout)
                columnRow(layout)
                    .padding(.leading, Self.axisWidth)
                    .padding(.top, Self.markerBand)
                overlays(layout)
                labels(layout, size: size)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .frame(height: Self.markerBand + Self.plotHeight + Self.labelBand)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Geometry

    /// Where each column sits across the plot.
    private struct Layout {
        let plotWidth: CGFloat
        let count: Int
        let apart: CGFloat

        var slot: CGFloat { count > 0 ? max(0, plotWidth - apart) / CGFloat(count) : 0 }

        /// `position` in columns to x in the plot, the last column's gap included.
        func x(_ position: Double) -> CGFloat {
            CGFloat(position) * slot + (apart > 0 && position >= Double(count - 1) ? apart : 0)
        }
    }

    private var top: Double { ticks.last.map { max($0, 0.000_1) } ?? 1 }

    /// From the top of the whole chart.
    private func y(_ value: Double) -> CGFloat {
        Self.markerBand + Self.plotHeight * (1 - CGFloat(min(max(value / top, 0), 1)))
    }

    // MARK: - Drawing

    /// Solid hairlines at each tick, the zero line a step darker.
    private func grid(_ layout: Layout) -> some View {
        Canvas { context, _ in
            for tick in ticks {
                let lineY = (y(tick) - 0.5).rounded() + 0.5
                var line = Path()
                line.move(to: CGPoint(x: Self.axisWidth, y: lineY))
                line.addLine(to: CGPoint(x: Self.axisWidth + layout.plotWidth, y: lineY))
                context.stroke(line, with: .color(tick == 0 ? DashboardTheme.baseline : DashboardTheme.gridline), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func columnRow(_ layout: Layout) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                if setsLastApart, index == columns.count - 1 {
                    Color.clear.frame(width: layout.apart, height: Self.plotHeight)
                }
                columnView(column, slot: layout.slot)
                    .frame(width: layout.slot, height: Self.plotHeight, alignment: .bottom)
                    .hoverTarget(column.id, hovered: $hovered)
                    .accessibilityElement()
                    .accessibilityLabel(column.label)
                    .accessibilityValue(column.accessibilityValue)
            }
        }
    }

    /// Square at the baseline, rounded at the data end; the hovered one lighter.
    @ViewBuilder
    private func columnView(_ column: Column, slot: CGFloat) -> some View {
        let width = max(1, min(Self.maxColumnWidth, slot - Self.gap))
        let height = column.value.map { Self.plotHeight * CGFloat(min(max($0 / top, 0), 1)) } ?? 0
        let radius = max(0, min(4, width / 3, height))
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: radius, topTrailing: radius), style: .continuous)
        let isHovered = hovered == column.id
        ZStack(alignment: .bottom) {
            // The whole slot takes the pointer, not just the column.
            Color.clear
            if height > 0 {
                Group {
                    if column.isHollow {
                        shape.fill(DashboardTheme.accent.opacity(isHovered ? 0.15 : 0))
                            .overlay { shape.strokeBorder(DashboardTheme.accent, lineWidth: 1) }
                    } else {
                        shape.fill(DashboardTheme.accent.opacity(isHovered ? 0.75 : 1))
                    }
                }
                .frame(width: width, height: max(height, 1))
            }
        }
    }

    /// The window before as a step line, and the marked value's rule.
    private func overlays(_ layout: Layout) -> some View {
        Canvas { context, _ in
            if let comparison, comparison.count == columns.count {
                var line = Path()
                for (index, value) in comparison.enumerated() {
                    let left = Self.axisWidth + layout.x(Double(index))
                    let point = CGPoint(x: left, y: y(value))
                    // The open-ended last column is its own step.
                    if index == 0 || (setsLastApart && index == comparison.count - 1) {
                        line.move(to: point)
                    } else {
                        line.addLine(to: point)
                    }
                    line.addLine(to: CGPoint(x: left + layout.slot, y: y(value)))
                }
                context.stroke(line, with: .color(Self.comparisonColor),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let marker {
                let x = (Self.axisWidth + layout.x(marker.position)).rounded() + 0.5
                var rule = Path()
                rule.move(to: CGPoint(x: x, y: Self.markerBand - 2))
                rule.addLine(to: CGPoint(x: x, y: Self.markerBand + Self.plotHeight))
                context.stroke(rule, with: .color(DashboardTheme.textPrimary), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func labels(_ layout: Layout, size: CGSize) -> some View {
        let plotMinX = Self.axisWidth, plotMaxX = Self.axisWidth + layout.plotWidth
        return ZStack(alignment: .topLeading) {
            ForEach(ticks, id: \.self) { tick in
                Text(tickLabel(tick))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DashboardTheme.textMuted)
                    // Never wrapped: a label longer than the room grows to the left.
                    .fixedSize()
                    .frame(width: Self.axisWidth - 6, alignment: .trailing)
                    .placed(x: (Self.axisWidth - 6) / 2, centredOn: y(tick), within: 0...Self.axisWidth, in: size)
            }
            ForEach(xLabels) { label in
                Text(label.text)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DashboardTheme.textMuted)
                    .placed(x: plotMinX + layout.x(label.position), top: Self.markerBand + Self.plotHeight + 3,
                            within: plotMinX...plotMaxX, in: size)
            }
            if let marker {
                Text(marker.text)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(DashboardTheme.textPrimary)
                    .placed(x: plotMinX + layout.x(marker.position), top: 0, within: plotMinX...plotMaxX, in: size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension View {
    /// Centred on `x` (kept within `range`), its top at `top`, in a frame of `size`.
    func placed(x: CGFloat, top: CGFloat, within range: ClosedRange<CGFloat>, in size: CGSize) -> some View {
        fixedSize()
            .alignmentGuide(.leading) { dimensions in
                -min(max(x - dimensions.width / 2, range.lowerBound), max(range.lowerBound, range.upperBound - dimensions.width))
            }
            .alignmentGuide(.top) { _ in -top }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Centred on `x` across and on `y` up and down.
    func placed(x: CGFloat, centredOn y: CGFloat, within range: ClosedRange<CGFloat>, in size: CGSize) -> some View {
        fixedSize()
            .alignmentGuide(.leading) { dimensions in
                -min(max(x - dimensions.width / 2, range.lowerBound), max(range.lowerBound, range.upperBound - dimensions.width))
            }
            .alignmentGuide(.top) { dimensions in -(y - dimensions.height / 2) }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
