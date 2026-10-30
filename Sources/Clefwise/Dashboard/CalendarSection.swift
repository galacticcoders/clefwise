import SwiftUI

/// A practice calendar: one cell per day in the window, darker for more notes answered.
struct CalendarSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    var body: some View {
        DashboardCard(title: "Practice calendar") {
            Text("Coming soon")
                .foregroundStyle(DashboardTheme.textMuted)
        }
    }
}
