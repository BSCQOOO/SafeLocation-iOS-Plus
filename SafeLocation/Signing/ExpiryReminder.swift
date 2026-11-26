import Foundation
import UserNotifications

enum ExpiryReminder {
    private static let prefix = "safeLocation.signing.expiry."
    static let enabledKey = "safeLocation.signing.remindersEnabled"
    static func clear() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [prefix + "72", prefix + "24", prefix + "6"])
    }

    static func schedule(expiration: Date) async throws -> Int {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return 0 }
        UserDefaults.standard.set(true, forKey: enabledKey)
        return try await replace(expiration: expiration)
    }

    static func reconcile() async {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { clear(); return }
        guard let profile = ProfileMetadata.current() else { clear(); return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { clear(); return }
        _ = try? await replace(expiration: profile.expiration)
    }

    private static func replace(expiration: Date) async throws -> Int {
        let center = UNUserNotificationCenter.current()
        clear()
        var count = 0
        for hours in [72,24,6] {
            let interval = expiration.addingTimeInterval(-Double(hours) * 3600).timeIntervalSinceNow
            guard interval > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = "SafeLocation 签名到期提醒"
            content.body = "当前描述文件预计在约 \(hours) 小时后到期，请及时使用可用签名工具续期。"
            content.sound = .default
            let request = UNNotificationRequest(identifier: prefix + String(hours), content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false))
            try await center.add(request)
            count += 1
        }
        return count
    }
}
