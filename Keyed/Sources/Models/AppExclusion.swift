import Foundation
import SwiftData

/// Uniqueness of `bundleIdentifier` is enforced at the store layer (not via
/// `@Attribute(.unique)`) so the schema stays CloudKit-compatible.
@Model
final class AppExclusion {
    var id = UUID()
    var bundleIdentifier: String = ""
    var appName: String = ""

    init(bundleIdentifier: String, appName: String) {
        id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }
}
