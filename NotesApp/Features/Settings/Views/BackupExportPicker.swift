import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let heyNotesBackup = UTType(exportedAs: "com.local.notesapp.library-backup", conformingTo: .data)
}

/// File-to-file export keeps large PDF libraries out of FileDocument/Data buffers.
struct BackupExportPicker: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: (Bool) -> Void
        private var finished = false
        init(completion: @escaping (Bool) -> Void) { self.completion = completion }
        private func finish(_ saved: Bool) { guard !finished else { return }; finished = true; completion(saved) }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(!urls.isEmpty) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(false) }
    }
}
