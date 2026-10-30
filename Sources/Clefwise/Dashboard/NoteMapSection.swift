import SwiftUI

/// The note map: every staff line and space per clef, darker for better known, blank where there's too little data yet.
struct NoteMapSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    var body: some View {
        DashboardCard(title: "Note map") {
            Text("Coming soon")
                .foregroundStyle(DashboardTheme.textMuted)
        }
    }
}
