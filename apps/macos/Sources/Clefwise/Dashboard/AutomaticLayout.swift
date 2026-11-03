import SwiftUI

/// Three panels side by side when they fit at their ideal widths; otherwise two side by side with
/// the third under the first, at the same width; otherwise one above the other. Nothing is ever
/// squeezed below its ideal width or made to overflow.
struct ThreeAcross<First: View, Second: View, Third: View>: View {
    var spacing: CGFloat = 28
    var rowSpacing: CGFloat = 24
    @ViewBuilder var first: First
    @ViewBuilder var second: Second
    @ViewBuilder var third: Third

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                first
                second
                third
            }
            Grid(alignment: .topLeading, horizontalSpacing: spacing, verticalSpacing: rowSpacing) {
                GridRow {
                    first
                    second
                }
                GridRow {
                    third
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                }
            }
            VStack(alignment: .leading, spacing: rowSpacing) {
                first
                second
                third
            }
        }
    }
}
