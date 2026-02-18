import Foundation
import Security

struct AnthropicProviderAdapter: ServiceProvider {
    let serviceId = "anthropic"

    func fetchSnapshot() async throws -> ServiceSnapshot {
        // Strategy 1: Read from OMC cache first to avoid frequent keychain prompts.
        if let cached = readOMCCache() {
            ProviderRecovery.log(.info, "[claude] load success source=omcCache")
            return cached
        }
        ProviderRecovery.log(.debug, "[claude] omc cache unavailable, trying oauth")

        // Strategy 2: Direct OAuth API call with refresh-token fallback.
        var oauthError: Error?
        do {
            let oauthResult = try await fetchViaOAuth()
            ProviderRecovery.log(.info, "[claude] load success source=oauth")
            return oauthResult
        } catch {
            ProviderRecovery.log(.default, "[claude] oauth failed: \(error.localizedDescription)")
            oauthError = error
        }

        // Token can expire; for OAuth 401, run Claude CLI once to refresh auth artifacts,
        // then retry cache/OAuth once.
        if let oauthFailure = oauthError, ProviderRecovery.isUnauthorized(oauthFailure) {
            guard ProviderRecovery.canRunCLIWarmup else {
                ProviderRecovery.log(
                    .default,
                    "[claude] oauth 401 but sandbox blocks CLI warmup. Re-authenticate via Terminal (`claude login`)."
                )
                throw oauthFailure
            }
            ProviderRecovery.log(.default, "[claude] oauth 401 detected, attempting CLI warmup")
            let ranWarmup = await ProviderRecovery.runCLIWarmup(
                command: "claude",
                arguments: [
                    "-p",
                    "ping",
                    "--output-format",
                    "json"
                ]
            )
            ProviderRecovery.log(
                .info,
                "[claude] warmup \(ranWarmup ? "executed" : "skipped_or_failed"), retrying cache/oauth"
            )

            if let cached = readOMCCache() {
                ProviderRecovery.log(.info, "[claude] load success after warmup source=omcCache")
                return cached
            }
            do {
                let oauthResult = try await fetchViaOAuth()
                ProviderRecovery.log(.info, "[claude] load success after warmup source=oauth")
                return oauthResult
            } catch {
                ProviderRecovery.log(.default, "[claude] oauth retry failed: \(error.localizedDescription)")
                oauthError = error
            }
        }

        if let oauthError {
            ProviderRecovery.log(.error, "[claude] load failed with oauth error: \(oauthError.localizedDescription)")
            throw oauthError
        }
        ProviderRecovery.log(.error, "[claude] load failed: not authenticated")
        throw ProviderError.notAuthenticated("Claude (no OAuth credentials or folder access)")
    }

    // MARK: - Strategy 1: OMC Usage Cache

    private func readOMCCache() -> ServiceSnapshot? {
        guard let data = ExternalDataAccess.shared.withDirectoryAccess(for: .claude, { claudeDir in
            let cacheURL = claudeDir
                .appendingPathComponent("plugins", isDirectory: true)
                .appendingPathComponent("oh-my-claudecode", isDirectory: true)
                .appendingPathComponent(".usage-cache.json")
            return try? Data(contentsOf: cacheURL)
        }) else { return nil }

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
            let subscriptionType: String?
            let rateLimitTier: String?

            enum CodingKeys: String, CodingKey {
                case fiveHourPercent
                case weeklyPercent
                case fiveHourResetsAt
                case weeklyResetsAt
                case subscriptionType
                case rateLimitTier
                case subscriptionTypeSnake = "subscription_type"
                case rateLimitTierSnake = "rate_limit_tier"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                fiveHourPercent = try container.decodeIfPresent(Int.self, forKey: .fiveHourPercent)
                weeklyPercent = try container.decodeIfPresent(Int.self, forKey: .weeklyPercent)
                fiveHourResetsAt = try container.decodeIfPresent(String.self, forKey: .fiveHourResetsAt)
                weeklyResetsAt = try container.decodeIfPresent(String.self, forKey: .weeklyResetsAt)
                subscriptionType = try container.decodeIfPresent(String.self, forKey: .subscriptionType)
                    ?? (try container.decodeIfPresent(String.self, forKey: .subscriptionTypeSnake))
                rateLimitTier = try container.decodeIfPresent(String.self, forKey: .rateLimitTier)
                    ?? (try container.decodeIfPresent(String.self, forKey: .rateLimitTierSnake))
            }
        }

