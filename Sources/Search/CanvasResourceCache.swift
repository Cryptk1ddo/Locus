import Foundation

/// Small bounded FIFO cache; nil is a real result, invalidated by content changes.
struct CanvasResourceCache<Value> {
    private struct Entry { let value: Value?; let cost: Int }
    private var values: [UUID: Entry] = [:]
    private var order: [UUID] = []
    let capacity: Int
    let costLimit: Int
    private(set) var totalCost = 0
    init(capacity: Int = 64, costLimit: Int = .max) { self.capacity = max(1, capacity); self.costLimit = max(0, costLimit) }
    func lookup(_ id: UUID) -> (found: Bool, value: Value?) {
        guard let entry = values[id] else { return (false, nil) }; return (true, entry.value)
    }
    mutating func insert(_ value: Value?, for id: UUID, cost: Int = 0) {
        remove(id)
        let cost = max(0, cost)
        guard cost <= costLimit else { return }
        while !order.isEmpty && (order.count >= capacity || totalCost > costLimit - cost) {
            let oldest = order.removeFirst(); totalCost -= values.removeValue(forKey: oldest)?.cost ?? 0
        }
        order.append(id); values[id] = Entry(value: value, cost: cost); totalCost += cost
    }
    mutating func remove(_ id: UUID) {
        if let old = values.removeValue(forKey: id) { totalCost -= old.cost; order.removeAll { $0 == id } }
    }
    mutating func removeAll() { values.removeAll(keepingCapacity: true); order.removeAll(keepingCapacity: true); totalCost = 0 }
    var count: Int { values.count }
}
