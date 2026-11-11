import SwiftUI

private enum TemplateFilter: Hashable {
    case all, category(TemplateCategory)
}

struct TemplateGallery: View {
    let choose: (PaperTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var filter: TemplateFilter? = .all
    @State private var selection: PaperTemplate
    @State private var search = ""
    @State private var compactColumn: NavigationSplitViewColumn = .detail

    init(current: PaperTemplate = .blank, choose: @escaping (PaperTemplate) -> Void) {
        self.choose = choose
        _selection = State(initialValue: current)
    }

    private var categories: [TemplateCategory] {
        if case .category(let category) = filter { return [category] }
        return TemplateCategory.allCases
    }
    private func templates(in category: TemplateCategory) -> [PaperTemplate] {
        PaperTemplate.allCases.filter {
            $0.category == category && (search.isEmpty || $0.title.localizedStandardContains(search) || $0.detail.localizedStandardContains(search))
        }
    }
    private var hasResults: Bool { categories.contains { !templates(in: $0).isEmpty } }
    private var showsAll: Bool { filter == nil || filter == .all }
    private var title: String {
        if case .category(let category) = filter { return category.title }
        return "All Templates"
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List(selection: $filter) {
                Label("All Templates", systemImage: "square.grid.2x2").tag(TemplateFilter.all)
                Section("Browse") {
                    ForEach(TemplateCategory.allCases, id: \.self) { category in
                        Label(category.title, systemImage: category.symbol).tag(TemplateFilter.category(category))
                    }
                }
            }
            .navigationTitle("Templates")
            .toolbar {
                if sizeClass == .compact {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 270)
            .scrollContentBackground(.hidden).background(AppTheme.background)
        } detail: {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !hasResults { ContentUnavailableView.search(text: search).frame(minHeight: 280) }
                        ForEach(categories, id: \.self) { category in
                            let items = templates(in: category)
                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack {
                                        Label(category.title, systemImage: category.symbol).font(.headline)
                                        Spacer()
                                        if showsAll {
                                            Button("See All") { filter = .category(category) }.font(.subheadline)
                                        }
                                    }
                                    if showsAll {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            LazyHStack(alignment: .top, spacing: 18) {
                                                ForEach(items, id: \.self) { card($0).frame(width: 140) }
                                            }.padding(.vertical, 4)
                                        }
                                    } else {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 20)], alignment: .leading, spacing: 24) {
                                            ForEach(items, id: \.self) { card($0) }
                                        }
                                    }
                                }
                            }
                        }
                    }.padding(24)
                }
                .background(AppTheme.background)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, prompt: "Search templates")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use Template") { choose(selection); dismiss() }.fontWeight(.semibold)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 12) {
                        Image(systemName: selection.category.symbol).foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selection.title).font(.subheadline.weight(.semibold))
                            Text(selection.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surface).overlay(alignment: .top) { Divider() }
                }
            }
        }
        .tint(AppTheme.accent)
        .onChange(of: filter) { _, _ in compactColumn = .detail }
    }

    private func card(_ template: PaperTemplate) -> some View {
        Button { selection = template } label: {
            VStack(alignment: .leading, spacing: 10) {
                TemplatePreview(template: template)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selection == template ? AppTheme.accent : .clear, lineWidth: 2))
                    .overlay(alignment: .topTrailing) {
                        if selection == template {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, AppTheme.accent)
                                .font(.title3).padding(7)
                        }
                    }
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                Text(template.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(template.title)
        .accessibilityValue(template.detail)
        .accessibilityAddTraits(selection == template ? [.isSelected, .isButton] : .isButton)
    }
}
