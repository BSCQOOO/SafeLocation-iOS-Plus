import CoreLocation
import Foundation
import UIKit
import UserNotifications

@MainActor
final class SpoofController: ObservableObject {
    enum Status: Equatable {
        case idle, connecting, active, reconnecting, restoring, routePlaying, joystick
        case failed(String)
        var title: String {
            switch self {
            case .idle: return "真实定位"
            case .connecting: return "正在连接"
            case .active: return "模拟定位中"
            case .reconnecting: return "正在重连"
            case .restoring: return "正在恢复真实定位"
            case .routePlaying: return "路线模拟中"
            case .joystick: return "摇杆控制中"
            case .failed: return "连接失败"
            }
        }
    }

    enum TravelMode: String, CaseIterable, Identifiable {
        case walk = "步行", cycle = "骑行", drive = "驾车"
        var id: String { rawValue }
        var baseSpeed: Double { self == .walk ? 1.4 : (self == .cycle ? 4.5 : 13.9) }
        var systemImage: String { self == .walk ? "figure.walk" : (self == .cycle ? "bicycle" : "car.fill") }
    }

    @Published var selectedCoordinate: CLLocationCoordinate2D?
    @Published var selectedName = "选定位置"
    @Published private(set) var simulatedCoordinate: CLLocationCoordinate2D?
    @Published private(set) var status: Status = .idle
    @Published var lastError: String?
    @Published private(set) var favorites = SavedPlaceStore.load("safeLocation.favorites")
    @Published private(set) var recents = SavedPlaceStore.load("safeLocation.recents")
    @Published private(set) var customProfiles = LocationProfileStore.load()
    @Published var travelMode: TravelMode = .walk
    @Published private(set) var routeProgress = 0.0
    @Published private(set) var isRoutePlaying = false
    @Published private(set) var isJoystickActive = false
    @Published private(set) var isRestoringRealLocation = false
    @Published private(set) var autoRestoreDeadline: Date?
    @Published private(set) var autoRestoreRemaining: TimeInterval?
    @Published private(set) var pendingAutoRestoreMinutes: Int?

    private let keeper = BackgroundLocationKeeper()
    private let audio = SilentAudioKeepAlive()
    private var resendTimer: Timer?, healthTimer: Timer?, joystickTimer: Timer?, restoreTimer: Timer?
    private var routeTask: Task<Void, Never>?
    private var joystickVector = CGVector.zero
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var lastPairingPath: String?
    private let deadlineKey = "safeLocation.autoRestoreDeadline"
    private let notificationID = "safeLocation.autoRestore"

    init() {
        if let d = UserDefaults.standard.object(forKey: deadlineKey) as? Date, d > .now {
            autoRestoreDeadline = d
            autoRestoreRemaining = d.timeIntervalSinceNow
            startRestoreTimer()
        }
    }

    var isSpoofing: Bool { simulatedCoordinate != nil }
    var routeStartCoordinate: CLLocationCoordinate2D? { simulatedCoordinate ?? keeper.lastKnownCoordinate }
    var autoRestoreDisplay: String? {
        if let r = autoRestoreRemaining, r > 0 {
            let t = Int(r.rounded(.up)), h = t / 3600, m = (t % 3600) / 60, s = t % 60
            return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
        }
        return pendingAutoRestoreMinutes.map { "下次 \($0) 分钟" }
    }

    func requestLocationPermission() { keeper.requestPermission() }

    func select(_ coordinate: CLLocationCoordinate2D, name: String? = nil, autoRestoreMinutes: Int? = nil, travelMode: TravelMode? = nil) {
        selectedCoordinate = coordinate
        selectedName = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? name! : Self.coordinateLabel(coordinate)
        if let autoRestoreMinutes, autoRestoreMinutes > 0 { pendingAutoRestoreMinutes = autoRestoreMinutes }
        if let travelMode { self.travelMode = travelMode }
    }

    func selectProfile(_ profile: LocationProfile) {
        selectedCoordinate = profile.coordinate
        selectedName = profile.name
        travelMode = TravelMode(rawValue: profile.travelModeRaw) ?? .walk
        pendingAutoRestoreMinutes = profile.autoRestoreMinutes
    }

