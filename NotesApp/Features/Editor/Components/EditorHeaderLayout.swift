import SwiftUI

/// Places the same three control trees on one or two rows in the initial layout pass.
/// This avoids measured-state jumps and duplicate popover anchors during rotation/tab changes.
struct EditorHeaderLayout: Layout {
    var toolbarVisible: Bool
    var prefersFullToolbarRow: Bool

    private func fullRow(_ width: CGFloat) -> Bool { toolbarVisible && (prefersFullToolbarRow || width < 1140) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 1156
        return CGSize(width: width, height: fullRow(width) ? 108 : 52)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let back = subviews[0], tools = subviews[1], actions = subviews[2]
        let backWidth = back.sizeThatFits(.unspecified).width
        let actionWidth = actions.sizeThatFits(.unspecified).width
        back.place(at: CGPoint(x: bounds.minX, y: bounds.minY + 26), anchor: .leading,
                   proposal: ProposedViewSize(width: backWidth, height: 44))
        actions.place(at: CGPoint(x: bounds.maxX, y: bounds.minY + 26), anchor: .trailing,
                      proposal: ProposedViewSize(width: actionWidth, height: 44))
        guard toolbarVisible else {
            tools.place(at: bounds.origin, proposal: ProposedViewSize(width: 0, height: 0)); return
        }
        if fullRow(bounds.width) {
            tools.place(at: CGPoint(x: bounds.minX, y: bounds.minY + 56), anchor: .topLeading,
                        proposal: ProposedViewSize(width: bounds.width, height: 52))
        } else {
            let left = backWidth > 0 ? backWidth + 8 : 0
            let width = max(44, bounds.width - left - actionWidth - 8)
            tools.place(at: CGPoint(x: bounds.minX + left, y: bounds.minY + 26), anchor: .leading,
                        proposal: ProposedViewSize(width: width, height: 52))
        }
    }
}
