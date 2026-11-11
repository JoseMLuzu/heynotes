import Foundation
import SwiftData

@Model
public final class Folder {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var colorRawValue: String? = nil
    public var isFavorite: Bool = false
    public var trashedAt: Date? = nil
    public var parent: Folder? = nil
    @Relationship(deleteRule: .nullify, inverse: \Folder.parent)
    public var children: [Folder] = []
    @Relationship(deleteRule: .nullify, inverse: \Notebook.folder)
    public var notebooks: [Notebook] = []

    public var color: FolderColor {
        get { colorRawValue.flatMap(FolderColor.init(rawValue:)) ?? .sage }
        set { colorRawValue = newValue.rawValue }
    }

    public init(title: String, parent: Folder? = nil, id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.parent = parent
        self.createdAt = createdAt
    }
}
