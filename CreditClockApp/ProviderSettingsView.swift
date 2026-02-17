import AppKit
import SwiftUI

struct ProviderSettingsView: View {
    @State private var accounts: [ProviderAccount] = ProviderId.allCases.map {
        ProviderAccount.defaultAccount(for: $0)
    }
    @State private var apiKeyInputs: [String: String] = [:]
    @State private var testResults: [String: TestResult] = [:]
    @State private var localAccessState: [LocalDataSource: Bool] = [:]
    @State private var localAccessMessage: String?

    private let credentialStore: CredentialStore = KeychainCredentialStore()

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
        }
    }

    private var localAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Grant one-time folder access for local usage caches.")
                .foregroundStyle(.secondary)

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
                        requestLocalAccess(for: source)
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

        Toggle("Enabled", isOn: account.isEnabled)

        LabeledContent("Auth Method") {
            Text("API Key")
                .foregroundStyle(.secondary)
        }

        HStack {
            SecureField("API Key", text: binding(for: id))
                .textFieldStyle(.roundedBorder)

            Button("Save") {
                saveKey(for: account.wrappedValue)
            }

            Button("Test") {
                Task { await testConnection(for: account.wrappedValue) }
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
            testResults[account.id] = TestResult(success: true, message: "Key saved")
        } catch {
            testResults[account.id] = TestResult(success: false, message: error.localizedDescription)
        }
    }

    private func testConnection(for account: ProviderAccount) async {
        let provider: ServiceProvider
        switch account.provider {
        case .openai: provider = OpenAIProviderAdapter()
        case .anthropic: provider = AnthropicProviderAdapter()
        case .gemini: provider = GeminiProviderAdapter()
        }

        do {
            _ = try await provider.fetchSnapshot()
            testResults[account.id] = TestResult(success: true, message: "Connected")
        } catch {
            testResults[account.id] = TestResult(success: false, message: error.localizedDescription)
        }
    }

    private func refreshLocalAccessState() {
        var next: [LocalDataSource: Bool] = [:]
        for source in LocalDataSource.allCases {
            next[source] = ExternalDataAccess.shared.hasBookmark(for: source)
        }
        localAccessState = next
    }

    private func requestLocalAccess(for source: LocalDataSource) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.title = "\(source.displayName) Folder Access"
        panel.message = "Choose the \(source.expectedDirectoryName) folder once to stop repeated permission prompts."
        panel.prompt = "Grant Access"
        panel.directoryURL = URL(fileURLWithPath: realHomeDirectory(), isDirectory: true)

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        guard selectedURL.lastPathComponent == source.expectedDirectoryName else {
            localAccessMessage = "Please select ~/\(source.expectedDirectoryName)"
            return
        }

        do {
            let bookmark = try selectedURL.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            ExternalDataAccess.shared.saveBookmark(bookmark, for: source)
            localAccessMessage = "\(source.displayName) access granted."
            refreshLocalAccessState()
        } catch {
            localAccessMessage = "Failed to save bookmark: \(error.localizedDescription)"
        }
    }

    private func clearLocalAccess(for source: LocalDataSource) {
        ExternalDataAccess.shared.clearBookmark(for: source)
        localAccessMessage = "\(source.displayName) access removed."
        refreshLocalAccessState()
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
