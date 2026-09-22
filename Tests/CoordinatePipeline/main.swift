import CoreLocation
import Foundation

struct CoordinateCase {
    let name: String
    let latitude: Double
    let longitude: Double
}

let cases: [CoordinateCase] = [
    .init(name: "Tokyo Station", latitude: 35.681236, longitude: 139.767125),
    .init(name: "Nagano City", latitude: 36.648549, longitude: 138.194243),
    .init(name: "Matsumoto", latitude: 36.238038, longitude: 137.972034),
    .init(name: "Western Nagano", latitude: 36.100000, longitude: 137.700000),
    .init(name: "Gifu", latitude: 35.423298, longitude: 136.760654),
    .init(name: "Nagoya", latitude: 35.181450, longitude: 136.906557),
    .init(name: "Toyama", latitude: 36.695291, longitude: 137.211338),
    .init(name: "Kyoto", latitude: 35.011564, longitude: 135.768149),
    .init(name: "Osaka", latitude: 34.693725, longitude: 135.502254),
    .init(name: "Seoul", latitude: 37.566295, longitude: 126.977945),
    .init(name: "Shanghai", latitude: 31.230416, longitude: 121.473701),
    .init(name: "Beijing", latitude: 39.904202, longitude: 116.407394),
    .init(name: "Shenzhen", latitude: 22.543096, longitude: 114.057865),
    .init(name: "Guangzhou", latitude: 23.129110, longitude: 113.264385),
    .init(name: "New York", latitude: 40.712800, longitude: -74.006000),
    .init(name: "Paris", latitude: 48.856600, longitude: 2.352200),
    .init(name: "Singapore", latitude: 1.352100, longitude: 103.819800)
]

let boundaryLongitudes: [Double] = [
    137.70,
    137.80,
    137.83,
    137.8346,
    137.8347,
    137.8348,
    137.84,
    137.90,
    138.00,
    139.00
]

func assertSame(
    _ lhs: CLLocationCoordinate2D,
    _ rhs: CLLocationCoordinate2D,
    _ message: String
) {
    precondition(
        lhs.latitude == rhs.latitude
            && lhs.longitude == rhs.longitude,
        message
    )
}

for item in cases {
    let mapKit = CLLocationCoordinate2D(
        latitude: item.latitude,
        longitude: item.longitude
    )
    let selected =
        CoordinatePipeline.selectedFromMapKit(mapKit)
    let dvt =
        CoordinatePipeline.dvtFromSelected(selected)

    assertSame(
        mapKit,
        selected,
        "\(item.name): MapKit -> Selected changed"
    )
    assertSame(
        selected,
        dvt,
        "\(item.name): Selected -> DVT changed"
    )

    print(
        String(
            format:
                "PASS %-18@ MapKit %.8f %.8f | Selected %.8f %.8f | DVT %.8f %.8f",
            item.name as NSString,
            mapKit.latitude,
            mapKit.longitude,
            selected.latitude,
            selected.longitude,
            dvt.latitude,
            dvt.longitude
        )
    )
}

for longitude in boundaryLongitudes {
    let mapKit = CLLocationCoordinate2D(
        latitude: 36.000000,
        longitude: longitude
    )
    let selected =
        CoordinatePipeline.selectedFromMapKit(mapKit)
    let dvt =
        CoordinatePipeline.dvtFromSelected(selected)

    assertSame(
        mapKit,
        selected,
        "137.8347 boundary: MapKit -> Selected changed"
    )
    assertSame(
        selected,
        dvt,
        "137.8347 boundary: Selected -> DVT changed"
    )

    print(
        String(
            format:
                "PASS boundary lon=%.4f -> %.4f",
            longitude,
            dvt.longitude
        )
    )
}

print("Coordinate pipeline regression tests passed.")
