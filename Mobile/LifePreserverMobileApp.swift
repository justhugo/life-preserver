import SwiftUI

@main
struct LifePreserverMobileApp: App {
    @StateObject private var store = MobileStore(preview: CommandLine.arguments.contains("--preview"))
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MobileUsageView(store: store)
                .task { await store.refresh() }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await store.refresh()
                        do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    }
                }
        }
    }
}
