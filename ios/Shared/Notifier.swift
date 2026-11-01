import Foundation
import UserNotifications

/// Local notifications posted when blocking starts. Nothing leaves the device.
enum Notifier {
    static func post(id: String, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = nil
            content.threadIdentifier = "openblock.blocking"
            if #available(iOS 15.0, *) { content.interruptionLevel = .active }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}
