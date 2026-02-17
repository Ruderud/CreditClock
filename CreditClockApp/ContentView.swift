import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ServiceStore

    var body: some View {
        NavigationStack {
            List(store.snapshots) { snapshot in
                ServiceRow(snapshot: snapshot)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 6)
            }
            .listStyle(.plain)
            .navigationTitle("CreditClock")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(store.isRefreshing)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let lastError = store.lastError {
                Text(lastError)
                    .font(.caption)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }
}

private struct ServiceRow: View {
    let snapshot: ServiceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(snapshot.name)
                    .font(.headline)
                Spacer()
                Text(snapshot.subscriptionState.title)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            ProgressView(value: snapshot.utilization)
                .tint(progressColor)

            HStack(spacing: 16) {
                Label("\(snapshot.usageUsed)/\(snapshot.usageLimit)", systemImage: "speedometer")
                Label("Refill \(snapshot.refillDescription)", systemImage: "clock")
                Spacer()
                Label("Left \(snapshot.remaining)", systemImage: "bolt.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusColor: Color {
        switch snapshot.subscriptionState {
        case .active: return .green
        case .trial: return .orange
        case .expired: return .red
        case .paused: return .yellow
        }
    }

    private var progressColor: Color {
        if snapshot.utilization > 0.9 { return .red }
        if snapshot.utilization > 0.7 { return .orange }
        return .green
    }
}

#Preview {
    ContentView(store: ServiceStore())
}
