import Foundation

struct SnapshotStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = AppGroup.defaults, key: String = AppGroup.snapshotKey) {
        self.defaults = defaults
        self.key = key
    }

    func save(_ snapshots: [ServiceSnapshot]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }
        defaults.set(data, forKey: key)
    }

    func load() -> [ServiceSnapshot] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ServiceSnapshot].self, from: data)) ?? []
    }
}
