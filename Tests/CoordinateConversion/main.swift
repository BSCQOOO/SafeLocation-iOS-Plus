import CoreLocation
import Foundation

func same(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, tolerance: Double = 0.000001) -> Bool {
    abs(a.latitude - b.latitude) < tolerance && abs(a.longitude - b.longitude) < tolerance
}

let nagano = CLLocationCoordinate2D(latitude: 36.6486, longitude: 138.1948)
let westernNagano = CLLocationCoordinate2D(latitude: 35.6, longitude: 137.7)
let tokyo = CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
let beijing = CLLocationCoordinate2D(latitude: 39.9087, longitude: 116.3975)
for point in [nagano, westernNagano, tokyo] {
    precondition(same(MapCoordinateConverter.mapToWGS84(point, system: .gcj02), point), "Japan must remain WGS-84")
    precondition(same(MapCoordinateConverter.wgs84ToMap(point, system: .gcj02), point), "Japan display must not shift")
}
let seoul = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.978)
precondition(same(MapCoordinateConverter.mapToWGS84(seoul, system: .gcj02, countryCode: "KR"), seoul))
let display = MapCoordinateConverter.wgs84ToMap(beijing, system: .gcj02)
precondition(!same(beijing, display))
precondition(same(MapCoordinateConverter.mapToWGS84(display, system: .gcj02, countryCode: "CN"), beijing, tolerance: 0.00001))
let raw = ResolvedLocationInput(coordinate: beijing, name: "raw", coordinateSpace: .wgs84)
precondition(same(raw.canonicalCoordinate(system: .gcj02), beijing))
let map = ResolvedLocationInput(coordinate: display, name: "map", coordinateSpace: .mapKit, countryCode: "CN")
precondition(same(map.canonicalCoordinate(system: .gcj02), beijing, tolerance: 0.00001))
let data = GPXService.export(name: "测试 & 路线", coordinates: [beijing, tokyo])
let track = try GPXService.parse(data: data)
precondition(track.name == "测试 & 路线" && track.coordinates.count == 2)
precondition(same(track.coordinates[0], beijing) && same(track.coordinates[1], tokyo))
print("Coordinate and GPX regression tests passed.")
