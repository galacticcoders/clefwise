import SwiftUI

/// How the detail sections write numbers, times, places on the staff and notes.
enum ReportFormat {
    /// "87%". Rounded, but never up to 100% while something was missed, nor down to 0% while
    /// something was right.
    static func percent(_ correct: Int, of total: Int) -> String {
        total > 0 ? "\(percentValue(correct, of: total))%" : "—"
    }

    /// The whole percentage `percent` prints; 0 when there's nothing to divide.
    static func percentValue(_ correct: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        var value = Int((Double(correct) / Double(total) * 100).rounded())
        if correct < total { value = min(value, 99) }
        if correct > 0 { value = max(value, 1) }
        return value
    }

    /// "1.2 s"; "—" without a time.
    static func seconds(_ ms: Int?) -> String {
        guard let ms else { return "—" }
        return (Double(ms) / 1000).formatted(.number.precision(.fractionLength(1))) + " s"
    }

    /// Minutes and seconds, "1:05"; "—" when unknown.
    static func duration(_ ms: Int?) -> String {
        guard let ms else { return "—" }
        let seconds = Int((Double(ms) / 1000).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func count(_ value: Int) -> String { value.formatted() }

    /// "2 hours ago", "yesterday"; "just now" within a minute.
    static func relative(_ date: Date, to now: Date) -> String {
        guard abs(now.timeIntervalSince(date)) >= 60 else { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Where a staff position is, counted from the bottom as musicians do: "line 1", "space 4",
    /// "below the staff", "ledger line 2 above".
    static func staffPlace(_ position: Int) -> String {
        switch position {
        case 0...8:
            return position % 2 == 0 ? "line \(position / 2 + 1)" : "space \(position / 2 + 1)"
        case 9:
            return "above the staff"
        case -1:
            return "below the staff"
        case 10...:
            let ledger = (position - 8) / 2
            return position % 2 == 0 ? "ledger line \(ledger) above" : "above ledger line \(ledger)"
        default:
            let ledger = -position / 2
            return position % 2 == 0 ? "ledger line \(ledger) below" : "below ledger line \(ledger)"
        }
    }

    /// A note as the dashboard names it. Letters keep the octave ("F♯5"); solfège and sargam go
    /// without ("Fa♯"), as their octave numbering differs from country to country.
    static func noteName(_ pitch: Pitch, _ naming: NamingSystem) -> String {
        naming == .letters ? pitch.name : naming.name(of: pitch)
    }

    /// What goes with a note's name to tell it apart: the clef, plus, without octave numbers, the
    /// place on the staff ("Treble · line 5"), since Fa♯ could be F♯4 or F♯5.
    static func noteContext(_ pitch: Pitch, clef: Clef, _ naming: NamingSystem) -> String {
        naming == .letters ? clef.name : "\(clef.name) · \(staffPlace(clef.position(of: pitch)))"
    }
}

/// The look every section's table view shares: quiet headings over a hairline, aligned digits.
enum ReportTable {
    static func heading(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DashboardTheme.textMuted)
    }

    static func cell(_ text: String, muted: Bool = false) -> some View {
        Text(text)
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(muted ? DashboardTheme.textMuted : DashboardTheme.textPrimary)
    }

    /// A full-width hairline between rows of a `Grid`.
    static func rule() -> some View {
        Rectangle()
            .fill(DashboardTheme.gridline)
            .frame(height: 1)
            .gridCellUnsizedAxes(.horizontal)
    }
}

/// A line for a section with nothing to show yet.
struct NothingYetText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(DashboardTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

/// One horizontal bar from a baseline on the left, in the accent colour, with its value just past
/// the tip. `fraction` is of the room the longest bar may take, which leaves space for its value.
struct HorizontalValueBar: View {
    let fraction: Double
    let value: String
    /// Too few answers to judge: an outline instead of a fill.
    var isHollow = false
    var isHighlighted = false
    var thickness: CGFloat = 14
    var valueRoom: CGFloat = 46
    /// Rows stacked without gaps draw one continuous baseline; spaced-out ones look tidier without.
    var showsBaseline = true

    var body: some View {
        GeometryReader { proxy in
            let length = max(3, (proxy.size.width - valueRoom) * min(max(fraction, 0), 1))
            let radius = min(4, length / 2)
            // Square at the baseline, rounded at the data end.
            let bar = UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: radius, topTrailing: radius), style: .continuous)
            HStack(spacing: 6) {
                ZStack {
                    if isHollow {
                        bar.strokeBorder(DashboardTheme.accent, lineWidth: 1)
                    } else {
                        bar.fill(DashboardTheme.accent.opacity(isHighlighted ? 0.75 : 1))
                    }
                }
                .frame(width: length, height: thickness)
                Text(value)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DashboardTheme.textSecondary)
                    .fixedSize()
            }
            .frame(maxHeight: .infinity)
        }
        .background(alignment: .leading) {
            if showsBaseline {
                Rectangle()
                    .fill(DashboardTheme.baseline)
                    .frame(width: 1)
            }
        }
    }
}
