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

        // File-based (App Group primary)
        if let url = appGroupFileURL() {
            do {
                let data = try Data(contentsOf: url)
                if let snapshots = try? decoder.decode([ServiceSnapshot].self, from: data), !snapshots.isEmpty {
                    writeFallback(data)
                    return (snapshots, "source=appGroupFile count=\(snapshots.count)")
                }
                debugMessages.append("appGroupFile decodeEmpty")
            } catch {
                debugMessages.append("appGroupFile error=\(error.localizedDescription)")
            }
        } else {
            debugMessages.append("appGroupFile unavailable")
        }

        // File-based fallback
        let fallbackURL = SharedFallbackPath.url(fileName: fileName)
        do {
            let data = try Data(contentsOf: fallbackURL)
            if let snapshots = try? decoder.decode([ServiceSnapshot].self, from: data), !snapshots.isEmpty {
                return (snapshots, "source=fallbackFile count=\(snapshots.count)")
            }
            debugMessages.append("fallbackFile decodeEmpty")
        } catch {
            debugMessages.append("fallbackFile error=\(error.localizedDescription)")
        }

        // Widget container bridge file
        let bridgeURL = WidgetBridgePath.currentProcessURL(fileName: fileName)
        do {
            let data = try Data(contentsOf: bridgeURL)
            if let snapshots = try? decoder.decode([ServiceSnapshot].self, from: data), !snapshots.isEmpty {
                return (snapshots, "source=widgetBridgeFile count=\(snapshots.count)")
            }
            debugMessages.append("widgetBridgeFile decodeEmpty")
        } catch {
            debugMessages.append("widgetBridgeFile error=\(error.localizedDescription)")
        }

        // UserDefaults (fallback)
        guard let data = AppGroup.defaults?.data(forKey: AppGroup.snapshotKey),
              let snapshots = try? decoder.decode([ServiceSnapshot].self, from: data) else {
            debugMessages.append("userDefaults empty")
            return ([], debugMessages.joined(separator: " | "))
        }
        if !snapshots.isEmpty {
            writeFallback(data)
        }
        return (snapshots, "source=userDefaults count=\(snapshots.count)")
    }

    private func appGroupFileURL() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupId
        ) else { return nil }
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return container.appendingPathComponent(fileName)
    }

    private func writeFallback(_ data: Data) {
        let fallbackURL = SharedFallbackPath.url(fileName: fileName)
        try? data.write(to: fallbackURL, options: .atomic)
    }

    private func writeWidgetBridge(_ data: Data) {
        let bridgeURL = WidgetBridgePath.appWriteURL(fileName: fileName)
        try? data.write(to: bridgeURL, options: .atomic)
    }
}
