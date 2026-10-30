import SwiftUI

/// Progress on each piece practised: accuracy bar by bar.
struct PieceSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    var body: some View {
        DashboardCard(title: "Pieces") {
            Text("Coming soon")
                .foregroundStyle(DashboardTheme.textMuted)
        }
    }
}
