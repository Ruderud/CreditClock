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
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Credits")
                .font(.headline)

            ForEach(entry.snapshots.prefix(4)) { snapshot in
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor(for: snapshot.subscriptionState))
                        .frame(width: 7, height: 7)
                    Text(snapshot.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("\(snapshot.remaining)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
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
}

#Preview(as: .systemMedium) {
    CreditClockWidget()
} timeline: {
    CreditClockEntry(date: .now, snapshots: ServiceSnapshot.samples)
}
