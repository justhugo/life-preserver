import SwiftUI

@main
struct LifePreserverMobileApp: App {
    @StateObject private var store = MobileStore(preview: CommandLine.arguments.contains("--preview"))
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MobileUsageView(store: store)
                .task {
                    await store.refresh()
                    if CommandLine.arguments.contains("--check-direct") {
                        print("Direct mobile verification: \(store.accounts.filter { $0.error == nil && !$0.isStale() }.count)/\(store.accounts.count) providers current")
                        if let message = store.message { print(message) }
                        fflush(stdout)
                        exit(store.accounts.count == 4 && !store.checkFailed ? 0 : 1)
                    }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active, !CommandLine.arguments.contains("--check-direct") else { return }
                    while !Task.isCancelled {
                        await store.refresh()
                        do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    }
                }
        }
    }
}
