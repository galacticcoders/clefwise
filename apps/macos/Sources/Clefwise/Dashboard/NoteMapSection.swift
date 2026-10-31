import SwiftUI

/// The note map: every staff line and space per clef, darker for better known, hollow where there's too little data yet.
struct NoteMapSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    @State private var hovered: String?

    var body: some View {
        DashboardCard(title: "Note map", subtitle: "How well you know each line and space") {
            // Bigger cells with the key beside them on a wide card; the key under the staves on a narrow one.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 48) {
                    staves(.large)
                    key(.vertical)
                        .padding(.top, 24)
                }
                HStack(alignment: .top, spacing: 36) {
                    staves(.regular)
                    key(.vertical)
                        .padding(.top, 24)
                }
                VStack(alignment: .leading, spacing: 18) {
                    staves(.regular)
                    key(.horizontal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hoverTip(for: hovered) { tip }
        } table: {
            table
        }
    }

    // MARK: Model

    /// The clefs the filter lets through, in staff order.
    private var clefs: [Clef] {
        switch report.filter.clef {
        case .all: Clef.allCases
        case .treble: [.treble]
        case .bass: [.bass]
        }
    }

    /// Each clef's places, highest first: the five lines and four spaces, and out to the furthest
    /// ledger position answered.
    private var columns: [(clef: Clef, places: [NoteMapPlace])] {
        clefs.map { clef in
            let answered = report.positions.filter { $0.clef == clef }
            let byPosition = Dictionary(answered.map { ($0.position, $0) }, uniquingKeysWith: { first, _ in first })
            let lowest = min(0, answered.map(\.position).min() ?? 0)
            let highest = max(8, answered.map(\.position).max() ?? 8)
            return (clef, (lowest...highest).reversed().map { NoteMapPlace(clef: clef, position: $0, progress: byPosition[$0]) })
        }
    }

    private func place(withID id: String) -> NoteMapPlace? {
        columns.lazy.flatMap(\.places).first { $0.id == id }
    }

    // MARK: Chart

    private func staves(_ size: NoteMapStaff.Size) -> some View {
        let columns = columns
        // The staves share one vertical scale, so their five lines line up side by side.
        let top = columns.compactMap { $0.places.first?.position }.max() ?? 8
        return HStack(alignment: .top, spacing: 28) {
            ForEach(columns, id: \.clef) { column in
                VStack(spacing: 6) {
                    Text(column.clef.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardTheme.textSecondary)
                    NoteMapStaff(places: column.places, top: top, size: size, naming: naming, hovered: $hovered)
                }
            }
        }
        .fixedSize()
    }

    private func key(_ axis: Axis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AccuracyLegend(axis: axis)
            note("Lines on the left, spaces on the right. Long rules are the staff, short ones ledger lines.")
            if report.answersBeforeTracking > 0 {
                note("Includes \(ReportFormat.count(report.answersBeforeTracking)) answers from before detailed tracking, which have no times.")
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(DashboardTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 180, alignment: .leading)
    }

    @ViewBuilder private var tip: some View {
        if let hovered, let place = place(withID: hovered) {
            let name = ReportFormat.noteName(place.natural, naming)
            let label = "\(name) · \(place.clef.name) \(ReportFormat.staffPlace(place.position))"
            if place.attempts == 0 {
                HoverTipText(value: "No answers yet", label: label)
            } else {
                let accuracy = ReportFormat.percent(place.correct, of: place.attempts)
                let before = place.progress?.attemptsBeforeTracking ?? 0
                HoverTipText(
                    value: place.level == nil ? "\(place.correct) of \(place.attempts) right" : "\(accuracy) right",
                    label: label,
                    details: [
                        place.level == nil ? "Too few answers to judge yet"
                            : "\(ReportFormat.count(place.correct)) of \(ReportFormat.count(place.attempts)) answers right",
                        place.progress?.medianResponseMs.map { "Median \(ReportFormat.seconds($0)) to a right answer" },
                        before > 0 ? "\(ReportFormat.count(before)) from before detailed tracking" : nil,
                    ].compactMap { $0 })
            }
        }
    }

    // MARK: Table

    private var table: some View {
        let columns = columns
        let showsBefore = report.positions.contains { $0.attemptsBeforeTracking > 0 }
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
            GridRow {
                ReportTable.heading("Clef")
                ReportTable.heading("Place")
                ReportTable.heading("Note")
                ReportTable.heading("Answers").gridColumnAlignment(.trailing)
                ReportTable.heading("Right").gridColumnAlignment(.trailing)
                ReportTable.heading("Accuracy").gridColumnAlignment(.trailing)
                ReportTable.heading("Median time").gridColumnAlignment(.trailing)
                if showsBefore {
                    ReportTable.heading("Before tracking").gridColumnAlignment(.trailing)
                }
            }
            ForEach(columns, id: \.clef) { column in
                ReportTable.rule()
                ForEach(column.places) { place in
                    GridRow {
                        ReportTable.cell(place.clef.name)
                        ReportTable.cell(capitalized(ReportFormat.staffPlace(place.position)))
                        ReportTable.cell(ReportFormat.noteName(place.natural, naming))
                        ReportTable.cell(ReportFormat.count(place.attempts), muted: place.attempts == 0)
                        ReportTable.cell(place.attempts > 0 ? ReportFormat.count(place.correct) : "—", muted: place.attempts == 0)
                        ReportTable.cell(ReportFormat.percent(place.correct, of: place.attempts), muted: place.level == nil)
                        ReportTable.cell(ReportFormat.seconds(place.progress?.medianResponseMs), muted: place.attempts == 0)
                        if showsBefore {
                            ReportTable.cell(ReportFormat.count(place.progress?.attemptsBeforeTracking ?? 0))
                        }
                    }
                }
            }
        }
    }

    /// "Line 1" from "line 1".
    private func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
}

