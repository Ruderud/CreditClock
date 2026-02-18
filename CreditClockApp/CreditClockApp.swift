import SwiftUI

@main
struct CreditClockApp: App {
    @StateObject private var store: ServiceStore

    init() {
        let initialStore = ServiceStore()
        _store = StateObject(wrappedValue: initialStore)

        Task { @MainActor in
            await initialStore.refresh()
            initialStore.reconcilePolling()
        }
    }

    var body: some Scene {
        MenuBarExtra("CreditClock", systemImage: "creditcard.circle") {
            MenuBarView(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            NavigationStack {
                ProviderSettingsView(store: store)
            }
            .frame(minWidth: 500, minHeight: 400)
        }
    }
}
