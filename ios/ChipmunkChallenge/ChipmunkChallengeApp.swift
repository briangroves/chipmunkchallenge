import SwiftUI

@main
struct ChipmunkChallengeApp: App {
    var body: some Scene {
        WindowGroup {
            // The native game. The old web version (GameWebView) stays in the project until everything is ported.
            GameView()
                .persistentSystemOverlays(.hidden)
        }
    }
}
