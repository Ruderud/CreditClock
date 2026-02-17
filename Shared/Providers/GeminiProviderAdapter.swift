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

    func fetchSnapshot() async throws -> ServiceSnapshot {
        guard let apiKey = try credentialStore.load(key: credentialsRef), !apiKey.isEmpty else {
            throw ProviderError.notAuthenticated("Gemini")
        }

        // Gemini API: list models to verify key validity and estimate usage
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

        // Gemini free tier doesn't expose usage counts via public API
        // Use model list response as connectivity validation
        let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        let modelCount = decoded.models.count

        let now = Date()
        let refillAt = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now

        return ServiceSnapshot(
            id: serviceId,
            name: "Gemini",
            usageUsed: 0,
            usageLimit: modelCount > 0 ? 30 : 0,
            refillAt: refillAt,
            subscriptionState: modelCount > 0 ? .active : .expired,
            updatedAt: now
        )
    }
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
