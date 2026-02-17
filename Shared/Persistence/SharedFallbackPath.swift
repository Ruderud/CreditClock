import Foundation

enum SharedFallbackPath {
    static let directoryName = ".creditclock"

    static func url(fileName: String) -> URL {
        let directory = URL(fileURLWithPath: realHomeDirectory(), isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }
}
