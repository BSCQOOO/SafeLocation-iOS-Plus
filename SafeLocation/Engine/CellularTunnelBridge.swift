import Combine
import Darwin
import Foundation
import Network
import UIKit

@MainActor
final class CellularTunnelBridge: ObservableObject {
    enum NetworkKind: String {
        case wifi = "Wi-Fi"
        case cellular = "蜂窝数据"
        case offline = "无外网"
        case other = "其他"
    }

    enum Stage: String {
        case idle
        case enablingVPN
        case waitingVPN
        case disablingCellular
        case settlingRoute
        case creatingDeveloperTunnel
        case enablingCellular
        case ready
        case failed

        var title: String {
            switch self {
            case .idle: return "空闲"
            case .enablingVPN: return "正在启动 LocalDevVPN"
            case .waitingVPN: return "等待 Tunnel 就绪"
            case .disablingCellular: return "正在临时关闭蜂窝数据"
            case .settlingRoute: return "等待本机路由稳定"
            case .creatingDeveloperTunnel: return "正在建立 Developer Tunnel"
            case .enablingCellular: return "正在恢复蜂窝数据"
            case .ready: return "纯蜂窝链路已完成"
            case .failed: return "纯蜂窝链路失败"
            }
        }
    }

    static let shared = CellularTunnelBridge()

    @Published private(set) var networkKind: NetworkKind = .other
    @Published private(set) var stage: Stage = .idle
    @Published private(set) var lastError: String?

    private static let turnOffShortcutKey = "safeLocation.cellular.turnOffShortcut"
    private static let turnOnShortcutKey = "safeLocation.cellular.turnOnShortcut"

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.safelocation.cellular-path")

    var isCellularOnly: Bool {
        networkKind == .cellular || Self.interfaceSnapshotIsCellularOnly()
    }

    var turnOffShortcutName: String {
        Self.shortcutName(for: Self.turnOffShortcutKey, fallback: "TurnOffData")
    }

    var turnOnShortcutName: String {
        Self.shortcutName(for: Self.turnOnShortcutKey, fallback: "TurnOnData")
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.networkKind = Self.classify(path)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    func setShortcutNames(turnOff: String, turnOn: String) {
        Self.storeShortcutName(turnOff, key: Self.turnOffShortcutKey)
        Self.storeShortcutName(turnOn, key: Self.turnOnShortcutKey)
        objectWillChange.send()
    }

    func markStage(_ stage: Stage) {
        self.stage = stage
        if stage != .failed {
            lastError = nil
        }
    }

    func markReady() {
        stage = .ready
        lastError = nil
    }

    func markIdle() {
        stage = .idle
        lastError = nil
    }

    func recordFailure(_ message: String) {
        stage = .failed
        lastError = message
    }

    @discardableResult
    func launchLocalDevVPN() -> Bool {
        guard LocalDevVPN.isInstalled else {
            LocalDevVPN.openOrInstall()
            recordFailure("未安装 LocalDevVPN。已打开安装页面。")
            return false
        }

        markStage(.enablingVPN)
        UIApplication.shared.open(LocalDevVPN.enableURL, options: [:]) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in
                self?.recordFailure("无法打开 LocalDevVPN。")
            }
        }
        return true
    }

    @discardableResult
    func runTurnOffDataShortcut() -> Bool {
        markStage(.disablingCellular)
        return runShortcut(
            named: turnOffShortcutName,
            phase: "off",
            successURL: "safelocation://cellular-off-ready"
        )
    }

    @discardableResult
    func runTurnOnDataShortcut() -> Bool {
        markStage(.enablingCellular)
        return runShortcut(
            named: turnOnShortcutName,
            phase: "on",
            successURL: "safelocation://cellular-on-ready"
        )
    }

    private func runShortcut(named name: String, phase: String, successURL: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            recordFailure("快捷指令名称为空。")
            return false
        }

        let shortcutsRoot = URL(string: "shortcuts://")!
        guard UIApplication.shared.canOpenURL(shortcutsRoot) else {
            recordFailure("系统“快捷指令”App 不可用。")
            return false
        }

        let failureURL = "safelocation://cellular-shortcut-error?phase=\(phase)"
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "x-success", value: successURL),
            URLQueryItem(name: "x-cancel", value: failureURL),
            URLQueryItem(name: "x-error", value: failureURL)
        ]

        guard let url = components.url else {
            recordFailure("无法生成快捷指令回调 URL。")
            return false
        }

        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in
                self?.recordFailure("无法运行快捷指令“\(trimmed)”。")
            }
        }
        return true
    }

    private static func interfaceSnapshotIsCellularOnly() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return false
        }
        defer { freeifaddrs(ifaddr) }

        var hasWiFi = false
        var hasCellular = false
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next

            guard interface.ifa_flags & UInt32(IFF_UP) != 0,
                  let address = interface.ifa_addr else {
                continue
            }

            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            if name == "en0" {
                hasWiFi = true
            } else if name.hasPrefix("pdp_ip") {
                hasCellular = true
            }
        }

        return hasCellular && !hasWiFi
    }

    private static func classify(_ path: NWPath) -> NetworkKind {
        guard path.status == .satisfied else { return .offline }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        return .other
    }

    private static func shortcutName(for key: String, fallback: String) -> String {
        let value = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return fallback }
        return value
    }

    private static func storeShortcutName(_ value: String, key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
    }
}
