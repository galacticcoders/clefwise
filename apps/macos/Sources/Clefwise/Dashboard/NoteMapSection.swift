import SwiftUI

/// What a note map shows for each line and space.
enum NoteMapMeasure {
    /// How well it's known: darker blue for better, hollow where there's too little data yet.
    case accuracy
    /// How often it came up: darker orange for more answers, hollow where there are none.
    case practice
    /// How fast it's named now (`PositionProgress.recentMedianResponseMs`): darker aqua for faster
    /// (`SpeedScale`), hollow where there are too few right answers yet.
    case speed
}

/// A note map: every staff line and space per clef, drawn like a staff and coloured by `measure`.
struct NoteMapSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem
    var measure = NoteMapMeasure.accuracy

    @State private var hovered: String?

    private var title: String {
        switch measure {
        case .accuracy: "Note map"
        case .practice: "Practice map"
        case .speed: "Speed map"
        }
    }
    private var subtitle: String {
        switch measure {
        case .accuracy: "How well you know each line and space"
        case .practice: "How often each line and space comes up"
        case .speed: "How fast you name each line and space now"
        }
    }

    var body: some View {
        DashboardCard(title: title, subtitle: subtitle) {
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

    /// The practice classes, from the busiest place shown.
    private var practiceScale: PracticeScale {
        PracticeScale(maximum: columns.flatMap(\.places).map(\.attempts).max() ?? 0)
    }

    /// How a place's cell looks under `measure`.
    private func style(_ place: NoteMapPlace, scale: PracticeScale) -> NoteMapCellStyle {
        switch measure {
        case .accuracy:
            return NoteMapCellStyle(
                fill: place.level.map(AccuracyScale.fill), label: AccuracyScale.labelColor(level: place.level),
                accessibilityValue: place.attempts == 0 ? "No answers yet"
                    : "\(ReportFormat.percent(place.correct, of: place.attempts)) of \(place.attempts) answers right")
        case .practice:
            let level = scale.level(answers: place.attempts)
            return NoteMapCellStyle(
                fill: level.map(PracticeScale.fill), label: PracticeScale.labelColor(level: level),
                accessibilityValue: place.attempts == 0 ? "Not practised yet" : answers(place.attempts))
        case .speed:
            let level = place.speedLevel
            return NoteMapCellStyle(
                fill: level.map(SpeedScale.fill), label: SpeedScale.labelColor(level: level),
                accessibilityValue: place.attempts == 0 ? "No answers yet"
                    : level == nil ? rightAnswersSoFar(place.recentRightAnswers)
                    : "\(SpeedScale.seconds(place.recentMs)) now, from \(rightAnswers(place.recentRightAnswers))")
        }
    }

    /// "1 answer", "647 answers".
    private func answers(_ count: Int) -> String {
        count == 1 ? "1 answer" : "\(ReportFormat.count(count)) answers"
    }

    /// "1 right answer", "20 right answers".
    private func rightAnswers(_ count: Int) -> String {
        count == 1 ? "1 right answer" : "\(ReportFormat.count(count)) right answers"
    }

    /// Why a place has no speed yet: "3 right answers so far; 5 needed".
    private func rightAnswersSoFar(_ count: Int) -> String {
        "\(count == 0 ? "No right answers" : rightAnswers(count)) so far; \(SpeedScale.minimumRightAnswers) needed"
    }

    // MARK: Chart

    private func staves(_ size: NoteMapStaff.Size) -> some View {
        let columns = columns
        // The staves share one vertical scale, so their five lines line up side by side.
        let top = columns.compactMap { $0.places.first?.position }.max() ?? 8
        let scale = practiceScale
        return HStack(alignment: .top, spacing: 28) {
            ForEach(columns, id: \.clef) { column in
                VStack(spacing: 6) {
                    Text(column.clef.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardTheme.textSecondary)
                    NoteMapStaff(places: column.places, top: top, size: size, naming: naming, hovered: $hovered,
                                 style: { style($0, scale: scale) })
                }
            }
        }
        .fixedSize()
    }

    private func key(_ axis: Axis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch measure {
            case .accuracy:
                AccuracyLegend(axis: axis)
            case .practice:
                let scale = practiceScale
                ScaleLegend(title: "Answers", classLabels: scale.classLabels, fill: PracticeScale.fill,
                            hollowMeaning: "Not practised yet", axis: axis)
            case .speed:
                ScaleLegend(title: "Median time now", classLabels: SpeedScale.classLabels(), fill: SpeedScale.fill,
                            hollowMeaning: "Fewer than \(SpeedScale.minimumRightAnswers) right answers", axis: axis)
                note("Each time is the median of that place's last \(PositionProgress.recentWindow) right answers.")
            }
            note("Lines on the left, spaces on the right. Long rules are the staff, short ones ledger lines.")
            if report.answersBeforeTracking > 0 {
                // They count on the other maps, but without times they can't on this one.
                let count = ReportFormat.count(report.answersBeforeTracking)
                note(measure == .speed ? "Leaves out the \(count) answers from before detailed tracking, which have no times."
                                       : "Includes \(count) answers from before detailed tracking, which have no times.")
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
        switch measure {
        case .accuracy: accuracyTip
        case .practice: practiceTip
        case .speed: speedTip
        }
    }

    @ViewBuilder private var speedTip: some View {
        if let hovered, let place = place(withID: hovered) {
            let name = ReportFormat.noteName(place.natural, naming)
            let label = "\(name) · \(place.clef.name) \(ReportFormat.staffPlace(place.position))"
            let before = place.progress?.attemptsBeforeTracking ?? 0
            if place.attempts == 0 {
                HoverTipText(value: "No answers yet", label: label)
            } else if place.speedLevel == nil {
                HoverTipText(value: "Too few right answers yet", label: label, details: [
                    rightAnswersSoFar(place.recentRightAnswers),
                    before > 0 ? "\(answers(before)) from before detailed tracking, without times" : nil,
                ].compactMap { $0 })
            } else {
                let used = place.recentRightAnswers
                HoverTipText(value: "\(SpeedScale.seconds(place.recentMs)) now", label: label, details: [
                    used >= PositionProgress.recentWindow ? "Median of its last \(used) right answers"
                        : "Median of its \(used) right answers so far",
                    place.progress?.medianResponseMs.map { "Over the period: \(SpeedScale.seconds($0))" },
                ].compactMap { $0 })
            }
        }
    }

    @ViewBuilder private var practiceTip: some View {
        if let hovered, let place = place(withID: hovered) {
            let name = ReportFormat.noteName(place.natural, naming)
            let label = "\(name) · \(place.clef.name) \(ReportFormat.staffPlace(place.position))"
            if place.attempts == 0 {
                HoverTipText(value: "Not practised yet", label: label)
            } else {
                let places = columns.flatMap(\.places)
                let total = places.map(\.attempts).reduce(0, +)
                let practised = places.filter { $0.attempts > 0 }.count
                HoverTipText(value: answers(place.attempts), label: label, details: [
                    "\(ReportFormat.percent(place.attempts, of: total)) of the answers on this map",
                    "Number \(rank(of: place, in: places)) of \(practised) by practice",
                ])
            }
        }
    }

    /// 1 for the most answered place; places with as many answers share a rank.
    private func rank(of place: NoteMapPlace, in places: [NoteMapPlace]) -> Int {
        places.filter { $0.attempts > place.attempts }.count + 1
    }

    @ViewBuilder private var accuracyTip: some View {
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

    @ViewBuilder private var table: some View {
        switch measure {
        case .accuracy: accuracyTable
        case .practice: practiceTable
        case .speed: speedTable
        }
    }

    /// Slowest first, so the places still to speed up lead; then those with too few right answers to
    /// judge, in staff order (as are ties).
    private var speedTable: some View {
        let places = columns.flatMap(\.places)
        let ranked = places.enumerated().sorted { first, second in
            let (a, b) = (first.element.judgedRecentMs ?? -1, second.element.judgedRecentMs ?? -1)
            return a != b ? a > b : first.offset < second.offset
        }.map(\.element)
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
            GridRow {
                ReportTable.heading("Clef")
                ReportTable.heading("Place")
                ReportTable.heading("Note")
                ReportTable.heading("Now").gridColumnAlignment(.trailing)
                ReportTable.heading("Right answers used").gridColumnAlignment(.trailing)
                ReportTable.heading("Over the period").gridColumnAlignment(.trailing)
            }
            ReportTable.rule()
            ForEach(ranked) { place in
                let judged = place.speedLevel != nil
                GridRow {
                    ReportTable.cell(place.clef.name)
                    ReportTable.cell(capitalized(ReportFormat.staffPlace(place.position)))
                    ReportTable.cell(ReportFormat.noteName(place.natural, naming))
                    ReportTable.cell(SpeedScale.seconds(place.recentMs), muted: !judged)
                    ReportTable.cell(ReportFormat.count(place.recentRightAnswers), muted: !judged)
                    ReportTable.cell(SpeedScale.seconds(place.progress?.medianResponseMs), muted: !judged)
                }
            }
        }
    }

    /// Most answered first, so the most and least practised are at either end; ties keep staff order.
    private var practiceTable: some View {
        let places = columns.flatMap(\.places)
        let total = places.map(\.attempts).reduce(0, +)
        let ranked = places.enumerated().sorted { ($1.element.attempts, $0.offset) < ($0.element.attempts, $1.offset) }.map(\.element)
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
            GridRow {
                ReportTable.heading("Rank").gridColumnAlignment(.trailing)
                ReportTable.heading("Clef")
                ReportTable.heading("Place")
                ReportTable.heading("Note")
                ReportTable.heading("Answers").gridColumnAlignment(.trailing)
                ReportTable.heading("Share").gridColumnAlignment(.trailing)
            }
            ReportTable.rule()
            ForEach(ranked) { place in
                let none = place.attempts == 0
                GridRow {
                    ReportTable.cell(none ? "—" : ReportFormat.count(rank(of: place, in: places)), muted: none)
                    ReportTable.cell(place.clef.name)
                    ReportTable.cell(capitalized(ReportFormat.staffPlace(place.position)))
                    ReportTable.cell(ReportFormat.noteName(place.natural, naming))
                    ReportTable.cell(ReportFormat.count(place.attempts), muted: none)
                    ReportTable.cell(none ? "—" : ReportFormat.percent(place.attempts, of: total), muted: none)
                }
            }
        }
    }

    private var accuracyTable: some View {
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
    /// How each place's cell looks: the section's measure decides.
    let style: (NoteMapPlace) -> NoteMapCellStyle

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
                let style = style(place)
                ScaleCell(fill: style.fill, isHighlighted: hovered == place.id)
                    .overlay {
                        Text(name)
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundStyle(style.label)
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
                    .accessibilityValue(style.accessibilityValue)
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

/// A cell's fill (nil: hollow), its label's colour, and what it says to VoiceOver.
private struct NoteMapCellStyle {
    let fill: Color?
    let label: Color
    let accessibilityValue: String
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
    /// The median time of its latest right answers, and how many that is (`PositionProgress`).
    var recentMs: Int? { progress?.recentMedianResponseMs }
    var recentRightAnswers: Int { progress?.recentRightAnswers ?? 0 }
    var speedLevel: Int? { SpeedScale.level(medianMs: recentMs, rightAnswers: recentRightAnswers) }
    /// `recentMs` when there are enough right answers to judge it; nil otherwise.
    var judgedRecentMs: Int? { speedLevel == nil ? nil : recentMs }
}
