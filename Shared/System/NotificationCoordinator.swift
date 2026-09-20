import Foundation
import UserNotifications

@MainActor final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()
    nonisolated static let identifier = "kusc.scheduled-start"
    private let writes = ScheduledNotificationWrites()
    func install() { UNUserNotificationCenter.current().delegate = self }
    func schedule(_ request: ScheduledStartRequest) async throws {
        let center = UNUserNotificationCenter.current()
        let authorized = try await center.requestAuthorization(options: [.alert, .sound])
        guard authorized else { throw NotificationError.permissionDenied }
        let task = writes.submit(id: request.id, write: { [self] in
            try await center.add(notification(request, body: "Tap to start KUSC live. Output: \(request.output.summary)."))
        }, remove: { [self] in remove(request.id) })
        try await task.value
    }
    func replaceFallback(_ request: ScheduledStartRequest, body: String) {
        writes.submit(id: request.id, write: { [self] in
            try await UNUserNotificationCenter.current().add(notification(request, body: body))
        }, remove: { [self] in remove(request.id) })
    }
    private func notification(_ request: ScheduledStartRequest, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "KUSC scheduled start"
        content.body = body
        content.sound = .default
        content.userInfo = ["action": "start-live", "scheduleID": request.id.uuidString]
        // Keep the fallback at T; no early pre-roll notification. Past failures notify promptly.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, request.date.timeIntervalSinceNow), repeats: false)
        return UNNotificationRequest(identifier: Self.identifier + "." + request.id.uuidString, content: content, trigger: trigger)
    }
    func cancel(requestID: UUID) {
        writes.cancel(id: requestID) { remove(requestID) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
    private func remove(_ id: UUID) {
        let identifiers = [Self.identifier + "." + id.uuidString]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix(Self.identifier) {
            let rawID = response.notification.request.content.userInfo["scheduleID"] as? String
            let id = rawID.flatMap(UUID.init(uuidString:))
            Task { @MainActor in
                AppModel.shared.startFromNotification(requestID: id)
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            if AppModel.shared.isAudible { completionHandler([]) }
            else { completionHandler([.banner, .sound]) }
        }
    }
    enum NotificationError: LocalizedError {
        case permissionDenied
        var errorDescription: String? { "Enable KUSC notifications in iPhone Settings before scheduling a start." }
    }
}
