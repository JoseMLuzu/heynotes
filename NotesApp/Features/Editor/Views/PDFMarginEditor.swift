import SwiftUI

struct PDFMarginEditor: View {
    let session: EditorSession
    @State private var fraction: Double
    @Environment(\.dismiss) private var dismiss
    init(session: EditorSession) {
        self.session = session
        _fraction = State(initialValue: (session.page?.pdfRightMargin ?? 0) / max(1, Double(session.page?.contentSize.width ?? 768)))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Note Space") {
                    Picker("Width", selection: $fraction) {
                        Text("None").tag(0.0); Text("Small").tag(0.25); Text("Medium").tag(0.5); Text("Wide").tag(1.0)
                    }.pickerStyle(.segmented)
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 4).fill(.white).overlay(Text("PDF").foregroundStyle(.secondary))
                        if fraction > 0 { RoundedRectangle(cornerRadius: 4).fill(AppTheme.accent.opacity(0.12)).frame(width: 180 * fraction).overlay(Text("Notes").font(.caption)) }
                    }.frame(height: 150).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.gray.opacity(0.3)))
                    Text("Adds space to the right of this PDF page. Existing ink and the original PDF stay in their coordinates. The exported page includes the extra space.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("PDF Note Margin").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        Task {
                            guard await session.flush() else { return }
                            let base = Double(session.page?.contentSize.width ?? 768)
                            if session.setMargin(min(fraction * base, 14400 - base)) { dismiss() }
                        }
                    }.disabled(session.busy)
                }
            }
            .alert("Could Not Change Margin", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
                Button("OK") { session.errorMessage = nil }
            } message: { Text(session.errorMessage ?? "") }
        }
        .compactAppSheetPresentation(idealHeight: 470)
        .tint(AppTheme.accent)
    }
}
