import XCTest
@testable import Search

final class ReleaseChannelTests: XCTestCase {
    func testOnlyThisRepositoryCanSupplyReleaseAssets() {
        let base = "https://github.com/Cryptk1ddo/Locus/releases/download/v0.1.0/"
        XCTAssertNotNil(ReleaseChannel.asset(base + "Locus-arm64.zip"))
        for bad in ["http://github.com/Cryptk1ddo/Locus/releases/download/v0.1.0/Locus.zip",
                    "https://github.com/another/Locus/releases/download/v0.1.0/Locus.zip",
                    "https://github.com/Cryptk1ddo/Locus-evil/releases/download/v0.1.0/Locus.zip",
                    "https://github.com/Cryptk1ddo/Locus/releases/download/../other.zip",
                    base + "Locus.zip?redirect=elsewhere", base + "Locus.zip#fragment",
                    "https://github.com:443/Cryptk1ddo/Locus/releases/download/v0.1.0/Locus.zip"] {
            XCTAssertNil(ReleaseChannel.asset(bad), bad)
        }
    }

    func testChecksumsMustBeCompleteSHA256Hex() {
        XCTAssertEqual(ReleaseChannel.checksum(String(repeating: "A", count: 64)), String(repeating: "a", count: 64))
        XCTAssertNil(ReleaseChannel.checksum(String(repeating: "g", count: 64)))
        XCTAssertNil(ReleaseChannel.checksum(""))
        XCTAssertNil(ReleaseChannel.checksum(String(repeating: "a", count: 63)))
    }

    @MainActor func testDevelopmentManifestCannotAuthorizeInstallation() throws {
        let base = "https://github.com/Cryptk1ddo/Locus/releases/download/v0.1.0/"
        var manifest: [String: Any] = ["version": "0.1.0", "build": 20261014000000,
            "url": base + "Locus-\(ReleaseChannel.architecture).zip",
            "dmg": base + "Locus-\(ReleaseChannel.architecture).dmg",
            "sha256": String(repeating: "a", count: 64), "dmgSha256": String(repeating: "b", count: 64)]
        let release = try XCTUnwrap(Updater.parse(JSONSerialization.data(withJSONObject: manifest), authenticated: false))
        XCTAssertFalse(release.authenticated)
        manifest["url"] = base + "Locus-wrong-chip.zip"
        XCTAssertNil(Updater.parse(try JSONSerialization.data(withJSONObject: manifest), authenticated: false))
        manifest["url"] = base + "Locus-\(ReleaseChannel.architecture).zip"
        manifest["sha256"] = "bad"
        XCTAssertNil(Updater.parse(try JSONSerialization.data(withJSONObject: manifest), authenticated: false))
    }
}
