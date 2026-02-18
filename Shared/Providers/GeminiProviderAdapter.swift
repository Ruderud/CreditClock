import Foundation

struct GeminiProviderAdapter: ServiceProvider {
    let serviceId = "gemini"
    private let credentialStore: CredentialStore
    private let credentialsRef: String

    init(credentialStore: CredentialStore = KeychainCredentialStore(),
         credentialsRef: String = "com.creditclock.gemini.credential") {
        self.credentialStore = credentialStore
        self.credentialsRef = credentialsRef
    }

    static func hasLocalCLIOAuthCredentials() -> Bool {
        loadLocalOAuthCredentials() != nil
    }

    func fetchSnapshot() async throws -> ServiceSnapshot {
        var cliError: Error?

        do {
            if let snapshot = try await fetchViaCLIQuota() {
                return snapshot
            }
        } catch {
            cliError = error
        }

        if let snapshot = try await fetchViaAPIKey() {
            return snapshot
        }

        if let cliError {
            throw cliError
        }
        throw ProviderError.notAuthenticated("Gemini (no CLI OAuth credentials or API key)")
    }

    // MARK: - Strategy 1: Gemini CLI OAuth Quota (Daily reset)

    private func fetchViaCLIQuota() async throws -> ServiceSnapshot? {
        guard var credentials = Self.loadLocalOAuthCredentials() else { return nil }
        guard let accessToken = try await validAccessToken(from: &credentials), !accessToken.isEmpty else {
            return nil
        }

        let loadResponse = try await requestLoadCodeAssist(accessToken: accessToken)
        guard let projectId = loadResponse.cloudaicompanionProject, !projectId.isEmpty else {
            return nil
        }

        let quotaResponse = try await requestRetrieveUserQuota(accessToken: accessToken, project: projectId)
        guard let flashBucket = selectBucket(
                from: quotaResponse.buckets,
                modelPrefix: "gemini-3-flash"
        ), let proBucket = selectBucket(
            from: quotaResponse.buckets,
            modelPrefix: "gemini-3-pro"
        ) else {
            return nil
        }

        let flashRemaining = normalizedRemaining(from: flashBucket)
        let proRemaining = normalizedRemaining(from: proBucket)
        let flashUsage = 1 - flashRemaining
        let proUsage = 1 - proRemaining

        let flashReset = parseISO8601Date(flashBucket.resetTime) ?? nextDayReset()
        let proReset = parseISO8601Date(proBucket.resetTime) ?? nextDayReset()
        let primaryUsage = max(flashUsage, proUsage)

        writeWidgetUsageCache(
            flashUsage: flashUsage,
            proUsage: proUsage,
            flashReset: flashReset,
            proReset: proReset
        )

        return ServiceSnapshot(
            id: serviceId,
            name: "Gemini CLI",
            usageUsed: Int((primaryUsage * 100).rounded()),
            usageLimit: 100,
            refillAt: min(flashReset, proReset),
            subscriptionState: primaryUsage >= 0.95 ? .paused : .active,
            subscriptionDetail: nil,
            updatedAt: Date(),
            fiveHourUtilization: flashUsage,
            weeklyUtilization: proUsage,
            fiveHourRefillAt: flashReset,
            weeklyRefillAt: proReset,
            primaryQuotaLabel: "Gemini 3 Flash",
            secondaryQuotaLabel: "Gemini 3 Pro",
            primaryRingLabel: "G3F"
        )
    }

    // MARK: - Strategy 2: Gemini API Key fallback

