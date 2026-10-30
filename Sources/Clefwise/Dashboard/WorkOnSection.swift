import SwiftUI

/// Notes to work on: the most-missed and the slowest notes (spelled, so F♯5 apart from F5) as ranked bars.
struct WorkOnSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    var body: some View {
        DashboardCard(title: "Notes to work on") {
            Text("Coming soon")
                .foregroundStyle(DashboardTheme.textMuted)
        }
    }
}
