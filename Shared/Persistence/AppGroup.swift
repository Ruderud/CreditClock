import Foundation

enum AppGroup {
    static let identifier = "group.com.creditclock.shared"
    static let snapshotKey = "service_snapshots"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
