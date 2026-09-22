import CoreLocation
import Foundation
import MapKit

enum MapCoordinateConverter {
    enum MapCoordinateSystem: String, Equatable, Sendable {
        case wgs84 = "WGS-84"
        case gcj02 = "GCJ-02"
    }

    /// Apple Maps' mainland-China map service uses GCJ-02 at the map
    /// boundary. Everywhere else is kept in WGS-84. The actual geographic
    /// gate is applied per coordinate below, so this no longer depends on a
    /// network probe, device language, or a search-result name.
    static func detectMapCoordinateSystem() async -> MapCoordinateSystem {
        .gcj02
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
        // Never transform Hong Kong, Macau or Taiwan. The old implementation
        // used one huge rectangle that also captured Seoul, Busan, Okinawa,
        // Taiwan and parts of Southeast Asia, creating hundreds-of-metres
        // offsets outside mainland China.
        if latitude >= 22.08, latitude <= 22.58,
           longitude >= 113.80, longitude <= 114.52 {
            return false
        }

        if latitude >= 22.05, latitude <= 22.24,
           longitude >= 113.52, longitude <= 113.64 {
            return false
        }

        if latitude >= 21.75, latitude <= 25.45,
           longitude >= 119.25, longitude <= 122.20 {
            return false
        }

        // Hainan uses the mainland Apple Maps service as well.
        if latitude >= 18.0, latitude <= 20.35,
           longitude >= 108.5, longitude <= 111.5 {
            return true
        }

        return pointInMainlandPolygon(
            latitude: latitude,
            longitude: longitude
        )
    }

    private static let mainlandPolygon: [
        (latitude: Double, longitude: Double)
    ] = [
        (53.6, 121.5),
        (53.0, 134.8),
        (48.0, 134.8),
        (43.0, 131.0),
        (40.5, 124.5),
        (37.0, 122.5),
        (30.0, 122.8),
        (24.0, 118.5),
        (21.5, 112.0),
        (20.7, 109.5),
        (22.0, 106.5),
        (24.0, 104.0),
        (28.0, 98.0),
        (28.5, 94.0),
        (30.0, 88.0),
        (27.5, 80.0),
        (31.5, 78.0),
        (35.0, 73.5),
        (40.5, 73.5),
        (45.0, 82.0),
        (49.0, 87.0),
        (49.0, 117.0)
    ]

    private static func pointInMainlandPolygon(
        latitude: Double,
        longitude: Double
    ) -> Bool {
        var inside = false
        var previous = mainlandPolygon.count - 1

        for index in mainlandPolygon.indices {
            let currentPoint = mainlandPolygon[index]
            let previousPoint = mainlandPolygon[previous]

            let crossesLatitude =
                (currentPoint.latitude > latitude)
                != (previousPoint.latitude > latitude)

            if crossesLatitude {
                let denominator =
                    previousPoint.latitude
                    - currentPoint.latitude

                let safeDenominator =
                    abs(denominator) < 0.0000001
                    ? 0.0000001
                    : denominator

                let boundaryLongitude =
                    (
                        previousPoint.longitude
                        - currentPoint.longitude
                    )
                    * (
                        latitude
                        - currentPoint.latitude
                    )
                    / safeDenominator
                    + currentPoint.longitude

                if longitude < boundaryLongitude {
                    inside.toggle()
                }
            }

            previous = index
        }

        return inside
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
