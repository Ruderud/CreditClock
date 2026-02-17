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
            snapshots: result.snapshots,
            isRefreshing: refreshStateStore.isRefreshing(),
            debugInfo: result.debug
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CreditClockEntry>) -> Void) {
        let result = store.loadWithDiagnostics()
        let entry = CreditClockEntry(
            date: Date(),
            snapshots: result.snapshots,
            isRefreshing: refreshStateStore.isRefreshing(),
            debugInfo: result.debug
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
                    ForEach(entry.snapshots.prefix(maxRows)) { snapshot in
                        WidgetServiceQuotaRow(snapshot: snapshot, metrics: metrics)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
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
    }

    private var maxRows: Int {
        switch family {
        case .systemLarge:
            return 4
        default:
            return 2
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
}

private struct WidgetServiceQuotaRow: View {
    let snapshot: ServiceSnapshot
    let metrics: WidgetLayoutMetrics

    private var countdownProgress: Double {
        1 - snapshot.fiveHourRefillRingProgress
    }

    var body: some View {
        HStack(alignment: .center, spacing: metrics.rowSpacing) {
            VStack(spacing: 0) {
                CircularCountdownRing(progress: countdownProgress, color: quotaColor(for: snapshot.fiveHourRemaining))
                    .frame(width: metrics.ringSize, height: metrics.ringSize)

                Spacer()
                    .frame(height: metrics.ringTimeGap)

                Text(remainingTimeText)
                    .font(metrics.timeFont.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: metrics.ringBlockWidth, alignment: .center)

            VStack(alignment: .leading, spacing: metrics.lineSpacing) {
                Text(snapshot.displayName)
                    .font(metrics.serviceFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)

                WidgetQuotaProgressLine(title: "5h", remainingFraction: snapshot.fiveHourRemaining, metrics: metrics)
                WidgetQuotaProgressLine(title: "1w", remainingFraction: snapshot.weeklyRemaining, metrics: metrics)
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
        let seconds = max(snapshot.fiveHourRefillDate.timeIntervalSinceNow, 0)
        if seconds < 60 { return "<1m" }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: seconds) ?? "0m"
    }

    private func quotaColor(for remaining: Double) -> Color {
        let value = min(max(remaining, 0), 1)
        if value <= 0.10 { return .red }
        if value <= 0.30 { return .orange }
        return .green
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
    let updatedFont: Font

    static let medium = WidgetLayoutMetrics(
        outerPadding: 8,
        rootSpacing: 3,
        cardSpacing: 4,
        rowSpacing: 7,
        ringTimeGap: 5,
        ringSize: 19,
        ringBlockWidth: 33,
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
        updatedFont: .system(size: 10)
    )

    static let large = WidgetLayoutMetrics(
        outerPadding: 10,
        rootSpacing: 5,
        cardSpacing: 5,
        rowSpacing: 8,
        ringTimeGap: 6,
        ringSize: 21,
        ringBlockWidth: 38,
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
        updatedFont: .caption2
    )
}

// MARK: - Circular Countdown Ring

struct CircularCountdownRing: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

#Preview(as: .systemMedium) {
    CreditClockWidget()
} timeline: {
    CreditClockEntry(date: Date(), snapshots: ServiceSnapshot.samples, isRefreshing: false, debugInfo: "preview")
}
