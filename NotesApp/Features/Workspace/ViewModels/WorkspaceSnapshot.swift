import Foundation

enum WorkspacePane: String, Codable { case primary, secondary
    var other: WorkspacePane { self == .primary ? .secondary : .primary }
}

/// New optional fields keep the previously shipped single-editor tab state decodable.
struct WorkspaceSnapshot: Codable, Equatable {
    var openIDs: [UUID] = []
    var recentIDs: [UUID] = []
    var activeID: UUID?
    var pages: [UUID: UUID] = [:]
    var primaryID: UUID?
    var secondaryID: UUID?
    var splitFraction: Double?
    var panesReversed: Bool?
}
