import Foundation
import UserNotifications
import BackgroundTasks

/// Manages push notification registration and scheduling for sun/shade transition alerts.
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Schedule Transition Notification

    /// Schedules an immediate local notification when a bar's patio enters sunlight.
    func scheduleTransitionNotification(barName: String) {
        let content = UNMutableNotificationContent()
        content.title = "☀️ Patio in the Sun!"
        content.body  = "\(barName)'s patio is in the sun right now."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "sun-transition-\(barName)-\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { _ in }
    }

    /// Schedules a future notification for when a patio is expected to enter sunlight.
    func scheduleUpcomingNotification(barName: String, sunriseTime: Date) {
        guard sunriseTime > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "☀️ Patio Sun Alert"
        content.body  = "\(barName)'s patio is about to be in the sun!"
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: sunriseTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "sun-upcoming-\(barName)-\(Int(sunriseTime.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Pending Notifications

    func cancelNotifications(for barName: String) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.contains(barName) }
                .map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Background Task Scheduling

    func scheduleBackgroundSunCheck() {
        SummertimeChiApp.scheduleNextSunCheck()
    }
}
