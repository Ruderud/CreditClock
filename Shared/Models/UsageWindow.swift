import Foundation

struct UsageWindow: Codable, Hashable {
    let windowStart: Date
    let windowEnd: Date
    let used: Int
    let limit: Int
    let refillAt: Date

    var remaining: Int { max(limit - used, 0) }
    var timeRemaining: TimeInterval { max(refillAt.timeIntervalSinceNow, 0) }
    var totalWindowDuration: TimeInterval { windowEnd.timeIntervalSince(windowStart) }
    var elapsedSinceWindowStart: TimeInterval { max(Date().timeIntervalSince(windowStart), 0) }

    var ringProgress: Double {
        guard totalWindowDuration > 0 else { return 0 }
        return min(elapsedSinceWindowStart / totalWindowDuration, 1)
    }

    var utilization: Double {
        guard limit > 0 else { return 0 }
        return min(Double(used) / Double(limit), 1)
    }
}
