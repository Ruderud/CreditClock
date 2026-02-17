import Foundation

struct SnapshotStore {
    private let groupId = AppGroup.identifier
    private let fileName = "snapshots.json"

    /// Primary: file in App Group container. Fallback: UserDefaults suite.
    func save(_ snapshots: [ServiceSnapshot]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }

        // File-based (primary)
        if let url = containerFileURL() {
            try? data.write(to: url, options: .atomic)
        }

        // UserDefaults (fallback)
        let defaults = AppGroup.defaults
        defaults.set(data, forKey: AppGroup.snapshotKey)
        defaults.synchronize()
    }

    func load() -> [ServiceSnapshot] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // File-based (primary)
        if let url = containerFileURL(),
           let data = try? Data(contentsOf: url),
           let snapshots = try? decoder.decode([ServiceSnapshot].self, from: data),
           !snapshots.isEmpty {
            return snapshots
        }

        // UserDefaults (fallback)
        guard let data = AppGroup.defaults.data(forKey: AppGroup.snapshotKey) else { return [] }
        return (try? decoder.decode([ServiceSnapshot].self, from: data)) ?? []
    }

    private func containerFileURL() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupId
        ) else { return nil }
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return container.appendingPathComponent(fileName)
    }
}
