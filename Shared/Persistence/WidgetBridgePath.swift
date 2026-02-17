import Foundation

enum WidgetBridgePath {
    static let widgetBundleId = "com.creditclock.app.widget"

    static func appWriteURL(fileName: String) -> URL {
        let root = URL(fileURLWithPath: realHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Containers/\(widgetBundleId)/Data/Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(fileName)
    }

    static func currentProcessURL(fileName: String) -> URL {
        if Bundle.main.bundleIdentifier == widgetBundleId,
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return docs.appendingPathComponent(fileName)
        }
        return appWriteURL(fileName: fileName)
    }
}
