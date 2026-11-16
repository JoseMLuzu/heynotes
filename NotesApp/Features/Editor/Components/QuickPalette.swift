import SwiftUI

enum QuickPaletteLayout {
    static let cellSize: CGFloat = 44
    static let cellSpacing: CGFloat = 8
    static let columns = 3
    static let collapsedSize = CGSize(width: 108, height: 60)
    static var gridWidth: CGFloat { CGFloat(columns) * cellSize + CGFloat(columns - 1) * cellSpacing }
    static func expandedSize(favorites: Int) -> CGSize {
        let items = min(6, max(1, favorites) + 1)
        let rows = (items + columns - 1) / columns
        // 12-point insets, one 44-point header, and an 8-point gap before the tools.
        return CGSize(width: 176, height: 76 + CGFloat(rows) * cellSize + CGFloat(rows - 1) * cellSpacing)
    }
}

/// Only the small palette is hit-testable; the surrounding overlay lets ink/pan through.
struct QuickPalette: View {
    let palette: QuickPalettePreferences
    let tools: ToolPreferences
    var onExitFocus: (() -> Void)? = nil
    let canInteract: () -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var translation = CGSize.zero
    @State private var showingManager = false
    @State private var editing: PaletteFavoriteDraft?
    @State private var showingProfiles = false
    @State private var targetFavoriteID: UUID?
    @State private var dropNotice: String?

