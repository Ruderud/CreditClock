import AppKit
import Security
import SwiftUI

struct ProviderSettingsView: View {
    @ObservedObject var store: ServiceStore
    @State private var accounts: [ProviderAccount] = ProviderId.allCases.map {
        ProviderAccount.defaultAccount(for: $0)
    }
    @State private var apiKeyInputs: [String: String] = [:]
    @State private var testResults: [String: TestResult] = [:]
    @State private var localAccessState: [LocalDataSource: Bool] = [:]
    @State private var connectionState: [ProviderId: Bool] = [:]
    @State private var localAccessMessage: String?
    @State private var expandedLogs: Set<ProviderId> = []
    @State private var claudeAuthInProgress = false
    @State private var claudeAuthMessage: String?

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

        if provider == .anthropic {
            HStack {
                Button("Auth Status") {
                    Task { await runClaudeAuthStatus() }
                }
                .disabled(claudeAuthInProgress)

                Button("Re-login Claude") {
                    Task { await reloginClaudeInApp() }
                }
                .disabled(claudeAuthInProgress)

                if claudeAuthInProgress {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let claudeAuthMessage {
                Text(claudeAuthMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        providerLogSection(for: provider)
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

        providerLogSection(for: account.wrappedValue.provider)
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

    private func runClaudeAuthStatus() async {
        claudeAuthInProgress = true
        defer { claudeAuthInProgress = false }

        let local = readClaudeLocalOAuthStatus()

        do {
            _ = try await AnthropicProviderAdapter().fetchSnapshot()
            claudeAuthMessage = summarizeClaudeAuthStatus(localStatus: local, fetchError: nil)
        } catch {
            claudeAuthMessage = summarizeClaudeAuthStatus(localStatus: local, fetchError: error)
        }
    }

    private func reloginClaudeInApp() async {
        claudeAuthInProgress = true
        claudeAuthMessage = "Opening Terminal for Claude login..."
        let result = await launchClaudeAuthInTerminal()
        claudeAuthInProgress = false
        switch result {
        case .opened:
            claudeAuthMessage = "Terminal에서 `claude auth login`을 실행했습니다. 브라우저 로그인 후 돌아와 `Auth Status` 또는 `Test`를 눌러주세요."
        case .permissionDenied:
            let copied = copyClaudeLoginCommandToPasteboard()
            _ = openTerminalApp()
            if copied {
                claudeAuthMessage = "Terminal 자동 제어 권한이 거부되었습니다. macOS 설정에서 CreditClock -> Terminal 자동화를 허용해주세요. `claude auth login` 명령어를 클립보드에 복사했습니다."
            } else {
                claudeAuthMessage = "Terminal 자동 제어 권한이 거부되었습니다. macOS 설정에서 CreditClock -> Terminal 자동화를 허용한 뒤 다시 시도하거나, Terminal에서 `claude auth login`을 직접 실행해주세요."
            }
        case .scriptCreationFailed:
            let copied = copyClaudeLoginCommandToPasteboard()
            _ = openTerminalApp()
            claudeAuthMessage = copied
                ? "자동 실행 스크립트 생성에 실패했습니다. Terminal을 열었고 `claude auth login` 명령어를 클립보드에 복사했습니다."
                : "자동 실행 스크립트 생성에 실패했습니다. Terminal에서 `claude auth login`을 직접 실행해주세요."
        case .scriptError(let code, let message):
            let copied = copyClaudeLoginCommandToPasteboard()
            _ = openTerminalApp()
            claudeAuthMessage = copied
                ? "자동 실행 실패(code \(code)): \(message). Terminal을 열었고 `claude auth login` 명령어를 클립보드에 복사했습니다."
                : "자동 실행 실패(code \(code)): \(message). Terminal에서 `claude auth login`을 직접 실행해주세요."
        }
    }

    private func launchClaudeAuthInTerminal() async -> TerminalLaunchResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let home = realHomeDirectory()
                let command = """
                export HOME="\(home)";
                export PATH="\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH";
                clear;
                echo "Running: claude auth login";
                if command -v claude >/dev/null 2>&1; then
                  claude auth login;
                else
                  echo "claude CLI not found in PATH.";
                  echo "Install Claude CLI or check your PATH.";
                fi
                """

                let escaped = command
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")

                let source = """
                tell application "Terminal"
                    activate
                    do script "\(escaped)"
                end tell
                """

                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .scriptCreationFailed)
                    return
                }

                _ = script.executeAndReturnError(&error)
                guard let error else {
                    continuation.resume(returning: .opened)
                    return
                }

                let code = error[NSAppleScript.errorNumber] as? Int ?? -1
                let message = (error[NSAppleScript.errorMessage] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "unknown AppleScript error"

                if code == -1743 {
                    continuation.resume(returning: .permissionDenied)
                    return
                }

                continuation.resume(returning: .scriptError(code: code, message: message))
            }
        }
    }

    @discardableResult
    private func copyClaudeLoginCommandToPasteboard() -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString("claude auth login", forType: .string)
    }

