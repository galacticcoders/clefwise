import Charts
import SwiftUI

/// "What you practised": notes answered per day (per week past 45 days, as "Over time" goes), as
/// columns stacked by answer method in `AnswerMethod` order, bottom to top, each in its colour. The
/// column's height is the whole; its parts show whether a period was naming, playing or both.
/// Placeholder: to be built (see the contract in the branch's first commit).
struct PracticeMixSection: View {
    let report: ProgressReport
    /// Note names on the dashboard follow the naming system in use.
    let naming: NamingSystem

    var body: some View {
        EmptyView()
    }
}

/// The answer methods' key, shared by every chart that colours by method: a swatch and the name of
/// each of `methods`, under "Naming" and "Playing" (`AnswerMethod.byFamily`), in `AnswerMethod`
/// order. Placeholder: to be built.
struct MethodLegend: View {
    let methods: [AnswerMethod]

    var body: some View {
        EmptyView()
    }
}
