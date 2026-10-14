import AppKit
import UserNotifications

/// Posts a system notification when a long command finishes in the background.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let sessionIDKey = "sessionID"

    /// Called with the session ID when the user clicks a notification.
    var onOpenSession: ((UUID) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    override init() {
        super.init()
        center.delegate = self
    }

    /// Asks for permission at the point of need: when a command has been
    /// running long enough that the user may want to be told when it ends.
    func requestAuthorizationIfNeeded() {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func notifyFinished(command: String, sessionName: String, sessionID: UUID, exitCode: Int?, duration: Duration) {
        let content = UNMutableNotificationContent()
        let succeeded = exitCode == 0
        content.title = succeeded
            ? String(localized: "Comando terminado")
            : String(localized: "El comando falló")
        content.subtitle = sessionName
        let elapsed = duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
        if let exitCode, !succeeded {
            content.body = String(localized: "\(command) · código \(exitCode) · \(elapsed)")
        } else {
            content.body = String(localized: "\(command) · \(elapsed)")
        }
        content.sound = .default
        content.threadIdentifier = sessionID.uuidString
        content.userInfo = [Self.sessionIDKey: sessionID.uuidString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let value = response.notification.request.content.userInfo[Self.sessionIDKey] as? String,
              let id = UUID(uuidString: value) else { return }
        await MainActor.run {
            NSApp.activate()
            onOpenSession?(id)
        }
    }
}
