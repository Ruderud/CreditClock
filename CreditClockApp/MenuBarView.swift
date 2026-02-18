import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: ServiceStore
    @Environment(\.openSettings) private var openSettings
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?

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

            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLoginEnabled },
                set: { updateLaunchAtLogin($0) }
            ))

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button {
                openSettingsWithAppActivation()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .onAppear {
            launchAtLoginEnabled = currentLaunchAtLoginEnabled()
        }
    }

    private func openSettingsWithAppActivation() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
    }

    private func statusColor(for state: SubscriptionState) -> Color {
        switch state {
        case .active: return .green
        case .trial: return .orange
        case .expired: return .red
        case .paused: return .yellow
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = enabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginEnabled = currentLaunchAtLoginEnabled()
            launchAtLoginError = "Launch at Login update failed: \(error.localizedDescription)"
        }
    }

    private func currentLaunchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
