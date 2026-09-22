import Foundation

struct PendingLocationImport: Codable {
    let input: String
    let shouldTeleport: Bool
    let createdAt: Date
}

enum PendingImportBridge {
    static let notification = Notification.Name("safeLocation.pendingImport.changed")
    private static let key = "safeLocation.pendingImport.v1"

    static func submit(_ input: String, shouldTeleport: Bool = false) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let payload = PendingLocationImport(
            input: trimmed,
            shouldTeleport: shouldTeleport,
            createdAt: .now
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
            NotificationCenter.default.post(name: notification, object: nil)
        }
    }

    static func take(maxAge: TimeInterval = 10 * 60) -> PendingLocationImport? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let payload = try? JSONDecoder().decode(PendingLocationImport.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: key)
        guard Date().timeIntervalSince(payload.createdAt) <= maxAge else { return nil }
        return payload
    }
}
