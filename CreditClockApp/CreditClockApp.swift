import SwiftUI

@main
struct CreditClockApp: App {
    @StateObject private var store = ServiceStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 620, minHeight: 480)
                .task {
                    await store.refresh()
                }
        }
    }
}
