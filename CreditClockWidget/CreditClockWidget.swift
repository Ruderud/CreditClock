import SwiftUI
import WidgetKit

struct CreditClockEntry: TimelineEntry {
    let date: Date
    let snapshots: [ServiceSnapshot]
    let isRefreshing: Bool
    let debugInfo: String
}

struct CreditClockTimelineProvider: TimelineProvider {
    private let store = SnapshotStore()
    private let refreshStateStore = RefreshStateStore()

    func placeholder(in context: Context) -> CreditClockEntry {
        CreditClockEntry(
            date: Date(),
            snapshots: ServiceSnapshot.samples,
            isRefreshing: false,
            debugInfo: "preview"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CreditClockEntry) -> Void) {
        let result = store.loadWithDiagnostics()
        let patched = WidgetLocalUsageOverlay.patch(result.snapshots)
        if context.isPreview {
            completion(CreditClockEntry(
                date: Date(),
                snapshots: ServiceSnapshot.samples,
                isRefreshing: false,
                debugInfo: "preview"
            ))
            return
        }
        completion(CreditClockEntry(
            date: Date(),
            snapshots: patched.snapshots,
            isRefreshing: refreshStateStore.isRefreshing(),
            debugInfo: "\(result.debug) | overlay=\(patched.debug)"
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CreditClockEntry>) -> Void) {
        let result = store.loadWithDiagnostics()
        let patched = WidgetLocalUsageOverlay.patch(result.snapshots)
        let entry = CreditClockEntry(
            date: Date(),
            snapshots: patched.snapshots,
            isRefreshing: refreshStateStore.isRefreshing(),
            debugInfo: "\(result.debug) | overlay=\(patched.debug)"
        )
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct CreditClockWidget: Widget {
    let kind = "CreditClockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CreditClockTimelineProvider()) { entry in
            CreditClockWidgetView(entry: entry)
        }
        .configurationDisplayName("CreditClock")
        .description("AI 구독 사용량/리필 시간/상태를 한 번에 확인합니다.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CreditClockWidgetView: View {
    let entry: CreditClockEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.rootSpacing) {
            HStack {
                Text("AI Credits")
                    .font(metrics.headerFont)
                Spacer()
                if entry.isRefreshing {
                    Text("Refreshing...")
                        .font(metrics.updatedFont)
                        .foregroundStyle(.secondary)
                }
            }

            if entry.snapshots.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.isRefreshing ? "Syncing data..." : "No synced data")
                        .font(metrics.serviceFont)
                        .foregroundStyle(.secondary)
                    Text(entry.isRefreshing ? "Please wait a moment." : "Open CreditClock and refresh once.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(entry.debugInfo)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                }
            } else {
                VStack(spacing: metrics.cardSpacing) {
                    ForEach(prioritizedSnapshots.prefix(maxRows)) { snapshot in
                        WidgetServiceQuotaRow(snapshot: snapshot, metrics: metrics)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                if hiddenCount > 0 {
                    Text("미표기 \(hiddenCount)개")
                        .font(metrics.updatedFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("Updated \(entry.date.formatted(date: .omitted, time: .shortened))")
                    .font(metrics.updatedFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(metrics.outerPadding)
        .containerBackground(for: .widget) {
            Color.secondary.opacity(0.1)
        }
        .widgetURL(AppDeepLink.dashboardURL)
    }

    private var maxRows: Int {
        switch family {
        case .systemMedium:
            return 2
        default:
            return 4
        }
    }

    private var metrics: WidgetLayoutMetrics {
        switch family {
        case .systemMedium:
            return .medium
        default:
            return .large
        }
    }

    private var prioritizedSnapshots: [ServiceSnapshot] {
        entry.snapshots.sorted { lhs, rhs in
            let leftPriority = priority(of: lhs.id)
            let rightPriority = priority(of: rhs.id)
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var hiddenCount: Int {
        max(prioritizedSnapshots.count - maxRows, 0)
    }

    private func priority(of serviceId: String) -> Int {
        switch serviceId {
        case "anthropic":
            return 0
        case "openai":
            return 1
        case "gemini":
            return 2
        default:
            return 3
        }
    }
}

private struct WidgetServiceQuotaRow: View {
    let snapshot: ServiceSnapshot
    let metrics: WidgetLayoutMetrics

    private var countdownProgress: Double {
        let remaining = max(snapshot.fiveHourRefillDate.timeIntervalSinceNow, 0)
        let total = inferredPrimaryWindowDuration ?? max(snapshot.fiveHourRefillDate.timeIntervalSince(snapshot.updatedAt), 0)
        guard total > 0 else { return remaining > 0 ? 1 : 0 }
        return min(max(remaining / total, 0), 1)
    }

    var body: some View {
        HStack(alignment: .center, spacing: metrics.rowSpacing) {
            VStack(spacing: 0) {
                CircularCountdownRing(
                    progress: countdownProgress,
                    color: quotaColor(for: snapshot.fiveHourRemaining),
                    label: ringLabel,
                    labelFont: metrics.ringCenterFont
                )
                    .frame(width: metrics.ringSize, height: metrics.ringSize)

                Spacer()
                    .frame(height: metrics.ringTimeGap)

                Text(remainingTimeText)
                    .font(metrics.timeFont.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
            }
            .frame(width: metrics.ringBlockWidth, alignment: .center)

            VStack(alignment: .leading, spacing: metrics.lineSpacing) {
                Text(snapshot.displayName)
                    .font(metrics.serviceFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)

                WidgetQuotaProgressLine(title: shortQuotaTitle(snapshot.primaryQuotaTitle), remainingFraction: snapshot.fiveHourRemaining, metrics: metrics)
                WidgetQuotaProgressLine(title: shortQuotaTitle(snapshot.secondaryQuotaTitle), remainingFraction: snapshot.weeklyRemaining, metrics: metrics)
            }
        }
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .padding(.vertical, metrics.rowVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    private var remainingTimeText: String {
        snapshot.fiveHourRefillRemainingText
    }

    private var ringLabel: String {
        snapshot.id == "gemini" ? "1D" : snapshot.primaryRingTitle
    }

    private var inferredPrimaryWindowDuration: TimeInterval? {
        switch snapshot.id {
        case "openai", "anthropic":
            return 5 * 3600
        case "gemini":
            return 24 * 3600
        default:
            return parseWindowDuration(from: snapshot.primaryRingTitle)
                ?? parseWindowDuration(from: snapshot.primaryQuotaTitle)
        }
    }

    private func parseWindowDuration(from label: String) -> TimeInterval? {
        let lowered = label.lowercased()
        let digits = lowered.prefix { $0.isNumber }
        guard let value = Double(digits) else { return nil }
        if lowered.contains("day") || lowered.hasSuffix("d") {
            return value * 24 * 3600
        }
        if lowered.contains("week") || lowered.hasSuffix("w") {
            return value * 7 * 24 * 3600
        }
        if lowered.contains("hour") || lowered.hasSuffix("h") {
            return value * 3600
        }
        return nil
    }

    private func quotaColor(for remaining: Double) -> Color {
        let value = min(max(remaining, 0), 1)
        if value <= 0.10 { return .red }
        if value <= 0.30 { return .orange }
        return .green
    }

    private func shortQuotaTitle(_ title: String) -> String {
        let lowered = title.lowercased()
        if lowered.contains("gemini 3 flash") { return "G3F" }
        if lowered.contains("gemini 3 pro") { return "G3P" }
        return title
    }
}

private struct WidgetQuotaProgressLine: View {
    let title: String
    let remainingFraction: Double
    let metrics: WidgetLayoutMetrics

    private var clampedRemaining: Double {
        min(max(remainingFraction, 0), 1)
    }

    private var percentText: String {
        "\(Int((clampedRemaining * 100).rounded()))%"
    }

    private var tintColor: Color {
        if clampedRemaining <= 0.10 { return .red }
        if clampedRemaining <= 0.30 { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: metrics.progressSpacing) {
            Text(title)
                .font(metrics.labelFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: metrics.labelWidth, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tintColor)
                        .frame(width: geo.size.width * clampedRemaining)
                }
            }
            .frame(height: metrics.barHeight)

            Text(percentText)
                .font(metrics.percentFont.monospacedDigit())
                .foregroundStyle(tintColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: metrics.percentWidth, alignment: .trailing)
        }
    }
}

private struct WidgetLayoutMetrics {
    let outerPadding: CGFloat
    let rootSpacing: CGFloat
    let cardSpacing: CGFloat
    let rowSpacing: CGFloat
    let ringTimeGap: CGFloat
    let ringSize: CGFloat
    let ringBlockWidth: CGFloat
    let lineSpacing: CGFloat
    let rowHorizontalPadding: CGFloat
    let rowVerticalPadding: CGFloat
    let cardCornerRadius: CGFloat
    let progressSpacing: CGFloat
    let labelWidth: CGFloat
    let barHeight: CGFloat
    let percentWidth: CGFloat
    let headerFont: Font
    let serviceFont: Font
    let labelFont: Font
    let percentFont: Font
    let timeFont: Font
    let ringCenterFont: Font
    let updatedFont: Font

    static let medium = WidgetLayoutMetrics(
        outerPadding: 8,
        rootSpacing: 3,
        cardSpacing: 4,
        rowSpacing: 7,
        ringTimeGap: 5,
        ringSize: 22,
        ringBlockWidth: 50,
        lineSpacing: 1,
        rowHorizontalPadding: 6,
        rowVerticalPadding: 4,
        cardCornerRadius: 8,
        progressSpacing: 3,
        labelWidth: 14,
        barHeight: 5,
        percentWidth: 38,
        headerFont: .subheadline.weight(.semibold),
        serviceFont: .caption2.weight(.semibold),
        labelFont: .system(size: 10, weight: .semibold),
        percentFont: .system(size: 10, weight: .semibold, design: .rounded),
        timeFont: .system(size: 9, weight: .medium, design: .rounded),
        ringCenterFont: .system(size: 8, weight: .semibold, design: .rounded),
        updatedFont: .system(size: 10)
    )

    static let large = WidgetLayoutMetrics(
        outerPadding: 10,
        rootSpacing: 5,
        cardSpacing: 5,
        rowSpacing: 8,
        ringTimeGap: 6,
        ringSize: 24,
        ringBlockWidth: 58,
        lineSpacing: 2,
        rowHorizontalPadding: 7,
        rowVerticalPadding: 5,
        cardCornerRadius: 9,
        progressSpacing: 3,
        labelWidth: 15,
        barHeight: 6,
        percentWidth: 38,
        headerFont: .headline,
        serviceFont: .caption.weight(.semibold),
        labelFont: .system(size: 11, weight: .semibold),
        percentFont: .system(size: 11, weight: .semibold, design: .rounded),
        timeFont: .system(size: 10, weight: .medium, design: .rounded),
        ringCenterFont: .system(size: 9, weight: .semibold, design: .rounded),
        updatedFont: .caption2
    )
}

private enum WidgetLocalUsageOverlay {
    static func patch(_ snapshots: [ServiceSnapshot]) -> (snapshots: [ServiceSnapshot], debug: String) {
        var debug: [String] = []
        var patched = snapshots.map { snapshot in
            switch snapshot.id {
            case "anthropic":
                if let info = readClaudeCache() {
                    debug.append("claude:cache")
                    return apply(info: info, to: snapshot)
                }
                debug.append("claude:none")
                return snapshot
            case "openai":
                if let info = readCodexCache() {
                    debug.append("codex:cache")
                    return apply(info: info, to: snapshot)
                }
                debug.append("codex:none")
                return snapshot
            default:
                return snapshot
            }
        }

        if let index = patched.firstIndex(where: { $0.id == "gemini" }) {
            if let info = readGeminiCache() {
                patched[index] = apply(info: info, to: patched[index])
                debug.append("gemini:cache")
            } else {
                debug.append("gemini:none")
            }
        } else if let info = readGeminiCache() {
            patched.append(makeGeminiSnapshot(from: info))
            debug.append("gemini:add")
        } else {
            debug.append("gemini:none")
        }

        patched.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (patched, debug.joined(separator: ","))
    }

    private static func apply(info: LocalCacheInfo, to snapshot: ServiceSnapshot) -> ServiceSnapshot {
        let updatedAt = max(snapshot.updatedAt, info.updatedAt)
        let fiveHourUtilization = info.fiveHourUtilization ?? snapshot.fiveHourUtilization
        let weeklyUtilization = info.weeklyUtilization ?? snapshot.weeklyUtilization
        let usageUsed = info.primaryUsagePercent ?? snapshot.usageUsed
        let usageLimit = snapshot.usageLimit > 0 ? snapshot.usageLimit : (info.primaryUsagePercent != nil ? 100 : 0)
        return ServiceSnapshot(
            id: snapshot.id,
            name: snapshot.name,
            usageUsed: usageUsed,
            usageLimit: usageLimit,
            refillAt: info.fiveHourRefillAt ?? snapshot.refillAt,
            subscriptionState: snapshot.subscriptionState,
            subscriptionDetail: snapshot.subscriptionDetail,
            updatedAt: updatedAt,
            fiveHourUtilization: fiveHourUtilization,
            weeklyUtilization: weeklyUtilization,
            fiveHourRefillAt: info.fiveHourRefillAt ?? snapshot.fiveHourRefillAt,
            weeklyRefillAt: info.weeklyRefillAt ?? snapshot.weeklyRefillAt,
            primaryQuotaLabel: info.primaryQuotaLabel ?? snapshot.primaryQuotaLabel,
            secondaryQuotaLabel: info.secondaryQuotaLabel ?? snapshot.secondaryQuotaLabel,
            primaryRingLabel: info.primaryRingLabel ?? snapshot.primaryRingLabel
        )
    }

    private static func makeGeminiSnapshot(from info: LocalCacheInfo) -> ServiceSnapshot {
        let fallbackRefill = Calendar.current.date(byAdding: .hour, value: 24, to: info.updatedAt) ?? info.updatedAt
        let fiveHourRefill = info.fiveHourRefillAt ?? fallbackRefill
        let weeklyRefill = info.weeklyRefillAt ?? fallbackRefill
        let utilization = max(
            info.fiveHourUtilization ?? 0,
            info.weeklyUtilization ?? 0
        )

        return ServiceSnapshot(
            id: "gemini",
            name: "Gemini CLI",
            usageUsed: info.primaryUsagePercent ?? Int((utilization * 100).rounded()),
            usageLimit: 100,
            refillAt: fiveHourRefill,
            subscriptionState: utilization >= 0.95 ? .paused : .active,
            subscriptionDetail: nil,
            updatedAt: info.updatedAt,
            fiveHourUtilization: info.fiveHourUtilization,
            weeklyUtilization: info.weeklyUtilization,
            fiveHourRefillAt: fiveHourRefill,
            weeklyRefillAt: weeklyRefill,
            primaryQuotaLabel: info.primaryQuotaLabel ?? "Gemini 3 Flash",
            secondaryQuotaLabel: info.secondaryQuotaLabel ?? "Gemini 3 Pro",
            primaryRingLabel: info.primaryRingLabel ?? "G3F"
        )
    }

    private static func readClaudeCache() -> LocalCacheInfo? {
        readCache(for: .claude, relativePath: "plugins/oh-my-claudecode/.usage-cache.json", maxAgeMs: 300_000)
    }

    private static func readCodexCache() -> LocalCacheInfo? {
        guard let info = readCache(for: .codex, relativePath: ".usage-cache.json", maxAgeMs: 1_800_000) else {
            return nil
        }
        guard isFreshCodexCache(info) else { return nil }
        return info
    }

    private static func readGeminiCache() -> LocalCacheInfo? {
        let fallbackURL = SharedFallbackPath.url(fileName: "gemini-usage-cache.json")
        if let info = readCache(at: fallbackURL, maxAgeMs: 1_800_000) {
            return info
        }
        return readCache(for: .gemini, relativePath: ".usage-cache.json", maxAgeMs: 1_800_000)
    }

    private static func readCache(
        for source: LocalDataSource,
        relativePath: String,
        maxAgeMs: Double
    ) -> LocalCacheInfo? {
        if let data = ExternalDataAccess.shared.withDirectoryAccess(for: source, { sourceDir in
            let path = appendRelativePath(relativePath, to: sourceDir)
            return try? Data(contentsOf: path)
        }), let info = parseCache(data: data, maxAgeMs: maxAgeMs) {
            return info
        }

        guard !isSandboxed else { return nil }

        let directPath = appendRelativePath(
            relativePath,
            to: URL(fileURLWithPath: realHomeDirectory(), isDirectory: true)
                .appendingPathComponent(source.expectedDirectoryName, isDirectory: true)
        )
        return readCache(at: directPath, maxAgeMs: maxAgeMs)
    }

    private static func readCache(at url: URL, maxAgeMs: Double) -> LocalCacheInfo? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseCache(data: data, maxAgeMs: maxAgeMs)
    }

    private static func parseCache(data: Data, maxAgeMs: Double) -> LocalCacheInfo? {
        guard let cache = try? JSONDecoder().decode(LocalUsageCache.self, from: data),
              cache.error != true,
              let usage = cache.data else { return nil }

        let age = Date().timeIntervalSince1970 * 1000 - cache.timestamp
        guard age >= 0, age < maxAgeMs else { return nil }

        return LocalCacheInfo(
            updatedAt: Date(timeIntervalSince1970: cache.timestamp / 1000),
            fiveHourUtilization: percentToFraction(usage.fiveHourPercent),
            weeklyUtilization: percentToFraction(usage.weeklyPercent),
            fiveHourRefillAt: parseISO8601(usage.fiveHourResetsAt),
            weeklyRefillAt: parseISO8601(usage.weeklyResetsAt),
            primaryQuotaLabel: usage.primaryQuotaLabel,
            secondaryQuotaLabel: usage.secondaryQuotaLabel,
            primaryRingLabel: usage.primaryRingLabel
        )
    }

    private static func appendRelativePath(_ relativePath: String, to base: URL) -> URL {
        relativePath
            .split(separator: "/")
            .reduce(base) { partial, component in
                partial.appendingPathComponent(String(component))
            }
    }

    private static func percentToFraction(_ percent: Int?) -> Double? {
        guard let percent else { return nil }
        return min(max(Double(percent) / 100, 0), 1)
    }

    private static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = isoWithFractional.date(from: raw) {
            return date
        }
        return isoStandard.date(from: raw)
    }

    private static func isFreshCodexCache(_ info: LocalCacheInfo) -> Bool {
        let now = Date()
        let graceSeconds: TimeInterval = 90
        guard let fiveHourRefillAt = info.fiveHourRefillAt,
              let weeklyRefillAt = info.weeklyRefillAt else {
            return false
        }
        return fiveHourRefillAt.timeIntervalSince(now) >= -graceSeconds
            && weeklyRefillAt.timeIntervalSince(now) >= -graceSeconds
    }

    private static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}

private struct LocalCacheInfo {
    let updatedAt: Date
    let fiveHourUtilization: Double?
    let weeklyUtilization: Double?
    let fiveHourRefillAt: Date?
    let weeklyRefillAt: Date?
    let primaryQuotaLabel: String?
    let secondaryQuotaLabel: String?
    let primaryRingLabel: String?

    var primaryUsagePercent: Int? {
        let maxUsage = max(fiveHourUtilization ?? 0, weeklyUtilization ?? 0)
        if maxUsage <= 0 {
            return nil
        }
        return Int((maxUsage * 100).rounded())
    }
}

private struct LocalUsageCache: Decodable {
    let timestamp: Double
    let data: Usage?
    let error: Bool?

    struct Usage: Decodable {
        let fiveHourPercent: Int?
        let weeklyPercent: Int?
        let fiveHourResetsAt: String?
        let weeklyResetsAt: String?
        let primaryQuotaLabel: String?
        let secondaryQuotaLabel: String?
        let primaryRingLabel: String?

        enum CodingKeys: String, CodingKey {
            case fiveHourPercent = "fiveHourPercent"
            case weeklyPercent = "weeklyPercent"
            case fiveHourResetsAt = "fiveHourResetsAt"
            case weeklyResetsAt = "weeklyResetsAt"
            case primaryQuotaLabel = "primaryQuotaLabel"
            case secondaryQuotaLabel = "secondaryQuotaLabel"
            case primaryRingLabel = "primaryRingLabel"
        }
    }
}

// MARK: - Circular Countdown Ring

struct CircularCountdownRing: View {
    let progress: Double
    let color: Color
    let label: String
    let labelFont: Font

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(labelFont.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

#Preview(as: .systemMedium) {
    CreditClockWidget()
} timeline: {
    CreditClockEntry(date: Date(), snapshots: ServiceSnapshot.samples, isRefreshing: false, debugInfo: "preview")
}
