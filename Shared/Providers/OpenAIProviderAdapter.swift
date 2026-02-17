import Foundation

struct OpenAIProviderAdapter: ServiceProvider {
    let serviceId = "openai"

    func fetchSnapshot() async throws -> ServiceSnapshot {
        // Strategy 1: Read usage cache
        if let cached = readUsageCache() {
            return cached
        }

        // Strategy 2: Parse session logs directly and write cache
        if let parsed = parseSessionLogsAndCache() {
            return parsed
        }

        // Strategy 3: JWT subscription info fallback
        if let jwt = readCodexAuth() {
            return jwt
        }

        throw ProviderError.notAuthenticated("Codex (no credentials found)")
    }

    // MARK: - Strategy 1: Usage Cache

    private func readUsageCache() -> ServiceSnapshot? {
        let cachePath = realHomeDirectory() + "/.codex/.usage-cache.json"
        guard let data = FileManager.default.contents(atPath: cachePath) else { return nil }

        guard let cache = try? JSONDecoder().decode(CodexUsageCache.self, from: data),
              let usage = cache.data,
              !cache.error else { return nil }

        // Cache older than 30 minutes is stale (polling refreshes via Strategy 2)
        let cacheAge = Date().timeIntervalSince1970 * 1000 - cache.timestamp
        guard cacheAge < 1_800_000 else { return nil }

        let fiveH = usage.fiveHourPercent
        let weekly = usage.weeklyPercent
        let primaryPercent = max(fiveH, weekly)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fiveHourReset: Date
        if let d = iso.date(from: usage.fiveHourResetsAt) {
            fiveHourReset = d
        } else {
            fiveHourReset = Date().addingTimeInterval(3600)
        }

        return ServiceSnapshot(
            id: serviceId,
            name: "Codex — 5h:\(fiveH)% wk:\(weekly)%",
            usageUsed: primaryPercent,
            usageLimit: 100,
            refillAt: fiveHourReset,
            subscriptionState: primaryPercent >= 90 ? .paused : .active,
            updatedAt: Date()
        )
    }

    // MARK: - Strategy 2: Session Log Parsing

    private func parseSessionLogsAndCache() -> ServiceSnapshot? {
        let home = realHomeDirectory()
        let sessionsDir = home + "/.codex/sessions"
        let cal = Calendar.current
        let today = Date()

        var latestTs = ""
        var primaryPct = 0.0
        var primaryResets: TimeInterval = 0
        var secondaryPct = 0.0
        var secondaryResets: TimeInterval = 0
        var found = false

        for dayOffset in 0..<3 {
            guard let date = cal.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let y = cal.component(.year, from: date)
            let m = String(format: "%02d", cal.component(.month, from: date))
            let d = String(format: "%02d", cal.component(.day, from: date))
            let dayDir = "\(sessionsDir)/\(y)/\(m)/\(d)"

            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dayDir) else { continue }

            for file in files where file.hasSuffix(".jsonl") {
                let path = "\(dayDir)/\(file)"
                guard let handle = FileHandle(forReadingAtPath: path) else { continue }
                defer { handle.closeFile() }

                // Read last 100KB only for efficiency
                let fileSize = handle.seekToEndOfFile()
                let readSize: UInt64 = min(fileSize, 100_000)
                handle.seek(toFileOffset: fileSize - readSize)
                guard let data = handle.availableData as Data?,
                      let content = String(data: data, encoding: .utf8) else { continue }

                for line in content.components(separatedBy: .newlines) {
                    guard !line.isEmpty,
                          line.contains("\"limit_id\":\"codex\""),
                          !line.contains("codex_"),
                          let lineData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                          let payload = json["payload"] as? [String: Any],
                          let rateLimits = payload["rate_limits"] as? [String: Any],
                          rateLimits["limit_id"] as? String == "codex",
                          let ts = json["timestamp"] as? String else { continue }

                    if ts > latestTs {
                        latestTs = ts
                        let primary = rateLimits["primary"] as? [String: Any]
                        let secondary = rateLimits["secondary"] as? [String: Any]
                        primaryPct = primary?["used_percent"] as? Double ?? 0
                        primaryResets = primary?["resets_at"] as? TimeInterval ?? 0
                        secondaryPct = secondary?["used_percent"] as? Double ?? 0
                        secondaryResets = secondary?["resets_at"] as? TimeInterval ?? 0
                        found = true
                    }
                }
            }
        }

