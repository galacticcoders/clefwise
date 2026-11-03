import SwiftUI

/// The Progress window: the filters, then every section for the same filter, two columns when
/// the window is wide and one when it's narrow.
struct DashboardView: View {
    let game: Game
    @Bindable var store: ProgressStore

    /// Content width from which section pairs sit side by side.
    private static let twoColumnWidth: CGFloat = 940
    private static let spacing: CGFloat = 16
    private static let padding: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                let width = min(proxy.size.width - 2 * Self.padding, 1400)
                VStack(alignment: .leading, spacing: Self.spacing) {
                    Text("Your progress")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(DashboardTheme.textPrimary)
                    filterRow
                        .padding(.bottom, 4)
                    content(width: width)
                }
                .frame(width: width, alignment: .leading)
                .padding(Self.padding)
                .frame(maxWidth: .infinity)
            }
        }
        .background(DashboardTheme.page)
        .frame(minWidth: 720, minHeight: 520)
        .navigationTitle("Progress")
        .onAppear { store.reload() }
        // A round just ended in the main window: it's in the log now.
        .onChange(of: game.phase) { old, new in
            if old == .playing, new != .playing { store.reload() }
        }
    }

    // MARK: - Filters

    private var filterRow: some View {
        HStack(spacing: 12) {
            Picker("Range", selection: range) {
                ForEach(ProgressFilter.Range.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .rebuiltOnAppearanceChange()
            .help("Which days the dashboard counts")

            Picker("Clef", selection: clef) {
                ForEach(ProgressFilter.ClefFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Count notes in either clef, or only in one")

            Button {
                game.recorder.recordUIAction("progressRefresh")
                store.reload()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Read the usage log again")

            if store.hasLoaded {
                Text("Updated \(store.report.generatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(DashboardTheme.textSecondary)
            }
            ProgressView()
                .controlSize(.small)
                .opacity(store.isLoading ? 1 : 0)
                .accessibilityHidden(!store.isLoading)
            Spacer(minLength: 0)
        }
    }

    // The store saves and reloads; these also log which control changed it.
    private var range: Binding<ProgressFilter.Range> {
        $store.filter.range.recordingChanges(as: "progressRange", to: game.recorder) { $0.rawValue }
    }

    private var clef: Binding<ProgressFilter.ClefFilter> {
        $store.filter.clef.recordingChanges(as: "progressClef", to: game.recorder) { $0.rawValue }
    }

    // MARK: - Sections

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        let report = store.report
        if !store.hasLoaded {
            ProgressView("Reading your practice…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 120)
        } else if report.isEmpty {
            EmptyDashboard(report: report)
        } else {
            sections(report, width: width)
                // Reloading keeps the last numbers up, dimmed, rather than flashing a placeholder.
                .opacity(store.isLoading ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.2), value: store.isLoading)
        }
    }

    private func sections(_ report: ProgressReport, width: CGFloat) -> some View {
        let naming = game.settings.naming
        let isWide = width >= Self.twoColumnWidth
        let column = isWide ? (width - Self.spacing) / 2 : width
        return VStack(alignment: .leading, spacing: Self.spacing) {
            KPISection(report: report, naming: naming)
            TrendSection(report: report, naming: naming)
            AutomaticSection(report: report, naming: naming)
            // Side by side, so a line or space sits at the same height in both: how well it's known
            // next to how often it comes up.
            pair(isWide, column) {
                NoteMapSection(report: report, naming: naming, measure: .accuracy)
            } and: {
                NoteMapSection(report: report, naming: naming, measure: .practice)
            }
            pair(isWide, column) {
                NoteMapSection(report: report, naming: naming, measure: .speed)
            } and: {
                WorkOnSection(report: report, naming: naming)
            }
            pair(isWide, column) {
                CalendarSection(report: report, naming: naming)
            } and: {
                BreakdownSection(report: report, naming: naming)
            }
            if !report.pieces.isEmpty {
                PieceSection(report: report, naming: naming)
            }
            RecentRoundsSection(report: report, naming: naming)
            if report.unreadableLines > 0 || report.answersBeforeTracking > 0 {
                DashboardNotes(report: report)
            }
        }
    }

    /// Two sections side by side in equal columns, or one above the other.
    @ViewBuilder
    private func pair(_ isWide: Bool, _ column: CGFloat, @ViewBuilder _ first: () -> some View,
                      @ViewBuilder and second: () -> some View) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: Self.spacing) {
                first().frame(width: column)
                second().frame(width: column)
            }
        } else {
            first()
            second()
        }
    }
}

/// No answers for the filter: says why, and how to get some.
private struct EmptyDashboard: View {
    let report: ProgressReport

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DashboardTheme.textMuted)
                .padding(.bottom, 4)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DashboardTheme.textPrimary)
            Text(message)
                .foregroundStyle(DashboardTheme.textSecondary)
                .multilineTextAlignment(.center)
            if report.unreadableLines > 0 {
                DashboardNotes(report: report)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
        .padding(.horizontal, 24)
        .background(DashboardTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DashboardTheme.border, lineWidth: 1)
        }
    }

    /// The streak isn't limited by the filter, so it tells whether there's practice elsewhere.
    private var hasPractisedBefore: Bool { report.longestStreakDays > 0 }

    private var title: String {
        guard hasPractisedBefore else { return "No practice yet" }
        let notes = switch report.filter.clef {
        case .all: "No notes"
        case .treble: "No treble clef notes"
        case .bass: "No bass clef notes"
        }
        return report.filter.range == .all ? "\(notes) yet" : "\(notes) in the \(report.filter.range.label.lowercased())"
    }

    private var message: String {
        guard hasPractisedBefore, report.filter != ProgressFilter(range: .all, clef: .all) else {
            return "Practise a round and your progress appears here."
        }
        return "Practise a round and your progress appears here, or pick another range or clef above."
    }
}

