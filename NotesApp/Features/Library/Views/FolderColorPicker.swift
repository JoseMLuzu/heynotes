import SwiftUI

struct FolderColorPicker: View {
    let folder: Folder
    let save: (FolderColor) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "folder.fill").font(.system(size: 52)).foregroundStyle(folder.color.color)
                        .accessibilityHidden(true)
                    Text(folder.title).font(.headline).lineLimit(2)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 14) {
                        ForEach(FolderColor.allCases) { color in
                            ColorChoiceButton(title: color.title, color: color.color, selected: folder.color == color) {
                                if save(color) { dismiss() } else { failed = true }
                            }
                        }
                    }
                    Text("A small cue to find your folders faster.").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("Folder Color").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Could Not Save Color", isPresented: $failed) { Button("OK") {} } message: {
                Text("The previous folder color was preserved. Try again after closing this panel.")
            }
        }
        .appSheetPresentation()
        .tint(AppTheme.accent)
    }
}

struct FolderSidebarLabel: View {
    let folder: Folder
    let selected: Bool
    var body: some View {
        HStack(spacing: 8) {
            Label(folder.title, systemImage: selected ? "folder.fill" : "folder")
            Spacer(minLength: 4)
            Circle().fill(folder.color.color).frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground).opacity(0.7), lineWidth: 0.7))
                .accessibilityHidden(true)
        }
        .accessibilityValue("\(folder.color.title) folder")
    }
}
