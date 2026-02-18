import Foundation

enum AppDeepLink {
    static let dashboardWindowID = "dashboard"
    static let scheme = "creditclock"
    static let dashboardHost = "dashboard"

    static var dashboardURL: URL? {
        URL(string: "\(scheme)://\(dashboardHost)")
    }
}
