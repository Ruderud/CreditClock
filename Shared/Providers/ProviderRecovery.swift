import Foundation
import OSLog

enum ProviderRecovery {
    static var canRunCLIWarmup: Bool {
        !isSandboxed
    }

    static func isUnauthorized(_ error: Error) -> Bool {
        guard let providerError = error as? ProviderError else { return false }
        if case let .httpError(code, _) = providerError {
            return code == 401
        }
        return false
    }

    @discardableResult
    static func runCLIWarmup(
        command: String,
        arguments: [String],
        timeoutNs: UInt64 = 4_000_000_000
    ) async -> Bool {
        let argsDescription = arguments.joined(separator: " ")
        guard canRunCLIWarmup else {
            logger.warning("Warmup skipped (sandbox). command=\(command, privacy: .public) args=\(argsDescription, privacy: .public)")
            return false
        }

        logger.info("Warmup start. command=\(command, privacy: .public) args=\(argsDescription, privacy: .public)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        var environment = ProcessInfo.processInfo.environment
        let home = realHomeDirectory()
        let existingPath = environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
        environment["PATH"] = [
            "\(home)/.volta/bin",
            "\(home)/.npm-global/bin",
            "\(home)/bin",
            existingPath
        ].joined(separator: ":")
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: home, isDirectory: true)

        do {
            try process.run()
        } catch {
            logger.error("Warmup launch failed. command=\(command, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return false
        }

        let pollNs: UInt64 = 100_000_000
        var elapsedNs: UInt64 = 0
        while process.isRunning && elapsedNs < timeoutNs {
            try? await Task.sleep(nanoseconds: pollNs)
            elapsedNs += pollNs
        }

        guard process.isRunning else {
            logger.info("Warmup finished quickly. command=\(command, privacy: .public) status=\(process.terminationStatus)")
            return true
        }

        process.terminate()
        try? await Task.sleep(nanoseconds: 300_000_000)

        if process.isRunning {
            process.interrupt()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        logger.info("Warmup timeout/terminated. command=\(command, privacy: .public) status=\(process.terminationStatus)")
        return true
    }

    static func log(_ level: OSLogType, _ message: String) {
        logger.log(level: level, "\(message, privacy: .public)")
    }

    private static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.creditclock",
        category: "ProviderRecovery"
    )
}
