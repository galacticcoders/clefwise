import SwiftUI

/// Chart colours and chrome for the dashboard. The palette is the data-viz reference palette,
/// checked on the white card surface with its validator: the three categorical slots pass every
/// colour-blindness gate (aqua is under 3:1 contrast, so wherever it's used its series needs
/// visible labels or the table view); the blue ramp passes as an ordered scale from step 250.
/// The app is light-only, so there is no dark set.
enum DashboardTheme {
    /// Cards (the chart surface) and the window behind them.
    static let surface = Color.white
    static let page = Theme.background

    static let textPrimary = Color(hex: 0x0B0B0B)
    static let textSecondary = Color(hex: 0x52514E)
    /// Axis labels and other quiet text.
    static let textMuted = Color(hex: 0x898781)
    /// Solid 1 px rules, never dashed.
    static let gridline = Color(hex: 0xE1E0D9)
    static let baseline = Color(hex: 0xC3C2B7)
    static let border = Color.black.opacity(0.10)

    /// Categorical series in this fixed order (blue, orange, aqua); never more than three at once.
    static let series: [Color] = [Color(hex: 0x2A78D6), Color(hex: 0xEB6834), Color(hex: 0x1BAF7A)]
    /// The one colour for single-series charts.
    static var accent: Color { series[0] }
    /// What everything that isn't the point is drawn in.
    static let deemphasis = Color(hex: 0xC3C2B7)

    /// The blue scale, light to dark (steps 100…700), for amounts: the note map, the calendar.
    static let ramp: [Color] = [0xCDE2FB, 0xB7D3F6, 0x9EC5F4, 0x86B6EF, 0x6DA7EC, 0x5598E7, 0x3987E5,
                                0x2A78D6, 0x256ABF, 0x1C5CAB, 0x184F95, 0x104281, 0x0D366B].map(Color.init(hex:))

    /// `fraction` (0…1) on the blue scale. `fromStep` skips the palest steps where a cell must
    /// still stand out from the white card (an ordered scale starts no lighter than step 250 = 3).
    static func rampColor(_ fraction: Double, fromStep: Int = 0) -> Color {
        let steps = ramp[fromStep...]
        let index = Int((min(max(fraction, 0), 1) * Double(steps.count - 1)).rounded())
        return steps[steps.startIndex + index]
    }
    /// Text on a ramp cell: white on the darker half, ink on the lighter.
    static func textOnRamp(_ fraction: Double) -> Color { fraction > 0.5 ? .white : textPrimary }

    /// Status: only for "better / worse than before", always with an arrow and words.
    static let good = Color(hex: 0x0CA30C)
    static let goodText = Color(hex: 0x006300)
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