/// Small print about what the numbers leave out.
private struct DashboardNotes: View {
    let report: ProgressReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if report.unreadableLines > 0 {
                note(report.unreadableLines == 1
                     ? "1 line of the usage log couldn't be read and is left out."
                     : "\(report.unreadableLines.formatted()) lines of the usage log couldn't be read and are left out.")
            }
            if report.answersBeforeTracking > 0 {
                note("\(report.answersBeforeTracking.formatted()) answers from before detailed tracking began count in the note map and notes to work on only: they have no dates or times.")
            }
        }
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(DashboardTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Shared pieces for the charts

/// Number and time formats shared by the dashboard's tiles, tooltips and tables.
enum DashboardFormat {
    /// "1 h 25 min", "12 min", "under 1 min", "0 min".
    static func duration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0 min" }
        let minutes = Int((seconds / 60).rounded())
        guard minutes > 0 else { return "under 1 min" }
        let hours = minutes / 60
        if hours == 0 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min"
    }

    /// "87%"
    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    /// "1.2 s"
    static func seconds(milliseconds: Int) -> String { seconds(Double(milliseconds) / 1000) }
    static func seconds(_ seconds: Double) -> String {
        "\(seconds.formatted(.number.precision(.fractionLength(1)))) s"
    }

    /// "2,170", or "128K" once a count is too long to take in at a glance.
    static func count(_ value: Int) -> String {
        value >= 100_000 ? value.formatted(.number.notation(.compactName)) : value.formatted()
    }

    /// "Tue 14 Oct"
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "1 note", "12 notes"
    static func notes(_ count: Int) -> String { count == 1 ? "1 note" : "\(count.formatted()) notes" }
}

