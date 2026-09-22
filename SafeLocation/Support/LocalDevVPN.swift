import Darwin
import Foundation
import UIKit

enum LocalDevVPN {
    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!
    static let detectURL = URL(string: "localdevvpn://")!
    static let enableURL = URL(string: "localdevvpn://enable?scheme=safelocation")!

    // LocalDevVPN upstream defaults:
    // Tunnel/interface IP: 10.7.1.1/32
    // Device/peer IP:      10.7.0.1/32
    private static let defaultInterfaceIP = "10.7.1.1"
    private static let defaultPeerIP = "10.7.0.1"

    static var isInstalled: Bool {
        UIApplication.shared.canOpenURL(detectURL)
    }

    static var detectedInterfaceIP: String? {
        let entries = ipv4InterfaceAddresses()

        // Prefer the exact LocalDevVPN default tunnel interface.
        if let match = entries.first(where: {
            $0.name.hasPrefix("utun") && $0.address == defaultInterfaceIP
        }) {
            return match.address
        }

        // If Safe Location is using the default peer, accept a 10.7.x.x utun
        // interface. This avoids a false negative on iOS 27 where the local
        // interface is 10.7.1.1 while the DVT peer remains 10.7.0.1.
        if TunnelConfig.targetIP == defaultPeerIP,
           let match = entries.first(where: {
               $0.name.hasPrefix("utun") && $0.address.hasPrefix("10.7.")
           }) {
            return match.address
        }

        // Compatibility fallback for older/local setups that assign the peer
        // address directly to an interface.
        if let match = entries.first(where: { $0.address == TunnelConfig.targetIP }) {
            return match.address
        }

        return nil
    }

    static var isConnected: Bool {
        detectedInterfaceIP != nil
    }

    static func openOrInstall() {
        UIApplication.shared.open(isInstalled ? enableURL : appStoreURL)
    }

    private struct IPv4Entry {
        let name: String
        let address: String
    }

    private static func ipv4InterfaceAddresses() -> [IPv4Entry] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var results: [IPv4Entry] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first

        while let current = ptr {
            let interface = current.pointee
            defer { ptr = interface.ifa_next }

            guard let sockaddr = interface.ifa_addr,
                  sockaddr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                sockaddr,
                socklen_t(MemoryLayout<sockaddr_in>.size),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else {
                continue
            }

            let name = interface.ifa_name.map { String(cString: $0) } ?? ""
            results.append(IPv4Entry(name: name, address: String(cString: host)))
        }

        return results
    }
}
