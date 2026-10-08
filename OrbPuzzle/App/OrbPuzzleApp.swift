import SwiftUI
import UIKit

enum AppIdleTimerPolicy {
    static func shouldDisableIdleTimer(for scenePhase: ScenePhase) -> Bool {
        scenePhase == .active
    }
}

@main
struct OrbPuzzleApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    applyIdleTimerPolicy(for: scenePhase)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    applyIdleTimerPolicy(for: newPhase)
                }
        }
    }

    @MainActor
    private func applyIdleTimerPolicy(for scenePhase: ScenePhase) {
        let shouldDisable = AppIdleTimerPolicy.shouldDisableIdleTimer(for: scenePhase)
        UIApplication.shared.isIdleTimerDisabled = shouldDisable
#if DEBUG
        print("[IDLE_TIMER] disabled=\(shouldDisable)")
#endif
    }
}
