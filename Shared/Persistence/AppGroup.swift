import Foundation

enum AppGroup {
    static let identifier = "group.com.creditclock.shared"
    static let snapshotKey = "service_snapshots"
    static let refreshInProgressKey = "refresh.in_progress"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
