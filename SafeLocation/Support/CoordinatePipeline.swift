import CoreLocation
import Foundation

/// Canonical coordinate contract for Safe Location.
///
/// Public Core Location / MapKit coordinates are treated as WGS-84 throughout
/// the app. The selected coordinate is the single source of truth and is sent
/// unchanged to Apple's DVT LocationSimulation service. GCJ conversion must
/// never be inferred from language, locale, map camera position or a coarse
/// geographic bounding box.
enum CoordinatePipeline {
    static func selectedFromMapKit(
        _ coordinate: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        #if DEBUG
        log(
            stage: "MapKit",
            coordinate: coordinate,
            detail: "WGS-84"
        )
        log(
            stage: "Selected",
            coordinate: coordinate,
            detail: "conversion=none"
        )
        #endif

        return coordinate
    }

    static func dvtFromSelected(
        _ coordinate: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        #if DEBUG
        log(
            stage: "Before DVT",
            coordinate: coordinate,
            detail: "WGS-84"
        )
        log(
            stage: "DVT",
            coordinate: coordinate,
            detail: "conversion=none"
        )
        #endif

        return coordinate
    }

    static func logSelected(
        _ coordinate: CLLocationCoordinate2D
    ) {
        #if DEBUG
        log(
            stage: "Selected",
            coordinate: coordinate,
            detail: "WGS-84"
        )
        #endif
    }

    #if DEBUG
    private static func log(
        stage: String,
        coordinate: CLLocationCoordinate2D,
        detail: String
    ) {
        print(
            "[SafeLocation][Coordinate] \(stage): "
            + String(
                format:
                    "lat=%.8f lon=%.8f %@",
                coordinate.latitude,
                coordinate.longitude,
                detail
            )
        )
    }
    #endif
}
