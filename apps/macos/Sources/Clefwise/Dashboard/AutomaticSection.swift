import SwiftUI

/// "Becoming automatic": the signs, in response times, that naming a note no longer takes working
/// out (`ProgressReport.responseTimes`), as three panels, each with a plain-language line under it:
/// - **How long your answers take:** the shape of the times now (and the window before), with the
///   median marked and the middle half in words. Times that bunch up are a sign.
/// - **Mistakes by speed:** whether mistakes come with the fastest answers (rushing) or not.
/// - **After the note before:** whether a note a step from the last is named faster than a far
///   jump, which means it's still partly worked out from the one before.
struct AutomaticSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use (none appear here).
    let naming: NamingSystem

    @State private var hovered: String?

    /// Narrower panels and the charts' labels start to crowd.
    private static let panelWidth: CGFloat = 270

    private var times: ResponseTimes { report.responseTimes }

    var body: some View {
        DashboardCard(title: "Becoming automatic", subtitle: "Signs that naming notes no longer takes working out") {
            if times.current.rightAnswers == 0 {
                emptyText
            } else {
                ThreeAcross {
                    timesPanel
                } second: {
                    speedPanel
                } third: {
                    previousNotePanel
                }
            }
        } table: {
            if times.current.rightAnswers == 0 {
                emptyText
            } else {
                // Three across when they fit. The first is long and the others short, so when they
                // don't, the short two stack beside it.
                let first = timesTable
                let second = speedTable
                let third = previousNoteTable
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 28) {
                        first
                        second
                        third
                    }
                    HStack(alignment: .top, spacing: 28) {
                        first
                        VStack(alignment: .leading, spacing: 24) {
                            second
                            third
                        }
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        first
                        second
                        third
                    }
                }
            }
        }
    }

    private var emptyText: some View {
        Text("Name some notes right and you'll see here how your times are settling.")
            .font(.callout)
            .foregroundStyle(DashboardTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    // MARK: - Shared pieces

    /// A panel's title, what it measures, then its chart, keys and line. At least `panelWidth`
    /// wide, and ideally that, so the three fit side by side whenever they can.
    private func panel(_ title: String, _ subtitle: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashboardTheme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .frame(minWidth: Self.panelWidth, idealWidth: Self.panelWidth, maxWidth: .infinity, alignment: .topLeading)
    }

    /// The plain-language line under a chart.
    @ViewBuilder
    private func insight(_ text: String?) -> some View {
        if let text {
            Text(text)
                .font(.callout)
                .foregroundStyle(DashboardTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What a hollow column means.
    private func hollowKey(_ text: String) -> some View {
        HStack(spacing: 6) {
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, topTrailing: 3), style: .continuous)
                .strokeBorder(DashboardTheme.accent, lineWidth: 1)
                .frame(width: 10, height: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(DashboardTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "12%", "2,5%": a share on an axis.
    private func percentTick(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1))))%"
    }

    private func count(_ value: Int, _ one: String, _ many: String) -> String {
        value == 1 ? "1 \(one)" : "\(ReportFormat.count(value)) \(many)"
    }

    private var periodNames: (current: String, previous: String?) {
        AutomaticInsight.periodNames(report.filter.range)
    }

    /// "the 30 days before", inside a sentence.
    private var previousInSentence: String? {
        report.filter.range.days.map { "the \($0) days before" }
    }

    // MARK: - How long your answers take

    /// The window before, when it has right answers to compare with (never for all time, which
    /// has nothing before it to name).
    private var previousHistogram: [Int]? {
        guard report.filter.range.days != nil, let previous = times.previousHistogram,
              previous.count == times.histogram.count, previous.reduce(0, +) > 0 else { return nil }
        return previous
    }

    /// The window before's quartiles, likewise.
    private var previousSpread: TimeSpread? {
        report.filter.range.days == nil ? nil : times.previous
    }

    /// Each bin's share of the window's right answers, in percent.
    private static func shares(_ counts: [Int]) -> [Double] {
        let total = counts.reduce(0, +)
        return counts.map { total > 0 ? Double($0) / Double(total) * 100 : 0 }
    }

    private var timesPanel: some View {
        let counts = times.histogram
        let total = counts.reduce(0, +)
        let shares = Self.shares(counts)
        let previousShares = previousHistogram.map(Self.shares)
        let top = max(shares.max() ?? 0, previousShares?.max() ?? 0)
        let binsPerSecond = 1000 / ResponseTimes.histogramBinMs
        let lastBin = ResponseTimes.histogramBins
        return panel("How long your answers take", "Share of right answers, by seconds taken") {
            AutomaticColumnChart(
                columns: counts.indices.map { index in
                    AutomaticColumnChart.Column(
                        id: "times.\(index)", value: shares[index],
                        label: AutomaticInsight.histogramBinLabel(index),
                        accessibilityValue: "\(ReportFormat.percent(counts[index], of: total)) of right answers")
                },
                ticks: NiceScale.ticks(for: top),
                tickLabel: percentTick,
                xLabels: (0..<(lastBin / binsPerSecond)).map {
                    AutomaticColumnChart.AxisLabel(text: $0.formatted(), position: Double($0 * binsPerSecond))
                } + [AutomaticColumnChart.AxisLabel(text: "\((lastBin / binsPerSecond).formatted())+",
                                                    position: Double(lastBin) + 0.5)],
                comparison: previousShares,
                marker: times.current.medianMs.map { median in
                    // A median past the last edge sits on the open-ended bin.
                    AutomaticColumnChart.AxisLabel(
                        text: "Median \(DashboardFormat.seconds(milliseconds: median))",
                        position: min(Double(median) / Double(ResponseTimes.histogramBinMs), Double(lastBin) + 0.5))
                },
                setsLastApart: true,
                hovered: $hovered)
            if let previous = periodNames.previous, previousShares != nil {
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(DashboardTheme.accent)
                            .frame(width: 10, height: 10)
                        Text(periodNames.current)
                    }
                    HStack(spacing: 5) {
                        Capsule()
                            .fill(AutomaticColumnChart.comparisonColor)
                            .frame(width: 14, height: 2)
                        Text(previous)
                    }
                }
                .font(.caption)
                .foregroundStyle(DashboardTheme.textSecondary)
                .accessibilityElement(children: .combine)
            }
            insight(AutomaticInsight.spreadLine(current: times.current, previous: previousSpread))
        }
        .hoverTip(for: hovered) { timesTip }
    }

    @ViewBuilder private var timesTip: some View {
        if let hovered, hovered.hasPrefix("times."), let index = Int(hovered.dropFirst("times.".count)),
           times.histogram.indices.contains(index) {
            let counts = times.histogram
            HoverTipText(
                value: "\(ReportFormat.percent(counts[index], of: counts.reduce(0, +))) of right answers",
                label: AutomaticInsight.histogramBinLabel(index),
                details: [
                    count(counts[index], "right answer", "right answers"),
                    previousHistogram.flatMap { previous in
                        previousInSentence.map { "\(ReportFormat.percent(previous[index], of: previous.reduce(0, +))) in \($0)" }
                    },
                ].compactMap { $0 })
        }
    }

    // MARK: - Mistakes by speed

    private var speedPanel: some View {
        let bins = times.bySpeed
        let rates = bins.map { $0.mistakeRate.map { $0 * 100 } }
        let top = rates.compactMap { $0 }.max() ?? 0
        let hasHollow = bins.contains { $0.answers > 0 && $0.answers < AccuracyScale.minimumAnswers }
        return panel("Mistakes by speed", "Share of answers wrong, by seconds taken") {
            if bins.allSatisfy({ $0.answers == 0 }) {
                NothingYetText("No answers in this range yet.")
            } else {
                AutomaticColumnChart(
                    columns: bins.indices.map { index in
                        let bin = bins[index]
                        return AutomaticColumnChart.Column(
                            id: "speed.\(bin.id)", value: rates[index],
                            isHollow: bin.answers < AccuracyScale.minimumAnswers,
                            label: AutomaticInsight.speedBinLabel(bin),
                            accessibilityValue: bin.answers == 0 ? "No answers"
                                : "\(ReportFormat.percent(bin.wrong, of: bin.answers)) wrong, of \(count(bin.answers, "answer", "answers"))")
                    },
                    ticks: NiceScale.ticks(for: top),
                    tickLabel: percentTick,
                    xLabels: bins.indices.map {
                        AutomaticColumnChart.AxisLabel(text: AutomaticInsight.speedAxisLabel(bins[$0]), position: Double($0) + 0.5)
                    },
                    hovered: $hovered)
                if hasHollow {
                    hollowKey("Fewer than \(AccuracyScale.minimumAnswers) answers: too few to judge yet")
                }
                insight(AutomaticInsight.speedLine(bins))
            }
        }
        .hoverTip(for: hovered) { speedTip }
    }

    @ViewBuilder private var speedTip: some View {
        if let hovered, hovered.hasPrefix("speed."), let lower = Int(hovered.dropFirst("speed.".count)),
           let bin = times.bySpeed.first(where: { $0.lowerMs == lower }) {
            let label = AutomaticInsight.speedBinLabel(bin)
            if bin.answers == 0 {
                HoverTipText(value: "No answers", label: label)
            } else {
                HoverTipText(
                    value: "\(ReportFormat.percent(bin.wrong, of: bin.answers)) wrong",
                    label: label,
                    details: [
                        "\(ReportFormat.count(bin.wrong)) of \(count(bin.answers, "answer", "answers")) wrong",
                        bin.answers < AccuracyScale.minimumAnswers ? "Too few answers to judge yet" : nil,
                    ].compactMap { $0 })
            }
        }
    }

    // MARK: - After the note before

    /// Distances with enough right answers for a median worth drawing. The rest are only in the
    /// table: "Same line or space" is usually a handful (random rounds never repeat a note), and a
    /// long outline at the top of the list would draw the eye to the least certain number.
    private var shownDistances: [PreviousNoteRow] {
        times.byPreviousNote.filter { $0.correct >= AccuracyScale.minimumAnswers && $0.medianMs != nil }
    }

    /// "Same line or space: too few right answers yet (3)." for distances left out that have some.
    private var leftOutDistances: String? {
        let few = times.byPreviousNote.filter { $0.correct > 0 && $0.correct < AccuracyScale.minimumAnswers }
        guard !few.isEmpty else { return nil }
        let names = few.map { "\($0.distance.label.lowercased()) (\($0.correct))" }
        let list = names.count == 1 ? names[0] : "\(names.dropLast().joined(separator: ", ")) and \(names.last!)"
        return "Not shown, too few right answers yet: \(list)."
    }

    private var previousNotePanel: some View {
        let rows = shownDistances
        let longest = Double(rows.compactMap(\.medianMs).max() ?? 1)
        return panel("After the note before", "Median time, by distance from the note before") {
            if rows.isEmpty {
                NothingYetText(times.byPreviousNote.contains { $0.correct > 0 }
                               ? "Too few right answers yet after another note on the same staff."
                               : "Notes that follow another on the same staff show up here.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        let id = "previous.\(row.distance.rawValue)"
                        let median = DashboardFormat.seconds(milliseconds: row.medianMs ?? 0)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(Text(row.distance.label).font(.callout.weight(.medium)).foregroundStyle(DashboardTheme.textPrimary))  \(Text(count(row.correct, "right answer", "right answers")).font(.caption).foregroundStyle(DashboardTheme.textMuted))")
                                .fixedSize(horizontal: false, vertical: true)
                            HorizontalValueBar(fraction: Double(row.medianMs ?? 0) / longest, value: median,
                                               isHighlighted: hovered == id, showsBaseline: false)
                                .frame(height: 14)
                        }
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // The whole row is the hover target, not just the bar.
                        .hoverTarget(id, hovered: $hovered)
                        .accessibilityElement()
                        .accessibilityLabel(AutomaticInsight.distanceDescription(row.distance))
                        .accessibilityValue("Median \(median), \(count(row.correct, "right answer", "right answers"))")
                    }
                }
                if let leftOutDistances {
                    Text(leftOutDistances)
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                insight(AutomaticInsight.previousNoteLine(times.byPreviousNote))
            }
        }
        .hoverTip(for: hovered) { previousNoteTip }
    }

    @ViewBuilder private var previousNoteTip: some View {
        if let hovered, hovered.hasPrefix("previous."),
           let distance = PreviousNoteDistance(rawValue: String(hovered.dropFirst("previous.".count))),
           let row = times.byPreviousNote.first(where: { $0.distance == distance }), let median = row.medianMs {
            HoverTipText(
                value: "\(DashboardFormat.seconds(milliseconds: median)) median",
                label: AutomaticInsight.distanceDescription(distance),
                details: ["\(ReportFormat.count(row.correct)) of \(count(row.answers, "answer", "answers")) right"])
        }
    }

    // MARK: - Tables

    private func tableTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DashboardTheme.textSecondary)
    }

    /// The shared table look, at the text's full width: a Grid squeezed by the layout around it
    /// cut its headings short, while every cell at full width keeps its measured width true.
    private func tableHeading(_ title: String) -> some View {
        ReportTable.heading(title).fixedSize()
    }

    private func tableCell(_ text: String, muted: Bool = false) -> some View {
        ReportTable.cell(text, muted: muted).fixedSize()
    }

    private func range(_ spread: TimeSpread?) -> String {
        guard let lower = spread?.lowerQuartileMs, let upper = spread?.upperQuartileMs else { return "—" }
        return AutomaticInsight.secondsRange(lower, upper)
    }

    /// The quartiles now and before, then every bin from the first to the last with an answer in
    /// either window.
    private var timesTable: some View {
        let counts = times.histogram
        let total = counts.reduce(0, +)
        let previous = previousHistogram
        let previousTotal = previous?.reduce(0, +) ?? 0
        let used = counts.indices.filter { counts[$0] > 0 || (previous?[$0] ?? 0) > 0 }
        let shown = used.isEmpty ? [] : Array(used.first!...used.last!)
        let before = previousSpread
        let beforeName = report.filter.range.days.map { "\($0) days before" }
        // One grid, so each window is one column all the way down: the summary's values for this
        // window sit in the bins' count column, the window before's in its own.
        let hasBefore = before != nil || previous != nil
        return VStack(alignment: .leading, spacing: 12) {
            tableTitle("How long your answers take")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                GridRow {
                    tableHeading("")
                    tableHeading(periodNames.current)
                    tableHeading("")
                    if hasBefore, let beforeName {
                        tableHeading(beforeName)
                    }
                }
                ReportTable.rule()
                summaryRow("Right answers", times.current, before, hasBefore) { ReportFormat.count($0.rightAnswers) }
                summaryRow("Middle half", times.current, before, hasBefore) { range($0) }
                summaryRow("Spread", times.current, before, hasBefore) {
                    $0.spreadMs.map { DashboardFormat.seconds(milliseconds: $0) } ?? "—"
                }
                summaryRow("Median", times.current, before, hasBefore) { ReportFormat.seconds($0.medianMs) }
                Color.clear
                    .frame(height: 8)
                    .gridCellUnsizedAxes(.horizontal)
                GridRow {
                    tableHeading("Time")
                    tableHeading("Right answers").gridColumnAlignment(.trailing)
                    tableHeading("Share").gridColumnAlignment(.trailing)
                    if hasBefore, let beforeName {
                        tableHeading(beforeName).gridColumnAlignment(.trailing)
                    }
                }
                ReportTable.rule()
                ForEach(shown, id: \.self) { index in
                    GridRow {
                        tableCell(AutomaticInsight.histogramBinLabel(index))
                        tableCell(ReportFormat.count(counts[index]))
                        tableCell(ReportFormat.percent(counts[index], of: total))
                        if hasBefore {
                            tableCell(previous.map { ReportFormat.percent($0[index], of: previousTotal) } ?? "—")
                        }
                    }
                }
            }
        }
    }

    private func summaryRow(_ name: String, _ now: TimeSpread, _ before: TimeSpread?, _ hasBefore: Bool,
                            _ value: @escaping (TimeSpread) -> String) -> some View {
        GridRow {
            tableCell(name)
            tableCell(value(now))
            Color.clear
                .gridCellUnsizedAxes([.horizontal, .vertical])
            if hasBefore {
                tableCell(before.map(value) ?? "—")
            }
        }
    }

    private var speedTable: some View {
        let bins = times.bySpeed
        let answers = bins.map(\.answers).reduce(0, +)
        let wrong = bins.map(\.wrong).reduce(0, +)
        return VStack(alignment: .leading, spacing: 12) {
            tableTitle("Mistakes by speed")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                GridRow {
                    tableHeading("Time")
                    tableHeading("Answers").gridColumnAlignment(.trailing)
                    tableHeading("Wrong").gridColumnAlignment(.trailing)
                    tableHeading("Mistakes").gridColumnAlignment(.trailing)
                }
                ReportTable.rule()
                ForEach(bins) { bin in
                    GridRow {
                        tableCell(AutomaticInsight.speedBinLabel(bin))
                        tableCell(ReportFormat.count(bin.answers))
                        tableCell(ReportFormat.count(bin.wrong))
                        tableCell(ReportFormat.percent(bin.wrong, of: bin.answers),
                                         muted: bin.answers < AccuracyScale.minimumAnswers)
                    }
                }
                ReportTable.rule()
                GridRow {
                    tableCell("All speeds")
                    tableCell(ReportFormat.count(answers))
                    tableCell(ReportFormat.count(wrong))
                    tableCell(ReportFormat.percent(wrong, of: answers))
                }
            }
        }
    }

    private var previousNoteTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            tableTitle("After the note before")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                GridRow {
                    tableHeading("From the note before")
                    tableHeading("Answers").gridColumnAlignment(.trailing)
                    tableHeading("Right").gridColumnAlignment(.trailing)
                    tableHeading("Median time").gridColumnAlignment(.trailing)
                }
                ReportTable.rule()
                ForEach(times.byPreviousNote) { row in
                    GridRow {
                        tableCell(row.distance.label)
                        tableCell(ReportFormat.count(row.answers))
                        tableCell(ReportFormat.count(row.correct))
                        tableCell(ReportFormat.seconds(row.medianMs), muted: row.correct < AccuracyScale.minimumAnswers)
                    }
                }
            }
        }
    }
}
