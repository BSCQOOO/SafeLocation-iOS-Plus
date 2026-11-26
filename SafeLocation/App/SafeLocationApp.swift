import CoreLocation
import SwiftUI

@main
struct SafeLocationApp: App {
    @StateObject private var session = SpoofController()
    @StateObject private var pairing = PairingStore()
    @StateObject private var pairService = PairOnDeviceService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(pairing)
                .environmentObject(pairService)
                .preferredColorScheme(.dark)
                .task { await ExpiryReminder.reconcile() }
                .onOpenURL { url in
                    Task { @MainActor in await handleIncoming(url) }
                }
        }
    }

    @MainActor
    private func handleIncoming(_ url: URL) async {
        let ext = url.pathExtension.lowercased()
        if ["plist", "mobiledevicepairing", "mobiledevicepair"].contains(ext) {
            guard !session.isProbingInstallation, !session.isSpoofing, !session.isRestoringRealLocation, !session.isRoutePlaying, !session.isJoystickActive, session.interruptedCoordinate == nil || !pairing.hasPairingFile else {
                session.lastError = "请先结束或恢复定位会话，再导入配对文件。"
                return
            }
            do { try pairing.importPairing(from: url) } catch { session.lastError = error.localizedDescription }
            return
        }

        guard url.scheme?.lowercased() == "safelocation" else { return }
        let command = (url.host ?? "").lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch command {
        case "restore", "clear", "panic":
            session.emergencyRestore()

        case "vpn":
            TunnelProvider.current.openClient()

        case "timer":
            let minutes = items.first(where: { $0.name == "minutes" })?.value.flatMap(Int.init)
            session.configureAutoRestore(minutes: minutes)

        case "set", "select", "import":
            let name = items.first(where: { $0.name == "name" })?.value
            let minutes = items.first(where: { $0.name == "restore" })?.value.flatMap(Int.init)

            if let input = items.first(where: { $0.name == "input" })?.value {
                do {
                    if let resolved = try await MapLinkResolver.resolve(input) {
                        session.select(
                            resolved.canonicalCoordinate(system: MapCoordinateConverter.effectiveSystem),
                            name: name ?? resolved.name,
                            autoRestoreMinutes: minutes
                        )
                        if command == "set" { session.teleport(pairing: pairing) }
                    }
                } catch {
                    session.lastError = error.localizedDescription
                }
                return
            }

            if let latText = items.first(where: { $0.name == "lat" })?.value,
               let lonText = items.first(where: { $0.name == "lon" })?.value,
               let lat = Double(latText), let lon = Double(lonText),
               (-90...90).contains(lat), (-180...180).contains(lon) {
                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                session.select(coordinate, name: name, autoRestoreMinutes: minutes)
                if command == "set" { session.teleport(pairing: pairing) }
            }

        default:
            break
        }
    }
}
