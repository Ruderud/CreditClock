import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: ServiceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.snapshots) { snapshot in
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor(for: snapshot.subscriptionState))
                        .frame(width: 8, height: 8)
                    Text(snapshot.name)
                        .lineLimit(1)
                    Spacer()
                    Text("\(snapshot.remaining)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(snapshot.refillDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }

            Divider()

            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh Now", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)

            Divider()

            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            } label: {
                Label("Open CreditClock", systemImage: "macwindow")
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
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
