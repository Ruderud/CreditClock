import Foundation
import Combine
import WidgetKit

@MainActor
final class ServiceStore: ObservableObject {
    @Published private(set) var snapshots: [ServiceSnapshot] = []
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?
    @Published private(set) var healthMap: [String: FetchHealth] = [:]

    private var providers: [ServiceProvider]
    private let snapshotStore: SnapshotStore
    private let credentialStore: CredentialStore

    var hasConfiguredProviders: Bool {
        !ServiceStore.buildProviders(credentialStore: credentialStore).isEmpty
    }

    init(
        providers: [ServiceProvider]? = nil,
        snapshotStore: SnapshotStore = SnapshotStore(),
        credentialStore: CredentialStore = KeychainCredentialStore()
    ) {
        self.credentialStore = credentialStore
        self.snapshotStore = snapshotStore

        if let providers {
            self.providers = providers
        } else {
            self.providers = ServiceStore.buildProviders(credentialStore: credentialStore)
        }

        let cached = snapshotStore.load()
        self.snapshots = cached
    }

    func refresh() async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        providers = ServiceStore.buildProviders(credentialStore: credentialStore)

        guard !providers.isEmpty else {
            snapshots = []
            snapshotStore.save([])
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        var next: [ServiceSnapshot] = []

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
                lastError = error.localizedDescription
                var health = healthMap[provider.serviceId] ?? .initial
                health.recordFailure(error: error.localizedDescription)
                healthMap[provider.serviceId] = health
            }
        }

        guard !next.isEmpty else { return }
        snapshots = next.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        snapshotStore.save(snapshots)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Returns true on success (for PollingScheduler)
    func refreshReturningSuccess() async -> Bool {
        await refresh()
        return lastError == nil
    }

    private static func buildProviders(credentialStore: CredentialStore) -> [ServiceProvider] {
        var result: [ServiceProvider] = []

        // Anthropic: always included (uses Claude Code OAuth or OMC cache, no API key needed)
        result.append(AnthropicProviderAdapter())

        // OpenAI: included if Codex CLI directory exists
        let codexDir = realHomeDirectory() + "/.codex"
        if FileManager.default.fileExists(atPath: codexDir) {
            result.append(OpenAIProviderAdapter())
        }

        // Other providers that require API keys
        for provider in ProviderId.allCases {
            guard provider != .anthropic, provider != .openai else { continue }
            let ref = "com.creditclock.\(provider.rawValue).credential"
            let hasKey = (try? credentialStore.load(key: ref))?.isEmpty == false

            if hasKey {
                switch provider {
                case .gemini:
                    result.append(GeminiProviderAdapter(credentialStore: credentialStore))
                case .openai, .anthropic:
                    break
                }
            }
        }

        return result
    }
}
