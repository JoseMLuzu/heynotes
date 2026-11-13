import SwiftUI

struct NavigationBackButton: View {
    let destination: String?
    let action: () -> Void

    var body: some View {
        EditorMoreButton(title: destination.map { "Back to \($0)" } ?? "Back",
                         identifier: "library.back", symbol: "chevron.backward", action: action)
            .frame(width: 44, height: 44)
            .modifier(EditorGlassSurface(shape: Circle()))
            .disabled(destination == nil)
            .help(destination.map { "Back to \($0)" } ?? "Library")
    }
}
