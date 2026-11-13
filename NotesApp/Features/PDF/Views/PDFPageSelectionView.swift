import SwiftUI

struct PDFPageSelectionView: View {
    @State private var selection: PDFImportSelection
    let close: () -> Void
    let confirm: ([Int]) async -> String?
    init(draft: PDFImportDraft, close: @escaping () -> Void, confirm: @escaping ([Int]) async -> String?) {
        _selection = State(initialValue: PDFImportSelection(draft: draft))
        self.close = close; self.confirm = confirm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selection.draft.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                        Text("\(selection.draft.pageCount) pages · Choose what to bring into your notebook.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Picker("Pages to import", selection: $selection.mode) {
                        ForEach(PDFImportSelection.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if selection.mode == .selected {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Pages, e.g. 1, 3–5, 8", text: $selection.rangeText)
                                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityLabel("Page numbers or ranges")
                                    .onSubmit { selection.applyRange() }
                                Button("Apply") { selection.applyRange() }.frame(minHeight: 44)
                            }
                            if let error = selection.rangeError { Text(error).font(.caption).foregroundStyle(.red) }
                            HStack {
                                Text("\(selection.count) selected").font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Button("Clear Selection") { selection.clear() }.font(.subheadline).frame(minHeight: 44)
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 180), spacing: 16)], spacing: 20) {
                        ForEach(0..<selection.draft.pageCount, id: \.self) { index in
                            PDFImportThumbnail(draft: selection.draft, index: index, selected: selection.contains(index)) {
                                selection.toggle(index)
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Import PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close).disabled(selection.importing) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { if await selection.confirm(using: confirm) { close() } }
                    } label: {
                        if selection.importing { ProgressView("Importing…") }
                        else { Text(selection.importTitle).fontWeight(.semibold) }
                    }
                    .disabled(!selection.canImport)
                    .accessibilityIdentifier("pdf.confirmImport")
                }
            }
            .disabled(selection.importing)
            .alert("Could Not Import PDF", isPresented: Binding(get: { selection.errorMessage != nil }, set: { if !$0 { selection.errorMessage = nil } })) {
                Button("OK") { selection.errorMessage = nil }
            } message: { Text(selection.errorMessage ?? "") }
        }
        .tint(AppTheme.accent)
        .interactiveDismissDisabled(selection.importing)
        .appSheetPresentation()
    }
}

private struct PDFImportThumbnail: View {
    let draft: PDFImportDraft
    let index: Int
    let selected: Bool
    let toggle: () -> Void
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Color.white
                        if let image { Image(uiImage: image).resizable().scaledToFit() }
                        else if failed { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary) }
                        else { ProgressView() }
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? AppTheme.accent : .gray.opacity(0.25), lineWidth: selected ? 2 : 1))
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.palette).foregroundStyle(selected ? AppTheme.accent : .gray, .white)
                        .font(.title3).padding(8)
                }
                Text("Page \(index + 1)").font(.caption.weight(.medium)).foregroundStyle(.primary)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? "Double-tap to change the selection." : "Double-tap to select this page.")
        .task(id: draft.id, priority: .utility) {
            do {
                let result = try await PDFDocumentService.importPreviews.background(path: draft.document.path, index: index, storage: draft.storage, maxPixels: 320)
                try Task.checkCancellation(); image = result; failed = false
            } catch is CancellationError { }
            catch { failed = true }
        }
    }
}
