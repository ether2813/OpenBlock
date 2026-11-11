import Foundation
import UserNotifications

/// Local notifications posted when blocking starts. Nothing leaves the device.
enum Notifier {
    /// Posts right away. The monitor extension can be suspended as soon as its callback returns,
    /// so this must not wait on an asynchronous settings check first; iOS simply drops the request
    /// when notifications aren't allowed.
    static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "openblock.blocking"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
