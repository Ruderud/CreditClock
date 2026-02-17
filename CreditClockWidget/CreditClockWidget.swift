import SwiftUI
import WidgetKit

struct CreditClockEntry: TimelineEntry {
    let date: Date
    let snapshots: [ServiceSnapshot]
}

struct CreditClockTimelineProvider: TimelineProvider {
    private let store = SnapshotStore()

    func placeholder(in context: Context) -> CreditClockEntry {
        CreditClockEntry(date: Date(), snapshots: ServiceSnapshot.samples)
    }

    func getSnapshot(in context: Context, completion: @escaping (CreditClockEntry) -> Void) {
        let snapshots = store.load()
        completion(CreditClockEntry(date: Date(), snapshots: snapshots.isEmpty ? ServiceSnapshot.samples : snapshots))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CreditClockEntry>) -> Void) {
        let snapshots = store.load()
        let entry = CreditClockEntry(date: Date(), snapshots: snapshots.isEmpty ? ServiceSnapshot.samples : snapshots)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Credits")
                .font(.headline)

            ForEach(entry.snapshots.prefix(4)) { snapshot in
                HStack(spacing: 8) {
                    CircularCountdownRing(progress: snapshot.refillRingProgress, color: statusColor(for: snapshot.subscriptionState))
                        .frame(width: 20, height: 20)

                    Text(snapshot.name)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.2))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(progressColor(for: snapshot.utilization))
                                .frame(width: geo.size.width * snapshot.utilization)
                        }
                    }
                    .frame(width: 40, height: 6)

                    Text("\(snapshot.remaining)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(width: 28, alignment: .trailing)
                }
            }

            Spacer(minLength: 0)

            Text("Updated \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .containerBackground(for: .widget) {
            Color.secondary.opacity(0.1)
        }
    }

    private func statusColor(for state: SubscriptionState) -> Color {
        switch state {
        case .active: return .green
        case .trial: return .orange
        case .expired: return .red
        case .paused: return .yellow
        }
    }

    private func progressColor(for utilization: Double) -> Color {
        if utilization > 0.9 { return .red }
        if utilization > 0.7 { return .orange }
        return .green
    }
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
    CreditClockEntry(date: Date(), snapshots: ServiceSnapshot.samples)
}
