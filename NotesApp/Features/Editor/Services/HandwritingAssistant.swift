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
        fontName = HandwritingFont.choices.first(where: { $0.name == savedFont })?.name ?? HandwritingFont.defaultName
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
        let font = fontName, selectedLanguage = language
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
                               font: font, language: selectedLanguage)
        }
    }

    func convertPage(session: EditorSession) async {
        cancel()
        let snapshot = session.canvas?.drawing ?? session.drawing
        guard !snapshot.strokes.isEmpty else { message = "Write something on this page first."; return }
        await convert(snapshot, snapshot: snapshot, session: session, token: generation,
                      font: fontName, language: language)
    }

    private func convert(_ source: PKDrawing, snapshot: PKDrawing, session: EditorSession,
                         token: Int, font: String, language: String) async {
        guard session.ready, !session.busy, let pageID = session.page?.id,
              !source.strokes.isEmpty, session.canvas != nil,
              UIApplication.shared.applicationState == .active else { return }
        processing = true; message = "Reading handwriting on this iPad…"
        do {
            let result = try await recognizer.recognize(source, language: language)
            guard generation == token, !Task.isCancelled else { return }
            processing = false
            guard let result else {
                message = "Could not read this phrase confidently. Original ink was kept."
                return
            }
            let applied = await session.applyRecognizedHandwriting(result, source: source, snapshot: snapshot,
                                                                 pageID: pageID, fontName: font,
                                                                 isCurrent: { self.generation == token })
            // apply resets the baseline and invalidates this generation after a successful edit.
            if applied { message = "Converted. Edit the text or restore its original ink from Inserted Content." }
            else if generation == token { message = "The page changed. Original ink was kept." }
        } catch is CancellationError { }
        catch {
            guard generation == token else { return }
            processing = false; message = "Recognition is unavailable. Original ink was kept."
        }
    }
}
