import CoreLocation
import Darwin
import Foundation
import idevice

enum LocationEngineError: LocalizedError {
    case invalidIP, pairingRead, tunnelCreate, remoteServer, simulationCreate, locationSet, locationClear, notActive

    var errorDescription: String? {
        switch self {
        case .invalidIP: return "Tunnel IP 无效，请检查设置。"
        case .pairingRead: return "无法读取 RPPairing 文件，请重新配对。"
        case .tunnelCreate: return "tunnel_create_rppairing 失败：utun 已存在时请检查 10.7.0.1 peer 路由与当前网络状态。"
        case .remoteServer: return "Tunnel 已连接，但 RemoteXPC 握手失败。"
        case .simulationCreate: return "无法打开 Apple LocationSimulation 服务。"
        case .locationSet: return "设置模拟定位失败。"
        case .locationClear: return "恢复真实定位失败。"
        case .notActive: return "当前没有可用的模拟定位会话。"
        }
    }

    static func from(code: Int32) -> LocationEngineError {
        switch code {
        case 1: return .invalidIP
        case 2: return .pairingRead
        case 3: return .tunnelCreate
        case 9: return .remoteServer
        case 10: return .simulationCreate
        case 11: return .locationSet
        case 12: return .locationClear
        default: return .locationSet
        }
    }
}

enum LocationEngine {
    private static let queue = DispatchQueue(label: "com.safelocation.location", qos: .userInitiated)
    private static var adapter: OpaquePointer?
    private static var handshake: OpaquePointer?
    private static var remoteServer: OpaquePointer?
    private static var simulation: OpaquePointer?

    static var isSessionActive: Bool { simulation != nil }

    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Result<Void, LocationEngineError> {
        let selected = CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
        let dvtCoordinate =
            CoordinatePipeline.dvtFromSelected(
                selected
            )

        var result: Result<Void, LocationEngineError> = .failure(.locationSet)
        queue.sync {
            let code = setLocked(
                latitude: dvtCoordinate.latitude,
                longitude: dvtCoordinate.longitude,
                pairingPath: pairingPath,
                deviceIP: deviceIP
            )
            result = code == 0 ? .success(()) : .failure(.from(code: code))
        }
        return result
    }

    static func clear() -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.locationClear)
        queue.sync {
            guard let simulation else { result = .success(()); return }
            let err = location_simulation_clear(simulation)
            cleanup()
            if let err {
                idevice_error_free(err)
                result = .failure(.locationClear)
            } else {
                result = .success(())
            }
        }
        return result
    }

    /// Restores the device to real location with a stale-session recovery path.
    ///
    /// The fast path clears the live LocationSimulation handle. If that handle
    /// has gone stale (common after foreground/background or a tunnel reset),
    /// reconnect once using the last simulated coordinate and immediately clear
    /// the newly opened simulation session.
    static func restore(
        latitude: Double?,
        longitude: Double?,
        pairingPath: String?,
        deviceIP: String
    ) -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.locationClear)

        queue.sync {
            if let simulation {
                let error = location_simulation_clear(simulation)
                cleanup()

                if let error {
                    idevice_error_free(error)
                } else {
                    result = .success(())
                    return
                }
            } else {
                cleanup()
            }

            guard
                let latitude,
                let longitude,
                let pairingPath,
                FileManager.default.fileExists(atPath: pairingPath)
            else {
                result = .failure(.notActive)
                return
            }

            let selected = CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )
            let dvtCoordinate =
                CoordinatePipeline.dvtFromSelected(
                    selected
                )

            let setCode = setLocked(
                latitude: dvtCoordinate.latitude,
                longitude: dvtCoordinate.longitude,
                pairingPath: pairingPath,
                deviceIP: deviceIP
            )

            guard setCode == 0 else {
                result = .failure(.from(code: setCode))
                return
            }

            guard let simulation else {
                cleanup()
                result = .failure(.locationClear)
                return
            }

            let clearError = location_simulation_clear(simulation)
            cleanup()

            if let clearError {
                idevice_error_free(clearError)
                result = .failure(.locationClear)
            } else {
                result = .success(())
            }
        }

        return result
    }

    private static func cleanup() {
        if let simulation { location_simulation_free(simulation); self.simulation = nil }
        if let remoteServer { remote_server_free(remoteServer); self.remoteServer = nil }
        if let handshake { rsd_handshake_free(handshake); self.handshake = nil }
        if let adapter { adapter_free(adapter); self.adapter = nil }
    }

    private static func setLocked(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Int32 {
        if let simulation {
            if let err = location_simulation_set(simulation, latitude, longitude) {
                idevice_error_free(err)
                cleanup()
            } else {
                return 0
            }
        }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(49152).bigEndian
        guard deviceIP.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else { return 1 }

        var pairingHandle: OpaquePointer?
        if let err = pairingPath.withCString({ rp_pairing_file_read($0, &pairingHandle) }) {
            idevice_error_free(err)
            return 2
        }
        guard let pairingHandle else { return 2 }
        defer { rp_pairing_file_free(pairingHandle) }

        let providerError = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing(
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.stride),
                    "SafeLocation",
                    pairingHandle,
                    nil,
                    nil,
                    &adapter,
                    &handshake
                )
            }
        }
        if let providerError {
            idevice_error_free(providerError)
            cleanup()
            return 3
        }

        if let err = remote_server_connect_rsd(adapter, handshake, &remoteServer) {
            idevice_error_free(err)
            cleanup()
            return 9
        }
        if let err = location_simulation_new(remoteServer, &simulation) {
            idevice_error_free(err)
            cleanup()
            return 10
        }
        remoteServer = nil

        if let err = location_simulation_set(simulation, latitude, longitude) {
            idevice_error_free(err)
            cleanup()
            return 11
        }
        return 0
    }
}
