import Foundation

struct ProviderConnectionStore {
    private var defaults: UserDefaults {
        AppGroup.defaults ?? .standard
    }

    private func key(for provider: ProviderId) -> String {
        "provider.connected.\(provider.rawValue)"
    }

    func isConnected(_ provider: ProviderId) -> Bool {
        defaults.bool(forKey: key(for: provider))
    }

    func setConnected(_ connected: Bool, for provider: ProviderId) {
        defaults.set(connected, forKey: key(for: provider))
        defaults.synchronize()
    }
}