        guard found else { return nil }

        // Write cache for next read
        writeUsageCache(
            fiveHour: Int(primaryPct), weekly: Int(secondaryPct),
            fiveHourResets: primaryResets, weeklyResets: secondaryResets
        )

        let fiveH = Int(primaryPct)
        let weekly = Int(secondaryPct)
        let primaryPercent = max(fiveH, weekly)
        let fiveHourReset = Date(timeIntervalSince1970: primaryResets)

        return ServiceSnapshot(
            id: serviceId,
            name: "Codex — 5h:\(fiveH)% wk:\(weekly)%",
            usageUsed: primaryPercent,
            usageLimit: 100,
            refillAt: fiveHourReset,
            subscriptionState: primaryPercent >= 90 ? .paused : .active,
            updatedAt: Date()
        )
    }

    private func writeUsageCache(fiveHour: Int, weekly: Int, fiveHourResets: TimeInterval, weeklyResets: TimeInterval) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let cache = CodexUsageCache(
            timestamp: Date().timeIntervalSince1970 * 1000,
            data: CodexUsageCache.UsageData(
                fiveHourPercent: fiveHour,
                weeklyPercent: weekly,
                fiveHourResetsAt: iso.string(from: Date(timeIntervalSince1970: fiveHourResets)),
                weeklyResetsAt: iso.string(from: Date(timeIntervalSince1970: weeklyResets))
            ),
            error: false
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(cache) {
            let cachePath = realHomeDirectory() + "/.codex/.usage-cache.json"
            try? data.write(to: URL(fileURLWithPath: cachePath))
        }
    }

    // MARK: - Strategy 3: JWT Subscription Info

    private func readCodexAuth() -> ServiceSnapshot? {
        let authPath = realHomeDirectory() + "/.codex/auth.json"
        guard let data = FileManager.default.contents(atPath: authPath) else { return nil }

        guard let auth = try? JSONDecoder().decode(CodexAuth.self, from: data),
              let idToken = auth.tokens?.idToken,
              let claims = decodeJWTPayload(idToken) else { return nil }

        let authInfo = claims["https://api.openai.com/auth"] as? [String: Any]
        let planType = authInfo?["chatgpt_plan_type"] as? String ?? "unknown"

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withTimeZone]

        guard let untilStr = authInfo?["chatgpt_subscription_active_until"] as? String,
              let activeUntil = iso.date(from: untilStr) else { return nil }

        let now = Date()
        let remainingDays = max(Int(ceil(activeUntil.timeIntervalSince(now) / 86400)), 0)

        return ServiceSnapshot(
            id: serviceId,
            name: "Codex \(planType.capitalized) — \(remainingDays)d left",
            usageUsed: 0,
            usageLimit: 100,
            refillAt: activeUntil,
            subscriptionState: now > activeUntil ? .expired : .active,
            updatedAt: now
        )
    }

    private func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        base64 = base64.replacingOccurrences(of: "-", with: "+")
                       .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }
}

// MARK: - Models

private struct CodexUsageCache: Codable {
    let timestamp: Double
    let data: UsageData?
    let error: Bool

    struct UsageData: Codable {
        let fiveHourPercent: Int
        let weeklyPercent: Int
        let fiveHourResetsAt: String
        let weeklyResetsAt: String
    }
}

private struct CodexAuth: Decodable {
    let tokens: Tokens?

    struct Tokens: Decodable {
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
        }
    }
}