        guard let cache = try? JSONDecoder().decode(OMCCache.self, from: data),
              let usage = cache.data,
              cache.error != true else { return nil }

        // Cache older than 5 minutes is stale
        let cacheAge = Date().timeIntervalSince1970 * 1000 - cache.timestamp
        guard cacheAge < 300_000 else { return nil }

        let fiveHour = usage.fiveHourPercent ?? 0
        let weekly = usage.weeklyPercent ?? 0

        let fiveHourReset: Date
        if let d = parseISO8601Date(usage.fiveHourResetsAt) {
            fiveHourReset = d
        } else {
            fiveHourReset = Date().addingTimeInterval(3600)
        }
        let weeklyReset: Date
        if let d = parseISO8601Date(usage.weeklyResetsAt) {
            weeklyReset = d
        } else {
            weeklyReset = Date().addingTimeInterval(7 * 24 * 3600)
        }

        // Use the higher utilization as primary display
        let primaryPercent = max(fiveHour, weekly)
        let subscriptionDetail = normalizedPlanDetail(
            subscriptionType: usage.subscriptionType,
            rateLimitTier: usage.rateLimitTier
        ) ?? readCachedPlanDetailFromCredentials()

        return ServiceSnapshot(
            id: serviceId,
            name: "Claude — 5h:\(fiveHour)% wk:\(weekly)%",
            usageUsed: primaryPercent,
            usageLimit: 100,
            refillAt: fiveHourReset,
            subscriptionState: primaryPercent >= 90 ? .paused : .active,
            subscriptionDetail: subscriptionDetail,
            updatedAt: Date(),
            fiveHourUtilization: Double(fiveHour) / 100,
            weeklyUtilization: Double(weekly) / 100,
            fiveHourRefillAt: fiveHourReset,
            weeklyRefillAt: weeklyReset,
            primaryQuotaLabel: nil,
            secondaryQuotaLabel: nil,
            primaryRingLabel: nil
        )
    }

    // MARK: - Strategy 2: Direct OAuth API

    private func fetchViaOAuth() async throws -> ServiceSnapshot {
        guard var credentials = readClaudeCodeOAuthCredentials() else {
            throw ProviderError.notAuthenticated("Claude OAuth credentials not found")
        }

        guard let accessToken = try await validAccessToken(from: &credentials), !accessToken.isEmpty else {
            throw ProviderError.notAuthenticated("Claude OAuth token expired. Reconnect in Settings.")
        }

        do {
            let decoded = try await requestOAuthUsage(accessToken: accessToken)
            return makeSnapshot(from: decoded, credentials: credentials)
        } catch ProviderError.httpError(let code, _) where code == 401 {
            // Token can be revoked/expired before local expiresAt. Refresh once and retry.
            guard let refreshToken = credentials.refreshToken,
                  let refreshed = try await refreshAccessToken(refreshToken: refreshToken) else {
                throw ProviderError.notAuthenticated("Claude OAuth token expired. Reconnect in Settings.")
            }
            credentials.accessToken = refreshed.accessToken
            credentials.refreshToken = refreshed.refreshToken ?? credentials.refreshToken
            credentials.expiresAtMs = refreshed.expiresAtMs
            writeClaudeCodeOAuthCredentials(credentials)

            let decoded = try await requestOAuthUsage(accessToken: credentials.accessToken)
            return makeSnapshot(from: decoded, credentials: credentials)
        }
    }

    private func makeSnapshot(from decoded: OAuthUsageResponse, credentials: ClaudeOAuthCredentials) -> ServiceSnapshot {
        let fiveHour = Int(decoded.fiveHour?.utilization ?? 0)
        let weekly = Int(decoded.sevenDay?.utilization ?? 0)

        let resetDate = parseISO8601Date(decoded.fiveHour?.resetsAt) ?? Date().addingTimeInterval(3600)
        let weeklyReset = parseISO8601Date(decoded.sevenDay?.resetsAt) ?? Date().addingTimeInterval(7 * 24 * 3600)
        let primaryPercent = max(fiveHour, weekly)
        let subscriptionDetail = normalizedPlanDetail(
            subscriptionType: decoded.subscriptionType ?? credentials.subscriptionType,
            rateLimitTier: decoded.rateLimitTier ?? credentials.rateLimitTier
        )
        cachePlanDetail(subscriptionDetail)

        return ServiceSnapshot(
            id: serviceId,
            name: "Claude — 5h:\(fiveHour)% wk:\(weekly)%",
            usageUsed: primaryPercent,
            usageLimit: 100,
            refillAt: resetDate,
            subscriptionState: primaryPercent >= 90 ? .paused : .active,
            subscriptionDetail: subscriptionDetail,
            updatedAt: Date(),
            fiveHourUtilization: Double(fiveHour) / 100,
            weeklyUtilization: Double(weekly) / 100,
            fiveHourRefillAt: resetDate,
            weeklyRefillAt: weeklyReset,
            primaryQuotaLabel: nil,
            secondaryQuotaLabel: nil,
            primaryRingLabel: nil
        )
    }

    private func requestOAuthUsage(accessToken: String) async throws -> OAuthUsageResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.httpError(0, "Claude OAuth usage API")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.httpError(http.statusCode, "Claude OAuth usage API")
        }

        return try JSONDecoder().decode(OAuthUsageResponse.self, from: data)
    }

    // MARK: - Keychain OAuth Token

    private func readClaudeCodeOAuthCredentials() -> ClaudeOAuthCredentials? {
        if let creds = AnthropicProviderAdapter.readClaudeCodeOAuthCredentialsFromKeychain() {
            return creds
        }
        return readClaudeCodeOAuthCredentialsFromFile()
    }

    private static func readClaudeCodeOAuthCredentialsFromKeychain() -> ClaudeOAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return parseOAuthCredentials(from: data, source: .keychain)
    }

    private func readClaudeCodeOAuthCredentialsFromFile() -> ClaudeOAuthCredentials? {
        guard let data = ExternalDataAccess.shared.withDirectoryAccess(for: .claude, { claudeDir in
            let credsURL = claudeDir.appendingPathComponent(".credentials.json")
            return try? Data(contentsOf: credsURL)
        }) else { return nil }
        return AnthropicProviderAdapter.parseOAuthCredentials(from: data, source: .file)
    }

    private static func parseOAuthCredentials(from data: Data, source: OAuthCredentialSource) -> ClaudeOAuthCredentials? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let oauth = (raw["claudeAiOauth"] as? [String: Any]) ?? raw

        guard let accessToken = stringValue(in: oauth, keys: ["accessToken", "access_token"]), !accessToken.isEmpty else {
            return nil
        }

        let refreshToken = stringValue(in: oauth, keys: ["refreshToken", "refresh_token"])
        let expiresAtMs = numericValue(in: oauth, keys: ["expiresAt", "expires_at"]).map { value in
            value > 10_000_000_000 ? value : value * 1000
        }
        let subscriptionType = stringValue(in: oauth, keys: ["subscriptionType", "subscription_type"])
        let rateLimitTier = stringValue(in: oauth, keys: ["rateLimitTier", "rate_limit_tier"])

        return ClaudeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAtMs: expiresAtMs,
            subscriptionType: subscriptionType,
            rateLimitTier: rateLimitTier,
            source: source
        )
    }

    private func validAccessToken(from credentials: inout ClaudeOAuthCredentials) async throws -> String? {
        let nowMs = Date().timeIntervalSince1970 * 1000
        if let expiresAtMs = credentials.expiresAtMs {
            if expiresAtMs - nowMs > 60_000 {
                return credentials.accessToken
            }
        } else {
            return credentials.accessToken
        }

        guard let refreshToken = credentials.refreshToken,
              let refreshed = try await refreshAccessToken(refreshToken: refreshToken) else {
            return nil
        }

        credentials.accessToken = refreshed.accessToken
        credentials.refreshToken = refreshed.refreshToken ?? credentials.refreshToken
        credentials.expiresAtMs = refreshed.expiresAtMs
        writeClaudeCodeOAuthCredentials(credentials)
        return credentials.accessToken
    }

    private func refreshAccessToken(refreshToken: String) async throws -> RefreshedOAuthToken? {
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let clientID = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_CLIENT_ID"]
            ?? Self.defaultOAuthClientID

        let formValues: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ]
        let form = formValues
            .map { key, value in
                "\(Self.percentEncode(key))=\(Self.percentEncode(value))"
            }
            .joined(separator: "&")
        request.httpBody = form.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(OAuthRefreshResponse.self, from: data)
        guard !decoded.accessToken.isEmpty else { return nil }

        let expiresAtMs: Double? = {
            if let expiresIn = decoded.expiresIn {
                return Date().timeIntervalSince1970 * 1000 + (expiresIn * 1000)
            }
            if let expiresAt = decoded.expiresAt {
                return expiresAt > 10_000_000_000 ? expiresAt : expiresAt * 1000
            }
            return nil
        }()

        return RefreshedOAuthToken(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresAtMs: expiresAtMs
        )
    }

    private func writeClaudeCodeOAuthCredentials(_ credentials: ClaudeOAuthCredentials) {
        switch credentials.source {
        case .keychain:
            Self.writeClaudeCodeOAuthCredentialsToKeychain(credentials)
        case .file:
            break
        }
    }

    private static func writeClaudeCodeOAuthCredentialsToKeychain(_ credentials: ClaudeOAuthCredentials) {
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &result)
        guard readStatus == errSecSuccess, let data = result as? Data else { return }
        guard var raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if var oauth = raw["claudeAiOauth"] as? [String: Any] {
            oauth["accessToken"] = credentials.accessToken
            oauth["refreshToken"] = credentials.refreshToken
            if let expiresAtMs = credentials.expiresAtMs {
                oauth["expiresAt"] = Int64(expiresAtMs.rounded())
            }
            raw["claudeAiOauth"] = oauth
        } else {
            raw["accessToken"] = credentials.accessToken
            raw["refreshToken"] = credentials.refreshToken
            if let expiresAtMs = credentials.expiresAtMs {
                raw["expiresAt"] = Int64(expiresAtMs.rounded())
            }
        }

        guard let updatedData = try? JSONSerialization.data(withJSONObject: raw) else { return }
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials"
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: updatedData
        ]
        _ = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
    }

    private static func stringValue(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func numericValue(in dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dict[key] as? Double {
                return value
            }
            if let value = dict[key] as? Int {
                return Double(value)
            }
            if let value = dict[key] as? Int64 {
                return Double(value)
            }
            if let value = dict[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = dict[key] as? String, let parsed = Double(value) {
                return parsed
            }
        }
        return nil
    }

    private static func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func normalizedPlanDetail(subscriptionType: String?, rateLimitTier: String?) -> String? {
        if let normalized = normalizeTierToken(subscriptionType) {
            return normalized
        }
        if let normalized = normalizeTierToken(rateLimitTier) {
            return normalized
        }
        return nil
    }

    private func normalizeTierToken(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let lowered = raw.lowercased()
        if lowered.contains("max") {
            return "Max"
        }
        if lowered.contains("pro") {
            return "Pro"
        }
        if lowered.contains("free") {
            return "Free"
        }
        return nil
    }

    private func readCachedPlanDetailFromCredentials() -> String? {
        if Self.planDetailResolved {
            return Self.cachedPlanDetail
        }

        let detail = readClaudeCodeOAuthCredentials().flatMap {
            normalizedPlanDetail(subscriptionType: $0.subscriptionType, rateLimitTier: $0.rateLimitTier)
        }
        Self.cachedPlanDetail = detail
        Self.planDetailResolved = true
        return detail
    }

    private func cachePlanDetail(_ detail: String?) {
        guard let detail, !detail.isEmpty else { return }
        Self.cachedPlanDetail = detail
        Self.planDetailResolved = true
    }

    private func parseISO8601Date(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let parsed = Self.iso8601WithFractional.date(from: value) {
            return parsed
        }
        return Self.iso8601Standard.date(from: value)
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let defaultOAuthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static var cachedPlanDetail: String?
    private static var planDetailResolved = false
}

// MARK: - OAuth API Response

private struct OAuthUsageResponse: Decodable {
    let fiveHour: Window?
    let sevenDay: Window?
    let subscriptionType: String?
    let rateLimitTier: String?

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
        case subscriptionType = "subscription_type"
        case rateLimitTier = "rate_limit_tier"
    }
}

private struct OAuthRefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?
    let expiresAt: Double?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
    }
}

private struct RefreshedOAuthToken {
    let accessToken: String
    let refreshToken: String?
    let expiresAtMs: Double?
}

private enum OAuthCredentialSource {
    case keychain
    case file
}

private struct ClaudeOAuthCredentials {
    var accessToken: String
    var refreshToken: String?
    var expiresAtMs: Double?
    var subscriptionType: String?
    var rateLimitTier: String?
    let source: OAuthCredentialSource
}
