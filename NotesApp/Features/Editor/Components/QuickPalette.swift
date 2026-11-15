import SwiftUI

enum QuickPaletteLayout {
    static let collapsedSize = CGSize(width: 108, height: 60)
    static func expandedSize(favorites: Int) -> CGSize {
        let items = min(6, max(1, favorites) + 1)
        let rows = (items + 2) / 3
        return CGSize(width: 156, height: 112 + CGFloat(rows) * 44 + CGFloat(rows - 1) * 4)
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
    @State private var gridFrame = CGRect.zero
    @State private var dropTargeted = false
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
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    PaletteDragHandle(canMove: canInteract) { translation = $0 } ended: { offset, cancelled in
                        if !cancelled {
                            palette.place(PalettePlacement.position(for: CGPoint(x: base.x + offset.width, y: base.y + offset.height),
                                                                    palette: size, viewport: geometry.size))
                        }
                        translation = .zero
                    }.frame(width: 44, height: 44)
                    if collapsed {
                        if onExitFocus != nil {
                            exitFocusButton
                        } else {
                            Button {
                                guard canInteract() else { return }
                                if forcedCompact { showingManager = true } else { palette.isCollapsed = false }
                            } label: { Image(systemName: "square.grid.2x2").frame(width: 44, height: 44) }
                            .accessibilityLabel(forcedCompact ? "Customize Quick Palette" : "Expand Quick Palette")
                            .contextMenu { paletteMenu }
                        }
                    } else {
                        Menu { paletteMenu } label: {
                            Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                            .accessibilityLabel("Quick Palette Options")
                        if onExitFocus != nil {
                            exitFocusButton
                        } else {
                            Button { if canInteract() { palette.isCollapsed = true } } label: {
                                Image(systemName: "minus").frame(width: 44, height: 44)
                            }.accessibilityLabel("Collapse Quick Palette")
                        }
                    }
                }
                if !collapsed {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 4), count: 3), spacing: 4) {
                        ForEach(palette.favorites) { favorite in favoriteButton(favorite) }
                        if palette.favorites.count < QuickPalettePreferences.maximumFavorites {
                            Button { if canInteract() { edit(tools.capturePreset()) } } label: {
                                Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Save Current Tool as Favorite")
                            .help("Save current tool")
                        }
                    }
                    .background(GeometryReader { grid in
                        Color.clear.preference(key: PaletteGridFrame.self, value: grid.frame(in: .named("quickPaletteDrop")))
                    })
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: palette.favorites.map(\.id))
                    Menu { profileMenu } label: {
                        HStack(spacing: 6) {
                            Text(palette.activeProfile.name).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .font(.caption.weight(.medium)).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppTheme.controlSurface, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("Palette Profile: \(palette.activeProfile.name)")
                }
            }
            .padding(8)
            .frame(width: size.width, height: size.height)
            .coordinateSpace(name: "quickPaletteDrop")
            .buttonStyle(.plain)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.09)).allowsHitTesting(false))
            .overlay {
                RoundedRectangle(cornerRadius: 18).strokeBorder(AppTheme.accent, lineWidth: 2)
                    .opacity(dropTargeted ? 1 : 0).allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                if let dropNotice {
                    Text(dropNotice).font(.caption).multilineTextAlignment(.center)
                        .padding(8).frame(width: size.width)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
            .onPreferenceChange(PaletteGridFrame.self) { gridFrame = $0 }
            .onDrop(of: [.paletteTool], delegate: PaletteToolDrop(palette: palette, profileID: palette.activeProfile.id,
                grid: collapsed ? .zero : gridFrame, canInteract: canInteract,
                hovering: { targeted, favoriteID in
                    if targeted, dropNotice != nil { dropNotice = nil }
                    if dropTargeted != targeted { dropTargeted = targeted }
                    if targetFavoriteID != favoriteID { targetFavoriteID = favoriteID }
                }, completed: { _, message in
                    dropNotice = message
                    if let message { UIAccessibility.post(notification: .announcement, argument: message) }
                }))
            .offset(x: origin.x, y: origin.y)
            .opacity(fits ? 1 : 0)
            .allowsHitTesting(fits)
            .accessibilityHidden(!fits)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: collapsed)
            .onChange(of: geometry.size) { _, _ in translation = .zero }
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
            VStack(spacing: 2) {
                Image(systemName: favorite.tool.symbol).font(.system(size: 19))
                    .foregroundStyle(.primary)
                    .overlay(alignment: .topTrailing) {
                        if favorite.tool.usesInkStyle {
                            Circle().fill(favorite.ink.color).frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.3)))
                                .offset(x: 7, y: -2)
                        }
                    }
                if favorite.tool.usesInkStyle || favorite.tool == .eraser {
                    Text(favorite.tool == .eraser ? (favorite.eraserMode == .strokes ? "Stroke" : favorite.eraserWidth.formatted(.number.precision(.fractionLength(0)))) : favorite.ink.width.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .background(selected ? AppTheme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? AppTheme.accent.opacity(0.45) : .clear))
            .contentShape(Rectangle())
        }
        .accessibilityLabel(favorite.name)
        .accessibilityValue("\(favorite.tool.title), \(favorite.detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(favorite.name)
        .contextMenu {
            Button("Edit Favorite", systemImage: "slider.horizontal.3") { edit(favorite) }
            Button("Replace with Current Tool", systemImage: "arrow.triangle.2.circlepath") {
                var replacement = tools.capturePreset(); replacement.id = favorite.id; edit(replacement)
            }
            Button("Remove Favorite", systemImage: "minus.circle", role: .destructive) { palette.remove(favorite.id) }
                .disabled(palette.favorites.count <= 1)
        }
        .modifier(PaletteToolDragSource(snapshot: { favorite }, palette: palette, fromFavorite: true, canInteract: canInteract))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.accent, lineWidth: 2)
                .opacity(dropTargeted && targetFavoriteID == favorite.id ? 1 : 0).allowsHitTesting(false)
        }
    }

    @ViewBuilder private var paletteMenu: some View {
        Menu("Profiles", systemImage: "rectangle.stack") { profileMenu }
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
