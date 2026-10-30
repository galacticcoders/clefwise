import SwiftUI

/// The headline tiles: practice time, notes answered, accuracy and typical response time against the previous period, and the daily streak.
struct KPISection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    var body: some View {
        DashboardCard(title: "Overview") {
            Text("Coming soon")
                .foregroundStyle(DashboardTheme.textMuted)
        }
    }
}