/// One clef's lines and spaces drawn like a staff: line positions in the left column with a staff
/// line through them, spaces in the right one between the lines, high notes at the top, each a
/// cell as tall as a staff space.
private struct NoteMapStaff: View {
    /// Highest first, every position from the lowest to the highest.
    let places: [NoteMapPlace]
    /// The position at the top of the drawing, shared by the clefs side by side.
    let top: Int
    var size = Size.regular
    let naming: NamingSystem
    @Binding var hovered: String?

    enum Size {
        case regular, large
    }

    /// Half a staff space: one step up or down.
    private var step: CGFloat { size == .large ? 15 : 12 }
    private var cellWidth: CGFloat { size == .large ? 62 : 46 }
    private var fontSize: CGFloat { size == .large ? 13 : 12 }
    private let columnGap: CGFloat = 8
    /// How far the staff lines run past the cells.
    private let margin: CGFloat = 12

    private var width: CGFloat { margin * 2 + cellWidth * 2 + columnGap }

    private func y(_ position: Int) -> CGFloat { CGFloat(top - position) * step + step }

    private func x(_ position: Int) -> CGFloat {
        margin + cellWidth / 2 + (position.isMultiple(of: 2) ? 0 : cellWidth + columnGap)
    }

    var body: some View {
        let lowest = places.last?.position ?? 0
        ZStack(alignment: .topLeading) {
            rules(lowest: lowest)
            ForEach(places) { place in
                let name = ReportFormat.noteName(place.natural, naming)
                AccuracyCell(level: place.level, isHighlighted: hovered == place.id)
                    .overlay {
                        Text(name)
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundStyle(AccuracyScale.labelColor(level: place.level))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 3)
                    }
                    .frame(width: cellWidth, height: step * 2 - 2)
                    // The hit target takes in the gaps, so neighbouring targets meet.
                    .padding(.vertical, 1)
                    .padding(.horizontal, columnGap / 2)
                    .hoverTarget(place.id, hovered: $hovered)
                    .position(x: x(place.position), y: y(place.position))
                    .accessibilityElement()
                    .accessibilityLabel("\(name), \(place.clef.name) \(ReportFormat.staffPlace(place.position))")
                    .accessibilityValue(place.attempts == 0 ? "No answers yet"
                        : "\(ReportFormat.percent(place.correct, of: place.attempts)) of \(place.attempts) answers right")
            }
        }
        .frame(width: width, height: y(lowest) + step, alignment: .topLeading)
    }

    /// The five staff lines across the whole column, and short ledger lines around the line cells
    /// beyond them.
    private func rules(lowest: Int) -> some View {
        Canvas { context, _ in
            var staff = Path()
            var ledgers = Path()
            for position in stride(from: lowest, through: places.first?.position ?? 8, by: 1) where position.isMultiple(of: 2) {
                let lineY = y(position)
                if (0...8).contains(position) {
                    staff.move(to: CGPoint(x: 0, y: lineY))
                    staff.addLine(to: CGPoint(x: width, y: lineY))
                } else {
                    ledgers.move(to: CGPoint(x: margin - 5, y: lineY))
                    ledgers.addLine(to: CGPoint(x: margin + cellWidth + 5, y: lineY))
                }
            }
            context.stroke(staff, with: .color(DashboardTheme.baseline), lineWidth: 1)
            context.stroke(ledgers, with: .color(DashboardTheme.baseline), lineWidth: 1)
        }
    }
}

/// One line or space of one clef, answered or not.
private struct NoteMapPlace: Identifiable {
    let clef: Clef
    let position: Int
    let progress: PositionProgress?

    var id: String { "\(clef.rawValue)\(position)" }
    var natural: Pitch { clef.pitch(atPosition: position) }
    var attempts: Int { progress?.attempts ?? 0 }
    var correct: Int { progress?.correct ?? 0 }
    var level: Int? { AccuracyScale.level(correct: correct, of: attempts) }
}
