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
}