/// The hover readout for a mark: the value leads, what it is follows.
struct ChartTooltip: View {
    let value: String
    let label: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(DashboardTheme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(DashboardTheme.textSecondary)
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

extension View {
    /// Places `tooltip` beside the point `x` (from the view's leading edge): to its right in the
    /// left half of `width`, to its left in the right half, so it stays in view. `y` is its top.
    func tooltip(_ tooltip: some View, beside x: CGFloat, top y: CGFloat, in width: CGFloat) -> some View {
        overlay(alignment: .topLeading) {
            tooltip
                .alignmentGuide(.leading) { size in x < width / 2 ? -(x + 12) : size.width + 12 - x }
                .alignmentGuide(.top) { _ in -y }
                .allowsHitTesting(false)
        }
    }
}

/// A plain table for a chart's numbers: a header, hairline rules, numbers in aligned columns.
struct DashboardTable: View {
    struct Column {
        let title: String
        /// Numbers are trailing-aligned, labels leading.
        var isNumeric = true
    }

    let columns: [Column]
    let rows: [[String]]
    /// Taller tables scroll.
    var maxHeight: CGFloat = 320

    private let rowHeight: CGFloat = 26

    var body: some View {
        VStack(spacing: 0) {
            row(columns.map(\.title), isHeader: true)
            Rectangle().fill(DashboardTheme.baseline).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        row(rows[index], isHeader: false)
                        Rectangle().fill(DashboardTheme.gridline).frame(height: 1)
                    }
                }
            }
            .frame(height: min(CGFloat(rows.count) * (rowHeight + 1), maxHeight))
        }
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 12) {
            ForEach(cells.indices, id: \.self) { index in
                let numeric = columns.indices.contains(index) && columns[index].isNumeric
                Text(cells[index])
                    .font(isHeader ? .caption.weight(.semibold) : .callout)
                    .monospacedDigit()
                    .foregroundStyle(isHeader ? DashboardTheme.textSecondary : DashboardTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: numeric ? .trailing : .leading)
            }
        }
        .frame(height: rowHeight)
        .padding(.horizontal, 4)
    }
}

/// Round tick values for an axis from 0: steps of 1, 2, 2.5 or 5 times a power of ten.
enum NiceScale {
    static func step(for maximum: Double, ticks: Int = 4) -> Double {
        guard maximum > 0 else { return 1 }
        let raw = maximum / Double(ticks)
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let nice: Double = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 2.5 ? 2.5 : normalized <= 5 ? 5 : 10
        return nice * magnitude
    }

    /// Ticks for a line that needn't start at zero (a bar always does): whole-number steps of 1,
    /// 2, 5, 10, 20, 25, 50… from the tick at or below the lowest value to the one at or above the
    /// highest. The span is at least `minimumSpan`, so small wobbles aren't blown up, grown
    /// around the values and kept within `bounds`.
    static func ticks(covering values: [Double], minimumSpan: Double, within bounds: ClosedRange<Double>,
                      count: Int = 4) -> [Double] {
        guard var low = values.min(), var high = values.max() else { return [bounds.lowerBound, bounds.upperBound] }
        if high - low < minimumSpan {
            let middle = (low + high) / 2
            low = middle - minimumSpan / 2
            high = middle + minimumSpan / 2
            if high > bounds.upperBound { (low, high) = (low - (high - bounds.upperBound), bounds.upperBound) }
            if low < bounds.lowerBound { (low, high) = (bounds.lowerBound, min(bounds.upperBound, high + bounds.lowerBound - low)) }
        }
        let raw = (high - low) / Double(count)
        let magnitude = pow(10, floor(log10(max(raw, 1))))
        let normalized = raw / magnitude
        let step = (normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 2.5 && magnitude >= 10 ? 2.5 : normalized <= 5 ? 5 : 10) * magnitude
        let start = max(bounds.lowerBound, (low / step).rounded(.down) * step)
        let end = min(bounds.upperBound, (high / step).rounded(.up) * step)
        return stride(from: start, through: end + step / 2, by: step).map { min($0, bounds.upperBound) }
    }

    /// 0, step, 2·step… up to the first tick at or above `maximum`.
    static func ticks(for maximum: Double, count: Int = 4) -> [Double] {
        let step = step(for: maximum, ticks: count)
        let top = max(step, (maximum / step).rounded(.up) * step)
        return stride(from: 0, through: top + step / 2, by: step).map { $0 }
    }
}
