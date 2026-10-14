import XCTest
import WebKit
@testable import Search

final class SystemNotificationsTests: XCTestCase {
    private func bundle(named name: String, identifier: String? = "com.example.locus", package: String = "APPL") throws -> Bundle {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notification-runtime-\(UUID())")
        let folder = root.appendingPathComponent(name)
        let contents = folder.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        var info = ["CFBundlePackageType": package, "CFBundleExecutable": "Search"]
        if let identifier { info["CFBundleIdentifier"] = identifier }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: folder))
    }

    func testPackagedApplicationRemainsEligible() throws {
        let app = try bundle(named: "Search.app")
        XCTAssertTrue(SystemNotifications.supports(app))
        // A probe never calls the real service, even from a proper app bundle.
        XCTAssertNil(SystemNotifications.center(bundle: app, testing: true))
    }

    func testXcodeExecutableFolderCannotRequestCenterEvenWithAppMetadata() throws {
        let debug = try bundle(named: "Debug")
        XCTAssertFalse(SystemNotifications.supports(debug))
        // This previously raised the exception shown by the Xcode launch.
        XCTAssertNil(SystemNotifications.center(bundle: debug, testing: false))
    }

    func testIncompleteOrNonApplicationBundleCannotRequestCenter() throws {
        for app in [try bundle(named: "MissingID.app", identifier: nil),
                    try bundle(named: "EmptyID.app", identifier: ""),
                    try bundle(named: "Test.app", package: "BNDL")] {
            XCTAssertFalse(SystemNotifications.supports(app))
            XCTAssertNil(SystemNotifications.center(bundle: app, testing: false))
        }
    }

    @MainActor
    func testUnbundledTabConfigurationCanAttachNotifications() {
        XCTAssertFalse(SystemNotifications.supports(.main))
        XCTAssertNil(SystemNotifications.center(testing: false))
        SiteNotifications.shared.attach(.nonPersistent())
        SiteNotifications.shared.authorize()
    }
}
