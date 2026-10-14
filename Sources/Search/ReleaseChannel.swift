import Foundation

/// Release URLs are confined to this repository, even when a manifest is unsigned.
enum ReleaseChannel {
    static let repository = "Cryptk1ddo/Locus"
    static let releases = URL(string: "https://github.com/\(repository)/releases")!
    #if arch(x86_64)
    static let architecture = "x86_64"
    #else
    static let architecture = "arm64"
    #endif
    static let feed = releases.appendingPathComponent("latest/download/appcast-\(architecture).json")

    static func asset(_ value: Any?) -> URL? {
        guard let text = value as? String, let url = URL(string: text),
              url.scheme == "https", url.host == "github.com", url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !url.pathComponents.contains(".."),
              url.path.hasPrefix("/\(repository)/releases/download/")
        else { return nil }
        return url
    }

    static func checksum(_ value: Any?) -> String? {
        guard let text = value as? String, text.count == 64,
              text.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) else { return nil }
        return text.lowercased()
    }
}
