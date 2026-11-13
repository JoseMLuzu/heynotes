import SwiftUI

/// Bounds are resolved only by a consumer; they do not write state or drive the layout.
/// Native presentation regressions use these anchors to verify a flip never moves controls.
struct StudyReviewAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func studyReviewAnchor(_ identifier: String) -> some View {
        accessibilityIdentifier(identifier)
            .anchorPreference(key: StudyReviewAnchors.self, value: .bounds) { [identifier: $0] }
    }
}
