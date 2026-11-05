import SwiftUI

@main
struct ChipmunkChallengeApp: App {
    init() {
        Theme.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Launch with `-web YES` to see the old web version, for side-by-side comparison.
            if UserDefaults.standard.bool(forKey: "web") {
                GameWebView()
                    .ignoresSafeArea()
                    .background(Color(red: 0x1f / 255, green: 0x2f / 255, blue: 0x1b / 255))
                    .persistentSystemOverlays(.hidden)
            } else {
                PlayScreen().persistentSystemOverlays(.hidden)
            }
            #else
            PlayScreen().persistentSystemOverlays(.hidden)
            #endif
        }
    }
}
