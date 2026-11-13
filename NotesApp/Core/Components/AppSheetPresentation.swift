import SwiftUI

/// Start app-owned forms at the available large height instead of a half-height stop.
/// Keep native scrolling, keyboard avoidance and interactive dismissal.
struct AppSheetPresentation: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .presentationSizing(.page)
                .presentationDetents([.large])
        } else {
            content.presentationDetents([.large])
        }
    }
}

extension View {
    func appSheetPresentation() -> some View { modifier(AppSheetPresentation()) }
    func compactAppSheetPresentation(idealHeight: CGFloat) -> some View {
        modifier(CompactAppSheetPresentation(idealHeight: idealHeight))
    }
}

/// Short dialogs fit their controls; long forms keep the existing expanded policy.
private struct CompactAppSheetPresentation: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric private var idealHeight: CGFloat

    init(idealHeight: CGFloat) {
        _idealHeight = ScaledMetric(wrappedValue: idealHeight, relativeTo: .body)
    }

    @ViewBuilder func body(content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            content.appSheetPresentation()
        } else if #available(iOS 18.0, *) {
            content
                .frame(idealWidth: 440, idealHeight: idealHeight)
                .presentationSizing(.fitted)
                .presentationDetents([.height(idealHeight)])
        } else {
            content.presentationDetents([.height(idealHeight)])
        }
    }
}
