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
    let subscriptionDetail: String?
    let updatedAt: Date
    let fiveHourUtilization: Double?
    let weeklyUtilization: Double?
    let fiveHourRefillAt: Date?
    let weeklyRefillAt: Date?
    let primaryQuotaLabel: String?
    let secondaryQuotaLabel: String?
    let primaryRingLabel: String?

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

    var subscriptionBadgeTitle: String {
        guard let detail = subscriptionDetail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty else {
            return subscriptionState.title
        }
        return "\(subscriptionState.title) · \(detail)"
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
        let base = fiveHourRefillAt ?? refillAt
        guard fiveHourRefillAt != nil else { return base }
        return normalizeCyclicRefill(base, windowDuration: inferredFiveHourWindowDuration)
    }

    var weeklyRefillDate: Date {
        let base = weeklyRefillAt ?? refillAt
        guard weeklyRefillAt != nil else { return base }
        return normalizeCyclicRefill(base, windowDuration: inferredWeeklyWindowDuration)
    }

    var fiveHourRefillRemainingText: String {
        formatRemainingHM(until: fiveHourRefillDate)
    }

    var weeklyRefillRemainingText: String {
        let secondsToRefill = weeklyRefillDate.timeIntervalSinceNow
        if secondsToRefill <= 48 * 3600 {
            return formatRemainingHM(until: weeklyRefillDate)
        }
        return formatRemainingDHM(until: weeklyRefillDate)
    }

    var primaryQuotaTitle: String {
        primaryQuotaLabel ?? "5h"
    }

    var secondaryQuotaTitle: String {
        secondaryQuotaLabel ?? "1w"
    }

    var primaryRingTitle: String {
        primaryRingLabel ?? primaryQuotaTitle
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

    private var inferredFiveHourWindowDuration: TimeInterval? {
        switch id {
        case "openai", "anthropic":
            return 5 * 3600
        case "gemini":
            return 24 * 3600
        default:
            return parseWindowDuration(from: primaryRingTitle)
                ?? parseWindowDuration(from: primaryQuotaTitle)
        }
    }

    private var inferredWeeklyWindowDuration: TimeInterval? {
        switch id {
        case "openai", "anthropic":
            return 7 * 24 * 3600
        case "gemini":
            return 24 * 3600
        default:
            return parseWindowDuration(from: secondaryQuotaTitle)
        }
    }

    private func parsePercent(token: String) -> Double? {
        guard let range = name.range(of: "\(token):", options: .caseInsensitive) else { return nil }
        let suffix = name[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        guard let value = Int(digits) else { return nil }
        return min(max(Double(value) / 100, 0), 1)
    }

    private func normalizeCyclicRefill(_ target: Date, windowDuration: TimeInterval?) -> Date {
        guard let windowDuration, windowDuration > 0 else { return target }
        let remaining = target.timeIntervalSinceNow
        guard remaining < 0 else { return target }
        let elapsed = -remaining
        let cyclesToAdvance = floor(elapsed / windowDuration) + 1
        return target.addingTimeInterval(cyclesToAdvance * windowDuration)
    }

    private func parseWindowDuration(from label: String?) -> TimeInterval? {
        guard let label else { return nil }
        let lowered = label.lowercased()
        let digits = lowered.prefix { $0.isNumber }
        guard let value = Double(digits), value > 0 else { return nil }
        if lowered.contains("day") || lowered.hasSuffix("d") {
            return value * 24 * 3600
        }
        if lowered.contains("week") || lowered.hasSuffix("w") || lowered.contains("wk") {
            return value * 7 * 24 * 3600
        }
        if lowered.contains("hour") || lowered.hasSuffix("h") {
            return value * 3600
        }
        return nil
    }

    private func ringProgress(updatedAt: Date, refillAt: Date) -> Double {
        let total = refillAt.timeIntervalSince(updatedAt)
        guard total > 0 else { return 1 }
        let elapsed = Date().timeIntervalSince(updatedAt)
        return min(max(elapsed / total, 0), 1)
    }

    private func formatRemainingHM(until target: Date) -> String {
        let remainingMinutes = max(Int(ceil(target.timeIntervalSinceNow / 60)), 0)
        let hours = remainingMinutes / 60
        let minutes = remainingMinutes % 60
        return "\(hours)h \(minutes)m"
    }

    private func formatRemainingDHM(until target: Date) -> String {
        let remainingMinutes = max(Int(ceil(target.timeIntervalSinceNow / 60)), 0)
        let days = remainingMinutes / (24 * 60)
        let dayRemainder = remainingMinutes % (24 * 60)
        let hours = dayRemainder / 60
        let minutes = dayRemainder % 60
        return "\(days)day \(hours)h \(minutes)m"
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
                subscriptionDetail: "Plus",
                updatedAt: Date(),
                fiveHourUtilization: 0.84,
                weeklyUtilization: 0.57,
                fiveHourRefillAt: Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date(),
                weeklyRefillAt: Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date(),
                primaryQuotaLabel: nil,
                secondaryQuotaLabel: nil,
                primaryRingLabel: nil
            ),
            ServiceSnapshot(
                id: "anthropic",
                name: "Claude — 5h:5% wk:57%",
                usageUsed: 41,
                usageLimit: 50,
                refillAt: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
                subscriptionState: .active,
                subscriptionDetail: "Max",
                updatedAt: Date(),
                fiveHourUtilization: 0.05,
                weeklyUtilization: 0.57,
                fiveHourRefillAt: Calendar.current.date(byAdding: .minute, value: 59, to: Date()) ?? Date(),
                weeklyRefillAt: Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date(),
                primaryQuotaLabel: nil,
                secondaryQuotaLabel: nil,
                primaryRingLabel: nil
            ),
            ServiceSnapshot(
                id: "gemini",
                name: "Gemini",
                usageUsed: 17,
                usageLimit: 30,
                refillAt: Calendar.current.date(byAdding: .hour, value: 8, to: Date()) ?? Date(),
                subscriptionState: .trial,
                subscriptionDetail: nil,
                updatedAt: Date(),
                fiveHourUtilization: nil,
                weeklyUtilization: nil,
                fiveHourRefillAt: nil,
                weeklyRefillAt: nil,
                primaryQuotaLabel: nil,
                secondaryQuotaLabel: nil,
                primaryRingLabel: nil
            )
        ]
    }
}
