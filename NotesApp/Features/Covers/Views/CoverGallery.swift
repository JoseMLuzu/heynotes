import SwiftUI

struct CoverGallery: View {
    let title: String
    let choose: (CoverStyle) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selection: CoverStyle
    @State private var collection: CoverCollection?
    @State private var search = ""

    init(current: CoverStyle, title: String = "", choose: @escaping (CoverStyle) -> Bool) {
        self.title = title; self.choose = choose
        _selection = State(initialValue: current)
    }

    private var collections: [CoverCollection] { collection.map { [$0] } ?? CoverCollection.allCases }
    private func covers(in group: CoverCollection) -> [CoverStyle] {
        CoverStyle.allCases.filter {
            $0.collection == group && (search.isEmpty || $0.title.localizedStandardContains(search)
                                      || group.title.localizedStandardContains(search)
                                      || $0.subject?.searchTerms.localizedStandardContains(search) == true)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if collections.allSatisfy({ covers(in: $0).isEmpty }) {
                        ContentUnavailableView.search(text: search)
                    }
                    ForEach(collections, id: \.self) { group in
                        let items = covers(in: group)
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(group.title).font(.title3.weight(.semibold))
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 20)], alignment: .leading, spacing: 24) {
                                    ForEach(items, id: \.self) { option in
                                        Button { selection = option } label: {
                                            VStack(alignment: .leading, spacing: 10) {
                                                NotebookCover(title: title, color: option.accentColor, style: option)
                                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selection == option ? AppTheme.accent : .clear, lineWidth: 3))
                                                    .overlay(alignment: .topTrailing) {
                                                        if selection == option {
                                                            Image(systemName: "checkmark.circle.fill").font(.title3)
                                                                .foregroundStyle(.white, AppTheme.accent).padding(8)
                                                        }
                                                    }
                                                Text(option.title).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                                            }.contentShape(Rectangle())
                                        }
                                        .buttonStyle(QuietPressStyle())
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(option.title)
                                        .accessibilityAddTraits(selection == option ? [.isButton, .isSelected] : .isButton)
                                    }
                                }
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: 1300, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Notebook Covers")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search covers")
            .safeAreaInset(edge: .top, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filter("All Covers", value: nil)
                        ForEach(CoverCollection.allCases, id: \.self) { filter($0.title, value: $0) }
                    }.padding(.horizontal, 24)
                }
                .frame(height: 52)
                .background(AppTheme.background)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Cover") { if choose(selection) { dismiss() } }.fontWeight(.semibold)
                }
            }
        }.tint(AppTheme.accent)
    }

    private func filter(_ title: String, value: CoverCollection?) -> some View {
        Button { collection = value } label: {
            Text(title).font(.subheadline.weight(collection == value ? .semibold : .regular))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(collection == value ? AppTheme.accent.opacity(0.1) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(collection == value ? .isSelected : [])
    }
}