    private func fetchViaAPIKey() async throws -> ServiceSnapshot? {
        guard let apiKey = try credentialStore.load(key: credentialsRef), !apiKey.isEmpty else {
            return nil
        }

        // Gemini API: list models to verify key validity and estimate usage.
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey)
        ]

        let start = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        _ = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let http = response as? HTTPURLResponse
            throw ProviderError.httpError(http?.statusCode ?? 0, "Gemini")
        }

        // Gemini public API key mode doesn't expose daily request quota fractions.
        // Keep API-key mode as connectivity fallback.
        let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        let modelCount = decoded.models.count

        let now = Date()
        let refillAt = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now

        return ServiceSnapshot(
            id: serviceId,
            name: "Gemini API",
            usageUsed: 0,
            usageLimit: modelCount > 0 ? 30 : 0,
            refillAt: refillAt,
            subscriptionState: modelCount > 0 ? .active : .expired,
            subscriptionDetail: nil,
            updatedAt: now,
            fiveHourUtilization: nil,
            weeklyUtilization: nil,
            fiveHourRefillAt: nil,
            weeklyRefillAt: nil,
            primaryQuotaLabel: nil,
            secondaryQuotaLabel: nil,
            primaryRingLabel: nil
        )
    }

    private func requestLoadCodeAssist(accessToken: String) async throws -> GeminiLoadCodeAssistResponse {
        var request = URLRequest(url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let payload = GeminiLoadCodeAssistRequest(
            metadata: GeminiLoadCodeAssistRequest.Metadata(
                ideType: "IDE_UNSPECIFIED",
                platform: "PLATFORM_UNSPECIFIED",
                pluginType: "GEMINI"
            )
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ProviderError.httpError(code, "Gemini CLI")
        }

        return try JSONDecoder().decode(GeminiLoadCodeAssistResponse.self, from: data)
    }

    private func requestRetrieveUserQuota(accessToken: String, project: String) async throws -> GeminiQuotaResponse {
        var request = URLRequest(url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(GeminiQuotaRequest(project: project))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ProviderError.httpError(code, "Gemini CLI Quota")
        }

        return try JSONDecoder().decode(GeminiQuotaResponse.self, from: data)
    }

    private func validAccessToken(from credentials: inout GeminiCLIOAuthCredentials) async throws -> String? {
        let nowMs = Date().timeIntervalSince1970 * 1000
        if let token = credentials.accessToken,
           !token.isEmpty,
           let expiry = credentials.expiryDate,
           expiry - nowMs > 60_000 {
            return token
        }

        if let refreshToken = credentials.refreshToken,
           !refreshToken.isEmpty,
           let refreshedToken = try await refreshAccessToken(refreshToken: refreshToken, credentials: credentials) {
            credentials.accessToken = refreshedToken
            return refreshedToken
        }

        return credentials.accessToken
    }

    private func refreshAccessToken(
        refreshToken: String,
        credentials: GeminiCLIOAuthCredentials
    ) async throws -> String? {
        guard let clientID = oauthClientID(from: credentials), !clientID.isEmpty else {
            return nil
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var formValues: [String: String] = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        if let clientSecret = oauthClientSecret(from: credentials), !clientSecret.isEmpty {
            formValues["client_secret"] = clientSecret
        }

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

        let refreshed = try JSONDecoder().decode(GeminiTokenRefreshResponse.self, from: data)
        return refreshed.accessToken
    }

    private func selectBucket(from buckets: [GeminiQuotaResponse.Bucket], modelPrefix: String) -> GeminiQuotaResponse.Bucket? {
        let requestBuckets = buckets.filter { ($0.tokenType ?? "").uppercased() == "REQUESTS" }

        if let exact = requestBuckets.first(where: {
            guard let id = $0.modelId else { return false }
            return id.hasPrefix(modelPrefix) && !id.hasSuffix("_vertex")
        }) {
            return exact
        }

        return requestBuckets.first(where: { ($0.modelId ?? "").hasPrefix(modelPrefix) })
    }

    private func normalizedRemaining(from bucket: GeminiQuotaResponse.Bucket) -> Double {
        if let fraction = bucket.remainingFraction {
            return min(max(fraction, 0), 1)
        }
        if let amount = bucket.remainingAmount, let value = Double(amount) {
            return min(max(value, 0), 1)
        }
        return 1
    }

    private func parseISO8601Date(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let parsed = Self.iso8601WithFractional.date(from: value) {
            return parsed
        }
        return Self.iso8601Standard.date(from: value)
    }

    private func nextDayReset() -> Date {
        let now = Date()
        return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
    }

    private func writeWidgetUsageCache(
        flashUsage: Double,
        proUsage: Double,
        flashReset: Date,
        proReset: Date
    ) {
        let cache = GeminiWidgetUsageCache(
            timestamp: Date().timeIntervalSince1970 * 1000,
            data: GeminiWidgetUsageCache.UsageData(
                fiveHourPercent: Int((min(max(flashUsage, 0), 1) * 100).rounded()),
                weeklyPercent: Int((min(max(proUsage, 0), 1) * 100).rounded()),
                fiveHourResetsAt: Self.iso8601WithFractional.string(from: flashReset),
                weeklyResetsAt: Self.iso8601WithFractional.string(from: proReset),
                primaryQuotaLabel: "Gemini 3 Flash",
                secondaryQuotaLabel: "Gemini 3 Pro",
                primaryRingLabel: "G3F"
            ),
            error: false
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(cache) else { return }

        let fallbackURL = SharedFallbackPath.url(fileName: "gemini-usage-cache.json")
        try? data.write(to: fallbackURL, options: .atomic)
    }

    private static func loadLocalOAuthCredentials() -> GeminiCLIOAuthCredentials? {
        if let data = dataFromBookmarkedHome(for: .gemini) {
            return try? JSONDecoder().decode(GeminiCLIOAuthCredentials.self, from: data)
        }
        if !isSandboxed {
            let directURL = URL(fileURLWithPath: realHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".gemini", isDirectory: true)
                .appendingPathComponent("oauth_creds.json")
            if let data = try? Data(contentsOf: directURL) {
                return try? JSONDecoder().decode(GeminiCLIOAuthCredentials.self, from: data)
            }
        }
        return nil
    }

    private static func dataFromBookmarkedHome(for source: LocalDataSource) -> Data? {
        ExternalDataAccess.shared.withDirectoryAccess(for: source) { sourceDir in
            let home = sourceDir.deletingLastPathComponent()
            let credsURL = home
                .appendingPathComponent(".gemini", isDirectory: true)
                .appendingPathComponent("oauth_creds.json")
            return try? Data(contentsOf: credsURL)
        }
    }

    private static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private func oauthClientID(from credentials: GeminiCLIOAuthCredentials) -> String? {
        let env = ProcessInfo.processInfo.environment
        if let id = env["GEMINI_OAUTH_CLIENT_ID"], !id.isEmpty {
            return id
        }
        return credentials.clientID
    }

    private func oauthClientSecret(from credentials: GeminiCLIOAuthCredentials) -> String? {
        let env = ProcessInfo.processInfo.environment
        if let secret = env["GEMINI_OAUTH_CLIENT_SECRET"], !secret.isEmpty {
            return secret
        }
        return credentials.clientSecret
    }

    private static func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
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
}

// MARK: - Gemini API Response Models

private struct GeminiModelsResponse: Decodable {
    let models: [GeminiModel]

    struct GeminiModel: Decodable {
        let name: String
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case name
            case displayName
        }
    }
}

private struct GeminiCLIOAuthCredentials: Codable {
    var accessToken: String?
    let refreshToken: String?
    let scope: String?
    let tokenType: String?
    let idToken: String?
    let expiryDate: Double?
    let clientID: String?
    let clientSecret: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
        case idToken = "id_token"
        case expiryDate = "expiry_date"
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}

private struct GeminiTokenRefreshResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct GeminiLoadCodeAssistRequest: Encodable {
    let metadata: Metadata

    struct Metadata: Encodable {
        let ideType: String
        let platform: String
        let pluginType: String
    }
}

private struct GeminiLoadCodeAssistResponse: Decodable {
    let cloudaicompanionProject: String?
}

private struct GeminiQuotaRequest: Encodable {
    let project: String
}

private struct GeminiQuotaResponse: Decodable {
    let buckets: [Bucket]

    struct Bucket: Decodable {
        let remainingAmount: String?
        let remainingFraction: Double?
        let resetTime: String?
        let tokenType: String?
        let modelId: String?
    }
}

private struct GeminiWidgetUsageCache: Codable {
    let timestamp: Double
    let data: UsageData?
    let error: Bool

    struct UsageData: Codable {
        let fiveHourPercent: Int
        let weeklyPercent: Int
        let fiveHourResetsAt: String
        let weeklyResetsAt: String
        let primaryQuotaLabel: String?
        let secondaryQuotaLabel: String?
        let primaryRingLabel: String?
    }
}
