import Foundation
import Security

struct AnthropicProviderAdapter: ServiceProvider {
    let serviceId = "anthropic"

    func fetchSnapshot() async throws -> ServiceSnapshot {
        // Strategy 1: Read from OMC cache (updated every 30s when Claude Code is running)
        if let cached = readOMCCache() {
            return cached
        }

        // Strategy 2: Direct OAuth API call using Claude Code credentials from Keychain
        if let oauthResult = try await fetchViaOAuth() {
            return oauthResult
        }

        throw ProviderError.notAuthenticated("Claude (no OAuth credentials found)")
    }

    // MARK: - Strategy 1: OMC Usage Cache

    private func readOMCCache() -> ServiceSnapshot? {
        let cachePath = realHomeDirectory() + "/.claude/plugins/oh-my-claudecode/.usage-cache.json"
        guard let data = FileManager.default.contents(atPath: cachePath) else { return nil }

        struct OMCCache: Decodable {
            let timestamp: Double
            let data: OMCUsage?
            let error: Bool?
        }
        struct OMCUsage: Decodable {
            let fiveHourPercent: Int?
            let weeklyPercent: Int?
            let fiveHourResetsAt: String?
            let weeklyResetsAt: String?
        }

        guard let cache = try? JSONDecoder().decode(OMCCache.self, from: data),
              let usage = cache.data,
              cache.error != true else { return nil }

        // Cache older than 5 minutes is stale
        let cacheAge = Date().timeIntervalSince1970 * 1000 - cache.timestamp
        guard cacheAge < 300_000 else { return nil }

        let fiveHour = usage.fiveHourPercent ?? 0
        let weekly = usage.weeklyPercent ?? 0

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fiveHourReset: Date
        if let resetStr = usage.fiveHourResetsAt, let d = iso.date(from: resetStr) {
            fiveHourReset = d
        } else {
            fiveHourReset = Date().addingTimeInterval(3600)
        }

        // Use the higher utilization as primary display
        let primaryPercent = max(fiveHour, weekly)

        return ServiceSnapshot(
            id: serviceId,
            name: "Claude — 5h:\(fiveHour)% wk:\(weekly)%",
            usageUsed: primaryPercent,
            usageLimit: 100,
            refillAt: fiveHourReset,
            subscriptionState: primaryPercent >= 90 ? .paused : .active,
            updatedAt: Date()
        )
    }

    // MARK: - Strategy 2: Direct OAuth API

    private func fetchViaOAuth() async throws -> ServiceSnapshot? {
        guard let token = readClaudeCodeOAuthToken() else { return nil }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil // Don't throw — fall through to error
        }

        let decoded = try JSONDecoder().decode(OAuthUsageResponse.self, from: data)

        let fiveHour = Int(decoded.fiveHour?.utilization ?? 0)
        let weekly = Int(decoded.sevenDay?.utilization ?? 0)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let resetDate: Date
        if let resetStr = decoded.fiveHour?.resetsAt, let d = iso.date(from: resetStr) {
            resetDate = d
        } else {
            resetDate = Date().addingTimeInterval(3600)
        }

        let primaryPercent = max(fiveHour, weekly)

        return ServiceSnapshot(
            id: serviceId,
            name: "Claude — 5h:\(fiveHour)% wk:\(weekly)%",
            usageUsed: primaryPercent,
            usageLimit: 100,
            refillAt: resetDate,
            subscriptionState: primaryPercent >= 90 ? .paused : .active,
            updatedAt: Date()
        )
    }

    // MARK: - Keychain OAuth Token

    private func readClaudeCodeOAuthToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }

        // Parse JSON to extract accessToken
        struct ClaudeCredentials: Decodable {
            let claudeAiOauth: OAuthFields?
            let accessToken: String?

            struct OAuthFields: Decodable {
                let accessToken: String?
            }
        }

        guard let creds = try? JSONDecoder().decode(ClaudeCredentials.self, from: data) else { return nil }
        return creds.claudeAiOauth?.accessToken ?? creds.accessToken
    }
}

// MARK: - OAuth API Response

private struct OAuthUsageResponse: Decodable {
    let fiveHour: Window?
    let sevenDay: Window?

    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}
