import Darwin
import Foundation
import idevice

/// Read-only feasibility test using the existing, pinned idevice ABI.
/// All handles are local to this operation; no simulated coordinate is written.
enum InstallationServiceProbe {
    enum ServiceStatus: String, Sendable {
        case notRun = "未执行"
        case connected = "已连接"
        case failed = "连接失败"
        case unavailable = "当前底层库未提供接口"
    }

    static var initialAFCStatus: ServiceStatus {
        #if SAFELOCATION_HAS_AFC
        return .notRun
        #else
        return .unavailable
        #endif
    }

    static var initialInstallationStatus: ServiceStatus {
        #if SAFELOCATION_HAS_INSTALLATION_PROXY
        return .notRun
        #else
        return .unavailable
        #endif
    }

    struct Report: Sendable {
        let pairingRead: Bool
        let authenticatedTunnel: Bool
        let afc: ServiceStatus
        let installationProxy: ServiceStatus
        let detail: String
        static let blocked = Report(pairingRead: false, authenticatedTunnel: false, afc: InstallationServiceProbe.initialAFCStatus, installationProxy: InstallationServiceProbe.initialInstallationStatus,
                                    detail: "请先完成配对并恢复真实定位。")
    }

    private static let queue = DispatchQueue(label: "com.safelocation.installation-probe", qos: .utility)

    static func run(pairingPath: String, deviceIP: String) async -> Report {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: probe(pairingPath: pairingPath, deviceIP: deviceIP))
            }
        }
    }

    private static func probe(pairingPath: String, deviceIP: String) -> Report {
        var pairingOK = false
        var tunnelOK = false
        var afcStatus = initialAFCStatus
        var installStatus = initialInstallationStatus
        func result(_ detail: String) -> Report {
            Report(pairingRead: pairingOK, authenticatedTunnel: tunnelOK, afc: afcStatus, installationProxy: installStatus, detail: detail)
        }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(49152).bigEndian
        guard deviceIP.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else { return result("设备 IP 无效。") }
        var record: OpaquePointer?
        if let error = pairingPath.withCString({ rp_pairing_file_read($0, &record) }) {
            idevice_error_free(error)
            return result("无法读取现有 RPPairing。")
        }
        guard let record else { return result("没有有效配对记录。") }
        defer { rp_pairing_file_free(record) }
        pairingOK = true

        var adapter: OpaquePointer?
        var handshake: OpaquePointer?
        defer {
            if let handshake { rsd_handshake_free(handshake) }
            if let adapter { adapter_free(adapter) }
        }
        let error = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing($0, socklen_t(MemoryLayout<sockaddr_in>.stride), "SafeLocation", record, nil, nil, &adapter, &handshake)
            }
        }
        if let error {
            idevice_error_free(error)
            return result("RPPairing / RSD 隧道连接失败。请检查所选 VPN 与本机配对。")
        }
        guard let adapter, let handshake else { return result("没有取得完整 RSD 句柄。") }
        tunnelOK = true

        #if SAFELOCATION_HAS_AFC
        var afc: OpaquePointer?
        if let error = afc_client_connect_rsd(adapter, handshake, &afc) {
            afcStatus = .failed
            idevice_error_free(error)
        } else {
            afcStatus = afc != nil ? .connected : .failed
        }
        if let afc { afc_client_free(afc) }
        #endif

        #if SAFELOCATION_HAS_INSTALLATION_PROXY
        var installer: OpaquePointer?
        if let error = installation_proxy_connect_rsd(adapter, handshake, &installer) {
            installStatus = .failed
            idevice_error_free(error)
        } else {
            installStatus = installer != nil ? .connected : .failed
        }
        if let installer { installation_proxy_client_free(installer) }
        #endif
        if afcStatus == .unavailable || installStatus == .unavailable {
            return result("RSD 已建立，但当前静态库缺少部分安装服务符号；未提供的接口没有执行测试，不代表设备拒绝连接。")
        }
        return result(afcStatus == .connected && installStatus == .connected
            ? "两个服务均返回连接句柄。尚未验证文件传输、安装权限或自身续签。"
            : "RSD 已建立，但至少一个安装服务连接失败；需要继续验证其他连接路径。")
    }
}
