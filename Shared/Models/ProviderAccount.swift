import Foundation

enum AuthMethod: String, Codable {
    case apiKey
    case oauth
}

enum ProviderId: String, Codable, CaseIterable {
    case openai
    case anthropic
    case gemini
}

struct ProviderAccount: Codable, Identifiable {
    let id: String
    let provider: ProviderId
    var authMethod: AuthMethod
    var credentialsRef: String
    var isEnabled: Bool
    var pollIntervalSeconds: TimeInterval

    static func defaultAccount(for provider: ProviderId) -> ProviderAccount {
        ProviderAccount(
            id: provider.rawValue,
            provider: provider,
            authMethod: .apiKey,
            credentialsRef: "com.creditclock.\(provider.rawValue).credential",
            isEnabled: false,
            pollIntervalSeconds: 300
        )
    }
}
