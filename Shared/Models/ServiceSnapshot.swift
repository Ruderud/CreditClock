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
    let fiveHourUtilization: Double?
    let weeklyUtilization: Double?
    let fiveHourRefillAt: Date?
    let weeklyRefillAt: Date?

    var remaining: Int {
        max(usageLimit - usageUsed, 0)
    }

    var utilization: Double {
        guard usageLimit > 0 else { return 0 }
        return min(Double(usageUsed) / Double(usageLimit), 1)
    }

    var displayName: String {
        name.components(separatedBy: " — ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? name
    }

    var fiveHourUsage: Double {
        if let fiveHourUtilization {
            return min(max(fiveHourUtilization, 0), 1)
        }
        if let parsed = parsedFiveHourUsage {
            return parsed
        }
        return utilization
    }

    var weeklyUsage: Double {
        if let weeklyUtilization {
            return min(max(weeklyUtilization, 0), 1)
        }
        if let parsed = parsedWeeklyUsage {
            return parsed
        }
        return utilization
    }

    var fiveHourRemaining: Double {
        1 - fiveHourUsage
    }

    var weeklyRemaining: Double {
        1 - weeklyUsage
    }

    var fiveHourRefillDate: Date {
        fiveHourRefillAt ?? refillAt
    }

    var weeklyRefillDate: Date {
        weeklyRefillAt ?? refillAt
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

    var fiveHourRefillRingProgress: Double {
        ringProgress(updatedAt: updatedAt, refillAt: fiveHourRefillDate)
    }

    var weeklyRefillRingProgress: Double {
        ringProgress(updatedAt: updatedAt, refillAt: weeklyRefillDate)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var parsedFiveHourUsage: Double? {
        parsePercent(token: "5h")
    }

    private var parsedWeeklyUsage: Double? {
        parsePercent(token: "wk")
    }

    private func parsePercent(token: String) -> Double? {
        guard let range = name.range(of: "\(token):", options: .caseInsensitive) else { return nil }
        let suffix = name[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        guard let value = Int(digits) else { return nil }
        return min(max(Double(value) / 100, 0), 1)
    }

    private func ringProgress(updatedAt: Date, refillAt: Date) -> Double {
        let total = refillAt.timeIntervalSince(updatedAt)
        guard total > 0 else { return 1 }
        let elapsed = Date().timeIntervalSince(updatedAt)
        return min(max(elapsed / total, 0), 1)
    }
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
                updatedAt: Date(),
                fiveHourUtilization: 0.84,
                weeklyUtilization: 0.57,
                fiveHourRefillAt: Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date(),
                weeklyRefillAt: Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date()
            ),
            ServiceSnapshot(
                id: "anthropic",
                name: "Claude — 5h:5% wk:57%",
                usageUsed: 41,
                usageLimit: 50,
                refillAt: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
                subscriptionState: .active,
                updatedAt: Date(),
                fiveHourUtilization: 0.05,
                weeklyUtilization: 0.57,
                fiveHourRefillAt: Calendar.current.date(byAdding: .minute, value: 59, to: Date()) ?? Date(),
                weeklyRefillAt: Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()
            ),
            ServiceSnapshot(
                id: "gemini",
                name: "Gemini",
                usageUsed: 17,
                usageLimit: 30,
                refillAt: Calendar.current.date(byAdding: .hour, value: 8, to: Date()) ?? Date(),
                subscriptionState: .trial,
                updatedAt: Date(),
                fiveHourUtilization: nil,
                weeklyUtilization: nil,
                fiveHourRefillAt: nil,
                weeklyRefillAt: nil
            )
        ]
    }
}
