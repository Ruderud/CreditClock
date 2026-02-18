import SwiftUI
import WidgetKit

@main
struct CreditClockApp: App {
    @StateObject private var store = ServiceStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 620, minHeight: 480)
                .task {
                    await store.refresh()
                    store.reconcilePolling()
                }
                .onChange(of: store.hasConfiguredProviders) { _, hasProviders in
                    if hasProviders {
                        store.reconcilePolling()
                    } else {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
        }

        MenuBarExtra("CreditClock", systemImage: "creditcard.circle") {
            MenuBarView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
