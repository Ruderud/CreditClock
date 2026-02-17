import SwiftUI
import WidgetKit

@main
struct CreditClockApp: App {
    @StateObject private var store = ServiceStore()
    @State private var scheduler: PollingScheduler?

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 620, minHeight: 480)
                .task {
                    await store.refresh()
                    startPollingIfNeeded()
                }
                .onChange(of: store.hasConfiguredProviders) { _, hasProviders in
                    if hasProviders {
                        startPollingIfNeeded()
                    } else if scheduler != nil {
                        scheduler?.stop()
                        scheduler = nil
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
        }

        MenuBarExtra("CreditClock", systemImage: "creditcard.circle") {
            MenuBarView(store: store)
        }
        .menuBarExtraStyle(.window)
    }

    private func startPollingIfNeeded() {
        guard scheduler == nil, store.hasConfiguredProviders else { return }
        let s = PollingScheduler { [store] in
            await store.refreshReturningSuccess()
        }
        scheduler = s
        s.start()
    }
}
