import Foundation
import SwiftData

@Model public final class NotebookSection {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var sortIndex: Int
    public var notebook: Notebook?
    @Relationship(deleteRule: .nullify, inverse: \NotePage.section)
    public var pages: [NotePage] = []
    public init(title: String, sortIndex: Int, id: UUID = UUID()) {
        self.id = id; self.title = title; self.sortIndex = sortIndex
    }
}
