import Foundation
import Combine
import WidgetKit

@MainActor
final class ServiceStore: ObservableObject {
    @Published private(set) var snapshots: [ServiceSnapshot] = []
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?
    @Published private(set) var healthMap: [String: FetchHealth] = [:]
    @Published private(set) var lastRefreshStartedAt: Date?
    @Published private(set) var lastRefreshFinishedAt: Date?
    @Published private(set) var lastRefreshSucceeded: Bool?
    @Published private(set) var lastRefreshFailureCount: Int = 0

    private var providers: [ServiceProvider]
    private var scheduler: PollingScheduler?
    private let snapshotStore: SnapshotStore
    private let credentialStore: CredentialStore
    private let refreshStateStore: RefreshStateStore

    var hasConfiguredProviders: Bool {
        !ServiceStore.buildProviders(credentialStore: credentialStore).isEmpty
    }

    init(
        providers: [ServiceProvider]? = nil,
        snapshotStore: SnapshotStore = SnapshotStore(),
        credentialStore: CredentialStore = KeychainCredentialStore(),
        refreshStateStore: RefreshStateStore = RefreshStateStore()
    ) {
        self.credentialStore = credentialStore
        self.snapshotStore = snapshotStore
        self.refreshStateStore = refreshStateStore
        self.refreshStateStore.setRefreshing(false)

        if let providers {
            self.providers = providers
        } else {
            self.providers = ServiceStore.buildProviders(credentialStore: credentialStore)
        }

        let cached = snapshotStore.load()
        self.snapshots = cached
        if providers == nil {
            reconcilePolling()
        }
    }

    func refresh() async {
        let refreshStartedAt = Date()
        lastRefreshStartedAt = refreshStartedAt
        lastRefreshFinishedAt = nil
        lastRefreshSucceeded = nil
        lastRefreshFailureCount = 0
        isRefreshing = true
        refreshStateStore.setRefreshing(true)
        WidgetCenter.shared.reloadAllTimelines()
        lastError = nil

        providers = ServiceStore.buildProviders(credentialStore: credentialStore)
        if providers.isEmpty {
            stopPolling()
        } else {
            startPollingIfNeeded()
        }
        let previousByServiceId = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })

        guard !providers.isEmpty else {
            // Keep and re-publish the last cached snapshots so widgets can sync even when
            // local folder access is not configured yet.
            snapshotStore.save(snapshots)
            WidgetCenter.shared.reloadAllTimelines()
            lastRefreshFinishedAt = Date()
            lastRefreshSucceeded = nil
            lastRefreshFailureCount = 0
            await finishRefresh(startedAt: refreshStartedAt)
            return
        }

        var next: [ServiceSnapshot] = []
        var failureCount = 0

        for provider in providers {
            let start = CFAbsoluteTimeGetCurrent()
            do {
                let snapshot = try await provider.fetchSnapshot()
                next.append(snapshot)
                let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                var health = healthMap[provider.serviceId] ?? .initial
                health.recordSuccess(latencyMs: ms)
                healthMap[provider.serviceId] = health
            } catch {
                failureCount += 1
                lastError = error.localizedDescription
                var health = healthMap[provider.serviceId] ?? .initial
                health.recordFailure(error: error.localizedDescription)
                healthMap[provider.serviceId] = health
                if let previous = previousByServiceId[provider.serviceId] {
                    next.append(previous)
                }
            }
        }

        if !next.isEmpty {
            snapshots = next.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            snapshotStore.save(snapshots)
            WidgetCenter.shared.reloadAllTimelines()
        }

        lastRefreshFinishedAt = Date()
        lastRefreshFailureCount = failureCount
        lastRefreshSucceeded = failureCount == 0
        await finishRefresh(startedAt: refreshStartedAt)
    }

    /// Returns true on success (for PollingScheduler)
    func refreshReturningSuccess() async -> Bool {
        await refresh()
        return lastError == nil
    }

    func reconcilePolling() {
        providers = ServiceStore.buildProviders(credentialStore: credentialStore)
        if providers.isEmpty {
            stopPolling()
            return
        }
        startPollingIfNeeded()
    }

    private func finishRefresh(startedAt: Date) async {
        let minRefreshingDisplaySeconds: TimeInterval = 1.5
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < minRefreshingDisplaySeconds {
            let wait = minRefreshingDisplaySeconds - elapsed
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }

        isRefreshing = false
        refreshStateStore.setRefreshing(false)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func startPollingIfNeeded() {
        guard scheduler == nil else { return }
        let next = PollingScheduler { [weak self] in
            guard let self else { return false }
            return await self.refreshReturningSuccess()
        }
        scheduler = next
        next.start()
    }

    private func stopPolling() {
        scheduler?.stop()
        scheduler = nil
    }

    private static func buildProviders(credentialStore: CredentialStore) -> [ServiceProvider] {
        var result: [ServiceProvider] = []
        let connections = ProviderConnectionStore()

        if connections.isConnected(.anthropic) {
            result.append(AnthropicProviderAdapter())
        }

        if connections.isConnected(.openai) {
            result.append(OpenAIProviderAdapter())
        }

        // Other providers that require API keys
        for provider in ProviderId.allCases {
            guard provider != .anthropic, provider != .openai else { continue }
            let ref = "com.creditclock.\(provider.rawValue).credential"
            let hasKey = (try? credentialStore.load(key: ref))?.isEmpty == false
            let isConnected = connections.isConnected(provider)

            switch provider {
            case .gemini:
                let hasLocalOAuth = GeminiProviderAdapter.hasLocalCLIOAuthCredentials()
                if hasLocalOAuth || (isConnected && hasKey) {
                    result.append(GeminiProviderAdapter(credentialStore: credentialStore))
                }
            case .openai, .anthropic:
                break
            }
        }

        return result
    }
}
