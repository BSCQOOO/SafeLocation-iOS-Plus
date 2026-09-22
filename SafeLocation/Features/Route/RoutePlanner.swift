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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = transport.mkType
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let first = response.routes.first else {
                errorMessage = "没有找到可用路线。"
                return
            }
            route = PlannedRoute(
                coordinates: first.polyline.coordinates,
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
