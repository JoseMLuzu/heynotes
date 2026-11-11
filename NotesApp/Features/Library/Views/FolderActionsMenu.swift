import SwiftUI

struct FolderActionsMenu: View {
    let folder: Folder
    let model: LibraryViewModel
    let newSubfolder: () -> Void
    let rename: () -> Void
    let changeColor: () -> Void
    let trash: () -> Void

    var body: some View {
        Button("New Subfolder", systemImage: "folder.badge.plus", action: newSubfolder)
        Button("Rename", systemImage: "pencil", action: rename)
        Button("Change Color", systemImage: "paintpalette", action: changeColor)
        Button(folder.isFavorite ? "Remove Favorite" : "Add to Favorites", systemImage: "star") { model.toggleFavorite(folder) }
        Menu("Move Folder", systemImage: "folder") {
            Button("Library") { model.move(folder, to: nil) }
            ForEach(model.validParents(for: folder)) { parent in
                Button(parent.pathTitle) { model.move(folder, to: parent) }
            }
        }
        Button("Move to Trash", systemImage: "trash", role: .destructive, action: trash)
    }
}

struct FolderCard: View {
    let folder: Folder
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            FolderCover(color: folder.color.color, favorite: folder.isFavorite)
            LibraryItemCaption(title: folder.title, detail: folder.pathTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(folder.title), folder\(folder.isFavorite ? ", favorite" : "")")
        .accessibilityValue("\(folder.pathTitle), \(folder.color.title)")
    }
}

/// The same portrait footprint as a notebook, with a tab and inset paper to distinguish folders.
private struct FolderCover: View {
    let color: Color
    let favorite: Bool
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.35))
                    .frame(width: width * 0.48, height: height * 0.2)
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.2))
                    .padding(.top, height * 0.08)
                RoundedRectangle(cornerRadius: 7)
                    .fill(AppTheme.surface)
                    .padding(.horizontal, 13).padding(.top, height * 0.10).padding(.bottom, 12)
                RoundedRectangle(cornerRadius: 7)
                    .fill(AppTheme.background)
                    .padding(.horizontal, 9).padding(.top, height * 0.13).padding(.bottom, 10)
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.background)
                    .overlay(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.18)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.12)))
                    .padding(.top, height * 0.17)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("FOLDER").font(.system(size: max(9, width * 0.044), weight: .medium)).tracking(2)
                        Spacer(minLength: 0)
                        if favorite { Image(systemName: "star.fill").font(.caption2) }
                    }
                    Spacer()
                    Image(systemName: "folder").font(.system(size: width * 0.27, weight: .ultraLight))
                    Spacer()
                    RoundedRectangle(cornerRadius: 1).frame(width: 24, height: 2).opacity(0.4)
                }
                .foregroundStyle(color)
                .padding(.horizontal, width * 0.14)
                .padding(.top, height * 0.28).padding(.bottom, height * 0.13)
            }
            .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 5)
        }
        .aspectRatio(0.82, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
