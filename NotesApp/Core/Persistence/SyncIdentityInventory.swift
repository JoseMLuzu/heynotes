import SwiftData
import CryptoKit
import Foundation

/// Project only committed domain UUIDs. Caller owns the context and save boundary.
struct SyncIdentityInventory {
    let identities: Set<SyncEntityIdentity>
    let counts: [String: Int]
    var digest: String { Self.digest(identities.map(\.recordName)) }

    static func digest(_ values: [String]) -> String {
        var hash = SHA256()
        for value in values.sorted() { hash.update(data: Data((value + "\n").utf8)) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func capture(in context: ModelContext) throws -> Self {
        var live = Set<SyncEntityIdentity>(), counts: [String: Int] = [:]
        func collect<T: PersistentModel>(_ type: T.Type, kind: SyncEntityKind, id: KeyPath<T, UUID> & Sendable) throws {
            var request = FetchDescriptor<T>(sortBy: [SortDescriptor(id)])
            request.propertiesToFetch = [id]; request.fetchLimit = 256; request.fetchOffset = 0
            var count = 0
            while true {
                try Task.checkCancellation()
                let ids = try autoreleasepool { try context.fetch(request).map { $0[keyPath: id] } }
                guard live.count + ids.count <= SyncInitialEnrollmentStore.maximumIdentities else { throw SyncEnrollmentError.tooLarge }
                for id in ids {
                    guard live.insert(.init(kind: kind, id: id)).inserted else { throw SyncEnrollmentError.inconsistentJournal }
                }
                count += ids.count; request.fetchOffset = count
                if ids.count < 256 { break }
            }
            counts[kind.rawValue] = count
        }
        try collect(Folder.self, kind: .folder, id: \.id)
        try collect(Notebook.self, kind: .notebook, id: \.id)
        try collect(NotePage.self, kind: .page, id: \.id)
        try collect(NotebookSection.self, kind: .section, id: \.id)
        try collect(StudyDeck.self, kind: .deck, id: \.id)
        try collect(Flashcard.self, kind: .card, id: \.id)
        try collect(ReviewRecord.self, kind: .review, id: \.id)
        return Self(identities: live, counts: counts)
    }
}
