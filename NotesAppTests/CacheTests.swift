import Foundation
import Testing
@testable import NotesAppCore

struct CacheTests {
    @Test func cacheRespectsBytesAndEvictsLeastRecentlyUsed() {
        var cache = CostLimitedCache<String, Int>(costLimit: 10, countLimit: 3)
        cache.insert(1, for: "first", cost: 4)
        cache.insert(2, for: "second", cost: 4)
        #expect(cache.value(for: "first") == 1)
        cache.insert(3, for: "third", cost: 4)
        #expect(cache.value(for: "second") == nil)
        #expect(cache.value(for: "first") == 1)
        #expect(cache.totalCost == 8)
        cache.insert(9, for: "too-large", cost: 100)
        #expect(cache.value(for: "too-large") == nil)
        #expect(cache.totalCost == 8)
        cache.removeAll()
        #expect(cache.count == 0)
        #expect(cache.totalCost == 0)
    }

    @Test func replacingEntryAndCountLimitStayWithinBudget() {
        var cache = CostLimitedCache<String, Int>(costLimit: 20, countLimit: 1)
        cache.insert(1, for: "item", cost: 10)
        cache.insert(2, for: "item", cost: 3)
        #expect(cache.totalCost == 3)
        cache.insert(3, for: "other", cost: 5)
        #expect(cache.value(for: "item") == nil)
        #expect(cache.totalCost == 5)
        #expect(cache.count == 1)
    }

    @Test func repeatedBackupReplacementPreservesPreviousCheckpoint() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = DrawingStorage(root: root)
        for generation in 0..<5 {
            try await storage.write(Data(repeating: UInt8(generation), count: 1024), to: "ink.drawing")
            if generation > 0 {
                #expect(try await storage.read("ink.drawing.backup") == Data(repeating: UInt8(generation - 1), count: 1024))
            }
        }
        #expect(try await storage.read("ink.drawing") == Data(repeating: 4, count: 1024))
        #expect(try await storage.restoreBackup("ink.drawing") == Data(repeating: 3, count: 1024))
    }
}
