import Foundation
import SwiftData

@Model
final class AppExclusion {
    var id: UUID
    @Attribute(.unique) var bundleIdentifier: String
    var appName: String

    init(bundleIdentifier: String, appName: String) {
        id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }
}
