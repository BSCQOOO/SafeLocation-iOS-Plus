import CoreLocation
import Foundation

final class MapLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var heading: CLLocationDirection?
    @Published private(set) var course: CLLocationDirection?
    @Published private(set) var isSimulatedBySoftware = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()

    var coordinate: CLLocationCoordinate2D? {
        location?.coordinate
    }

    var horizontalAccuracy: CLLocationAccuracy? {
        location?.horizontalAccuracy
    }

    var headingDegrees: CLLocationDirection? {
        heading ?? course
    }

    var bestDirectionDegrees: CLLocationDirection? {
        heading ?? course
    }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = 1
        manager.headingOrientation = .portrait
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()

        case .authorizedAlways, .authorizedWhenInUse:
            startSensors()

        default:
            break
        }
    }

    func refresh() {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startSensors()
            manager.requestLocation()

        case .notDetermined:
            manager.requestWhenInUseAuthorization()

        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func bestCoordinate(
        maxAge: TimeInterval = 12,
        maxHorizontalAccuracy: CLLocationAccuracy = 120,
        allowSimulated: Bool = true
    ) -> CLLocationCoordinate2D? {
        guard let location else { return nil }
        guard location.horizontalAccuracy >= 0 else { return nil }
        guard abs(location.timestamp.timeIntervalSinceNow) <= maxAge else { return nil }
        guard allowSimulated || !isSimulatedBySoftware else { return nil }

        guard location.horizontalAccuracy <= maxHorizontalAccuracy else {
            return nil
        }

        return location.coordinate
    }

    func bestRealCoordinate(
        maxAge: TimeInterval = 12,
        maxHorizontalAccuracy: CLLocationAccuracy = 120
    ) -> CLLocationCoordinate2D? {
        bestCoordinate(
            maxAge: maxAge,
            maxHorizontalAccuracy: maxHorizontalAccuracy,
            allowSimulated: false
        )
    }

    private func startSensors() {
        manager.startUpdatingLocation()

        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse {
            startSensors()
            manager.requestLocation()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let candidate = locations.last(where: {
            $0.horizontalAccuracy >= 0
        }) else {
            return
        }

        if let current = location {
            // Prefer the fresher fix. For nearly simultaneous fixes, prefer the
            // one with better horizontal accuracy.
            let delta = candidate.timestamp.timeIntervalSince(current.timestamp)
            if delta < -1 {
                return
            }

            if abs(delta) < 1,
               candidate.horizontalAccuracy > current.horizontalAccuracy,
               current.horizontalAccuracy >= 0 {
                return
            }
        }

        location = candidate
        course = candidate.course >= 0 ? candidate.course : nil

        if #available(iOS 15.0, *) {
            isSimulatedBySoftware =
                candidate.sourceInformation?.isSimulatedBySoftware ?? false
        } else {
            isSimulatedBySoftware = false
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        let value: CLLocationDirection

        if newHeading.trueHeading >= 0 {
            value = newHeading.trueHeading
        } else {
            value = newHeading.magneticHeading
        }

        guard value >= 0 else { return }
        heading = value
    }

    func locationManagerShouldDisplayHeadingCalibration(
        _ manager: CLLocationManager
    ) -> Bool {
        true
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Keep the last valid fix. Re-centering will request another update and
        // can still fall back to Safe Location's simulated/selected coordinate.
    }
}
