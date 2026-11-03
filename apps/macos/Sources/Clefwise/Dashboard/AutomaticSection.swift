import SwiftUI

/// "Becoming automatic": the signs, in response times, that naming a note no longer takes working
/// out (`ProgressReport.responseTimes`). Contract placeholder: the section's agent fills it in.
struct AutomaticSection: View {
    let report: ProgressReport
    let naming: NamingSystem

    var body: some View {
        DashboardCard(title: "Becoming automatic", subtitle: "Signs that naming notes no longer takes working out") {
            Text("Coming soon")
                .foregroundStyle(DashboardTheme.textMuted)
        }
    }
}
