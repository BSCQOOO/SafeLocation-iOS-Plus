import CoreLocation
import Foundation
import MapKit

enum MapCoordinateConverter {
    enum MapCoordinateSystem: String, Equatable, Sendable {
        case wgs84 = "WGS-84"
        case gcj02 = "GCJ-02"
    }

    /// MapKit can expose different coordinate representations depending on
    /// the active Apple Maps service region. Safe Location keeps the injected
    /// coordinate canonical in WGS-84 and converts only at the map boundary.
    static func detectMapCoordinateSystem() async -> MapCoordinateSystem {
        await withTaskGroup(of: MapCoordinateSystem?.self) { group in
            group.addTask {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = "22.283819, 114.158439"

                do {
                    let response = try await MKLocalSearch(request: request).start()
                    guard let first = response.mapItems.first else {
                        return nil
                    }

                    let name = (first.name ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()

                    // This fixed Hong Kong anchor is intentionally independent
                    // from the user's/spoofed location. On the domestic MapKit
                    // representation its first result is 林士街 (or a localized
                    // transliteration of the same street).
                    if name.contains("林士") ||
                        name.contains("lin shi") ||
                        name.contains("linshi") {
                        return .gcj02
                    }

                    return .wgs84
                } catch {
                    return nil
                }
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: 4_500_000_000)
                return nil
            }

            let detected = await group.next() ?? nil
            group.cancelAll()

            // The current product is primarily used with mainland Apple Maps.
            // A failed probe must be conservative: GCJ-02 prevents the large
            // map-selection offset reported on domestic tiles.
            return detected ?? .gcj02
        }
    }

    static func mapToWGS84(
        _ coordinate: CLLocationCoordinate2D,
        system: MapCoordinateSystem
    ) -> CLLocationCoordinate2D {
        guard system == .gcj02 else { return coordinate }

        let converted = gcj02ToWgs84(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        return CLLocationCoordinate2D(
            latitude: converted.latitude,
            longitude: converted.longitude
        )
    }

    static func wgs84ToMap(
        _ coordinate: CLLocationCoordinate2D,
        system: MapCoordinateSystem
    ) -> CLLocationCoordinate2D {
        guard system == .gcj02 else { return coordinate }

        let converted = wgs84ToGcj02(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        return CLLocationCoordinate2D(
            latitude: converted.latitude,
            longitude: converted.longitude
        )
    }

    static func gcj02ToWgs84(
        latitude: Double,
        longitude: Double
    ) -> (latitude: Double, longitude: Double) {
        guard usesGCJ02ServiceArea(
            latitude: latitude,
            longitude: longitude
        ) else {
            return (latitude, longitude)
        }

        // Two correction passes reduce the residual error to sub-meter scale
        // for ordinary mainland-China coordinates.
        var wgsLatitude = latitude
        var wgsLongitude = longitude

        for _ in 0..<2 {
            let offset = delta(
                latitude: wgsLatitude,
                longitude: wgsLongitude
            )
            wgsLatitude = latitude - offset.latitude
            wgsLongitude = longitude - offset.longitude
        }

        return (wgsLatitude, wgsLongitude)
    }

    static func wgs84ToGcj02(
        latitude: Double,
        longitude: Double
    ) -> (latitude: Double, longitude: Double) {
        guard usesGCJ02ServiceArea(
            latitude: latitude,
            longitude: longitude
        ) else {
            return (latitude, longitude)
        }

        let offset = delta(
            latitude: latitude,
            longitude: longitude
        )

        return (
            latitude + offset.latitude,
            longitude + offset.longitude
        )
    }

    private static let semiMajorAxis = 6_378_245.0
    private static let eccentricitySquared =
        0.00669342162296594323

    private static func usesGCJ02ServiceArea(
        latitude: Double,
        longitude: Double
    ) -> Bool {
        let broadChina =
            latitude >= 0.8293 &&
            latitude <= 55.8271 &&
            longitude >= 72.004 &&
            longitude <= 137.8347

        return broadChina
    }

    private static func delta(
        latitude: Double,
        longitude: Double
    ) -> (latitude: Double, longitude: Double) {
        let latitudeTransform = transformLatitude(
            x: longitude - 105.0,
            y: latitude - 35.0
        )
        let longitudeTransform = transformLongitude(
            x: longitude - 105.0,
            y: latitude - 35.0
        )

        let radians = latitude / 180.0 * .pi
        var magic = sin(radians)
        magic =
            1 -
            eccentricitySquared *
            magic *
            magic
        let squareRoot = sqrt(magic)

        let latitudeOffset =
            latitudeTransform *
            180.0 /
            (
                (
                    semiMajorAxis *
                    (1 - eccentricitySquared)
                ) /
                (
                    magic *
                    squareRoot
                ) *
                .pi
            )

        let longitudeOffset =
            longitudeTransform *
            180.0 /
            (
                semiMajorAxis /
                squareRoot *
                cos(radians) *
                .pi
            )

        return (
            latitudeOffset,
            longitudeOffset
        )
    }

    private static func transformLatitude(
        x: Double,
        y: Double
    ) -> Double {
        var value =
            -100.0 +
            2.0 * x +
            3.0 * y +
            0.2 * y * y +
            0.1 * x * y +
            0.2 * sqrt(abs(x))

        value +=
            (
                20.0 * sin(6.0 * x * .pi) +
                20.0 * sin(2.0 * x * .pi)
            ) *
            2.0 /
            3.0
        value +=
            (
                20.0 * sin(y * .pi) +
                40.0 * sin(y / 3.0 * .pi)
            ) *
            2.0 /
            3.0
        value +=
            (
                160.0 * sin(y / 12.0 * .pi) +
                320.0 * sin(y * .pi / 30.0)
            ) *
            2.0 /
            3.0

        return value
    }

    private static func transformLongitude(
        x: Double,
        y: Double
    ) -> Double {
        var value =
            300.0 +
            x +
            2.0 * y +
            0.1 * x * x +
            0.1 * x * y +
            0.1 * sqrt(abs(x))

        value +=
            (
                20.0 * sin(6.0 * x * .pi) +
                20.0 * sin(2.0 * x * .pi)
            ) *
            2.0 /
            3.0
        value +=
            (
                20.0 * sin(x * .pi) +
                40.0 * sin(x / 3.0 * .pi)
            ) *
            2.0 /
            3.0
        value +=
            (
                150.0 * sin(x / 12.0 * .pi) +
                300.0 * sin(x / 30.0 * .pi)
            ) *
            2.0 /
            3.0

        return value
    }
}
