import Foundation
import Network
import UIKit

enum TunnelProvider: String, CaseIterable, Identifiable {
    case localDevVPN = "LocalDevVPN"
    case shadowrocket = "Shadowrocket"

    static let preferenceKey = "safeLocation.tunnelProvider"
    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .localDevVPN
    }
    var id: String { rawValue }
    var title: String { rawValue }
    var instructions: String {
        switch self {
        case .localDevVPN:
            return "连接 LocalDevVPN 后返回 Safe Location。蜂窝网络连接失败时先使用 Wi-Fi。"
        case .shadowrocket:
            return "在 Shadowrocket → 设置 → 其它中开启「包含路由 10.7.0.1/32」，重新连接小火箭后返回。无需同时运行 LocalDevVPN。"
        }
    }
    // Interface presence is a hint, not proof of a working developer service.
    var hasCandidateInterface: Bool {
        switch self {
        case .localDevVPN: return LocalDevVPN.isConnected
        case .shadowrocket: return LocalDevVPN.hasAnyTunnelInterface
        }
    }
    var interfaceSummary: String {
        hasCandidateInterface ? "检测到隧道接口（待验证）" : "未检测到隧道接口"
    }
    var isInstalled: Bool {
        switch self {
        case .localDevVPN: return LocalDevVPN.isInstalled
        case .shadowrocket: return UIApplication.shared.canOpenURL(URL(string: "shadowrocket://")!)
        }
    }
    var actionTitle: String {
        switch self {
        case .localDevVPN: return isInstalled ? "打开 LocalDevVPN" : "安装 LocalDevVPN"
        case .shadowrocket: return isInstalled ? "打开 Shadowrocket" : "Shadowrocket 未安装"
        }
    }
    func openClient() {
        switch self {
        case .localDevVPN: LocalDevVPN.openOrInstall()
        case .shadowrocket:
            guard isInstalled else { return }
            UIApplication.shared.open(URL(string: "shadowrocket://connect")!)
        }
    }
    // Non-mutating TCP diagnostic. A successful handshake at TCP level does
    // not validate RPPairing or the DVT service. The native engine does that.
    func probeDeviceChannel() async -> Bool {
        guard hasCandidateInterface else { return false }
        let host = NWEndpoint.Host(TunnelConfig.effectiveIP)
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.safelocation.tunnel.probe")
            let connection = NWConnection(host: host, port: 49152, using: .tcp)
            var finished = false
            func finish(_ reachable: Bool) {
                guard !finished else { return }
                finished = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: reachable)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) { finish(false) }
        }
    }
}
