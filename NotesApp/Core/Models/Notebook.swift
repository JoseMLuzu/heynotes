import Foundation
import SwiftData

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
    @Relationship(deleteRule: .cascade, inverse: \NotebookSection.notebook)
    public var sections: [NotebookSection] = []
    public var orderedSections: [NotebookSection] {
        sections.sorted { $0.sortIndex == $1.sortIndex ? $0.id.uuidString < $1.id.uuidString : $0.sortIndex < $1.sortIndex }
    }

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
