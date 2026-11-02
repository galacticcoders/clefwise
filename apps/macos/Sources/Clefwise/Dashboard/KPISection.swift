import SwiftUI

/// The headline tiles: practice time, notes answered, accuracy and typical response time against the previous period, and the daily streak.
struct KPISection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    var body: some View {
        DashboardCard(title: "Overview", subtitle: subtitle) {
            // As many tiles to a row as fit: all five on a wide window, then three, then two.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                        if index > 0 {
                            Rectangle().fill(DashboardTheme.gridline).frame(width: 1)
                                .padding(.horizontal, 16)
                        }
                        tile.frame(minWidth: 150, maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                grid(columns: 3)
                grid(columns: 2)
            }
        }
    }

    private func grid(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .topLeading), count: columns),
                  alignment: .leading, spacing: 20) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { $0.element }
        }
    }

    private var subtitle: String {
        let clef = report.filter.clef == .all ? "" : " · \(report.filter.clef.label) clef"
        guard let days = report.filter.range.days else { return "All time\(clef)" }
        return "\(report.filter.range.label)\(clef), against the \(days) days before"
    }

    /// "previous 30 days"; nil for all time, which has nothing before it.
    private var previousName: String? {
        report.filter.range.days.map { "previous \($0) days" }
    }

    private var totals: ProgressTotals { report.totals }

    private var tiles: [StatTile] {
        let previous = report.previousTotals
        return [
            StatTile(label: "Practice time", value: DashboardFormat.duration(totals.practiceSeconds),
                     delta: previous.flatMap { previous in
                         delta(Double(totals.practiceSeconds), Double(previous.practiceSeconds), previous: previous, upIsGood: true,
                               format: { DashboardFormat.duration($0) }, threshold: 30)
                     },
                     trend: trend(sum: { $0.practiceSeconds }),
                     trendHelp: "Practice time per day"),
            StatTile(label: "Notes answered", value: DashboardFormat.count(totals.answers),
                     delta: previous.flatMap { previous in
                         delta(Double(totals.answers), Double(previous.answers), previous: previous, upIsGood: true,
                               format: { DashboardFormat.count(Int($0.rounded())) }, threshold: 0.5)
                     },
                     trend: trend(sum: { Double($0.answers) }),
                     trendHelp: "Notes answered per day"),
            StatTile(label: "Accuracy", value: totals.accuracy.map(DashboardFormat.percent) ?? "–",
                     delta: accuracyDelta(previous),
                     trend: trendOfAccuracy,
                     trendHelp: "Accuracy per day; gaps are days without practice"),
            StatTile(label: "Typical response time",
                     value: totals.medianResponseMs.map { DashboardFormat.seconds(milliseconds: $0) } ?? "–",
                     delta: responseDelta(previous),
                     trend: trendOfResponse,
                     trendHelp: "Median time to a right answer per day; gaps are days without practice"),
            StatTile(label: "Day streak", value: report.currentStreakDays == 1 ? "1 day" : "\(report.currentStreakDays) days",
                     secondary: "Longest \(report.longestStreakDays == 1 ? "1 day" : "\(report.longestStreakDays) days")"),
        ]
    }

    // MARK: - Deltas

    /// `threshold` is the smallest difference worth calling a change, in the value's own unit.
    private func delta(_ current: Double, _ before: Double, previous: ProgressTotals, upIsGood: Bool,
                       format: (Double) -> String, threshold: Double) -> StatTile.Delta? {
        guard let previousName else { return nil }
        guard previous.answers > 0 else { return .note("None in the \(previousName)") }
        let difference = current - before
        guard abs(difference) >= threshold else { return .note("Same as the \(previousName)") }
        return .change(isUp: difference > 0, isBetter: (difference > 0) == upIsGood,
                       amount: format(abs(difference)), comparison: "vs \(previousName)")
    }

    /// In whole percentage points, from the rounded percentages shown, so the numbers agree.
    private func accuracyDelta(_ previous: ProgressTotals?) -> StatTile.Delta? {
        guard let previous, let previousName else { return nil }
        guard let now = totals.accuracy else { return nil }
        guard let before = previous.accuracy else { return .note("None in the \(previousName)") }
        let points = Int((now * 100).rounded()) - Int((before * 100).rounded())
        guard points != 0 else { return .note("Same as the \(previousName)") }
        return .change(isUp: points > 0, isBetter: points > 0,
                       amount: abs(points) == 1 ? "1 pt" : "\(abs(points)) pts", comparison: "vs \(previousName)")
    }

    /// Faster is better, so a drop is good news.
    private func responseDelta(_ previous: ProgressTotals?) -> StatTile.Delta? {
        guard let previous, let previousName else { return nil }
        guard let now = totals.medianResponseMs else { return nil }
        guard let before = previous.medianResponseMs else { return .note("None in the \(previousName)") }
        let tenths = Int((Double(now) / 100).rounded()) - Int((Double(before) / 100).rounded())
        guard tenths != 0 else { return .note("Same as the \(previousName)") }
        return .change(isUp: tenths > 0, isBetter: tenths < 0,
                       amount: DashboardFormat.seconds(Double(abs(tenths)) / 10), comparison: "vs \(previousName)")
    }

    // MARK: - Sparklines

    /// About a month of points at most: longer windows are summed by week or more.
    private var buckets: [ArraySlice<DayProgress>] {
        let days = report.days
        guard days.count > 1 else { return [] }
        let size = max(1, Int((Double(days.count) / 31).rounded(.up)))
        // Counted from today back, so the latest point is a whole bucket ending today.
        return stride(from: days.count, to: 0, by: -size).reversed().map { end in days[max(0, end - size)..<end] }
    }

    private func trend(sum value: (DayProgress) -> Double) -> [Double?]? {
        let buckets = buckets
        guard !buckets.isEmpty else { return nil }
        return buckets.map { $0.map(value).reduce(0, +) }
    }

    private var trendOfAccuracy: [Double?]? {
        let buckets = buckets
        guard !buckets.isEmpty else { return nil }
        return buckets.map { bucket in
            let answers = bucket.map(\.answers).reduce(0, +)
            return answers > 0 ? Double(bucket.map(\.correct).reduce(0, +)) / Double(answers) : nil
        }
    }

    /// A week's typical time is the middle of its days' (good enough for a trend line).
    private var trendOfResponse: [Double?]? {
        let buckets = buckets
        guard !buckets.isEmpty else { return nil }
        return buckets.map { bucket in
            let medians = bucket.compactMap(\.medianResponseMs).sorted()
            return medians.isEmpty ? nil : Double(medians[medians.count / 2])
        }
    }
}

