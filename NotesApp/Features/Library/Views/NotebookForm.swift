import SwiftUI

struct NotebookForm: View {
    let folders: [Folder]
    let initialFolderID: UUID?
    let save: (String, CoverStyle, PaperTemplate, Folder?) -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var title = ""
    @State private var cover: CoverStyle = .sage
    @State private var showingCovers = false
    @State private var template: PaperTemplate = .blank
    @State private var folderID: UUID?
    @State private var showingTemplates = false

    init(folders: [Folder], initialFolderID: UUID?, initialTemplate: PaperTemplate = .blank,
         save: @escaping (String, CoverStyle, PaperTemplate, Folder?) -> Bool) {
        self.folders = folders; self.initialFolderID = initialFolderID; self.save = save
        _template = State(initialValue: initialTemplate)
        _folderID = State(initialValue: initialFolderID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 24) {
                        NotebookCover(title: title, color: cover.accentColor, style: cover)
                            .frame(width: 86, height: 105)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your next idea." : title)
                                .font(.system(.title3, design: .serif, weight: .medium)).lineLimit(2)
                            Text("Make a little room for it.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: cover)
                }
                Section("Notebook") {
                    TextField("Title", text: $title)
                    Picker("Folder", selection: $folderID) {
                        Text("Inbox").tag(nil as UUID?)
                        ForEach(folders) { folder in Text(folder.pathTitle).tag(Optional(folder.id)) }
                    }
                }
                Section("Make it yours") {
                    Button { showingCovers = true } label: {
                        HStack(spacing: 14) {
                            NotebookCover(title: title, color: cover.accentColor, style: cover).frame(width: 44, height: 54)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cover.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Text("Browse Covers").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                    Button { showingTemplates = true } label: {
                        HStack(spacing: 14) {
                            TemplatePreview(template: template).frame(width: 44, height: 62)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Text("Browse Templates").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)

                }
            }
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if save(title, cover, template, folders.first { $0.id == folderID }) { dismiss() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .appSheetPresentation()
        .fullScreenCover(isPresented: $showingCovers) { CoverGallery(current: cover, title: title) { cover = $0; return true } }
        .fullScreenCover(isPresented: $showingTemplates) { TemplateGallery(current: template) { template = $0 } }
    }
}

struct TitleForm: View {
    let heading: String
    @State var title: String
    let save: (String) -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form { TextField("Title", text: $title) }
                .navigationTitle(heading)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { if save(title) { dismiss() } }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        .compactAppSheetPresentation(idealHeight: 200)
    }
}