    var body: some View {
        GeometryReader { geometry in
            let expanded = QuickPaletteLayout.expandedSize(favorites: palette.favorites.count)
            let forcedCompact = expanded.width + 24 > geometry.size.width || expanded.height + 24 > geometry.size.height
            let collapsed = forcedCompact || (onExitFocus == nil && palette.isCollapsed)
            let size = collapsed ? QuickPaletteLayout.collapsedSize : expanded
            let fits = size.width <= geometry.size.width && size.height <= geometry.size.height
            let base = PalettePlacement.origin(palette.position, palette: size, viewport: geometry.size)
            let origin = PalettePlacement.clamped(CGPoint(x: base.x + translation.width, y: base.y + translation.height),
                                                  palette: size, viewport: geometry.size)
            VStack(spacing: collapsed ? 0 : 8) {
                HStack(spacing: 0) {
                    PaletteDragHandle(canMove: canInteract) { translation = $0 } ended: { offset, cancelled in
                        if !cancelled {
                            palette.place(PalettePlacement.position(for: CGPoint(x: base.x + offset.width, y: base.y + offset.height),
                                                                    palette: size, viewport: geometry.size))
                        }
                        translation = .zero
                    }.frame(width: 44, height: 44)
                    if collapsed {
                        if onExitFocus != nil { exitFocusButton }
                        else {
                            Button {
                                guard canInteract() else { return }
                                if forcedCompact { showingManager = true } else { palette.isCollapsed = false }
                            } label: { Image(systemName: "square.grid.2x2").frame(width: 44, height: 44) }
                            .accessibilityLabel(forcedCompact ? "Customize Quick Palette" : "Expand Quick Palette")
                            .contextMenu { paletteMenu }
                        }
                    } else {
                        Menu { paletteMenu } label: {
                            HStack(spacing: 3) {
                                Text(palette.activeProfile.name).lineLimit(1).minimumScaleFactor(0.85)
                                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Palette profile and options: \(palette.activeProfile.name)")
                        .help("Switch profiles or customize the palette")
                        if onExitFocus != nil { exitFocusButton }
                        else {
                            Button { if canInteract() { palette.isCollapsed = true } } label: {
                                Image(systemName: "minus").font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary).frame(width: 44, height: 44)
                            }.accessibilityLabel("Collapse Quick Palette")
                        }
                    }
                }
                if !collapsed {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(QuickPaletteLayout.cellSize), spacing: QuickPaletteLayout.cellSpacing), count: QuickPaletteLayout.columns), spacing: QuickPaletteLayout.cellSpacing) {
                        ForEach(palette.favorites) { favorite in favoriteButton(favorite) }
                        if palette.favorites.count < QuickPalettePreferences.maximumFavorites {
                            Button { if canInteract() { edit(tools.capturePreset()) } } label: {
                                Image(systemName: "plus").font(.system(size: 17, weight: .regular))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: QuickPaletteLayout.cellSize, height: QuickPaletteLayout.cellSize)
                                    .background(AppTheme.accent.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))
                                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                            }
                            .accessibilityLabel("Save Current Tool as Favorite")
                            .accessibilityIdentifier("palette.append")
                            .onDrop(of: [.paletteTool], delegate: dropDestination())
                            .help("Save current tool")
                        }
                    }
                    .frame(width: QuickPaletteLayout.gridWidth)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: palette.favorites.map(\.id))
                }
            }
            .padding(collapsed ? 8 : 12)
            .frame(width: size.width, height: size.height)
            .buttonStyle(EditorToolbarButtonStyle())
            .modifier(EditorGlassSurface(shape: RoundedRectangle(cornerRadius: collapsed ? 30 : 24)))
            .overlay(alignment: .bottom) {
                if let dropNotice {
                    Text(dropNotice).font(.caption).multilineTextAlignment(.center)
                        .padding(8).frame(width: size.width)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
            .offset(x: origin.x, y: origin.y)
            .opacity(fits ? 1 : 0)
            .allowsHitTesting(fits)
            .accessibilityHidden(!fits)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: collapsed)
            .onChange(of: geometry.size) { _, _ in translation = .zero }
            .onChange(of: palette.activeProfile.id) { _, _ in
                targetFavoriteID = nil; dropNotice = nil
            }
            .task(id: dropNotice) {
                guard dropNotice != nil else { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                dropNotice = nil
            }
        }
        .tint(AppTheme.accent)
        .sheet(isPresented: $showingManager) { PaletteManager(palette: palette, tools: tools) }
        .sheet(item: $editing) { draft in ToolPresetEditor(draft: draft.preset) { palette.save($0, in: draft.profileID) } }
        .sheet(isPresented: $showingProfiles) { PaletteProfileManager(palette: palette, tools: tools) }
    }

    private var exitFocusButton: some View {
        EditorMoreButton(title: "Exit Focus Mode", identifier: "editor.exitFocusMode",
                         symbol: "arrow.down.right.and.arrow.up.left") { onExitFocus?() }
            .frame(width: 44, height: 44)
            .help("Restore tabs, navigation and the main toolbar")
    }

    private func favoriteButton(_ favorite: ToolPreset) -> some View {
        let selected = tools.matches(favorite)
        return Button {
            if canInteract() { tools.apply(favorite) }
        } label: {
            PaletteFavoriteIcon(favorite: favorite, selected: selected, dropTargeted: targetFavoriteID == favorite.id)
        }
        .accessibilityLabel(favorite.name)
        .accessibilityIdentifier("palette.favorite.\(favorite.id.uuidString)")
        .accessibilityValue("\(favorite.tool.title), \(favorite.detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("\(favorite.name). Drop a toolbar tool here to replace it.")
        .contextMenu {
            Button("Edit Favorite", systemImage: "slider.horizontal.3") { edit(favorite) }
            Button("Replace with Current Tool", systemImage: "arrow.triangle.2.circlepath") {
                var replacement = tools.capturePreset(); replacement.id = favorite.id; edit(replacement)
            }
            Button("Remove Favorite", systemImage: "minus.circle", role: .destructive) { palette.remove(favorite.id) }
                .disabled(palette.favorites.count <= 1)
        }
        .modifier(PaletteToolDragSource(snapshot: { favorite }, palette: palette, fromFavorite: true, canInteract: canInteract))
        .onDrop(of: [.paletteTool], delegate: dropDestination(favoriteID: favorite.id))
    }

    private func dropDestination(favoriteID: UUID? = nil) -> PaletteToolDrop {
        PaletteToolDrop(palette: palette, profileID: palette.activeProfile.id, favoriteID: favoriteID,
            canInteract: canInteract, hovering: { id, entered in
                if entered {
                    dropNotice = nil
                    if let id { targetFavoriteID = id }
                } else if targetFavoriteID == id { targetFavoriteID = nil }
            }, completed: { _, message in
                targetFavoriteID = nil; dropNotice = message
                if let message { UIAccessibility.post(notification: .announcement, argument: message) }
            })
    }

    @ViewBuilder private var paletteMenu: some View {
        Section("Profiles") { profileMenu }
        Divider()
        Button("Customize Favorites", systemImage: "slider.horizontal.3") { showingManager = true }
        Button("Save Current Tool", systemImage: "plus") { edit(tools.capturePreset()) }
            .disabled(palette.favorites.count >= QuickPalettePreferences.maximumFavorites)
        Menu("Move to Corner", systemImage: "arrow.up.left.and.arrow.down.right") {
            Button("Top Left") { palette.place(PalettePosition(x: 0, y: 0)) }
            Button("Top Right") { palette.place(PalettePosition(x: 1, y: 0)) }
            Button("Bottom Left") { palette.place(PalettePosition(x: 0, y: 1)) }
            Button("Bottom Right") { palette.place(PalettePosition(x: 1, y: 1)) }
        }
        Button("Restore Position", systemImage: "arrow.counterclockwise") { palette.place(PalettePosition()) }
        if let onExitFocus {
            Button("Exit Focus Mode", systemImage: "arrow.down.right.and.arrow.up.left", action: onExitFocus)
        } else {
            Button("Hide Quick Palette", systemImage: "eye.slash") { palette.isVisible = false }
        }
    }

    @ViewBuilder private var profileMenu: some View {
        ForEach(palette.profiles) { profile in
            Button {
                if canInteract() { palette.selectProfile(profile.id) }
            } label: {
                if profile.id == palette.activeProfile.id { Label(profile.name, systemImage: "checkmark") }
                else { Text(profile.name) }
            }
        }
        Divider()
        Button("Manage Profiles", systemImage: "rectangle.stack.badge.plus") { showingProfiles = true }
    }
    private func edit(_ preset: ToolPreset) { editing = PaletteFavoriteDraft(preset: preset, profileID: palette.activeProfile.id) }
}
