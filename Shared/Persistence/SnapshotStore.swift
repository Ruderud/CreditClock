import Foundation

struct SnapshotStore {
    private let groupId = AppGroup.identifier
    private let fileName = "snapshots.json"

    /// Primary: file in App Group container. Fallback: UserDefaults suite.
    func save(_ snapshots: [ServiceSnapshot]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }

        // File-based (App Group primary)
        if let url = appGroupFileURL() {
            try? data.write(to: url, options: .atomic)
        }

        // File-based fallback (always mirrored)
        writeFallback(data)
        writeWidgetBridge(data)

        // UserDefaults (fallback)
        if let defaults = AppGroup.defaults {
            defaults.set(data, forKey: AppGroup.snapshotKey)
            defaults.synchronize()
        }
    }

    func load() -> [ServiceSnapshot] {
        loadWithDiagnostics().snapshots
    }

    func loadWithDiagnostics() -> (snapshots: [ServiceSnapshot], debug: String) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var debugMessages: [String] = []
        var candidates: [SnapshotCandidate] = []

        func appendCandidate(source: String, data: Data) {
            guard let snapshots = try? decoder.decode([ServiceSnapshot].self, from: data), !snapshots.isEmpty else {
                debugMessages.append("\(source) decodeEmpty")
                return
            }
            candidates.append(
                SnapshotCandidate(
                    source: source,
                    snapshots: snapshots,
                    data: data,
                    priority: sourcePriority(source)
                )
            )
        }

        // File-based (App Group primary)
        if let url = appGroupFileURL() {
            do {
                let data = try Data(contentsOf: url)
                appendCandidate(source: "appGroupFile", data: data)
            } catch {
                debugMessages.append("appGroupFile error=\(error.localizedDescription)")
            }
        } else {
            debugMessages.append("appGroupFile unavailable")
        }

        // Direct path to group container (fallback for environments where containerURL can fail).
        let directGroupURL = directAppGroupFileURL()
        do {
            let data = try Data(contentsOf: directGroupURL)
            appendCandidate(source: "directAppGroupFile", data: data)
        } catch {
            debugMessages.append("directAppGroupFile error=\(error.localizedDescription)")
        }

        // File-based fallback
        let fallbackURL = SharedFallbackPath.url(fileName: fileName)
        do {
            let data = try Data(contentsOf: fallbackURL)
            appendCandidate(source: "fallbackFile", data: data)
        } catch {
            debugMessages.append("fallbackFile error=\(error.localizedDescription)")
        }

        // Widget container bridge file
        let bridgeURL = WidgetBridgePath.currentProcessURL(fileName: fileName)
        do {
            let data = try Data(contentsOf: bridgeURL)
            appendCandidate(source: "widgetBridgeFile", data: data)
        } catch {
            debugMessages.append("widgetBridgeFile error=\(error.localizedDescription)")
        }

        // UserDefaults (fallback)
        if let data = AppGroup.defaults?.data(forKey: AppGroup.snapshotKey) {
            appendCandidate(source: "userDefaults", data: data)
        } else {
            debugMessages.append("userDefaults empty")
        }

        guard let latest = selectLatestCandidate(from: candidates) else {
            return ([], debugMessages.joined(separator: " | "))
        }

        // Only mirror when the freshest source is the app-group file.
        // This prevents widget-side reads of stale fallback files from clobbering newer data.
        if latest.source == "appGroupFile" {
            writeFallback(latest.data)
            writeWidgetBridge(latest.data)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let latestUpdatedAt = formatter.string(from: latest.latestUpdatedAt)
        return (
            latest.snapshots,
            "source=\(latest.source) count=\(latest.snapshots.count) latestUpdatedAt=\(latestUpdatedAt)"
        )
    }

    private func appGroupFileURL() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupId
        ) else { return nil }
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return container.appendingPathComponent(fileName)
    }

    private func directAppGroupFileURL() -> URL {
        URL(fileURLWithPath: realHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Group Containers/\(groupId)", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private func writeFallback(_ data: Data) {
        let fallbackURL = SharedFallbackPath.url(fileName: fileName)
        try? data.write(to: fallbackURL, options: .atomic)
    }

    private func writeWidgetBridge(_ data: Data) {
        let bridgeURL = WidgetBridgePath.appWriteURL(fileName: fileName)
        try? data.write(to: bridgeURL, options: .atomic)
    }

    private func selectLatestCandidate(from candidates: [SnapshotCandidate]) -> SnapshotCandidate? {
        candidates.max { lhs, rhs in
            if lhs.latestUpdatedAt != rhs.latestUpdatedAt {
                return lhs.latestUpdatedAt < rhs.latestUpdatedAt
            }
            return lhs.priority < rhs.priority
        }
    }

    private func sourcePriority(_ source: String) -> Int {
        switch source {
        case "appGroupFile":
            return 4
        case "directAppGroupFile":
            return 3
        case "widgetBridgeFile":
            return 2
        case "fallbackFile":
            return 1
        case "userDefaults":
            return 0
        default:
            return 0
        }
    }
}

private struct SnapshotCandidate {
    let source: String
    let snapshots: [ServiceSnapshot]
    let data: Data
    let priority: Int

    var latestUpdatedAt: Date {
        snapshots.map(\.updatedAt).max() ?? .distantPast
    }
}