    func teleport(pairing: PairingStore) {
        guard ready(pairing), let coordinate = selectedCoordinate else { if selectedCoordinate == nil { fail("请先选择位置。") }; return }
        stopMovementOnly()
        if apply(coordinate, pairing: pairing, recent: true, state: .active, haptic: true),
           let minutes = pendingAutoRestoreMinutes, minutes > 0 {
            scheduleAutoRestore(minutes: minutes)
            pendingAutoRestoreMinutes = nil
        }
    }

    func restoreRealLocation(
        pairingPath: String? = nil
    ) {
        guard !isRestoringRealLocation else { return }

        UIImpactFeedbackGenerator(style: .soft)
            .impactOccurred()

        // Repeated taps while already real are intentionally a no-op, but still
        // leave the controller in a clean, observable idle state.
        guard simulatedCoordinate != nil || LocationEngine.isSessionActive else {
            stopMovementOnly()
            cancelAutoRestore(clearPending: true)
            routeProgress = 0
            status = .idle
            lastError = nil
            return
        }

        stopMovementOnly()
        resendTimer?.invalidate()
        resendTimer = nil
        healthTimer?.invalidate()
        healthTimer = nil
        cancelAutoRestore(clearPending: true)

        let coordinate = simulatedCoordinate
        let recoveryPairingPath =
            pairingPath
            ?? lastPairingPath
        let deviceIP = TunnelConfig.targetIP

        isRestoringRealLocation = true
        status = .restoring
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            let result = await Task.detached(
                priority: .userInitiated
            ) {
                LocationEngine.restore(
                    latitude: coordinate?.latitude,
                    longitude: coordinate?.longitude,
                    pairingPath: recoveryPairingPath,
                    deviceIP: deviceIP
                )
            }.value

            self.isRestoringRealLocation = false

            switch result {
            case .success:
                self.simulatedCoordinate = nil
                self.routeProgress = 0
                self.status = .idle
                self.lastError = nil
                self.keeper.stop()
                self.audio.stop()
                self.endBackgroundTask()
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.success)

            case .failure(.notActive):
                // A stale app-side session with no recoverable transport should
                // not be silently reported as restored.
                self.status = .failed(
                    LocationEngineError.notActive
                        .localizedDescription
                )
                self.lastError =
                    "恢复真实定位失败：模拟会话已断开，且无法重新建立清除会话。请保持 LocalDevVPN 已连接后重试。"

            case .failure(let error):
                self.status = .failed(
                    error.localizedDescription
                )
                self.lastError =
                    "恢复真实定位失败：\(error.localizedDescription)"
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.error)
            }
        }
    }

    func emergencyRestore(
        pairingPath: String? = nil
    ) {
        restoreRealLocation(
            pairingPath: pairingPath
        )
    }

    func configureAutoRestore(minutes: Int?) {
        guard let minutes, minutes > 0 else { cancelAutoRestore(clearPending: true); return }
        if isSpoofing { scheduleAutoRestore(minutes: minutes) } else { pendingAutoRestoreMinutes = minutes }
    }

    func scheduleAutoRestore(minutes: Int) {
        let d = Date().addingTimeInterval(TimeInterval(minutes * 60))
        autoRestoreDeadline = d; autoRestoreRemaining = d.timeIntervalSinceNow
        UserDefaults.standard.set(d, forKey: deadlineKey)
        startRestoreTimer(); scheduleNotification(after: d.timeIntervalSinceNow)
    }

    func cancelAutoRestore(clearPending: Bool = false) {
        restoreTimer?.invalidate(); restoreTimer = nil
        autoRestoreDeadline = nil; autoRestoreRemaining = nil
        UserDefaults.standard.removeObject(forKey: deadlineKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        if clearPending { pendingAutoRestoreMinutes = nil }
    }

    func checkAutoRestoreDeadline() {
        guard let d = autoRestoreDeadline else { return }
        if d <= .now { if isSpoofing { restoreRealLocation() } else { cancelAutoRestore() } }
        else { autoRestoreRemaining = d.timeIntervalSinceNow; startRestoreTimer() }
    }

    func startRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore) {
        guard ready(pairing), coordinates.count >= 2 else { if coordinates.count < 2 { fail("路线至少需要两个点。") }; return }
        stopMovementOnly(); isRoutePlaying = true; routeProgress = 0; status = .routePlaying
        let speed = travelMode.baseSpeed
        routeTask = Task { [weak self] in
            guard let self else { return }
            let total = max(1, coordinates.count - 1)
            for i in 0..<total {
                if Task.isCancelled { break }
                let a = coordinates[i], b = coordinates[i + 1]
                let meters = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                let steps = max(1, Int(ceil(meters / max(0.5, speed * 0.5))))
                for step in 1...steps {
                    if Task.isCancelled { break }
                    let t = Double(step) / Double(steps)
                    let c = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude-a.latitude)*t, longitude: a.longitude + (b.longitude-a.longitude)*t)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await MainActor.run {
                        _ = self.apply(c, pairing: pairing, recent: false, state: .routePlaying, haptic: false)
                        self.routeProgress = min(1, (Double(i) + t) / Double(total))
                    }
                }
            }
            await MainActor.run { self.isRoutePlaying = false; if self.isSpoofing { self.status = .active } }
        }
    }

    func stopRoute() { routeTask?.cancel(); routeTask = nil; isRoutePlaying = false; if isSpoofing { status = .active } }

    func startJoystick(pairing: PairingStore) {
        guard ready(pairing) else { return }
        stopRoute()
        guard let start = simulatedCoordinate ?? selectedCoordinate ?? keeper.lastKnownCoordinate else { fail("请先选择位置。") ; return }
        if simulatedCoordinate == nil { _ = apply(start, pairing: pairing, recent: false, state: .joystick, haptic: true) }
        isJoystickActive = true; status = .joystick
        joystickTimer?.invalidate()
        joystickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickJoystick(pairing: pairing) }
        }
    }

    func setJoystickVector(_ vector: CGVector) { joystickVector = vector }
    func stopJoystick() { isJoystickActive = false; joystickVector = .zero; joystickTimer?.invalidate(); joystickTimer = nil; if isSpoofing { status = .active } }

    @discardableResult
    func addFavorite() -> Bool {
        guard let c = selectedCoordinate ?? simulatedCoordinate ?? keeper.lastKnownCoordinate else {
            return false
        }

        let name = selectedCoordinate != nil
            ? selectedName
            : Self.coordinateLabel(c)

        let p = SavedPlace(
            name: name,
            latitude: c.latitude,
            longitude: c.longitude
        )

        favorites.removeAll {
            abs($0.latitude - p.latitude) < 0.00001 &&
            abs($0.longitude - p.longitude) < 0.00001
        }
        favorites.insert(p, at: 0)
        SavedPlaceStore.save(
            favorites,
            key: "safeLocation.favorites"
        )
        return true
    }
    func removeFavorite(_ place: SavedPlace) { favorites.removeAll { $0.id == place.id }; SavedPlaceStore.save(favorites, key: "safeLocation.favorites") }
    func clearRecents() { recents.removeAll(); SavedPlaceStore.save(recents, key: "safeLocation.recents") }

    func saveCurrentAsProfile(name: String, autoRestoreMinutes: Int?) {
        guard let c = selectedCoordinate else { fail("请先选择位置。") ; return }
        customProfiles.insert(LocationProfile(name: name.isEmpty ? selectedName : name, subtitle: Self.coordinateLabel(c), symbol: "location.circle.fill", latitude: c.latitude, longitude: c.longitude, travelModeRaw: travelMode.rawValue, autoRestoreMinutes: autoRestoreMinutes), at: 0)
        LocationProfileStore.save(customProfiles)
    }
    func removeProfile(_ profile: LocationProfile) { customProfiles.removeAll { $0.id == profile.id }; LocationProfileStore.save(customProfiles) }

    func recoverSessionIfNeeded(pairing: PairingStore) {
        checkAutoRestoreDeadline()
        guard !isRestoringRealLocation else { return }
        guard let c = simulatedCoordinate, pairing.hasPairingFile, LocalDevVPN.isConnected, !LocationEngine.isSessionActive else { return }
        status = .reconnecting; _ = apply(c, pairing: pairing, recent: false, state: .active, haptic: false)
    }

    private func ready(_ pairing: PairingStore) -> Bool {
        guard pairing.hasPairingFile else { fail("请先完成 iOS 27 本机配对。") ; return false }
        guard LocalDevVPN.isConnected else { fail("请先连接 LocalDevVPN。") ; return false }
        return true
    }
    private func fail(_ message: String) { lastError = message; status = .failed(message); UINotificationFeedbackGenerator().notificationOccurred(.error) }

    @discardableResult private func apply(_ c: CLLocationCoordinate2D, pairing: PairingStore, recent: Bool, state: Status, haptic: Bool) -> Bool {
        if status != .routePlaying && status != .joystick { status = .connecting }
        switch LocationEngine.set(latitude: c.latitude, longitude: c.longitude, pairingPath: pairing.pairingPath, deviceIP: TunnelConfig.targetIP) {
        case .success:
            lastPairingPath = pairing.pairingPath; simulatedCoordinate = c; selectedCoordinate = c; status = state; lastError = nil
            startBackground(); ensureTimers(pairing)
            if recent { pushRecent(c) }
            if haptic { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            return true
        case .failure(let e): fail(e.localizedDescription); return false
        }
    }

    private func tickJoystick(pairing: PairingStore) {
        guard isJoystickActive, let c = simulatedCoordinate else { return }
        let mag = hypot(joystickVector.dx, joystickVector.dy); guard mag > 0.08 else { return }
        let meters = travelMode.baseSpeed * min(1, mag) * 0.25
        let n = offset(c, east: joystickVector.dx/mag*meters, north: -joystickVector.dy/mag*meters)
        _ = apply(n, pairing: pairing, recent: false, state: .joystick, haptic: false)
    }

    private func stopMovementOnly() { stopRoute(); stopJoystick() }
    private func ensureTimers(_ pairing: PairingStore) {
        if resendTimer == nil {
            resendTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in Task { @MainActor in
                guard let self, let c = self.simulatedCoordinate else { return }
                _ = LocationEngine.set(latitude: c.latitude, longitude: c.longitude, pairingPath: pairing.pairingPath, deviceIP: TunnelConfig.targetIP)
            }}
        }
        if healthTimer == nil {
            healthTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in Task { @MainActor in
                guard let self else { return }; self.checkAutoRestoreDeadline()
                guard let c = self.simulatedCoordinate, !LocationEngine.isSessionActive else { return }
                self.status = .reconnecting; _ = self.apply(c, pairing: pairing, recent: false, state: .active, haptic: false)
            }}
        }
    }

    private func startBackground() {
        keeper.start(); audio.start()
        if backgroundTask == .invalid { backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "safe-location-session") { [weak self] in self?.endBackgroundTask() } }
    }
    private func endBackgroundTask() { guard backgroundTask != .invalid else { return }; UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }

    private func startRestoreTimer() {
        guard restoreTimer == nil else { return }
        restoreTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self, let d = self.autoRestoreDeadline else { return }
            let r = d.timeIntervalSinceNow
            if r <= 0 { if self.isSpoofing { self.restoreRealLocation() } else { self.cancelAutoRestore() } }
            else { self.autoRestoreRemaining = r }
        }}
    }
    private func scheduleNotification(after interval: TimeInterval) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent(); c.title = "Safe Location"; c.body = "自动恢复时间已到。"; c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: self.notificationID, content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)))
        }
    }

    private func clearBestEffort() -> Result<Void, LocationEngineError> {
        if LocationEngine.isSessionActive { return LocationEngine.clear() }
        guard let c = simulatedCoordinate, let path = lastPairingPath, FileManager.default.fileExists(atPath: path), LocalDevVPN.isConnected else { return .failure(.notActive) }
        switch LocationEngine.set(latitude: c.latitude, longitude: c.longitude, pairingPath: path, deviceIP: TunnelConfig.targetIP) {
        case .success: return LocationEngine.clear()
        case .failure(let e): return .failure(e)
        }
    }
    private func pushRecent(_ c: CLLocationCoordinate2D) {
        let p = SavedPlace(name: selectedName, latitude: c.latitude, longitude: c.longitude)
        recents.removeAll { abs($0.latitude-p.latitude) < 0.00015 && abs($0.longitude-p.longitude) < 0.00015 }
        recents.insert(p, at: 0); if recents.count > 30 { recents = Array(recents.prefix(30)) }; SavedPlaceStore.save(recents, key: "safeLocation.recents")
    }
    private func offset(_ c: CLLocationCoordinate2D, east: Double, north: Double) -> CLLocationCoordinate2D {
        let earth = 6_378_137.0, dLat = north / earth * (180 / Double.pi), cosine = max(0.0001, cos(c.latitude * Double.pi / 180)), dLon = east / (earth * cosine) * (180 / Double.pi)
        return CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
    }
    static func coordinateLabel(_ c: CLLocationCoordinate2D) -> String { String(format: "%.6f, %.6f", c.latitude, c.longitude) }
}
