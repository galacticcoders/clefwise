import SwiftUI

/// Accuracy and response time per day, as two charts side by side (never one chart with two scales).
struct TrendSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    var body: some View {
        DashboardCard(title: "Over time") {
            Text("Coming soon")
                .foregroundStyle(DashboardTheme.textMuted)
        }
    }
}
