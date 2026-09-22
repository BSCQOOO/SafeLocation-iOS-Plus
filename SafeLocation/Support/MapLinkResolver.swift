import CoreLocation
import Foundation
import MapKit

struct ResolvedLocationInput {
    enum CoordinateSpace {
        case wgs84
        case mapKit
    }

    let coordinate: CLLocationCoordinate2D
    let name: String
    let coordinateSpace: CoordinateSpace
}

enum MapLinkResolver {
    static func resolve(_ raw: String) async throws -> ResolvedLocationInput? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let coordinate = LocationInputParser.parse(text) {
            return ResolvedLocationInput(
                coordinate: coordinate,
                name: inferredName(from: text) ?? "输入位置",
                coordinateSpace: .wgs84
            )
        }

        if let url = URL(string: text),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let host = (components.host ?? "").lowercased()
            if host.contains("maps.apple.com") || host.contains("maps.google") || host.contains("google.com") {
                let queryItems = components.queryItems ?? []
                for key in ["q", "query", "address", "daddr", "saddr"] {
                    if let value = queryItems.first(where: { $0.name.lowercased() == key })?.value,
                       !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let coordinate = LocationInputParser.parse(value) {
                            return ResolvedLocationInput(
                                coordinate: coordinate,
                                name: value,
                                coordinateSpace:
                                    host.contains("maps.apple.com")
                                    ? .mapKit
                                    : .wgs84
                            )
                        }
                        if let result = try await localSearch(value) { return result }
                    }
                }
            }
        }

        // Plain place names are also accepted as a convenience.
        if !text.contains("://") {
            return try await localSearch(text)
        }
        return nil
    }

    private static func localSearch(_ query: String) async throws -> ResolvedLocationInput? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { return nil }
        return ResolvedLocationInput(
            coordinate: item.placemark.coordinate,
            name: item.name ?? query,
            coordinateSpace: .mapKit
        )
    }

    private static func inferredName(from raw: String) -> String? {
        guard let url = URL(string: raw),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        for key in ["q", "query", "name", "address"] {
            if let value = components.queryItems?.first(where: { $0.name.lowercased() == key })?.value,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               LocationInputParser.parse(value) == nil {
                return value
            }
        }
        return nil
    }
}
