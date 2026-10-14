import XCTest
@testable import Search

final class CanvasPerformanceTests: XCTestCase {
    func testNilResultsAreCachedUntilInvalidation() {
        var cache = CanvasResourceCache<String>(); let id = UUID()
        XCTAssertFalse(cache.lookup(id).found); cache.insert(nil, for: id)
        XCTAssertTrue(cache.lookup(id).found); XCTAssertNil(cache.lookup(id).value)
        cache.removeAll(); XCTAssertFalse(cache.lookup(id).found)
        cache.insert("value", for: id, cost: 4); cache.remove(id)
        XCTAssertFalse(cache.lookup(id).found); XCTAssertEqual(cache.totalCost, 0)
    }
    func testCacheEvictsByEntryAndMemoryBudget() {
        var cache = CanvasResourceCache<String>(capacity: 2, costLimit: 8)
        let a = UUID(), b = UUID(), c = UUID()
        cache.insert("a", for: a, cost: 4); cache.insert("b", for: b, cost: 4)
        cache.insert("c", for: c, cost: 5)
        XCTAssertFalse(cache.lookup(a).found); XCTAssertFalse(cache.lookup(b).found)
        XCTAssertEqual(cache.lookup(c).value, "c"); XCTAssertEqual(cache.totalCost, 5)
        cache.insert("too large", for: a, cost: 9); XCTAssertFalse(cache.lookup(a).found)
        cache.insert(nil, for: a); cache.insert(nil, for: b)
        XCTAssertEqual(cache.count, 2); XCTAssertEqual(cache.totalCost, 0)
    }
    func testReplacingCachedValueUpdatesCostAndOrder() {
        var cache = CanvasResourceCache<String>(capacity: 2, costLimit: 8)
        let a = UUID(), b = UUID(), c = UUID()
        cache.insert("a", for: a, cost: 4); cache.insert("b", for: b, cost: 4)
        cache.insert("updated", for: a, cost: 1); cache.insert(nil, for: c)
        XCTAssertEqual(cache.lookup(a).value, "updated"); XCTAssertFalse(cache.lookup(b).found)
        XCTAssertEqual(cache.totalCost, 1)
    }
    func testControlHullContainsCurveSamplesIncludingBends() {
        let curve = CanvasCurve(from: CGRect(x: -500,y: -100,width:100,height:200), side:.left, to:CGRect(x:100,y:400,width:200,height:100), toSide:.right)
        for i in 0...100 { XCTAssertTrue(curve.controlBounds.insetBy(dx: -0.01,dy: -0.01).contains(curve.point(Double(i)/100))) }
    }
    @MainActor func testVaultMonitorIsSharedAndReleasesLastClient() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("monitor-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at: root) }
        let vault = CanvasVault(workspace: root.appendingPathComponent("config/workspace.json"))
        XCTAssertTrue(vault.connect(root)); let a=UUID(), b=UUID()
        vault.acquireMonitor(a); vault.acquireMonitor(b)
        XCTAssertEqual(vault.monitoringDiagnostics["clients"] as? Int, 2)
        XCTAssertTrue(vault.monitoringDiagnostics["watching"] as? Bool == true || vault.monitoringDiagnostics["fallback"] as? Bool == true)
        vault.releaseMonitor(a); XCTAssertEqual(vault.monitoringDiagnostics["clients"] as? Int, 1)
        vault.releaseMonitor(b); XCTAssertEqual(vault.monitoringDiagnostics["watching"] as? Bool,false); XCTAssertEqual(vault.monitoringDiagnostics["fallback"] as? Bool,false)
    }
    func testCancelledVaultScanReadsNoEntries() throws {
        let ticket=VaultScanTicket();ticket.cancel()
        XCTAssertNil(CanvasVault.scan(FileManager.default.temporaryDirectory,ticket:ticket))
    }
    @MainActor func testDisconnectDropsQueuedBackgroundScan() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("disconnect-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        try Data("source".utf8).write(to:root.appendingPathComponent("note.md"))
        let vault=CanvasVault(workspace:root.appendingPathComponent("config/workspace.json")), client=UUID()
        XCTAssertTrue(vault.connect(root));vault.acquireMonitor(client);vault.disconnect()
        let revision=vault.revision
        try await Task.sleep(nanoseconds:400_000_000)
        XCTAssertEqual(vault.revision,revision);XCTAssertTrue(vault.entries.isEmpty);XCTAssertFalse(vault.connected)
        vault.releaseMonitor(client)
    }
    @MainActor func testDeletingSpaceRetiresItsVaultWithoutDeletingExternalFiles() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("retire-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let note=root.appendingPathComponent("note.md");try Data("keep".utf8).write(to:note)
        let store=WorkspaceStore(space:UUID(),file:root.appendingPathComponent("workspace/workspace.json"))
        let vault=CanvasVault.shared(workspace:store.file), client=UUID()
        XCTAssertTrue(vault.connect(root));vault.acquireMonitor(client);store.erase()
        XCTAssertFalse(vault.connected);XCTAssertEqual(vault.monitoringDiagnostics["clients"] as? Int,0)
        XCTAssertFalse(vault.monitoringDiagnostics["watching"] as? Bool ?? true)
        XCTAssertEqual(try String(contentsOf:note,encoding:.utf8),"keep")
    }

}
