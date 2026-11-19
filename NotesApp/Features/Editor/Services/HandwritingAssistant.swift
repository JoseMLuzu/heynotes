import Observation
import PencilKit

/// Opt-in, phrase-at-a-time conversion. Existing ink is excluded when enabling or switching tools.
@MainActor @Observable
final class HandwritingAssistant {
    private(set) var enabled = false
    var fontName: String {
        didSet { defaults.set(fontName, forKey: "editor.handwriting.font") }
    }
    var language: String {
        didSet { defaults.set(language, forKey: "editor.handwriting.language") }
    }
    var fontFilePath: String? {
        didSet { defaults.set(fontFilePath, forKey: "editor.handwriting.fontFile") }
    }
    var alignToPaper: Bool {
        didSet { defaults.set(alignToPaper, forKey: "editor.handwriting.alignToPaper") }
    }
    var sizeScale: Double {
        didSet { defaults.set(sizeScale, forKey: "editor.handwriting.sizeScale") }
    }
    var baselineOffset: Double {
        didSet { defaults.set(baselineOffset, forKey: "editor.handwriting.baselineOffset") }
    }
    private(set) var message = "Off — your handwriting stays unchanged."
    private(set) var processing = false
    @ObservationIgnored private var baseline = PKDrawing()
    @ObservationIgnored private var tool: EditorTool = .pen
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let recognizer: any HandwritingRecognizing

    init(defaults: UserDefaults = .standard, recognizer: any HandwritingRecognizing = VisionHandwritingRecognizer.shared) {
        self.defaults = defaults; self.recognizer = recognizer
        let savedFont = defaults.string(forKey: "editor.handwriting.font")
        fontName = savedFont.flatMap { !$0.isEmpty && $0.count <= 128 ? $0 : nil } ?? HandwritingFont.defaultName
        fontFilePath = defaults.string(forKey: "editor.handwriting.fontFile")
        alignToPaper = defaults.object(forKey: "editor.handwriting.alignToPaper") as? Bool ?? true
        sizeScale = ToolPreset.clamp(defaults.object(forKey: "editor.handwriting.sizeScale") as? Double ?? 1, to: 0.7...1.3)
        baselineOffset = ToolPreset.clamp(defaults.double(forKey: "editor.handwriting.baselineOffset"), to: -8...8)
        let savedLanguage = defaults.string(forKey: "editor.handwriting.language")
        language = ["en-US", "es-ES"].first(where: { $0 == savedLanguage }) ?? (Locale.preferredLanguages.first?.hasPrefix("es") == true ? "es-ES" : "en-US")
    }

    func setEnabled(_ value: Bool, session: EditorSession) {
        enabled = value; reset(to: session.canvas?.drawing ?? session.drawing)
        message = value ? "Write with Pen or Pencil. Pause for 1.2 seconds to convert." : "Off — your handwriting stays unchanged."
    }

    func setTool(_ value: EditorTool, session: EditorSession) {
        guard tool != value else { return }
        tool = value; reset(to: session.canvas?.drawing ?? session.drawing)
        if enabled { message = acceptsTool ? "Ready for your next phrase." : "Paused — select Pen or Pencil to continue." }
    }

    /// Invalidates both the debounce and any result already being computed by Vision.
    func cancel() {
        generation += 1; task?.cancel(); task = nil; processing = false
    }

    func reset(to drawing: PKDrawing) {
        cancel(); baseline = drawing
    }

    private var acceptsTool: Bool { tool == .pen || tool == .pencil }

    func changed(_ drawing: PKDrawing, session: EditorSession) {
        cancel()
        guard enabled, acceptsTool, session.ready, !session.busy else { return }
        guard drawing.strokes.count > baseline.strokes.count else { baseline = drawing; return }
        let count = baseline.strokes.count, prefix = baseline, token = generation
        let font = fontName, selectedLanguage = language, fontPath = fontFilePath, layout = layoutOptions
        task = Task { [weak self, weak session] in
            do { try await Task.sleep(for: .milliseconds(1_200)) } catch { return }
            guard let self, let session, self.generation == token else { return }
            let validPrefix = await Task.detached(priority: .utility) {
                StrokeContent.matches(Array(drawing.strokes.prefix(count)), prefix.strokes)
            }.value
            guard self.generation == token else { return }
            guard validPrefix else { self.reset(to: drawing); return }
            let source = PKDrawing(strokes: Array(drawing.strokes.dropFirst(count)))
            await self.convert(source, snapshot: drawing, session: session, token: token,
                               font: font, fontPath: fontPath, language: selectedLanguage, options: layout)
        }
    }

    func convertPage(session: EditorSession) async {
        guard session.writingRegion == nil else { message = "Close Zoom Writing before converting handwriting."; return }
        cancel()
        let snapshot = session.canvas?.drawing ?? session.drawing
        guard !snapshot.strokes.isEmpty else { message = "Write something on this page first."; return }
        await convert(snapshot, snapshot: snapshot, session: session, token: generation,
                      font: fontName, fontPath: fontFilePath, language: language, options: layoutOptions)
    }

    private func convert(_ source: PKDrawing, snapshot: PKDrawing, session: EditorSession,
                         token: Int, font: String, fontPath: String?, language: String, options: HandwritingLayoutOptions) async {
        guard session.ready, !session.busy, let pageID = session.page?.id,
              !source.strokes.isEmpty, session.canvas != nil,
              UIApplication.shared.applicationState == .active else { return }
        processing = true; message = "Reading handwriting on this iPad…"
        do {
            if let fontPath { _ = try await HandwritingFontStore.shared.load(path: fontPath, storage: session.storage) }
            let result = try await recognizer.recognizeLines(source, language: language)
            guard generation == token, !Task.isCancelled else { return }
            processing = false
            guard let result else {
                message = "Could not read this phrase confidently. Original ink was kept."
                return
            }
            let applied = await session.applyRecognizedHandwriting(result.map(\.text).joined(separator: "\n"), source: source, snapshot: snapshot,
                                                                 pageID: pageID, fontName: font, fontPath: fontPath,
                                                                 recognizedLines: result, options: options,
                                                                 isCurrent: { self.generation == token })
            // apply resets the baseline and invalidates this generation after a successful edit.
            if applied { message = "Converted. Edit the text or restore its original ink from Inserted Content." }
            else if generation == token { message = "This phrase could not fit safely, or the page changed. Original ink was kept." }
        } catch is CancellationError { }
        catch {
            guard generation == token else { return }
            processing = false; message = "Could not convert this phrase. Original ink was kept. \(error.localizedDescription)"
        }
    }
    private var layoutOptions: HandwritingLayoutOptions {
        .init(alignToPaper: alignToPaper, sizeScale: sizeScale, baselineOffset: baselineOffset)
    }
}
