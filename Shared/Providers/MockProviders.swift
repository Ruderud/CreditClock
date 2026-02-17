import Foundation

struct MockServiceProvider: ServiceProvider {
    let serviceId: String
    let serviceName: String
    let limit: Int
    let baselineUsed: Int
    let refillHours: Int
    let state: SubscriptionState

    func fetchSnapshot() async throws -> ServiceSnapshot {
        let variance = Int.random(in: -3...4)
        let used = max(min(baselineUsed + variance, limit), 0)
        let refillAt = Calendar.current.date(byAdding: .hour, value: refillHours, to: Date()) ?? Date()

        return ServiceSnapshot(
            id: serviceId,
            name: serviceName,
            usageUsed: used,
            usageLimit: limit,
            refillAt: refillAt,
            subscriptionState: state,
            updatedAt: Date()
        )
    }
}

enum ProviderCatalog {
    static func defaultProviders() -> [ServiceProvider] {
        [
            MockServiceProvider(
                serviceId: "openai",
                serviceName: "GPT / OpenAI",
                limit: 100,
                baselineUsed: 78,
                refillHours: 14,
                state: .active
            ),
            MockServiceProvider(
                serviceId: "anthropic",
                serviceName: "Claude",
                limit: 50,
                baselineUsed: 37,
                refillHours: 40,
                state: .active
            ),
            MockServiceProvider(
                serviceId: "gemini",
                serviceName: "Gemini",
                limit: 30,
                baselineUsed: 19,
                refillHours: 8,
                state: .trial
            )
        ]
    }
}
