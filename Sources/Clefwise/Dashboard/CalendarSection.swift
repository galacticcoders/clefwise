import SwiftUI

/// A practice calendar: one cell per day in the window, darker for more notes answered.
struct CalendarSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    var body: some View {
        DashboardCard(title: "Practice calendar", subtitle: "Notes answered each day") {
            if report.days.isEmpty {
                Text("No dated practice in this range yet.")
                    .foregroundStyle(DashboardTheme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                let scale = CalendarScale(maximum: report.days.map(\.answers).max() ?? 0)
                VStack(alignment: .leading, spacing: 14) {
                    CalendarGrid(days: report.days, scale: scale)
                    HStack(alignment: .bottom, spacing: 16) {
                        CalendarLegend(scale: scale)
                        Spacer(minLength: 0)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(DashboardTheme.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        } table: {
            DashboardTable(
                columns: [.init(title: "Day", isNumeric: false), .init(title: "Notes"), .init(title: "Practice time")],
                rows: report.days.reversed().map { day in
                    [DashboardFormat.day(day.day), day.answers.formatted(),
                     day.answers > 0 ? DashboardFormat.duration(day.practiceSeconds) : "–"]
                })
        }
    }

    /// "Practised on 22 of 30 days"
    private var summary: String {
        let practised = report.days.filter { $0.answers > 0 }.count
        return "Practised on \(practised) of \(report.days.count) \(report.days.count == 1 ? "day" : "days")"
    }
}

/// Notes answered binned into five steps of a round size, so the legend can name each step.
private struct CalendarScale {
    static let steps = 5
    /// Notes per step: the first round size that lets five steps reach the busiest day.
    let step: Int

    init(maximum: Int) {
        let needed = max(1, Int((Double(maximum) / Double(Self.steps)).rounded(.up)))
        var magnitude = 1
        while magnitude * 10 < needed { magnitude *= 10 }
        step = [1, 2, 3, 4, 5, 10].map { $0 * magnitude }.first { $0 >= needed } ?? needed
    }

    /// 0…4; nil for a day without practice.
    func bin(_ answers: Int) -> Int? {
        answers > 0 ? min(Self.steps - 1, (answers - 1) / step) : nil
    }

    /// Light to dark from ramp step 250, the palest an ordered scale may start on white.
    func color(bin: Int?) -> Color {
        guard let bin else { return CalendarGrid.emptyColor }
        return DashboardTheme.rampColor(Double(bin) / Double(Self.steps - 1), fromStep: 3)
    }

    /// "1–20", or "4" when each step is one note; the last step is open-ended ("81+").
    func label(bin: Int) -> String {
        let low = bin * step + 1, high = (bin + 1) * step
        if bin == Self.steps - 1 { return "\(low)+" }
        return low == high ? "\(low)" : "\(low)–\(high)"
    }
}

/// Weeks as columns and weekdays as rows, like a contribution graph, newest week on the right.
private struct CalendarGrid: View {
    let days: [DayProgress]
    let scale: CalendarScale

    /// A pale neutral, not the ramp's first step, so "none" never reads as "a little".
    static let emptyColor = DashboardTheme.gridline.opacity(0.7)

    private static let gap: CGFloat = 3
    private static let cellRange: ClosedRange<CGFloat> = 11...22
    private static let labelWidth: CGFloat = 34
    private static let monthHeight: CGFloat = 16

    @State private var width: CGFloat = 0
    @State private var hovered: Cell?

    private let calendar = Calendar.current

    private struct Cell: Equatable {
        let column: Int
        let row: Int
        let day: DayProgress
    }

    /// Columns of seven: each week's days from the locale's first weekday, nil outside the range.
    private var weeks: [[DayProgress?]] {
        guard let first = days.first?.day, let last = days.last?.day,
              let start = calendar.dateInterval(of: .weekOfYear, for: first)?.start else { return [] }
        let byDay = Dictionary(days.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { a, _ in a })
        var weeks: [[DayProgress?]] = []
        var weekStart = start
        while weekStart <= last {
            weeks.append((0..<7).map { offset in
                calendar.date(byAdding: .day, value: offset, to: weekStart).flatMap { byDay[calendar.startOfDay(for: $0)] }
            })
            guard let next = calendar.date(byAdding: .day, value: 7, to: weekStart) else { break }
            weekStart = next
        }
        return weeks
    }

    var body: some View {
        let weeks = weeks
        let cell = cellSize(columns: weeks.count)
        // Until the width is known, the scroll view (which takes any width) stands in.
        let fits = width > 0 && gridWidth(columns: weeks.count, cell: cell) <= width - Self.labelWidth
        VStack(alignment: .leading, spacing: 0) {
            // Measures the width on offer, whatever the grid needs.
            Color.clear
                .frame(height: 0)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { width = proxy.size.width }
                            .onChange(of: proxy.size.width) { width = $1 }
                    }
                }
            HStack(alignment: .top, spacing: 0) {
                weekdayLabels(cell: cell)
                    .padding(.top, Self.monthHeight)
                    .frame(width: Self.labelWidth, alignment: .leading)
                if fits {
                    grid(weeks, cell: cell)
                } else {
                    // Years of practice: the newest weeks show, the older ones scroll into view.
                    ScrollView(.horizontal) { grid(weeks, cell: cell) }
                        .defaultScrollAnchor(.trailing)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func cellSize(columns: Int) -> CGFloat {
        guard columns > 0, width > 0 else { return Self.cellRange.lowerBound }
        let available = width - Self.labelWidth - Self.gap * CGFloat(columns - 1)
        return min(max((available / CGFloat(columns)).rounded(.down), Self.cellRange.lowerBound), Self.cellRange.upperBound)
    }

    private func gridWidth(columns: Int, cell: CGFloat) -> CGFloat {
        CGFloat(columns) * cell + CGFloat(max(0, columns - 1)) * Self.gap
    }

    private func weekdayLabels(cell: CGFloat) -> some View {
        let symbols = calendar.shortWeekdaySymbols
        // Every other row when the cells are too short for a label each.
        let everyRow = cell >= 16
        return VStack(alignment: .leading, spacing: Self.gap) {
            ForEach(0..<7, id: \.self) { row in
                Text(everyRow || row % 2 == 1 ? symbols[(calendar.firstWeekday - 1 + row) % 7] : "")
                    .font(.caption2)
                    .foregroundStyle(DashboardTheme.textMuted)
                    .frame(height: cell)
            }
        }
    }

    private func grid(_ weeks: [[DayProgress?]], cell: CGFloat) -> some View {
        let pitch = cell + Self.gap
        return VStack(alignment: .leading, spacing: 0) {
            monthLabels(weeks, cell: cell)
                .frame(height: Self.monthHeight, alignment: .topLeading)
            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(weeks.indices, id: \.self) { column in
                    VStack(spacing: Self.gap) {
                        ForEach(0..<7, id: \.self) { row in
                            cellView(weeks[column][row], size: cell,
                                     isHovered: hovered?.column == column && hovered?.row == row)
                        }
                    }
                }
            }
            // The whole grid is the hit target: the pointer picks the nearest cell, gaps included.
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let column = min(max(Int(location.x / pitch), 0), weeks.count - 1)
                    let row = min(max(Int(location.y / pitch), 0), 6)
                    hovered = weeks.indices.contains(column) ? weeks[column][row].map { Cell(column: column, row: row, day: $0) } : nil
                case .ended:
                    hovered = nil
                }
            }
            .tooltip(tooltip, beside: hovered.map { CGFloat($0.column) * pitch + cell / 2 } ?? 0,
                     top: hovered.map { min(CGFloat($0.row) * pitch, max(0, 7 * pitch - 64)) } ?? 0,
                     in: max(0, width - Self.labelWidth))
        }
    }

    private func cellView(_ day: DayProgress?, size: CGFloat, isHovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: min(4, size / 4), style: .continuous)
            .fill(day.map { scale.color(bin: scale.bin($0.answers)) } ?? .clear)
            .frame(width: size, height: size)
            // Outlined in the gap around the cell, so it shows on the darkest step too.
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: min(4, size / 4) + 2, style: .continuous)
                        .strokeBorder(DashboardTheme.textPrimary, lineWidth: 1.5)
                        .padding(-2.5)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(day.map { "\(DashboardFormat.day($0.day)): \(DashboardFormat.notes($0.answers))" } ?? "")
            .accessibilityHidden(day == nil)
    }

    /// The month's short name over the first week it appears in, when there's room after the last one.
    private func monthLabels(_ weeks: [[DayProgress?]], cell: CGFloat) -> some View {
        let pitch = cell + Self.gap
        let minimumColumns = Int((30 / pitch).rounded(.up))
        var labels: [(column: Int, text: String)] = []
        for (column, week) in weeks.enumerated() {
            let shown = week.compactMap { $0 }
            guard let first = shown.first else { continue }
            // The first week shown is labelled with its month; later ones where a month begins.
            let monthStart = shown.first { calendar.component(.day, from: $0.day) == 1 }
            guard let date = monthStart?.day ?? (labels.isEmpty ? first.day : nil) else { continue }
            if let previous = labels.last, column - previous.column < minimumColumns {
                // A month starting just after the first week wins over the partial one before it.
                guard labels.count == 1 else { continue }
                labels.removeLast()
            }
            labels.append((column, date.formatted(.dateTime.month(.abbreviated))))
        }
        return ZStack(alignment: .topLeading) {
            ForEach(labels, id: \.column) { label in
                Text(label.text)
                    .font(.caption2)
                    .foregroundStyle(DashboardTheme.textMuted)
                    .fixedSize()
                    .offset(x: CGFloat(label.column) * pitch)
            }
        }
        .frame(width: gridWidth(columns: weeks.count, cell: cell), alignment: .topLeading)
    }

    @ViewBuilder
    private var tooltip: some View {
        if let day = hovered?.day {
            ChartTooltip(value: day.answers > 0 ? DashboardFormat.notes(day.answers) : "No practice",
                         label: DashboardFormat.day(day.day),
                         detail: day.answers > 0 ? "\(DashboardFormat.duration(day.practiceSeconds)) practised" : nil)
        }
    }
}

/// The scale: "None", then each step's colour with the notes it stands for.
private struct CalendarLegend: View {
    let scale: CalendarScale

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Notes answered")
                .font(.caption)
                .foregroundStyle(DashboardTheme.textSecondary)
            HStack(alignment: .top, spacing: 2) {
                swatch(CalendarGrid.emptyColor, "None")
                    .padding(.trailing, 8)
                ForEach(0..<CalendarScale.steps, id: \.self) { bin in
                    swatch(scale.color(bin: bin), scale.label(bin: bin))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 44, height: 12)
            Text(label)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(DashboardTheme.textMuted)
                .fixedSize()
        }
    }
}
