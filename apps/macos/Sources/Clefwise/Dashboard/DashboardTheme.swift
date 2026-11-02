import SwiftUI

/// Chart colours and chrome for the dashboard, light and dark. The palette is the data-viz
/// reference palette, checked with its validator on each mode's card surface:
/// - **Light** (white card): the three categorical slots pass every colour-blindness gate (aqua
///   is under 3:1 contrast, so wherever it's used its series needs visible labels or the table
///   view); the blue ramp passes as an ordered scale from step 250.
/// - **Dark** (`#1a1a19` card): the palette's dark steps of the same three hues pass every gate
///   on all pairs, all over 3:1. The ramp runs the other way (amounts get lighter, away from the
///   dark card) and starts no darker than step 550; the accuracy classes (steps 550, 450, 300,
///   200, 100) pass as an ordered scale, the darkest at 2.6:1.
enum DashboardTheme {
    /// Cards (the chart surface) and the window behind them.
    static let surface = Color(light: .white, dark: NSColor(hex: 0x1A1A19))
    static let page = Theme.background

    static let textPrimary = Color(light: NSColor(hex: 0x0B0B0B), dark: NSColor(hex: 0xF0EFEC))
    static let textSecondary = Color(light: NSColor(hex: 0x52514E), dark: NSColor(hex: 0xC3C2B7))
    /// Axis labels and other quiet text.
    static let textMuted = Color(hex: 0x898781)
    /// Solid 1 px rules, never dashed.
    static let gridline = Color(light: NSColor(hex: 0xE1E0D9), dark: NSColor(hex: 0x2C2C2A))
    static let baseline = Color(light: NSColor(hex: 0xC3C2B7), dark: NSColor(hex: 0x383835))
    static let border = Color(light: NSColor(0, 0, 0, alpha: 0.10), dark: NSColor(1, 1, 1, alpha: 0.10))

    /// Categorical series in this fixed order (blue, orange, aqua); never more than three at once.
    static let series: [Color] = [Color(light: NSColor(hex: 0x2A78D6), dark: NSColor(hex: 0x3987E5)),
                                  Color(light: NSColor(hex: 0xEB6834), dark: NSColor(hex: 0xD95926)),
                                  Color(light: NSColor(hex: 0x1BAF7A), dark: NSColor(hex: 0x199E70))]
    /// The one colour for single-series charts.
    static var accent: Color { series[0] }
    /// What everything that isn't the point is drawn in.
    static let deemphasis = Color(light: NSColor(hex: 0xC3C2B7), dark: NSColor(hex: 0x4A4945))

    /// The blue scale, light to dark (steps 100…700), for amounts: the note map, the calendar.
    private static let ramp: [Int] = [0xCDE2FB, 0xB7D3F6, 0x9EC5F4, 0x86B6EF, 0x6DA7EC, 0x5598E7, 0x3987E5,
                                      0x2A78D6, 0x256ABF, 0x1C5CAB, 0x184F95, 0x104281, 0x0D366B]

    /// `fraction` (0…1) on the blue scale: darker for more in light mode, lighter for more in dark.
    /// `fromStep` skips the steps nearest the card, where a cell must still stand out from it (an
    /// ordered scale starts no lighter than step 250 = 3 on white, no darker than step 550 on dark).
    static func rampColor(_ fraction: Double, fromStep: Int = 0) -> Color {
        func step(_ ramp: [Int]) -> NSColor {
            let steps = ramp[fromStep...]
            let index = Int((min(max(fraction, 0), 1) * Double(steps.count - 1)).rounded())
            return NSColor(hex: steps[steps.startIndex + index])
        }
        return Color(light: step(ramp), dark: step(ramp.reversed()))
    }
    /// Text on a ramp cell: light text on the darker half, dark text on the lighter.
    static func textOnRamp(_ fraction: Double) -> Color {
        Color(light: fraction > 0.5 ? .white : NSColor(hex: 0x0B0B0B),
              dark: fraction > 0.5 ? NSColor(hex: 0x0B0B0B) : NSColor(hex: 0xF0EFEC))
    }

    /// Status: only for "better / worse than before", always with an arrow and words.
    static let good = Color(hex: 0x0CA30C)
    static let goodText = Color(light: NSColor(hex: 0x006300), dark: NSColor(hex: 0x0CA30C))
    static let critical = Color(hex: 0xD03B3B)
}

extension Color {
    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// The card every dashboard section sits in: title, optional subtitle, and a Chart / Table switch
/// so every chart can also be read as numbers.
struct DashboardCard<Chart: View, Table: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var chart: Chart
    @ViewBuilder var table: Table
    var hasTable = true
    @State private var showsTable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(DashboardTheme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(DashboardTheme.textSecondary)
                    }
                }
                Spacer(minLength: 12)
                if hasTable {
                    Picker("Show as", selection: $showsTable) {
                        Text("Chart").tag(false)
                        Text("Table").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                }
            }
            if showsTable {
                table
            } else {
                chart
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DashboardTheme.border, lineWidth: 1)
        }
    }
}

extension DashboardCard where Table == EmptyView {
    /// A card without a table view (for content that already is numbers).
    init(title: String, subtitle: String? = nil, @ViewBuilder chart: () -> Chart) {
        self.init(title: title, subtitle: subtitle, chart: chart, table: { EmptyView() }, hasTable: false)
    }
}
