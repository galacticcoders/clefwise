import SwiftUI

/// The blue scale the note map and the piece bars share: accuracy in five classes, darker for
/// better known. A mark with too few answers to judge is drawn hollow instead, so "not enough yet"
/// never looks like "doing badly".
enum AccuracyScale {
    /// Fewer answers than this and a mark is drawn hollow.
    static let minimumAnswers = 5
    /// Lower bounds, in whole percent, of the classes after the first: under 60%, the 60s, 70s,
    /// 80s, and 90% and up.
    static let thresholds = [60, 70, 80, 90]
    static let classLabels = ["Under 60%", "60–69%", "70–79%", "80–89%", "90–100%"]
    /// Where each class sits on the ramp from step 250 (the lightest an ordered scale may start):
    /// steps 250, 350, 500, 600 and 700, far enough apart to tell neighbours apart, and with white
    /// labels only from where white reads better than ink.
    private static let rampFractions: [Double] = [0, 2.0 / 9, 5.0 / 9, 7.0 / 9, 1]

    /// The class of `correct` out of `attempts`; nil when that's too few to judge.
    static func level(correct: Int, of attempts: Int) -> Int? {
        guard attempts >= minimumAnswers else { return nil }
        // From the percentage as printed, so a cell never disagrees with its own tip.
        let percent = ReportFormat.percentValue(correct, of: attempts)
        return thresholds.filter { percent >= $0 }.count
    }

    static func fill(level: Int) -> Color { DashboardTheme.rampColor(rampFractions[level], fromStep: 3) }

    /// Ink or white for a label inside the mark; secondary ink inside a hollow one.
    static func labelColor(level: Int?) -> Color {
        level.map { DashboardTheme.textOnRamp(rampFractions[$0]) } ?? DashboardTheme.textSecondary
    }
}

/// A cell on the accuracy scale, or a hollow outline when there are too few answers to judge.
struct AccuracyCell: View {
    let level: Int?
    var cornerRadius: CGFloat = 4
    /// The hovered cell gets an ink outline, so it's clear which one the tip describes.
    var isHighlighted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let level {
                shape.fill(AccuracyScale.fill(level: level))
            } else {
                shape.fill(DashboardTheme.surface)
                shape.strokeBorder(DashboardTheme.baseline, lineWidth: 1)
            }
            if isHighlighted {
                shape.strokeBorder(DashboardTheme.textPrimary, lineWidth: 2)
            }
        }
    }
}

/// The scale's key: the five classes in order, then what a hollow mark means. In a row under a
/// chart, or as a column beside one with the best class at the top.
struct AccuracyLegend: View {
    var axis = Axis.horizontal
    var hollowMeaning = "Fewer than \(AccuracyScale.minimumAnswers) answers"

    var body: some View {
        Group {
            if axis == .horizontal {
                HStack(alignment: .top, spacing: 10) {
                    title
                    HStack(alignment: .top, spacing: 2) {
                        ForEach(AccuracyScale.classLabels.indices, id: \.self) { level in
                            VStack(spacing: 3) {
                                swatch(level)
                                    .frame(width: 52, height: 12)
                                label(AccuracyScale.classLabels[level])
                            }
                        }
                    }
                    hollowKey
                        .padding(.leading, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    title
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(AccuracyScale.classLabels.indices.reversed(), id: \.self) { level in
                            HStack(spacing: 6) {
                                swatch(level)
                                    .frame(width: 18, height: 14)
                                label(AccuracyScale.classLabels[level])
                            }
                        }
                    }
                    hollowKey
                        .padding(.top, 8)
                }
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Text("Accuracy")
            .font(.caption)
            .foregroundStyle(DashboardTheme.textSecondary)
    }

    private func swatch(_ level: Int) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(AccuracyScale.fill(level: level))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(DashboardTheme.textMuted)
    }

    private var hollowKey: some View {
        HStack(spacing: 6) {
            AccuracyCell(level: nil, cornerRadius: 2)
                .frame(width: 18, height: 14)
            Text(hollowMeaning)
                .font(.caption)
                .foregroundStyle(DashboardTheme.textSecondary)
        }
    }
}
