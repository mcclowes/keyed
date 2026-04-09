import Foundation
import SwiftData

@Model
final class AppExclusion {
    var id: UUID
    var bundleIdentifier: String
    var appName: String

    init(bundleIdentifier: String, appName: String) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }
}
