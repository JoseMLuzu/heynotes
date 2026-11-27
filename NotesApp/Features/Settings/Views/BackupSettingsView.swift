import SwiftUI
import SwiftData

struct BackupSettingsView: View {
    @State private var model: BackupSettingsModel
    @State private var importing = false
    @Binding var working: Bool

    init(container: ModelContainer, workspace: DocumentWorkspace? = nil, working: Binding<Bool>) {
        _model = State(initialValue: BackupSettingsModel(container: container, workspace: workspace))
        _working = working
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Label("Your library, safely kept", systemImage: "externaldrive.badge.checkmark")
                    .font(.headline).padding(.vertical, 4)
                Text("Save a complete copy of your notes and study cards to Files or an external drive. Everything works offline.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button { Task { await model.export() } } label: {
                    Label("Create Library Backup", systemImage: "square.and.arrow.up")
                }.disabled(model.busy || model.prepared != nil).accessibilityIdentifier("backup.export")
                Button { importing = true } label: {
                    Label("Restore from Backup", systemImage: "square.and.arrow.down")
                }.disabled(model.busy || model.prepared != nil).accessibilityIdentifier("backup.import")
            } footer: {
                Text("Backups include notebooks, folders, PDFs, handwriting, images, study progress and Trash. Restore adds content without replacing existing notes.")
            }
            Section {
                NavigationLink { DataRecoveryView() } label: { Label("Backup & Recovery Guide", systemImage: "lifepreserver") }
            } footer: {
                Text("A backup is not password-protected. Keep a trusted copy outside HeyNotes before deleting the app or changing devices.")
            }
            if model.busy { Section { HStack(spacing: 12) { ProgressView(); Text(model.activity) }.accessibilityElement(children: .combine) } }
            if let notice = model.notice { Section { Label(notice, systemImage: "checkmark.circle").foregroundStyle(.secondary) } }
            if let error = model.errorMessage { Section("Unable to Complete Backup") { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Backups").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.busy)
        .interactiveDismissDisabled(model.busy)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.heyNotesBackup]) { result in
            switch result {
            case .success(let url): Task { await model.prepare(url) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { model.errorMessage = error.localizedDescription }
            }
        }
        .sheet(item: $model.exportFile, onDismiss: { Task { await model.cleanupExport() } }) { file in
            BackupExportPicker(url: file.url) { model.finishExport(saved: $0) }.interactiveDismissDisabled()
        }
        .sheet(item: $model.prepared, onDismiss: { Task { await model.cancelPreparation() } }) { backup in
            BackupRestorePreview(backup: backup, busy: model.busy,
                                 restore: { Task { await model.restore() } },
                                 cancel: { Task { await model.cancelPreparation() } })
        }
        .onChange(of: model.busy, initial: true) { _, value in working = value }
        .onDisappear { if !model.busy { Task { await model.cancelPreparation() } } }
    }
}
