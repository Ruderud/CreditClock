import Foundation

struct RefreshStateStore {
    private let fileName = "refresh_state.json"

    func setRefreshing(_ refreshing: Bool) {
        AppGroup.defaults?.set(refreshing, forKey: AppGroup.refreshInProgressKey)
        AppGroup.defaults?.synchronize()

        let payload = RefreshStatePayload(refreshing: refreshing, updatedAt: Date().timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(payload) {
            let url = SharedFallbackPath.url(fileName: fileName)
            try? data.write(to: url, options: .atomic)
            let bridgeURL = WidgetBridgePath.appWriteURL(fileName: fileName)
            try? data.write(to: bridgeURL, options: .atomic)
        }
    }

    func isRefreshing() -> Bool {
        let defaultsValue = AppGroup.defaults?.object(forKey: AppGroup.refreshInProgressKey) as? Bool

        let url = SharedFallbackPath.url(fileName: fileName)
        let fileValue: Bool? = {
            guard let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(RefreshStatePayload.self, from: data) else {
                return nil
            }
            return payload.refreshing
        }()

        let bridgeURL = WidgetBridgePath.currentProcessURL(fileName: fileName)
        let bridgeValue: Bool? = {
            guard let data = try? Data(contentsOf: bridgeURL),
                  let payload = try? JSONDecoder().decode(RefreshStatePayload.self, from: data) else {
                return nil
            }
            return payload.refreshing
        }()

        return (defaultsValue == true) || (fileValue == true) || (bridgeValue == true)
    }
}

private struct RefreshStatePayload: Codable {
    let refreshing: Bool
    let updatedAt: TimeInterval
}
