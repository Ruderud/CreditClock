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

        Window("CreditClock", id: AppDeepLink.dashboardWindowID) {
            ContentView(store: store)
                .frame(minWidth: 420, minHeight: 520)
        }
        .handlesExternalEvents(matching: [AppDeepLink.dashboardHost])

        Settings {
            NavigationStack {
                ProviderSettingsView(store: store)
            }
            .frame(minWidth: 500, minHeight: 400)
        }
    }
}
