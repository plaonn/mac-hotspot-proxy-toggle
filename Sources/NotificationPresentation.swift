import Dispatch
import Foundation
import UserNotifications

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let foregroundOptions: UNNotificationPresentationOptions = [.banner, .list]

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.foregroundOptions)
    }
}

private final class NotificationSendResult {
    private let lock = NSLock()
    private var value = false

    func set(_ nextValue: Bool) {
        lock.lock()
        value = nextValue
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

func sendBundledNotification(title: String, body: String) -> Bool {
    let center = UNUserNotificationCenter.current()
    let presenter = NotificationPresenter()
    center.delegate = presenter

    let semaphore = DispatchSemaphore(value: 0)
    let result = NotificationSendResult()

    func addRequest() {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            result.set(error == nil)
            semaphore.signal()
        }
    }

    center.getNotificationSettings { settings in
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            addRequest()
        case .notDetermined:
            center.requestAuthorization(options: [.alert]) { granted, error in
                guard granted, error == nil else {
                    semaphore.signal()
                    return
                }
                addRequest()
            }
        case .denied:
            semaphore.signal()
        @unknown default:
            semaphore.signal()
        }
    }

    guard semaphore.wait(timeout: .now() + 5) == .success, result.get() else {
        return false
    }

    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
    withExtendedLifetime(presenter) {}
    return true
}
