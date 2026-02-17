import Foundation

enum LocalDataSource: String, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        }
    }

    var expectedDirectoryName: String {
        switch self {
        case .codex: return ".codex"
        case .claude: return ".claude"
        }
    }

    fileprivate var bookmarkKey: String {
        "localAccessBookmark.\(rawValue)"
    }
}

final class ExternalDataAccess {
    static let shared = ExternalDataAccess()

    private init() {}

    private var defaults: UserDefaults { AppGroup.defaults ?? .standard }

    func hasBookmark(for source: LocalDataSource) -> Bool {
        defaults.data(forKey: source.bookmarkKey) != nil
    }

    func hasAnyBookmark() -> Bool {
        LocalDataSource.allCases.contains { hasBookmark(for: $0) }
    }

    func isConfigured(for source: LocalDataSource) -> Bool {
        if hasBookmark(for: source) {
            return withDirectoryAccess(for: source) { url in
                FileManager.default.fileExists(atPath: url.path)
            } ?? false
        }
        guard !isSandboxed else { return false }

        let url = URL(fileURLWithPath: realHomeDirectory(), isDirectory: true)
            .appendingPathComponent(source.expectedDirectoryName, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path)
    }

    func saveBookmark(_ data: Data, for source: LocalDataSource) {
        defaults.set(data, forKey: source.bookmarkKey)
        defaults.synchronize()
    }

    func clearBookmark(for source: LocalDataSource) {
        defaults.removeObject(forKey: source.bookmarkKey)
        defaults.synchronize()
    }

    func withDirectoryAccess<T>(for source: LocalDataSource, _ body: (URL) -> T?) -> T? {
        if let bookmarkData = defaults.data(forKey: source.bookmarkKey) {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }

            if isStale,
               let refreshed = try? url.bookmarkData(
                   options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                   includingResourceValuesForKeys: nil,
                   relativeTo: nil
               ) {
                saveBookmark(refreshed, for: source)
            }

            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            return body(resolvedDirectory(from: url, for: source))
        }

        guard !isSandboxed else { return nil }
        let directURL = URL(fileURLWithPath: realHomeDirectory(), isDirectory: true)
            .appendingPathComponent(source.expectedDirectoryName, isDirectory: true)
        return body(directURL)
    }

    private func resolvedDirectory(from bookmarkURL: URL, for source: LocalDataSource) -> URL {
        if bookmarkURL.lastPathComponent == source.expectedDirectoryName {
            return bookmarkURL
        }
        return bookmarkURL.appendingPathComponent(source.expectedDirectoryName, isDirectory: true)
    }

    private var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
