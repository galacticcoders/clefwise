import SwiftUI

/// Hover tips for chart marks: a mark registers with `hoverTarget`, and the chart around it draws
/// the hovered mark's tip with `hoverTip`, above every other mark and kept inside the chart. Tips
/// only repeat what the table view shows, so nothing depends on hovering.
extension View {
    /// Sets `hovered` to `id` while the pointer is anywhere in this view's frame, so the target can
    /// be bigger than the mark drawn in it.
    func hoverTarget<ID: Hashable>(_ id: ID, hovered: Binding<ID?>) -> some View {
        contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    hovered.wrappedValue = id
                } else if hovered.wrappedValue == id {
                    hovered.wrappedValue = nil
                }
            }
            // Every target's frame, hovered or not: what's hovered is looked up when drawing, as a
            // preference that depended on the hover state didn't reliably update when it changed.
            .anchorPreference(key: HoverTipAnchors.self, value: .bounds) { [AnyHashable(id): $0] }
    }

    /// Draws `tip` (built for whatever is hovered now) over `hovered`'s target inside this view.
    func hoverTip<ID: Hashable, Tip: View>(for hovered: ID?, @ViewBuilder _ tip: @escaping () -> Tip) -> some View {
        overlayPreferenceValue(HoverTipAnchors.self) { anchors in
            GeometryReader { proxy in
                if let hovered, let anchor = anchors[AnyHashable(hovered)] {
                    HoverTipBubble(target: proxy[anchor], area: proxy.size, content: tip())
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// A tip's text: the value first and strongest, then what it's for, then any details.
struct HoverTipText: View {
    let value: String
    let label: String
    var details: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(DashboardTheme.textPrimary)
            Text(label)
                .font(.callout)
                .foregroundStyle(DashboardTheme.textSecondary)
            ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DashboardTheme.textMuted)
            }
        }
    }
}

private struct HoverTipAnchors: PreferenceKey {
    static var defaultValue: [AnyHashable: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [AnyHashable: Anchor<CGRect>], nextValue: () -> [AnyHashable: Anchor<CGRect>]) {
        value.merge(nextValue()) { current, _ in current }
    }
}

/// Above the target, or below it when the chart has no room above; centred on it, but never past
/// the chart's sides.
private struct HoverTipBubble<Content: View>: View {
    let target: CGRect
    let area: CGSize
    let content: Content
    private let gap: CGFloat = 6

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(DashboardTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(DashboardTheme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .fixedSize()
            .alignmentGuide(.leading) { size in
                -min(max(target.midX - size.width / 2, 0), max(area.width - size.width, 0))
            }
            .alignmentGuide(.top) { size in
                let above = target.minY - gap - size.height
                return -(above >= 0 ? above : target.maxY + gap)
            }
            .frame(width: area.width, height: area.height, alignment: .topLeading)
    }
}
