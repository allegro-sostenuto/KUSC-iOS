import Foundation
import UserNotifications

final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()
    static let identifier = "kusc.scheduled-start"
    func install() { UNUserNotificationCenter.current().delegate = self }
    func schedule(at date: Date) async throws {
        let center = UNUserNotificationCenter.current()
        let authorized = try await center.requestAuthorization(options: [.alert, .sound])
        guard authorized else { throw NotificationError.permissionDenied }
        let content = UNMutableNotificationContent()
        content.title = "KUSC scheduled start"
        content.body = "Tap to start KUSC live."
        content.sound = .default
        content.userInfo = ["action": "start-live"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
    }
    func cancelPending() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == Self.identifier {
            Task { @MainActor in
                AppModel.shared.startFromNotification()
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            if AppModel.shared.isPlaying { completionHandler([]) }
            else { completionHandler([.banner, .sound]) }
        }
    }
    enum NotificationError: LocalizedError {
        case permissionDenied
        var errorDescription: String? { "Enable KUSC notifications in iPhone Settings before scheduling a start." }
    }
}
