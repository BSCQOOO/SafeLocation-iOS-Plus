import CoreLocation
import Foundation
import MapKit

struct PlannedRoute: Identifiable, Equatable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
    let name: String

    static func == (lhs: PlannedRoute, rhs: PlannedRoute) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class RoutePlanner: ObservableObject {
    enum Transport: String, CaseIterable, Identifiable {
        case walking = "步行"
        case driving = "驾车"

        var id: String { rawValue }
        var mkType: MKDirectionsTransportType {
            switch self {
            case .walking: return .walking
            case .driving: return .automobile
            }
        }
        var systemImage: String {
            switch self {
            case .walking: return "figure.walk"
            case .driving: return "car.fill"
            }
        }
    }

    @Published var destinationText = ""
    @Published var transport: Transport = .walking
    @Published private(set) var route: PlannedRoute?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func build(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, name: String) async {
        guard !isLoading else { return }
        isLoading = true
        route = nil
        errorMessage = nil
        defer { isLoading = false }

        let request = MKDirections.Request()
        let system = MapCoordinateConverter.effectiveSystem
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: MapCoordinateConverter.wgs84ToMap(start, system: system)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: MapCoordinateConverter.wgs84ToMap(end, system: system)))
        request.transportType = transport.mkType
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let first = response.routes.first else {
                errorMessage = "没有找到可用路线。"
                return
            }
            route = PlannedRoute(
                coordinates: first.polyline.coordinates.map {
                    MapCoordinateConverter.mapToWGS84($0, system: system)
                },
                distance: first.distance,
                expectedTravelTime: first.expectedTravelTime,
                name: name
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        route = nil
        errorMessage = nil
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var result = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
        getCoordinates(&result, range: NSRange(location: 0, length: pointCount))
        return result
    }
}
