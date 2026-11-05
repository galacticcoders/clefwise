import SwiftUI

/// The latest rounds, newest first.
struct RecentRoundsSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    @State private var showsAll = false
    /// Rounds shown before "Show all", so the table doesn't run the dashboard's length.
    private let shortListLength = 10

    var body: some View {
        DashboardCard(title: "Recent rounds", subtitle: "Newest first") {
            if report.recentRounds.isEmpty {
                NothingYetText("No rounds in this period yet.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    // Every detail in its own column when there's room; folded into two-line cells otherwise.
                    ViewThatFits(in: .horizontal) {
                        wide
                        compact
                    }
                    if report.recentRounds.count > shortListLength {
                        Button(showsAll ? "Show fewer" : "Show all \(report.recentRounds.count) rounds") {
                            showsAll.toggle()
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                }
            }
        }
    }

    private var rounds: [RecentRound] {
        let newestFirst = report.recentRounds.sorted { $0.started > $1.started }
        return showsAll ? newestFirst : Array(newestFirst.prefix(shortListLength))
    }

    // MARK: Layouts

    private var wide: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                ReportTable.heading("When")
                ReportTable.heading("What")
                ReportTable.heading("Mode")
                ReportTable.heading("Answered with")
                ReportTable.heading("Names")
                ReportTable.heading("Score").gridColumnAlignment(.trailing)
                ReportTable.heading("Accuracy").gridColumnAlignment(.trailing)
                ReportTable.heading("Length").gridColumnAlignment(.trailing)
                ReportTable.heading("Ended")
            }
            ForEach(rounds) { round in
                ReportTable.rule()
                GridRow {
                    Text("\(Text(ReportFormat.relative(round.started, to: report.generatedAt)).foregroundStyle(DashboardTheme.textPrimary)) \(Text(clock(round.started)).foregroundStyle(DashboardTheme.textMuted))")
                        .font(.callout)
                        .monospacedDigit()
                    ReportTable.cell(round.description)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ReportTable.cell(mode(round))
                    ReportTable.cell(input(round))
                    ReportTable.cell(namingLabel(round))
                    ReportTable.cell("\(round.score)/\(round.attempts)")
                    ReportTable.cell(ReportFormat.percent(round.score, of: round.attempts))
                    ReportTable.cell(ReportFormat.duration(round.durationMs))
                    ending(round)
                        .font(.callout)
                }
            }
        }
    }

    private var compact: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                ReportTable.heading("When")
                ReportTable.heading("What")
                ReportTable.heading("Score").gridColumnAlignment(.trailing)
                ReportTable.heading("Length").gridColumnAlignment(.trailing)
            }
            ForEach(rounds) { round in
                ReportTable.rule()
                GridRow {
                    twoLines(ReportFormat.relative(round.started, to: report.generatedAt), clock(round.started))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(round.description)
                            .font(.callout)
                            .foregroundStyle(DashboardTheme.textPrimary)
                            .lineLimit(2)
                        Text("\(mode(round)) · \(input(round)) · \(namingLabel(round))")
                            .font(.caption)
                            .foregroundStyle(DashboardTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    twoLines(ReportFormat.percent(round.score, of: round.attempts), "\(round.score) of \(round.attempts)", alignment: .trailing)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(ReportFormat.duration(round.durationMs))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(DashboardTheme.textPrimary)
                        ending(round)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func twoLines(_ first: String, _ second: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(first)
                .font(.callout)
                .foregroundStyle(DashboardTheme.textPrimary)
            Text(second)
                .font(.caption)
                .foregroundStyle(DashboardTheme.textMuted)
        }
        .monospacedDigit()
        .fixedSize()
    }

    // MARK: Words

    /// The time of day, with the weekday when it wasn't today and the date when it's a week or more back.
    private func clock(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = report.generatedAt
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        return days < 7 ? date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            : date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    /// "60s Sprint", "Practice", "Practice · 5 min"
    private func mode(_ round: RecentRound) -> String {
        let label = Game.Mode(rawValue: round.mode)?.label ?? round.mode.capitalized
        return round.practiceLength.map { "\(label) · \($0)" } ?? label
    }
    private func input(_ round: RecentRound) -> String { Game.AnswerInput(rawValue: round.input)?.label ?? round.input.capitalized }
    private func namingLabel(_ round: RecentRound) -> String { NamingSystem(rawValue: round.naming)?.label ?? round.naming.capitalized }

    @ViewBuilder private func ending(_ round: RecentRound) -> some View {
        if let reason = round.endReason {
            Text(endingWords(reason))
                .foregroundStyle(DashboardTheme.textSecondary)
        } else {
            Text("—")
                .foregroundStyle(DashboardTheme.textMuted)
                .help("The round never ended in the log, so the app probably closed unexpectedly")
        }
    }

    private func endingWords(_ reason: RoundEndReason) -> String {
        switch reason {
        case .timeUp: "Time up"
        case .stopped: "Stopped"
        case .pieceComplete: "Piece finished"
        case .notesDone: "All notes done"
        case .abandoned: "Interrupted"
        case .appQuit: "App quit"
        }
    }
}
