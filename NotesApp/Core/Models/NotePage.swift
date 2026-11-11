import Foundation
import SwiftData

@Model
public final class NotePage {
    @Attribute(.unique) public var id: UUID
    public var notebook: Notebook?
    public var pageIndex: Int
    public var paperTemplateRawValue: String
    // Relative to the app's document root. Nil means a new page without saved ink.
    public var drawingFilePath: String?
    public var pdfFilePath: String? = nil
    public var pdfPageIndex: Int? = nil
    public var pageWidth: Double? = nil
    public var pageHeight: Double? = nil
    public var bookmarkTitle: String? = nil
    public var section: NotebookSection? = nil
    public var objectsData: Data? = nil
    public var pdfRightMargin: Double? = nil
    public var contentSize: CGSize { CGSize(width: pageWidth ?? 768, height: pageHeight ?? 1086) }

    public var logicalSize: CGSize {
        CGSize(width: contentSize.width + (pdfRightMargin ?? 0), height: contentSize.height)
    }
    public var createdAt: Date
    public var updatedAt: Date

    public var paperTemplate: PaperTemplate {
        get { PaperTemplate(rawValue: paperTemplateRawValue) ?? .blank }
        set { paperTemplateRawValue = newValue.rawValue }
    }

    public init(pageIndex: Int, paperTemplate: PaperTemplate = .blank,
                id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.pageIndex = pageIndex
        self.paperTemplateRawValue = paperTemplate.rawValue
        self.createdAt = now
        self.updatedAt = now
    }
}
