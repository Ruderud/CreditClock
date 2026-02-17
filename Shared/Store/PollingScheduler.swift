import Foundation
import Combine
import WidgetKit

@MainActor
final class PollingScheduler: ObservableObject {
    @Published private(set) var isPolling = false

    private let baseInterval: TimeInterval
    private let maxBackoffInterval: TimeInterval
    private var currentInterval: TimeInterval
    private var consecutiveFailures = 0
    private var timer: Task<Void, Never>?
    private let action: () async -> Bool

    init(
        baseInterval: TimeInterval = 60,
        maxBackoffInterval: TimeInterval = 300,
        action: @escaping () async -> Bool
    ) {
        self.baseInterval = baseInterval
        self.maxBackoffInterval = maxBackoffInterval
        self.currentInterval = baseInterval
        self.action = action
    }

    func start() {
        stop()
        isPolling = true
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                let success = await self.action()

                if success {
                    self.consecutiveFailures = 0
                    self.currentInterval = self.baseInterval
                } else {
                    self.consecutiveFailures += 1
                    let backoff = self.baseInterval * pow(2, Double(min(self.consecutiveFailures, 5)))
                    self.currentInterval = min(backoff, self.maxBackoffInterval)
                }

                WidgetCenter.shared.reloadAllTimelines()

                try? await Task.sleep(nanoseconds: UInt64(self.currentInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isPolling = false
    }

    func triggerNow() async {
        _ = await action()
        WidgetCenter.shared.reloadAllTimelines()
    }

    deinit {
        timer?.cancel()
    }
}
