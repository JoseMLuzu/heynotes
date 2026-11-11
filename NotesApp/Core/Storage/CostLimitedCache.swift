import Foundation

/// Small actor-owned LRU. Budgets account for image bytes, not just entry count.
struct CostLimitedCache<Key: Hashable, Value> {
    private struct Entry { let value: Value; let cost: Int; var access: UInt64 }
    private var entries: [Key: Entry] = [:]
    private var tick: UInt64 = 0
    private(set) var totalCost = 0
    let costLimit: Int
    let countLimit: Int
    var count: Int { entries.count }

    mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        tick &+= 1; entry.access = tick; entries[key] = entry
        return entry.value
    }
    mutating func insert(_ value: Value, for key: Key, cost: Int) {
        if let old = entries.removeValue(forKey: key) { totalCost -= old.cost }
        guard cost >= 0, cost <= costLimit, countLimit > 0 else { return }
        while !entries.isEmpty && (totalCost + cost > costLimit || entries.count >= countLimit) {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access }) else { break }
            totalCost -= oldest.value.cost; entries.removeValue(forKey: oldest.key)
        }
        tick &+= 1
        entries[key] = Entry(value: value, cost: cost, access: tick)
        totalCost += cost
    }
    mutating func removeAll() { entries.removeAll(); totalCost = 0 }
}

/// Cache hits still require a real source file; replaced or missing files never become stale successes.
struct FileFingerprint: Hashable, Sendable {
    let url: URL
    let bytes: Int
    let modified: Date
    let inode: UInt64

    init(url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let bytes = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { throw CocoaError(.fileReadUnknown) }
        self.url = url; self.bytes = bytes.intValue; self.modified = modified
        inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    }
}
