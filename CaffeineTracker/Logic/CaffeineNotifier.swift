import Foundation
import UserNotifications

/// Schedules the single "estimate is below your threshold" notification.
enum CaffeineNotifier {
    static let identifier = "caffeine.belowThreshold"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func message(thresholdMg: Double) -> String {
        "Your estimated caffeine is now below \(Int(thresholdMg.rounded())) mg."
    }

    /// Replaces any pending notification with one for the current countdown.
    static func reschedule(doses: [CaffeineDose], profile: UserProfile, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard profile.notificationsEnabled,
              let fireDate = CaffeineModel.timeBelow(thresholdMg: profile.thresholdMg, after: now, doses: doses, halfLifeHours: profile.halfLifeHours)
        else { return }
        let interval = fireDate.timeIntervalSince(now)
        guard interval >= 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Caffeine countdown ended"
        content.body = message(thresholdMg: profile.thresholdMg)
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    #if DEBUG
    /// Sends the same notification in a few seconds, to check it on a device or simulator.
    static func sendTest(thresholdMg: Double, after seconds: TimeInterval = 5) async {
        let content = UNMutableNotificationContent()
        content.title = "Caffeine countdown ended"
        content.body = message(thresholdMg: thresholdMg)
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "caffeine.test", content: content, trigger: trigger))
    }
    #endif

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
