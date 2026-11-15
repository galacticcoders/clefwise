import SwiftUI

/// Progress on each piece practised: accuracy and time bar by bar, and day by day how fast a new bar
/// is read (`PieceDayChart`). Once a piece's patterns are familiar its notes come fast; what still
/// takes time is reading a bar on arriving in it, so the two together show where the piece is slow
/// and whether that's coming down.
struct PieceSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    @State private var hovered: String?
    /// The strips wrap to this width, measured once it's known.
    @State private var width: CGFloat = 0

    /// From this content width a piece's day chart sits beside its bars; below it, under them.
    static let sideBySideWidth: CGFloat = 760
    /// Between the bars and the day chart beside them.
    static let columnGap: CGFloat = 32

    /// The day chart's width beside the bars: half what's left, from 340 to 460 pt.
    static func chartWidth(beside width: CGFloat) -> CGFloat {
        min(460, max(340, (width - columnGap) / 2))
    }

    var body: some View {
        DashboardCard(title: "Pieces", subtitle: "Accuracy and time bar by bar, and how fast you read a new bar day by day") {
            if report.pieces.isEmpty {
                NothingYetText(emptyText)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(report.pieces.enumerated()), id: \.element.id) { index, piece in
                        if index > 0 {
                            Rectangle()
                                .fill(DashboardTheme.gridline)
                                .frame(height: 1)
                        }
                        summary(of: piece, showsKeys: index == report.pieces.count - 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .hoverTip(for: hovered) { tip }
            }
        } table: {
            if report.pieces.isEmpty {
                NothingYetText(emptyText)
            } else {
                table
            }
        }
    }

    private let emptyText = "Open a MusicXML piece and practise it to see how each of its bars is going."

    /// A piece's title and details, its bars, and its day chart beside or under them. The last
    /// piece's bars have the keys under them, for every piece above too.
    private func summary(of piece: PieceProgressSummary, showsKeys: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(piece.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DashboardTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(details(of: piece))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(DashboardTheme.textSecondary)
            }
            if width > 0 {
                if piece.days.isEmpty {
                    bars(of: piece, width: width, showsKeys: showsKeys)
                } else if width >= Self.sideBySideWidth {
                    let chartWidth = Self.chartWidth(beside: width)
                    let barsWidth = width - Self.columnGap - chartWidth
                    HStack(alignment: .top, spacing: Self.columnGap) {
                        bars(of: piece, width: barsWidth, showsKeys: showsKeys)
                            .frame(width: barsWidth, alignment: .leading)
                        PieceDayChart(days: piece.days, width: chartWidth)
                            .frame(width: chartWidth)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        bars(of: piece, width: width, showsKeys: showsKeys)
                        PieceDayChart(days: piece.days, width: width)
                    }
                }
            }
        }
    }

    /// The bars' heading and the two strips, accuracy over time, and the keys when `showsKeys`.
    private func bars(of piece: PieceProgressSummary, width: CGFloat, showsKeys: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Bar by bar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashboardTheme.textPrimary)
                Text("How often you're right, and your median time to a right answer")
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if barNumbers(of: piece).isEmpty {
                NothingYetText("No bar has an answer yet.")
            } else {
                PieceBarStrip(piece: piece, bars: barNumbers(of: piece), width: width, hovered: $hovered)
            }
            if showsKeys {
                keys
                    .padding(.top, 6)
            }
        }
    }

    /// The accuracy key beside the time key: in rows when both fit across, else as two columns
    /// (each class over the next, the best at the top), which line up by construction.
    private var keys: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 32) {
                AccuracyLegend()
                timeLegend(.horizontal)
            }
            HStack(alignment: .top, spacing: 40) {
                AccuracyLegend(axis: .vertical)
                timeLegend(.vertical)
            }
        }
    }

    private func timeLegend(_ axis: Axis) -> some View {
        ScaleLegend(title: "Median time", classLabels: SpeedScale.classLabels(), fill: SpeedScale.fill,
                    hollowMeaning: "Fewer than \(MethodDay.minimumForTrend) right answers", axis: axis)
    }

    /// "87% right of 180 answers · 6 rounds · last practised 2 hours ago".
    private func details(of piece: PieceProgressSummary) -> String {
        let answers = piece.answers == 0 ? "No answers yet"
            : "\(ReportFormat.percent(piece.correct, of: piece.answers)) right of \(ReportFormat.count(piece.answers)) answers"
        return "\(answers) · \(rounds(piece.rounds)) · last practised \(ReportFormat.relative(piece.lastPractised, to: report.generatedAt))"
    }

    private func rounds(_ count: Int) -> String { count == 1 ? "1 round" : "\(count) rounds" }

    /// Bar 1 to the last bar of the part (or the last with an answer), plus any pickup bar before it.
    private func barNumbers(of piece: PieceProgressSummary) -> [Int] {
        let numbers = piece.bars.map(\.bar)
        let first = min(1, numbers.min() ?? 1)
        let last = max(piece.measureCount ?? 0, numbers.max() ?? 0)
        return last >= first ? Array(first...last) : []
    }

    @ViewBuilder private var tip: some View {
        if let hovered, let piece = report.pieces.first(where: { hovered.hasPrefix($0.id + "#") }),
           let number = Int(hovered.dropFirst(piece.id.count + 1)) {
            PieceBarTip(number: number, title: piece.title, bar: piece.bars.first { $0.bar == number })
        }
    }

    // MARK: Model

    /// A bar's class on the speed map's scale, or nil (hollow) with too few right answers to single
    /// notes to judge (`MethodDay.minimumForTrend`).
    static func timeLevel(of bar: BarProgress?) -> Int? {
        guard let bar, bar.rightSingleNotes >= MethodDay.minimumForTrend else { return nil }
        return SpeedScale.level(medianMs: bar.medianResponseMs, rightAnswers: bar.rightSingleNotes)
    }

    /// A bar's median time as its cell, tip and table say it ("2.8 s"); nil when it has none or
    /// too few right answers to judge.
    static func judgedTime(of bar: BarProgress?) -> String? {
        timeLevel(of: bar) == nil ? nil : SpeedScale.seconds(bar?.medianResponseMs)
    }

    /// "1 right answer", "13 right answers", "No right answers".
    static func rightAnswers(_ count: Int) -> String {
        count == 0 ? "No right answers" : count == 1 ? "1 right answer" : "\(ReportFormat.count(count)) right answers"
    }

    /// What a bar's tip says, row by row: its accuracy and its median time, each with what it comes
    /// from; a nil value is too few to judge. No rows for a bar without answers.
    static func tipRows(of bar: BarProgress?) -> [PieceBarTip.Row] {
        guard let bar, bar.attempts > 0 else { return [] }
        let accuracy = AccuracyScale.level(correct: bar.correct, of: bar.attempts) == nil
            ? nil : ReportFormat.percent(bar.correct, of: bar.attempts)
        let time = judgedTime(of: bar)
        return [PieceBarTip.Row(label: "Accuracy", value: accuracy, detail: "\(bar.correct) of \(bar.attempts) answers right"),
                // A judged time has at least `MethodDay.minimumForTrend` right answers, so never "No".
                PieceBarTip.Row(label: "Median time", value: time,
                                detail: time == nil ? rightAnswers(bar.rightSingleNotes) : "from \(rightAnswers(bar.rightSingleNotes))")]
    }

    /// What VoiceOver says of a bar: "87% of 15 answers right; median time 2.8 s".
    static func accessibilityValue(of bar: BarProgress?) -> String {
        guard let bar, bar.attempts > 0 else { return "No answers yet" }
        let accuracy = "\(ReportFormat.percent(bar.correct, of: bar.attempts)) of \(bar.attempts) answers right"
        let time = judgedTime(of: bar).map { "median time \($0)" } ?? "too few right answers to judge its time"
        return "\(accuracy); \(time)"
    }

    // MARK: Table

    /// For each piece: its days, newest first, then its bars.
    private var table: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(report.pieces) { piece in
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(piece.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(DashboardTheme.textPrimary)
                        Text(details(of: piece))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(DashboardTheme.textMuted)
                    }
                    if !piece.days.isEmpty {
                        daysTable(piece)
                    }
                    barsTable(piece)
                }
            }
            Text("In brackets: how many right answers a time is the median of. Grey numbers come from too few to judge: fewer than \(AccuracyScale.minimumAnswers) answers for an accuracy, or \(MethodDay.minimumForTrend) right answers for a time.")
                .font(.caption)
                .foregroundStyle(DashboardTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func subheading(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DashboardTheme.textSecondary)
    }

    /// Day, how it was answered, notes, accuracy and the two times, newest first.
    private func daysTable(_ piece: PieceProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            subheading("Reading a new bar, by day")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                GridRow {
                    ReportTable.heading("Day")
                    ReportTable.heading("How")
                    ReportTable.heading("Notes").gridColumnAlignment(.trailing)
                    ReportTable.heading("Accuracy").gridColumnAlignment(.trailing)
                    ReportTable.heading(PieceDayLine.barStart.label).gridColumnAlignment(.trailing)
                    ReportTable.heading(PieceDayLine.restOfBar.label).gridColumnAlignment(.trailing)
                }
                ReportTable.rule()
                ForEach(piece.days.reversed()) { day in
                    GridRow {
                        ReportTable.cell(DashboardFormat.day(day.day))
                        ReportTable.cell(PieceDayLine.methods(of: day) ?? "–")
                        ReportTable.cell(ReportFormat.count(day.answers))
                        ReportTable.cell(ReportFormat.percent(day.correct, of: day.answers),
                                         muted: AccuracyScale.level(correct: day.correct, of: day.answers) == nil)
                        timeCell(PieceDayLine.barStart, day)
                        timeCell(PieceDayLine.restOfBar, day)
                    }
                }
            }
        }
    }

    /// A day's time with how many right answers it's the median of: "1.9 s (12)"; grey when too
    /// few to judge, "–" without any.
    private func timeCell(_ line: PieceDayLine, _ day: PieceDay) -> some View {
        let ms = line.medianMs(of: day)
        let text = ms.map { "\(ReportFormat.seconds($0)) (\(ReportFormat.count(line.count(of: day))))" } ?? "–"
        return ReportTable.cell(text, muted: line.seconds(of: day) == nil)
    }

    /// Bar, answers, right, accuracy and median time, for the bars with answers; then those without.
    private func barsTable(_ piece: PieceProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            subheading("Bar by bar")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                GridRow {
                    ReportTable.heading("Bar")
                    ReportTable.heading("Answers").gridColumnAlignment(.trailing)
                    ReportTable.heading("Right").gridColumnAlignment(.trailing)
                    ReportTable.heading("Accuracy").gridColumnAlignment(.trailing)
                    ReportTable.heading("Median time").gridColumnAlignment(.trailing)
                }
                ReportTable.rule()
                ForEach(piece.bars.filter { $0.attempts > 0 }) { bar in
                    GridRow {
                        ReportTable.cell("Bar \(bar.bar)")
                        ReportTable.cell(ReportFormat.count(bar.attempts))
                        ReportTable.cell(ReportFormat.count(bar.correct))
                        ReportTable.cell(ReportFormat.percent(bar.correct, of: bar.attempts),
                                         muted: AccuracyScale.level(correct: bar.correct, of: bar.attempts) == nil)
                        ReportTable.cell(bar.medianResponseMs.map { "\(SpeedScale.seconds($0)) (\(ReportFormat.count(bar.rightSingleNotes)))" } ?? "–",
                                         muted: Self.timeLevel(of: bar) == nil)
                    }
                }
                let unanswered = unansweredBars(of: piece)
                if !unanswered.isEmpty {
                    Text("No answers yet in \(unanswered)")
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.textMuted)
                        .gridCellColumns(5)
                }
            }
        }
    }

    /// "bar 3" or "bars 3, 7–9 and 12".
    private func unansweredBars(of piece: PieceProgressSummary) -> String {
        let answered = Set(piece.bars.filter { $0.attempts > 0 }.map(\.bar))
        let missing = barNumbers(of: piece).filter { !answered.contains($0) }
        var runs: [ClosedRange<Int>] = []
        for bar in missing {
            if let last = runs.last, last.upperBound == bar - 1 {
                runs[runs.count - 1] = last.lowerBound...bar
            } else {
                runs.append(bar...bar)
            }
        }
        let parts = runs.map { $0.count == 1 ? "\($0.lowerBound)" : "\($0.lowerBound)–\($0.upperBound)" }
        guard let lastPart = parts.last else { return "" }
        if missing.count == 1 { return "bar \(lastPart)" }
        return parts.count == 1 ? "bars \(lastPart)" : "bars \(parts.dropLast().joined(separator: ", ")) and \(lastPart)"
    }
}

