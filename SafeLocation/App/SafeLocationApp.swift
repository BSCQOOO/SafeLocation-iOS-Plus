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
                .onOpenURL { url in
                    Task { @MainActor in await handleIncoming(url) }
                }
        }
    }

    @MainActor
    private func handleIncoming(_ url: URL) async {
        let ext = url.pathExtension.lowercased()
        if ["plist", "mobiledevicepairing", "mobiledevicepair"].contains(ext) {
            try? pairing.importPairing(from: url)
            return
        }

        guard url.scheme?.lowercased() == "safelocation" else { return }
        let command = (url.host ?? "").lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch command {
        case "":
            // LocalDevVPN returns to safelocation:// after requesting the
            // tunnel. Resume only when a Teleport is actually pending.
            session.handleLocalDevVPNCallback(pairing: pairing)

        case "cellular-off-ready":
            session.handleCellularDataOffCallback(pairing: pairing)

        case "cellular-on-ready":
            session.handleCellularDataOnCallback()

        case "cellular-shortcut-error":
            session.handleCellularShortcutFailure(url)

        case "restore", "clear", "panic":
            session.emergencyRestore()

        case "vpn":
            LocalDevVPN.openOrInstall()

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
                            resolved.coordinate,
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
