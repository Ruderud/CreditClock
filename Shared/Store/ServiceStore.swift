import Foundation
import Combine
import WidgetKit

@MainActor
final class ServiceStore: ObservableObject {
    @Published private(set) var snapshots: [ServiceSnapshot]
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    private let providers: [ServiceProvider]
    private let snapshotStore: SnapshotStore

    init(
        providers: [ServiceProvider] = ProviderCatalog.defaultProviders(),
        snapshotStore: SnapshotStore = SnapshotStore()
    ) {
        self.providers = providers
        self.snapshotStore = snapshotStore
        let cached = snapshotStore.load()
        self.snapshots = cached.isEmpty ? ServiceSnapshot.samples : cached
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        var next: [ServiceSnapshot] = []

        for provider in providers {
            do {
                let snapshot = try await provider.fetchSnapshot()
                next.append(snapshot)
            } catch {
                lastError = error.localizedDescription
            }
        }

        guard !next.isEmpty else { return }
        snapshots = next.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        snapshotStore.save(snapshots)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
