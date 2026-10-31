import SwiftUI

/// Progress on each piece practised: accuracy bar by bar.
struct PieceSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    @State private var hovered: String?
    /// The strips wrap to this width, measured once it's known.
    @State private var width: CGFloat = 0

    var body: some View {
        DashboardCard(title: "Pieces", subtitle: "Accuracy bar by bar") {
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
                        summary(of: piece)
                    }
                    AccuracyLegend()
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

    private func summary(of piece: PieceProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
            if barNumbers(of: piece).isEmpty {
                NothingYetText("No bar has an answer yet.")
            } else if width > 0 {
                PieceBarStrip(piece: piece, bars: barNumbers(of: piece), width: width, hovered: $hovered)
            }
        }
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
            let bar = piece.bars.first { $0.bar == number }
            let label = "Bar \(number) · \(piece.title)"
            if let bar, bar.attempts > 0 {
                let right = "\(bar.correct) of \(bar.attempts) answers right"
                if AccuracyScale.level(correct: bar.correct, of: bar.attempts) == nil {
                    HoverTipText(value: right, label: label, details: ["Too few answers to judge yet"])
                } else {
                    HoverTipText(value: "\(ReportFormat.percent(bar.correct, of: bar.attempts)) right", label: label, details: [right])
                }
            } else {
                HoverTipText(value: "No answers yet", label: label)
            }
        }
    }

    // MARK: Table

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
            GridRow {
                ReportTable.heading("Piece and bar")
                ReportTable.heading("Answers").gridColumnAlignment(.trailing)
                ReportTable.heading("Right").gridColumnAlignment(.trailing)
                ReportTable.heading("Accuracy").gridColumnAlignment(.trailing)
            }
            ForEach(report.pieces) { piece in
                ReportTable.rule()
                GridRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(piece.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(DashboardTheme.textPrimary)
                        Text("Last practised \(ReportFormat.relative(piece.lastPractised, to: report.generatedAt)) · \(rounds(piece.rounds))")
                            .font(.caption)
                            .foregroundStyle(DashboardTheme.textMuted)
                    }
                    ReportTable.cell(ReportFormat.count(piece.answers))
                    ReportTable.cell(ReportFormat.count(piece.correct))
                    ReportTable.cell(ReportFormat.percent(piece.correct, of: piece.answers))
                }
                ForEach(piece.bars.filter { $0.attempts > 0 }) { bar in
                    GridRow {
                        ReportTable.cell("Bar \(bar.bar)")
                            .padding(.leading, 12)
                        ReportTable.cell(ReportFormat.count(bar.attempts))
                        ReportTable.cell(ReportFormat.count(bar.correct))
                        ReportTable.cell(ReportFormat.percent(bar.correct, of: bar.attempts),
                                         muted: AccuracyScale.level(correct: bar.correct, of: bar.attempts) == nil)
                    }
                }
                let unanswered = unansweredBars(of: piece)
                if !unanswered.isEmpty {
                    Text("No answers yet in \(unanswered)")
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.textMuted)
                        .padding(.leading, 12)
                        .gridCellColumns(4)
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

/// A piece's bars in order, one cell each, wrapping in whole four-bar phrases when they don't fit
/// on one line, with the bar number under the first bar of each phrase as in a score.
private struct PieceBarStrip: View {
    let piece: PieceProgressSummary
    let bars: [Int]
    let width: CGFloat
    @Binding var hovered: String?

    private let gap: CGFloat = 2
    private let cellHeight: CGFloat = 20

    var body: some View {
        let (columns, cellWidth) = layout
        let byBar = Dictionary(piece.bars.map { ($0.bar, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = stride(from: 0, to: bars.count, by: columns).map { Array(bars[$0..<min($0 + columns, bars.count)]) }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.first) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { number in
                            cell(number, progress: byBar[number], width: cellWidth)
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

    /// Bars per line and each cell's width: as wide as fits up to 30 pt, and when even 12 pt cells
    /// won't fit on one line, lines of whole phrases (a multiple of eight bars where possible).
    private var layout: (columns: Int, cellWidth: CGFloat) {
        // Each cell takes its width plus the gap (half on either side, inside its hit target).
        let fit = max(1, Int(width / (12 + gap)))
        let columns = bars.count <= fit ? bars.count : fit >= 8 ? fit / 8 * 8 : max(1, fit / 4 * 4)
        return (columns, max(4, min(30, width / CGFloat(columns) - gap)))
    }

    private func cell(_ number: Int, progress: BarProgress?, width: CGFloat) -> some View {
        let id = "\(piece.id)#\(number)"
        let attempts = progress?.attempts ?? 0
        let correct = progress?.correct ?? 0
        return AccuracyCell(level: AccuracyScale.level(correct: correct, of: attempts), cornerRadius: 3,
                            isHighlighted: hovered == id)
            .frame(width: width, height: cellHeight)
            // The hit target takes in the gaps and a little above and below.
            .padding(.horizontal, gap / 2)
            .padding(.vertical, 3)
            .hoverTarget(id, hovered: $hovered)
            .accessibilityElement()
            .accessibilityLabel("Bar \(number)")
            .accessibilityValue(attempts == 0 ? "No answers yet" : "\(ReportFormat.percent(correct, of: attempts)) of \(attempts) answers right")
    }
}
