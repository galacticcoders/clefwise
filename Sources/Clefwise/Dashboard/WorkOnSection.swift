import SwiftUI

/// Notes to work on: the most-missed and the slowest notes (spelled, so F♯5 apart from F5) as ranked bars.
struct WorkOnSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    @State private var hovered: String?

    /// How many notes each list ranks.
    private let listLength = 8

    var body: some View {
        DashboardCard(title: "Notes to work on", subtitle: "The notes you miss most and name slowest") {
            HStack(alignment: .top, spacing: 28) {
                WorkOnBarList(title: "Most missed", measure: "Share of answers wrong", bars: missedBars,
                              emptyText: missedEmptyText, hovered: $hovered)
                WorkOnBarList(title: "Slowest", measure: "Median time to a right answer", bars: slowBars,
                              emptyText: slowEmptyText, hovered: $hovered)
            }
            .hoverTip(for: hovered) { tip }
        } table: {
            table
        }
    }

    // MARK: Model

    /// Notes answered at least 5 times and missed at least once, most often wrong first.
    private var mostMissed: [PitchProgress] {
        let ranked = report.pitches
            .filter { $0.attempts >= AccuracyScale.minimumAnswers && $0.correct < $0.attempts }
            .sorted { a, b in
                let (aWrong, bWrong) = (missRate(a), missRate(b))
                if aWrong != bWrong { return aWrong > bWrong }
                return a.attempts != b.attempts ? a.attempts > b.attempts : a.id < b.id
            }
        return Array(ranked.prefix(listLength))
    }

    /// Notes named right at least 5 times, slowest median first.
    private var slowest: [PitchProgress] {
        let ranked = report.pitches
            .filter { $0.correct >= AccuracyScale.minimumAnswers && $0.medianResponseMs != nil }
            .sorted { a, b in
                let (aTime, bTime) = (a.medianResponseMs ?? 0, b.medianResponseMs ?? 0)
                return aTime != bTime ? aTime > bTime : a.id < b.id
            }
        return Array(ranked.prefix(listLength))
    }

    private func missRate(_ pitch: PitchProgress) -> Double {
        Double(pitch.attempts - pitch.correct) / Double(pitch.attempts)
    }

    private var missedEmptyText: String {
        report.pitches.contains { $0.attempts >= AccuracyScale.minimumAnswers }
            ? "No misses on any note you've answered \(AccuracyScale.minimumAnswers) times or more. Well done!"
            : "Notes show up here once you've answered them \(AccuracyScale.minimumAnswers) times."
    }

    private var slowEmptyText: String {
        "Notes show up here once you've named them right \(AccuracyScale.minimumAnswers) times."
    }

    private var missedBars: [WorkOnBar] {
        let top = mostMissed.first.map(missRate) ?? 1
        return mostMissed.map { pitch in
            WorkOnBar(id: "missed.\(pitch.id)", pitch: pitch, naming: naming, fraction: missRate(pitch) / top,
                      value: ReportFormat.percent(pitch.attempts - pitch.correct, of: pitch.attempts))
        }
    }

    private var slowBars: [WorkOnBar] {
        let top = Double(slowest.first?.medianResponseMs ?? 1)
        return slowest.map { pitch in
            WorkOnBar(id: "slow.\(pitch.id)", pitch: pitch, naming: naming,
                      fraction: Double(pitch.medianResponseMs ?? 0) / top, value: ReportFormat.seconds(pitch.medianResponseMs))
        }
    }

    @ViewBuilder private var tip: some View {
        if let hovered, let bar = (missedBars + slowBars).first(where: { $0.id == hovered }) {
            let pitch = bar.pitch
            let right = "\(ReportFormat.count(pitch.correct)) of \(ReportFormat.count(pitch.attempts)) answers right"
            if hovered.hasPrefix("missed.") {
                HoverTipText(value: "\(bar.value) missed", label: "\(bar.name) · \(bar.context)",
                             details: [right, pitch.medianResponseMs.map { "Median \(ReportFormat.seconds($0)) to a right answer" }]
                                .compactMap { $0 })
            } else {
                HoverTipText(value: "\(bar.value) median", label: "\(bar.name) · \(bar.context)", details: [right])
            }
        }
    }

    // MARK: Table

    private var table: some View {
        VStack(alignment: .leading, spacing: 18) {
            tableBlock("Most missed", empty: missedEmptyText, rows: mostMissed)
            tableBlock("Slowest", empty: slowEmptyText, rows: slowest)
        }
    }

    private func tableBlock(_ title: String, empty: String, rows: [PitchProgress]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DashboardTheme.textSecondary)
            if rows.isEmpty {
                NothingYetText(empty)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                    GridRow {
                        ReportTable.heading("Note")
                        ReportTable.heading(naming == .letters ? "Clef" : "Clef · place")
                        ReportTable.heading("Answers").gridColumnAlignment(.trailing)
                        ReportTable.heading("Right").gridColumnAlignment(.trailing)
                        ReportTable.heading("Missed").gridColumnAlignment(.trailing)
                        ReportTable.heading("Median time").gridColumnAlignment(.trailing)
                    }
                    ReportTable.rule()
                    ForEach(rows) { pitch in
                        GridRow {
                            ReportTable.cell(ReportFormat.noteName(pitch.pitch, naming))
                            ReportTable.cell(ReportFormat.noteContext(pitch.pitch, clef: pitch.clef, naming))
                            ReportTable.cell(ReportFormat.count(pitch.attempts))
                            ReportTable.cell(ReportFormat.count(pitch.correct))
                            ReportTable.cell(ReportFormat.percent(pitch.attempts - pitch.correct, of: pitch.attempts))
                            ReportTable.cell(ReportFormat.seconds(pitch.medianResponseMs))
                        }
                    }
                }
            }
        }
    }
}

/// A note in one of the ranked lists.
private struct WorkOnBar: Identifiable {
    let id: String
    let pitch: PitchProgress
    let name: String
    let context: String
    /// Of the longest bar in its list.
    let fraction: Double
    let value: String

    init(id: String, pitch: PitchProgress, naming: NamingSystem, fraction: Double, value: String) {
        self.id = id
        self.pitch = pitch
        name = ReportFormat.noteName(pitch.pitch, naming)
        context = ReportFormat.noteContext(pitch.pitch, clef: pitch.clef, naming)
        self.fraction = fraction
        self.value = value
    }
}

/// One ranked bar chart: the note's name and clef on the left, its bar from a shared baseline.
private struct WorkOnBarList: View {
    let title: String
    /// What the bars measure, under the title.
    let measure: String
    let bars: [WorkOnBar]
    let emptyText: String
    @Binding var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashboardTheme.textPrimary)
                Text(measure)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textMuted)
            }
            if bars.isEmpty {
                NothingYetText(emptyText)
            } else {
                // Labels above the bars, so a long one ("komal Dha · Bass · below ledger line 2")
                // never squeezes them.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(bars) { bar in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(Text(bar.name).font(.callout.weight(.medium)).foregroundStyle(DashboardTheme.textPrimary))  \(Text(bar.context).font(.caption).foregroundStyle(DashboardTheme.textMuted))")
                                .fixedSize(horizontal: false, vertical: true)
                            HorizontalValueBar(fraction: bar.fraction, value: bar.value, isHighlighted: hovered == bar.id,
                                               showsBaseline: false)
                                .frame(height: 14)
                        }
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // The whole row is the hover target, not just the bar.
                        .hoverTarget(bar.id, hovered: $hovered)
                        .accessibilityElement()
                        .accessibilityLabel("\(bar.name), \(bar.context)")
                        .accessibilityValue(bar.value)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
