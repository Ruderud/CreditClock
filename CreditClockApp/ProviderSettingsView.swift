import AppKit
import SwiftUI

struct ProviderSettingsView: View {
    @State private var accounts: [ProviderAccount] = ProviderId.allCases.map {
        ProviderAccount.defaultAccount(for: $0)
    }
    @State private var apiKeyInputs: [String: String] = [:]
    @State private var testResults: [String: TestResult] = [:]
    @State private var localAccessState: [LocalDataSource: Bool] = [:]
    @State private var connectionState: [ProviderId: Bool] = [:]
    @State private var localAccessMessage: String?

    private let credentialStore: CredentialStore = KeychainCredentialStore()
    private let connectionStore = ProviderConnectionStore()

    var body: some View {
        Form {
            Section("Local Data Access") {
                localAccessSection
            }

            ForEach($accounts) { $account in
                Section {
                    providerCard(account: $account)
                } header: {
                    Text(account.provider.displayName)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Provider Settings")
        .onAppear {
            loadSavedKeys()
            refreshLocalAccessState()
            loadConnectionState()
        }
    }

    private var localAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Grant one-time folder access for local usage caches. Choose home folder once to cover Codex, Claude, and Gemini CLI.")
                .foregroundStyle(.secondary)

            Button("Grant Codex + Claude + Gemini Together (Recommended)") {
                _ = requestLocalAccess(for: .codex)
            }

            ForEach(LocalDataSource.allCases) { source in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.displayName)
                            .font(.body)
                        Text("Expected folder: ~/\(source.expectedDirectoryName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(localAccessState[source] == true ? "Granted" : "Not granted")
                        .font(.caption)
                        .foregroundStyle(localAccessState[source] == true ? .green : .secondary)
                    Button(localAccessState[source] == true ? "Re-select" : "Grant Access") {
                        _ = requestLocalAccess(for: source)
                    }
                    if localAccessState[source] == true {
                        Button("Clear") {
                            clearLocalAccess(for: source)
                        }
                    }
                }
            }

            if let localAccessMessage {
                Text(localAccessMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func providerCard(account: Binding<ProviderAccount>) -> some View {
        let id = account.wrappedValue.id
        let provider = account.wrappedValue.provider

        if provider == .openai || provider == .anthropic {
            localProviderCard(for: provider, id: id)
        } else {
            apiKeyProviderCard(account: account, id: id)
        }
    }

    @ViewBuilder
    private func localProviderCard(for provider: ProviderId, id: String) -> some View {
        LabeledContent("Auth Method") {
            Text(provider == .openai ? "Local Codex files" : "Claude local cache / OAuth")
                .foregroundStyle(.secondary)
        }

        HStack {
            Text(connectionState[provider] == true ? "Connected" : "Not connected")
                .foregroundStyle(connectionState[provider] == true ? .green : .secondary)
            Spacer()
            Button("Connect") {
                connect(provider)
            }
            .disabled(connectionState[provider] == true)

            Button("Disconnect") {
                disconnect(provider)
            }
            .disabled(connectionState[provider] != true)

            Button("Test") {
                Task { await testConnection(for: provider) }
            }
            .disabled(connectionState[provider] != true)
        }

        if let result = testResults[id] {
            Label(result.message, systemImage: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.success ? .green : .red)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func apiKeyProviderCard(account: Binding<ProviderAccount>, id: String) -> some View {
        Toggle(
            "Enabled",
            isOn: Binding(
                get: { connectionState[account.wrappedValue.provider] ?? false },
                set: {
                    connectionStore.setConnected($0, for: account.wrappedValue.provider)
                    connectionState[account.wrappedValue.provider] = $0
                }
            )
        )

        LabeledContent("Auth Method") {
            Text(account.wrappedValue.provider == .gemini ? "Gemini CLI OAuth or API Key" : "API Key")
                .foregroundStyle(.secondary)
        }

        HStack {
            SecureField("API Key", text: binding(for: id))
                .textFieldStyle(.roundedBorder)

            Button("Save") {
                saveKey(for: account.wrappedValue)
            }

            Button("Test") {
                Task { await testConnection(for: account.wrappedValue.provider) }
            }
        }

        if let result = testResults[id] {
            Label(result.message, systemImage: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.success ? .green : .red)
                .font(.caption)
        }
    }

    private func binding(for id: String) -> Binding<String> {
        Binding(
            get: { apiKeyInputs[id, default: ""] },
            set: { apiKeyInputs[id] = $0 }
        )
    }

    private func loadSavedKeys() {
        for account in accounts {
            if let key = try? credentialStore.load(key: account.credentialsRef), !key.isEmpty {
                let masked = String(repeating: "*", count: max(key.count - 4, 0)) + key.suffix(4)
                apiKeyInputs[account.id] = masked
            }
        }
    }

    private func saveKey(for account: ProviderAccount) {
        let key = apiKeyInputs[account.id, default: ""]
        guard !key.isEmpty, !key.contains("*") else { return }
        do {
            try credentialStore.save(key: account.credentialsRef, value: key)
            connectionStore.setConnected(true, for: account.provider)
            connectionState[account.provider] = true
            testResults[account.id] = TestResult(success: true, message: "Key saved")
        } catch {
            testResults[account.id] = TestResult(success: false, message: error.localizedDescription)
        }
    }

    private func testConnection(for providerId: ProviderId) async {
        let provider: ServiceProvider
        switch providerId {
        case .openai: provider = OpenAIProviderAdapter()
        case .anthropic: provider = AnthropicProviderAdapter()
        case .gemini: provider = GeminiProviderAdapter()
        }

        do {
            _ = try await provider.fetchSnapshot()
            testResults[providerId.rawValue] = TestResult(success: true, message: "Connected")
        } catch {
            testResults[providerId.rawValue] = TestResult(success: false, message: error.localizedDescription)
        }
    }

    private func refreshLocalAccessState() {
        var next: [LocalDataSource: Bool] = [:]
        for source in LocalDataSource.allCases {
            next[source] = ExternalDataAccess.shared.isConfigured(for: source)
        }
        localAccessState = next
    }

    private func requestLocalAccess(for source: LocalDataSource) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.title = "\(source.displayName) Folder Access"
        panel.message = "Choose your home folder to grant Codex + Claude + Gemini together, or choose only \(source.expectedDirectoryName)."
        panel.prompt = "Grant Access"
        panel.directoryURL = URL(fileURLWithPath: realHomeDirectory(), isDirectory: true)

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return false }

        let standardizedSelected = selectedURL.standardizedFileURL
        let homeURL = URL(fileURLWithPath: realHomeDirectory(), isDirectory: true).standardizedFileURL

        guard standardizedSelected == homeURL || standardizedSelected.lastPathComponent == source.expectedDirectoryName else {
            localAccessMessage = "Please select your home folder or ~/\(source.expectedDirectoryName)"
            return false
        }

        do {
            let bookmark = try standardizedSelected.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            if standardizedSelected == homeURL {
                ExternalDataAccess.shared.saveBookmark(bookmark, for: .codex)
                ExternalDataAccess.shared.saveBookmark(bookmark, for: .claude)
                ExternalDataAccess.shared.saveBookmark(bookmark, for: .gemini)
                localAccessMessage = "Codex + Claude + Gemini access granted together."
            } else {
                ExternalDataAccess.shared.saveBookmark(bookmark, for: source)
                localAccessMessage = "\(source.displayName) access granted."
            }
            refreshLocalAccessState()
            return true
        } catch {
            localAccessMessage = "Failed to save bookmark: \(error.localizedDescription)"
            return false
        }
    }

    private func clearLocalAccess(for source: LocalDataSource) {
        ExternalDataAccess.shared.clearBookmark(for: source)
        localAccessMessage = "\(source.displayName) access removed."
        refreshLocalAccessState()
    }

    private func loadConnectionState() {
        var next: [ProviderId: Bool] = [:]
        for provider in ProviderId.allCases {
            next[provider] = connectionStore.isConnected(provider)
        }
        connectionState = next
    }

    private func connect(_ provider: ProviderId) {
        switch provider {
        case .openai:
            guard ensureCombinedLocalAccess() else { return }
        case .anthropic:
            guard ensureCombinedLocalAccess() else { return }
        case .gemini:
            break
        }

        connectionStore.setConnected(true, for: provider)
        connectionState[provider] = true
        testResults[provider.rawValue] = TestResult(success: true, message: "Connected")
    }

    /// For local providers, request home-folder access once and reuse it for all sources.
    private func ensureCombinedLocalAccess() -> Bool {
        if ExternalDataAccess.shared.isConfigured(for: .codex),
           ExternalDataAccess.shared.isConfigured(for: .claude),
           ExternalDataAccess.shared.isConfigured(for: .gemini) {
            return true
        }
        return requestCombinedHomeAccess()
    }

    private func requestCombinedHomeAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.title = "Local Folder Access"
        panel.message = "Select your home folder once to grant Codex + Claude + Gemini CLI access together."
        panel.prompt = "Grant Access"
        panel.directoryURL = URL(fileURLWithPath: realHomeDirectory(), isDirectory: true)

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return false }

        let standardizedSelected = selectedURL.standardizedFileURL
        let homeURL = URL(fileURLWithPath: realHomeDirectory(), isDirectory: true).standardizedFileURL
        guard standardizedSelected == homeURL else {
            localAccessMessage = "Please select your home folder (~)."
            return false
        }

        do {
            let bookmark = try standardizedSelected.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            ExternalDataAccess.shared.saveBookmark(bookmark, for: .codex)
            ExternalDataAccess.shared.saveBookmark(bookmark, for: .claude)
            ExternalDataAccess.shared.saveBookmark(bookmark, for: .gemini)
            localAccessMessage = "Codex + Claude + Gemini access granted together."
            refreshLocalAccessState()
            return true
        } catch {
            localAccessMessage = "Failed to save bookmark: \(error.localizedDescription)"
            return false
        }
    }

    private func disconnect(_ provider: ProviderId) {
        connectionStore.setConnected(false, for: provider)
        connectionState[provider] = false
        testResults[provider.rawValue] = TestResult(success: true, message: "Disconnected")
    }
}

private struct TestResult {
    let success: Bool
    let message: String
}

extension ProviderId {
    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Gemini"
        }
    }
}
