import Foundation
import UserNotifications

/// UserNotifications raises an Objective-C exception for an unbundled process.
/// SwiftPM/Xcode executable launches must not ask it for a notification center.
enum SystemNotifications {
    static func supports(_ bundle: Bundle) -> Bool {
        bundle.bundleURL.pathExtension.lowercased() == "app"
            && bundle.bundleIdentifier?.isEmpty == false
            && bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL"
    }

    static func center(bundle: Bundle = .main, testing: Bool = Store.testing) -> UNUserNotificationCenter? {
        guard !testing, supports(bundle) else { return nil }
        return UNUserNotificationCenter.current()
    }
}
