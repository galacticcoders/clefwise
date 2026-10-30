import SwiftUI

/// How accuracy and speed differ by answer method and naming system.
struct BreakdownSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    @State private var hovered: String?

    var body: some View {
        DashboardCard(title: "How you answer", subtitle: "Accuracy and speed by answer method and naming system") {
            if groups.isEmpty {
                NothingYetText(emptyText)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    chart
                    if groups.contains(where: { $0.rows.contains(where: \.isHollow) }) {
                        HStack(spacing: 6) {
                            UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: 3, topTrailing: 3), style: .continuous)
                                .strokeBorder(DashboardTheme.accent, lineWidth: 1)
                                .frame(width: 18, height: 10)
                            Text("Fewer than \(AccuracyScale.minimumAnswers) answers: too few to judge yet")
                                .font(.caption)
                                .foregroundStyle(DashboardTheme.textSecondary)
                        }
                    }
                }
                .hoverTip(for: hovered) { tip }
            }
        } table: {
            if groups.isEmpty {
                NothingYetText(emptyText)
            } else {
                table
            }
        }
    }

    private let emptyText = "Answer some notes and you'll see how each way of answering compares."

    // MARK: Model

    private struct Row: Identifiable {
        let id: String
        let name: String
        let source: BreakdownRow

        var isHollow: Bool { source.answers < AccuracyScale.minimumAnswers }
        var accuracy: Double { source.accuracy ?? 0 }
    }

    private struct RowGroup: Identifiable {
        let title: String
        let rows: [Row]

        var id: String { title }
    }

    /// Each group's rows, most accurate first.
    private var groups: [RowGroup] {
        let methods = report.byInput.map { Row(id: "input.\($0.key)", name: Game.AnswerInput(rawValue: $0.key)?.label ?? $0.key.capitalized, source: $0) }
        let namings = report.byNaming.map { Row(id: "naming.\($0.key)", name: NamingSystem(rawValue: $0.key)?.label ?? $0.key.capitalized, source: $0) }
        return [RowGroup(title: "Answer method", rows: ranked(methods)), RowGroup(title: "Naming system", rows: ranked(namings))]
            .filter { !$0.rows.isEmpty }
    }

    private func ranked(_ rows: [Row]) -> [Row] {
        rows.sorted { a, b in
            a.accuracy != b.accuracy ? a.accuracy > b.accuracy : a.source.answers > b.source.answers
        }
    }

    // MARK: Chart

    /// Answers and median time as numbers; accuracy as a bar on a 0–100% scale, so the rows compare.
    /// Fixed columns around the bar, which takes what's left up to `barWidth`.
    private var chart: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(name: Color.clear.frame(height: 1),
                answers: ReportTable.heading("Answers"),
                accuracy: ReportTable.heading("Accuracy"),
                time: ReportTable.heading("Median time"))
                .padding(.bottom, 2)
            ForEach(groups) { group in
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardTheme.textSecondary)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                ForEach(group.rows) { row in
                    let accuracy = ReportFormat.percent(row.source.correct, of: row.source.answers)
                    self.row(
                        name: Text(row.name)
                            .font(.callout)
                            .foregroundStyle(DashboardTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8),
                        answers: Text(ReportFormat.count(row.source.answers))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(DashboardTheme.textSecondary),
                        accuracy: HorizontalValueBar(fraction: row.accuracy, value: accuracy, isHollow: row.isHollow,
                                                     isHighlighted: hovered == row.id, valueRoom: 40)
                            .frame(height: 28)
                            .hoverTarget(row.id, hovered: $hovered)
                            .accessibilityElement()
                            .accessibilityLabel("\(row.name) accuracy")
                            .accessibilityValue(accuracy),
                        time: Text(ReportFormat.seconds(row.source.medianResponseMs))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(DashboardTheme.textSecondary))
                }
            }
        }
    }

    private let barWidth: CGFloat = 400

    private func row(name: some View, answers: some View, accuracy: some View, time: some View) -> some View {
        HStack(spacing: 16) {
            name.frame(width: 104, alignment: .leading)
            answers.frame(width: 52, alignment: .trailing)
            accuracy.frame(minWidth: 120, maxWidth: barWidth, alignment: .leading)
            time.frame(width: 76, alignment: .trailing)
        }
    }

    @ViewBuilder private var tip: some View {
        if let hovered, let row = groups.lazy.flatMap(\.rows).first(where: { $0.id == hovered }) {
            let source = row.source
            HoverTipText(
                value: "\(ReportFormat.percent(source.correct, of: source.answers)) right",
                label: row.name,
                details: [
                    "\(ReportFormat.count(source.correct)) of \(ReportFormat.count(source.answers)) answers right",
                    row.isHollow ? "Too few answers to judge yet" : nil,
                    source.medianResponseMs.map { "Median \(ReportFormat.seconds($0)) to a right answer" },
                ].compactMap { $0 })
        }
    }

    // MARK: Table

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
            GridRow {
                ReportTable.heading("")
                ReportTable.heading("Answers").gridColumnAlignment(.trailing)
                ReportTable.heading("Right").gridColumnAlignment(.trailing)
                ReportTable.heading("Accuracy").gridColumnAlignment(.trailing)
                ReportTable.heading("Median time").gridColumnAlignment(.trailing)
            }
            ForEach(groups) { group in
                ReportTable.rule()
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardTheme.textSecondary)
                ForEach(group.rows) { row in
                    GridRow {
                        ReportTable.cell(row.name)
                        ReportTable.cell(ReportFormat.count(row.source.answers))
                        ReportTable.cell(ReportFormat.count(row.source.correct))
                        ReportTable.cell(ReportFormat.percent(row.source.correct, of: row.source.answers), muted: row.isHollow)
                        ReportTable.cell(ReportFormat.seconds(row.source.medianResponseMs))
                    }
                }
            }
        }
    }
}
