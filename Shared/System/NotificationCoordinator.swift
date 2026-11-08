import Foundation
import UserNotifications

@MainActor final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()
    nonisolated static let identifier = "kusc.scheduled-start"
    private let writes = ScheduledNotificationWrites()
    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let cancel = UNNotificationAction(identifier: "manage-schedule", title: "Tap to cancel", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: "scheduled-heads-up", actions: [cancel], intentIdentifiers: [])])
    }
    func schedule(_ request: ScheduledStartRequest) async throws {
        let center = UNUserNotificationCenter.current()
        let authorized: Bool
        do {
            authorized = try await center.requestAuthorization(options: [.alert, .sound])
            PlaybackDebugJournal.emit(category: "notification", name: "notification_authorization_checked", scheduleID: request.id.uuidString,
                                      details: ["authorized": String(authorized)])
        } catch {
            PlaybackDebugJournal.emit(category: "notification", name: "notification_authorization_failed", scheduleID: request.id.uuidString,
                                      details: ["error": PlaybackDiagnosticLog.sanitizedError(error)])
            throw error
        }
        guard authorized else { throw NotificationError.permissionDenied }
        let task = writes.submit(id: request.id, write: { [self] in
            do {
                try await center.add(headsUpNotification(request))
                try await center.add(notification(request, body: "Tap to start Philharmonic live. Output: \(request.output.summary)."))
                PlaybackDebugJournal.emit(category: "notification", name: "notification_scheduled", scheduleID: request.id.uuidString,
                                          details: ["kind": "heads_up_and_fallback", "evidence": "notification_center_accepted"])
            } catch {
                PlaybackDebugJournal.emit(category: "notification", name: "notification_schedule_failed", scheduleID: request.id.uuidString,
                                          details: ["error": PlaybackDiagnosticLog.sanitizedError(error)])
                remove(request.id); throw error
            }
        }, remove: { [self] in remove(request.id) })
        try await task.value
    }
    func replaceFallback(_ request: ScheduledStartRequest, body: String) {
        writes.submit(id: request.id, write: { [self] in
            do {
                try await UNUserNotificationCenter.current().add(notification(request, body: body))
                PlaybackDebugJournal.emit(category: "notification", name: "notification_scheduled", scheduleID: request.id.uuidString,
                                          details: ["kind": "fallback", "evidence": "notification_center_accepted"])
            } catch {
                PlaybackDebugJournal.emit(category: "notification", name: "notification_schedule_failed", scheduleID: request.id.uuidString,
                                          details: ["kind": "fallback", "error": PlaybackDiagnosticLog.sanitizedError(error)])
                throw error
            }
        }, remove: { [self] in remove(request.id) })
    }
    private func notification(_ request: ScheduledStartRequest, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "\(StationCatalog.station(id: request.stationID)?.name ?? "Philharmonic") scheduled start"
        content.body = body
        content.sound = .default
        content.userInfo = ["action": "start-live", "scheduleID": request.id.uuidString]
        // The fallback remains at T; a separate reminder opens cancellation at T-2 minutes.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, request.date.timeIntervalSinceNow), repeats: false)
        return UNNotificationRequest(identifier: Self.identifier + "." + request.id.uuidString, content: content, trigger: trigger)
    }
    func headsUpNotification(_ request: ScheduledStartRequest, now: Date = Date()) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Philharmonic scheduled start at \(request.date.formatted(date: .omitted, time: .shortened))"
        content.body = "\(StationCatalog.station(id: request.stationID)?.name ?? "Philharmonic"). Tap to cancel. Opens Scheduled Start at Delete Scheduled Start."
        content.sound = .default
        content.categoryIdentifier = "scheduled-heads-up"
        content.userInfo = ["action": "manage-schedule", "scheduleID": request.id.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, request.date.timeIntervalSince(now) - 120), repeats: false)
        return UNNotificationRequest(identifier: Self.identifier + "." + request.id.uuidString + ".heads-up", content: content, trigger: trigger)
    }
    func cancel(requestID: UUID) {
        PlaybackDebugJournal.emit(category: "notification", name: "notification_removal_requested", scheduleID: requestID.uuidString)
        writes.cancel(id: requestID) { remove(requestID) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
    private func remove(_ id: UUID) {
        let base = Self.identifier + "." + id.uuidString
        let identifiers = [base, base + ".heads-up"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix(Self.identifier) {
            let rawID = response.notification.request.content.userInfo["scheduleID"] as? String
            let id = rawID.flatMap(UUID.init(uuidString:))
            let manage = response.notification.request.content.userInfo["action"] as? String == "manage-schedule"
            PlaybackDebugJournal.emit(category: "notification", name: "notification_response_received", scheduleID: id?.uuidString,
                                      details: ["action": response.actionIdentifier == UNNotificationDismissActionIdentifier ? "dismiss" : (manage ? "manage_schedule" : "start_live")])
            Task { @MainActor in
                if response.actionIdentifier != UNNotificationDismissActionIdentifier {
                    if manage { AppModel.shared.openScheduleCancellation(requestID: id) }
                    else { AppModel.shared.startFromNotification(requestID: id) }
                }
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let reminder = notification.request.content.userInfo["action"] as? String == "manage-schedule"
            let id = (notification.request.content.userInfo["scheduleID"] as? String).flatMap(UUID.init(uuidString:))
            PlaybackDebugJournal.emit(category: "notification", name: "notification_presentation_requested", scheduleID: id?.uuidString,
                                      details: ["kind": reminder ? "heads_up" : "fallback",
                                                "suppressed_for_active_audio": String(AppModel.shared.isAudible && !reminder)])
            if AppModel.shared.isAudible && !reminder { completionHandler([]) }
            else { completionHandler([.banner, .sound]) }
        }
    }
    enum NotificationError: LocalizedError {
        case permissionDenied
        var errorDescription: String? { "Enable Philharmonic notifications in iPhone Settings before scheduling a start." }
    }
}
