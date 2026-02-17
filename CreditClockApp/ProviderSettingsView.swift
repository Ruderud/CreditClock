import SwiftUI

struct ProviderSettingsView: View {
    @State private var accounts: [ProviderAccount] = ProviderId.allCases.map {
        ProviderAccount.defaultAccount(for: $0)
    }
    @State private var apiKeyInputs: [String: String] = [:]
    @State private var testResults: [String: TestResult] = [:]

    private let credentialStore: CredentialStore = KeychainCredentialStore()

    var body: some View {
        Form {
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
        .onAppear(perform: loadSavedKeys)
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
