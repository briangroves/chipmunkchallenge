import BackgroundTasks
import UserNotifications

/// The red badge on the app icon: the number of boards waiting for review. Kept current when the app is open, and
/// every ~6 hours in the background (iOS decides the exact time; it runs less often if the app is rarely opened, and
/// not at all if Background App Refresh is off for it).
enum Badge {
    static let refreshID = "com.groveseng.boardreviewer.refresh"
    static let every: TimeInterval = 6 * 3600

    /// Asks once for permission to show a badge (no alerts or sounds).
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.badge])
    }

    static func set(_ n: Int) {
        UNUserNotificationCenter.current().setBadgeCount(n)
    }

    /// Book the next background check.
    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: refreshID)
        r.earliestBeginDate = Date(timeIntervalSinceNow: every)
        try? BGTaskScheduler.shared.submit(r)
    }

    /// The background check: count waiting boards on GitHub and set the badge.
    static func check() async {
        schedule()
        let repo = UserDefaults.standard.string(forKey: "repo") ?? "briangroves/chipmunk-board-queue"
        let token = Keychain.token
        guard !token.isEmpty, let n = try? await QueueRepo(repo: repo, token: token).waitingCount() else { return }
        // Boards decided on this phone but not sent yet (offline) aren't waiting any more.
        let unsent = (UserDefaults.standard.data(forKey: "outbox"))
            .flatMap { try? JSONDecoder().decode([Decision].self, from: $0) }?.count ?? 0
        set(max(0, n - unsent))
    }
}
