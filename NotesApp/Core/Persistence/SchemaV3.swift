import Foundation
import SwiftData

/// Frozen V3 layout. Never edit persisted fields.
public enum NotesSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(3, 0, 0) }
    public static var models: [any PersistentModel.Type] { [Folder.self, Notebook.self, NotePage.self] }
    @Model
    public final class Folder {
        @Attribute(.unique) public var id: UUID
        public var title: String
        public var createdAt: Date
        public var isFavorite: Bool = false
        public var trashedAt: Date? = nil
        public var parent: Folder? = nil
        @Relationship(deleteRule: .nullify, inverse: \Folder.parent)
        public var children: [Folder] = []
        @Relationship(deleteRule: .nullify, inverse: \Notebook.folder)
        public var notebooks: [Notebook] = []

        public init(title: String, parent: Folder? = nil, id: UUID = UUID(), createdAt: Date = .now) {
            self.id = id
            self.title = title
            self.parent = parent
            self.createdAt = createdAt
        }
    }

    @Model
    public final class Notebook {
        @Attribute(.unique) public var id: UUID
        public var title: String
        public var createdAt: Date
        public var updatedAt: Date
        public var coverColorRawValue: String
        public var trashedAt: Date? = nil
        public var isFavorite: Bool
        public var folder: Folder?
        @Relationship(deleteRule: .cascade, inverse: \NotePage.notebook)
        public var pages: [NotePage] = []

        public var coverColor: CoverColor {
            get { coverStyle.accentColor }
            set { coverColorRawValue = newValue.rawValue }
        }

        public var coverStyle: CoverStyle {
            get { CoverStyle(rawValue: coverColorRawValue) ?? .sage }
            set { coverColorRawValue = newValue.rawValue }
        }

        public var orderedPages: [NotePage] {
            pages.sorted {
                $0.pageIndex == $1.pageIndex
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.pageIndex < $1.pageIndex
            }
        }

        public init(title: String, coverColor: CoverColor = .sage, folder: Folder? = nil,
                    id: UUID = UUID(), now: Date = .now) {
            self.id = id
            self.title = title
            self.createdAt = now
            self.updatedAt = now
            self.coverColorRawValue = coverColor.rawValue
            self.isFavorite = false
            self.folder = folder
        }
    }

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

        public var logicalSize: CGSize {
            CGSize(width: pageWidth ?? 768, height: pageHeight ?? 1086)
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
}
