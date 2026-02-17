import Foundation

struct FetchHealth: Codable {
    var lastSuccessAt: Date?
    var lastFailureAt: Date?
    var lastErrorMessage: String?
    var consecutiveFailures: Int
    var latencyMs: Int?

    static var initial: FetchHealth {
        FetchHealth(
            lastSuccessAt: nil,
            lastFailureAt: nil,
            lastErrorMessage: nil,
            consecutiveFailures: 0,
            latencyMs: nil
        )
    }

    mutating func recordSuccess(latencyMs: Int) {
        self.lastSuccessAt = Date()
        self.consecutiveFailures = 0
        self.lastErrorMessage = nil
        self.latencyMs = latencyMs
    }

    mutating func recordFailure(error: String) {
        self.lastFailureAt = Date()
        self.consecutiveFailures += 1
        self.lastErrorMessage = error
    }
}