/// A piece's bars in order, one column each with two cells, accuracy over median time, under row
/// labels that name them; wrapping in whole four-bar phrases when they don't fit on one line, with
/// the bar number under the first bar of each phrase as in a score.
private struct PieceBarStrip: View {
    let piece: PieceProgressSummary
    let bars: [Int]
    /// The whole strip's, row labels included.
    let width: CGFloat
    @Binding var hovered: String?

    private let gap: CGFloat = 2
    private let cellHeight: CGFloat = 20
    /// Room for the row labels.
    private static let labelWidth: CGFloat = 58
    private static let rowLabels = ["Accuracy", "Time"]

    var body: some View {
        let (columns, cellWidth) = layout
        let byBar = Dictionary(piece.bars.map { ($0.bar, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = stride(from: 0, to: bars.count, by: columns).map { Array(bars[$0..<min($0 + columns, bars.count)]) }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.first) { row in
                HStack(alignment: .top, spacing: 0) {
                    labels
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 0) {
                            ForEach(row, id: \.self) { number in
                                column(number, progress: byBar[number], width: cellWidth)
                            }
                        }
                        HStack(spacing: 0) {
                            ForEach(row, id: \.self) { number in
                                Text(number >= 1 && (number - 1).isMultiple(of: 4) ? "\(number)" : "")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(DashboardTheme.textMuted)
                                    .fixedSize()
                                    .frame(width: cellWidth, alignment: .leading)
                                    .padding(.horizontal, gap / 2)
                            }
                        }
                    }
                }
            }
        }
    }

    /// "Accuracy" and "Time" level with their cells, on every line, so the strips read without the key.
    private var labels: some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(Self.rowLabels, id: \.self) { label in
                Text(label)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: cellHeight)
            }
        }
        .padding(.vertical, 3)
        .frame(width: Self.labelWidth, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// Bars per line and each cell's width: as wide as fits up to 30 pt, and when even 12 pt cells
    /// won't fit on one line, lines of whole phrases (a multiple of eight bars where possible).
    private var layout: (columns: Int, cellWidth: CGFloat) {
        let width = max(0, self.width - Self.labelWidth)
        // Each cell takes its width plus the gap (half on either side, inside its hit target).
        let fit = max(1, Int(width / (12 + gap)))
        let columns = bars.count <= fit ? bars.count : fit >= 8 ? fit / 8 * 8 : max(1, fit / 4 * 4)
        return (columns, max(4, min(30, width / CGFloat(columns) - gap)))
    }

    /// One bar: its accuracy cell over its time cell, one hover target, so the tip says both.
    private func column(_ number: Int, progress: BarProgress?, width: CGFloat) -> some View {
        let id = "\(piece.id)#\(number)"
        let attempts = progress?.attempts ?? 0
        let correct = progress?.correct ?? 0
        let isHovered = hovered == id
        let time = PieceSection.timeLevel(of: progress)
        return VStack(spacing: gap) {
            AccuracyCell(level: AccuracyScale.level(correct: correct, of: attempts), cornerRadius: 3, isHighlighted: isHovered)
                .frame(width: width, height: cellHeight)
            ScaleCell(fill: time.map(SpeedScale.fill), cornerRadius: 3, isHighlighted: isHovered)
                .frame(width: width, height: cellHeight)
        }
        // The hit target takes in the gaps and a little above and below.
        .padding(.horizontal, gap / 2)
        .padding(.vertical, 3)
        .hoverTarget(id, hovered: $hovered)
        .accessibilityElement()
        .accessibilityLabel("Bar \(number)")
        .accessibilityValue(PieceSection.accessibilityValue(of: progress))
    }
}

/// A bar's hover tip: the bar and piece, then its accuracy and median time, each with what it comes
/// from, or "too few to judge".
struct PieceBarTip: View {
    struct Row: Equatable, Identifiable {
        let label: String
        /// Nil: too few to judge.
        let value: String?
        let detail: String

        var id: String { label }
    }

    let number: Int
    let title: String
    let bar: BarProgress?

    var body: some View {
        let rows = PieceSection.tipRows(of: bar)
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bar \(number)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DashboardTheme.textPrimary)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(DashboardTheme.textSecondary)
            }
            if rows.isEmpty {
                Text("No answers yet")
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textMuted)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                    ForEach(rows) { row in
                        GridRow(alignment: .firstTextBaseline) {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(DashboardTheme.textSecondary)
                            if let value = row.value {
                                Text(value)
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(DashboardTheme.textPrimary)
                            } else {
                                Text("too few to judge")
                                    .font(.caption)
                                    .foregroundStyle(DashboardTheme.textMuted)
                            }
                            Text(row.detail)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(DashboardTheme.textMuted)
                        }
                    }
                }
            }
        }
    }
}
