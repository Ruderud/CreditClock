import Foundation

enum SubscriptionState: String, Codable, CaseIterable {
    case active
    case trial
    case expired
    case paused

    var title: String {
        switch self {
        case .active: return "Active"
        case .trial: return "Trial"
        case .expired: return "Expired"
        case .paused: return "Paused"
        }
    }
}

struct ServiceSnapshot: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let usageUsed: Int
    let usageLimit: Int
    let refillAt: Date
    let subscriptionState: SubscriptionState
    let updatedAt: Date

    var remaining: Int {
        max(usageLimit - usageUsed, 0)
    }

    var utilization: Double {
        guard usageLimit > 0 else { return 0 }
        return min(Double(usageUsed) / Double(usageLimit), 1)
    }

    var refillDescription: String {
        ServiceSnapshot.relativeFormatter.localizedString(for: refillAt, relativeTo: Date())
    }

    /// Progress for circular countdown ring (0 = just started, 1 = refill imminent)
    var refillRingProgress: Double {
        let total = refillAt.timeIntervalSince(updatedAt)
        guard total > 0 else { return 1 }
        let elapsed = Date().timeIntervalSince(updatedAt)
        return min(max(elapsed / total, 0), 1)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

extension ServiceSnapshot {
    static var samples: [ServiceSnapshot] {
        [
            ServiceSnapshot(
                id: "openai",
                name: "GPT / OpenAI",
                usageUsed: 84,
                usageLimit: 100,
                refillAt: Calendar.current.date(byAdding: .hour, value: 14, to: Date()) ?? Date(),
                subscriptionState: .active,
                updatedAt: Date()
            ),
            ServiceSnapshot(
                id: "anthropic",
                name: "Claude",
                usageUsed: 41,
                usageLimit: 50,
                refillAt: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
                subscriptionState: .active,
                updatedAt: Date()
            ),
            ServiceSnapshot(
                id: "gemini",
                name: "Gemini",
                usageUsed: 17,
                usageLimit: 30,
                refillAt: Calendar.current.date(byAdding: .hour, value: 8, to: Date()) ?? Date(),
                subscriptionState: .trial,
                updatedAt: Date()
            )
        ]
    }
}