    @discardableResult
    private func openTerminalApp() -> Bool {
        let appURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            return NSWorkspace.shared.open(appURL)
        }
        return false
    }

    private func summarizeClaudeAuthStatus(localStatus: ClaudeLocalOAuthStatus, fetchError: Error?) -> String {
        let sourceLabel: String = {
            switch localStatus.source {
            case .keychain: return "keychain"
            case .file: return ".claude/.credentials.json"
            case .none: return "none"
            }
        }()

        if fetchError == nil {
            var parts = ["Claude OAuth usable (direct API fetch succeeded)."]
            if localStatus.source != .none {
                parts.append("local source: \(sourceLabel)")
                if let expiresAt = localStatus.expiresAt {
                    parts.append("expires: \(dateText(expiresAt))")
                }
            } else {
                parts.append("local token source not found (may still be available via keychain prompt/session).")
            }
            return parts.joined(separator: " ")
        }

        if localStatus.source == .none {
            return "Claude local OAuth credentials not found. Terminal에서 `claude auth login` 실행 후 다시 `Auth Status` 또는 `Test`를 눌러주세요."
        }

        var parts = [
            "Claude local OAuth found (\(sourceLabel)) but fetch failed:",
            fetchError?.localizedDescription ?? "unknown error"
        ]
        if let expiresAt = localStatus.expiresAt {
            parts.append("(expires \(dateText(expiresAt))).")
        }
        return parts.joined(separator: " ")
    }

    private func readClaudeLocalOAuthStatus() -> ClaudeLocalOAuthStatus {
        if let keychainData = readClaudeCredentialsDataFromKeychain(),
           let parsed = parseClaudeLocalOAuthStatus(from: keychainData, source: .keychain) {
            return parsed
        }

        if let fileData = ExternalDataAccess.shared.withDirectoryAccess(for: .claude, { claudeDir in
            let credsURL = claudeDir.appendingPathComponent(".credentials.json")
            return try? Data(contentsOf: credsURL)
        }),
           let parsed = parseClaudeLocalOAuthStatus(from: fileData, source: .file) {
            return parsed
        }

        return ClaudeLocalOAuthStatus(
            source: .none,
            hasAccessToken: false,
            hasRefreshToken: false,
            expiresAt: nil
        )
    }

    private func readClaudeCredentialsDataFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private func parseClaudeLocalOAuthStatus(from data: Data, source: ClaudeCredentialSource) -> ClaudeLocalOAuthStatus? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let oauth = (raw["claudeAiOauth"] as? [String: Any]) ?? raw

        let accessToken = stringValue(in: oauth, keys: ["accessToken", "access_token"])
        let refreshToken = stringValue(in: oauth, keys: ["refreshToken", "refresh_token"])
        let expiresAtMs = numericValue(in: oauth, keys: ["expiresAt", "expires_at"]).map { value in
            value > 10_000_000_000 ? value : value * 1000
        }
        let expiresAt = expiresAtMs.map { Date(timeIntervalSince1970: $0 / 1000) }

        guard accessToken != nil || refreshToken != nil else { return nil }

        return ClaudeLocalOAuthStatus(
            source: source,
            hasAccessToken: accessToken != nil,
            hasRefreshToken: refreshToken != nil,
            expiresAt: expiresAt
        )
    }

    private func stringValue(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func numericValue(in dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dict[key] as? Double {
                return value
            }
            if let value = dict[key] as? Int {
                return Double(value)
            }
            if let value = dict[key] as? Int64 {
                return Double(value)
            }
            if let value = dict[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = dict[key] as? String, let parsed = Double(value) {
                return parsed
            }
        }
        return nil
    }

    @ViewBuilder
    private func providerLogSection(for provider: ProviderId) -> some View {
        let health = store.healthMap[provider.rawValue]
        let snapshotUpdatedAt = store.snapshots.first(where: { $0.id == provider.rawValue })?.updatedAt

        DisclosureGroup(isExpanded: expandedBinding(for: provider)) {
            VStack(alignment: .leading, spacing: 6) {
                logRow(title: "Snapshot updated", value: dateText(snapshotUpdatedAt))
                logRow(title: "Last success", value: dateText(health?.lastSuccessAt))
                logRow(title: "Last failure", value: dateText(health?.lastFailureAt))
                logRow(title: "Latency", value: health?.latencyMs.map { "\($0)ms" } ?? "-")
                logRow(title: "Consecutive failures", value: "\(health?.consecutiveFailures ?? 0)")
                if let error = health?.lastErrorMessage, !error.isEmpty {
                    logRow(title: "Last error", value: error)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Text("Fetch Log")
                Spacer()
                Text(providerLogStatusText(health: health, snapshotUpdatedAt: snapshotUpdatedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(providerLogStatusColor(health: health))
            }
        }
    }

    private func logRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func expandedBinding(for provider: ProviderId) -> Binding<Bool> {
        Binding(
            get: { expandedLogs.contains(provider) },
            set: { expanded in
                if expanded {
                    expandedLogs.insert(provider)
                } else {
                    expandedLogs.remove(provider)
                }
            }
        )
    }

    private func providerLogStatusText(health: FetchHealth?, snapshotUpdatedAt: Date?) -> String {
        if let success = health?.lastSuccessAt {
            return "OK \(dateText(success))"
        }
        if let failure = health?.lastFailureAt {
            return "FAIL \(dateText(failure))"
        }
        if let snapshotUpdatedAt {
            return "SNAPSHOT \(dateText(snapshotUpdatedAt))"
        }
        return "NO RECORD"
    }

    private func providerLogStatusColor(health: FetchHealth?) -> Color {
        if health?.lastSuccessAt != nil { return .green }
        if health?.lastFailureAt != nil { return .red }
        return .secondary
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "-" }
        return date.formatted(date: .abbreviated, time: .standard)
    }
}

private struct TestResult {
    let success: Bool
    let message: String
}

private enum ClaudeCredentialSource {
    case keychain
    case file
    case none
}

private struct ClaudeLocalOAuthStatus {
    let source: ClaudeCredentialSource
    let hasAccessToken: Bool
    let hasRefreshToken: Bool
    let expiresAt: Date?
}

private enum TerminalLaunchResult {
    case opened
    case permissionDenied
    case scriptCreationFailed
    case scriptError(code: Int, message: String)
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