/// One headline number: what it is, the number, how it compares, and its trend.
private struct StatTile: View {
    enum Delta {
        /// Arrow for the direction; status colour for whether that's better.
        case change(isUp: Bool, isBetter: Bool, amount: String, comparison: String)
        /// No comparison to make, said in words.
        case note(String)
    }

    let label: String
    let value: String
    var secondary: String?
    var delta: Delta?
    var trend: [Double?]?
    var trendHelp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.callout)
                .foregroundStyle(DashboardTheme.textSecondary)
                .lineLimit(1)
            // Proportional figures: tabular ones look loose at this size.
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(DashboardTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            deltaText
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if let trend {
                Sparkline(values: trend)
                    .frame(height: 26)
                    .padding(.top, 6)
                    .help(trendHelp ?? "")
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var deltaText: some View {
        switch delta {
        case .change(let isUp, let isBetter, let amount, let comparison):
            let status = isBetter ? DashboardTheme.goodText : DashboardTheme.critical
            Text("\(Text("\(isUp ? "▲" : "▼") \(amount)").foregroundStyle(status).fontWeight(.medium)) \(comparison)")
                .foregroundStyle(DashboardTheme.textSecondary)
                .accessibilityLabel("\(isUp ? "Up" : "Down") \(amount) \(comparison), \(isBetter ? "better" : "worse")")
        case .note(let text):
            Text(text).foregroundStyle(DashboardTheme.textSecondary)
        case nil:
            if let secondary {
                Text(secondary).foregroundStyle(DashboardTheme.textSecondary)
            }
        }
    }
}

/// A small trend line with no axes: the line in the de-emphasis grey, the latest point in the
/// accent. Missing values (days without practice) are gaps.
private struct Sparkline: View {
    let values: [Double?]

    var body: some View {
        Canvas { context, size in
            let present = values.compactMap { $0 }
            guard let low = present.min(), let high = present.max(), values.count > 1 else { return }
            let inset: CGFloat = 6
            let span = high - low
            func point(_ index: Int, _ value: Double) -> CGPoint {
                let x = inset + (size.width - 2 * inset) * CGFloat(index) / CGFloat(values.count - 1)
                let fraction = span > 0 ? (value - low) / span : 0.5
                return CGPoint(x: x, y: inset + (size.height - 2 * inset) * (1 - fraction))
            }

            var line = Path()
            var isolated: [CGPoint] = []
            var runStart: Int?
            for (index, value) in values.enumerated() {
                guard let value else {
                    runStart = nil
                    continue
                }
                let here = point(index, value)
                if runStart == nil {
                    line.move(to: here)
                    runStart = index
                    let next = index + 1
                    if next >= values.count || values[next] == nil { isolated.append(here) }
                } else {
                    line.addLine(to: here)
                }
            }
            context.stroke(line, with: .color(DashboardTheme.deemphasis),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            // A day on its own between gaps draws no line: a small dot shows it.
            for dot in isolated {
                context.fill(Path(ellipseIn: CGRect(x: dot.x - 2, y: dot.y - 2, width: 4, height: 4)),
                             with: .color(DashboardTheme.deemphasis))
            }
            if let last = values.indices.last(where: { values[$0] != nil }), let value = values[last] {
                let latest = point(last, value)
                context.fill(Path(ellipseIn: CGRect(x: latest.x - 6, y: latest.y - 6, width: 12, height: 12)), with: .color(DashboardTheme.surface))
                context.fill(Path(ellipseIn: CGRect(x: latest.x - 4, y: latest.y - 4, width: 8, height: 8)),
                             with: .color(DashboardTheme.accent))
            }
        }
    }
}
