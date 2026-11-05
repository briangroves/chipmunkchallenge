import SwiftUI

@main
struct ChipmunkChallengeApp: App {
    var body: some Scene {
        WindowGroup {
            GameWebView()
                .ignoresSafeArea()            // the page handles the notch itself (viewport-fit=cover)
                .background(Color(red: 0x1f / 255, green: 0x2f / 255, blue: 0x1b / 255))
                .persistentSystemOverlays(.hidden)
        }
    }
}
