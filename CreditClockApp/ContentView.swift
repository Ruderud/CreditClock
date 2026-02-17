import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ServiceStore
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if store.snapshots.isEmpty {
                    emptyStateView
                } else {
                    List(store.snapshots) { snapshot in
                        ServiceRow(snapshot: snapshot)
                            .listRowSeparator(.hidden)
                            .padding(.vertical, 6)
                    }
                    .listStyle(.plain)
                }
            }
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
                ToolbarItem(placement: .automatic) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                Task { await store.refresh() }
            }) {
                NavigationStack {
                    ProviderSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
                .frame(minWidth: 500, minHeight: 400)
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

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No providers configured")
                .font(.title2)
            Text("Add your API keys in Settings to start tracking usage.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                showSettings = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ServiceRow: View {
    let snapshot: ServiceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(snapshot.displayName)
                    .font(.headline)
                Spacer()
                Text(snapshot.subscriptionState.title)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            QuotaProgressLine(
                title: "5h",
                remainingFraction: snapshot.fiveHourRemaining,
                remainingTimeText: snapshot.fiveHourRefillRemainingText
            )

            QuotaProgressLine(
                title: "1w",
                remainingFraction: snapshot.weeklyRemaining,
                remainingTimeText: snapshot.weeklyRefillRemainingText
            )
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
}

private struct QuotaProgressLine: View {
    let title: String
    let remainingFraction: Double
    let remainingTimeText: String

    private var clampedRemaining: Double {
        min(max(remainingFraction, 0), 1)
    }

    private var remainingPercentText: String {
        "\(Int((clampedRemaining * 100).rounded()))%"
    }

    private var tintColor: Color {
        if clampedRemaining <= 0.10 { return .red }
        if clampedRemaining <= 0.30 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(title) · \(remainingTimeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(remainingPercentText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(tintColor)
            }

            ProgressView(value: clampedRemaining)
                .tint(tintColor)
        }
    }
}

#Preview {
    ContentView(store: ServiceStore())
}
