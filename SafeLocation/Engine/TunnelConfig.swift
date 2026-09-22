import Foundation

enum TunnelConfig {
    static let defaultIP = "10.7.0.1"
    static let defaultsKey = "safeLocation.targetDeviceIP"

    static var targetIP: String {
        let value = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return defaultIP }
        return value
    }

    static func setTargetIP(_ value: String) {
        UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: defaultsKey)
    }
}
