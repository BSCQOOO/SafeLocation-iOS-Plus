import CoreLocation
import Foundation
import MapKit

@MainActor
final class SearchController: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if !trimmed.isEmpty {
                completer.queryFragment = query
            } else {
                results = []
            }
        }
    }

    @Published private(set) var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()
    private var preferredCoordinate: CLLocationCoordinate2D?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func setSearchCenter(_ coordinate: CLLocationCoordinate2D?) {
        preferredCoordinate = coordinate

        guard let coordinate else { return }

        completer.region = localRegion(around: coordinate)

        let trimmed = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        // Re-issue the fragment after the region changes so autocomplete is
        // immediately re-ranked around the simulated/selected location.
        if !trimmed.isEmpty {
            completer.queryFragment = ""
            completer.queryFragment = query
        }
    }

    nonisolated func completerDidUpdateResults(
        _ completer: MKLocalSearchCompleter
    ) {
        let newResults = Array(completer.results.prefix(12))

        Task { @MainActor in
            self.results = newResults
        }
    }

    nonisolated func completer(
        _ completer: MKLocalSearchCompleter,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.results = []
        }
    }

    func resolve(
        _ completion: MKLocalSearchCompletion
    ) async throws -> (
        coordinate: CLLocationCoordinate2D,
        name: String
    ) {
        let request = MKLocalSearch.Request(completion: completion)

        if let preferredCoordinate {
            request.region = localRegion(around: preferredCoordinate)
        }

        let response = try await MKLocalSearch(request: request).start()

        guard let item = nearestItem(
            in: response.mapItems
        ) else {
            throw SearchError.noResult
        }

        return (
            item.placemark.coordinate,
            item.name ?? completion.title
        )
    }

    func resolveNearbyQuery(
        _ rawQuery: String
    ) async throws -> (
        coordinate: CLLocationCoordinate2D,
        name: String
    )? {
        let text = rawQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]

        if let preferredCoordinate {
            request.region = localRegion(around: preferredCoordinate)
        }

        let response = try await MKLocalSearch(request: request).start()

        guard let item = nearestItem(
            in: response.mapItems
        ) else {
            return nil
        }

        return (
            item.placemark.coordinate,
            item.name ?? text
        )
    }

    private func nearestItem(
        in items: [MKMapItem]
    ) -> MKMapItem? {
        guard let preferredCoordinate else {
            return items.first
        }

        let origin = CLLocation(
            latitude: preferredCoordinate.latitude,
            longitude: preferredCoordinate.longitude
        )

        return items.min { lhs, rhs in
            let left = CLLocation(
                latitude: lhs.placemark.coordinate.latitude,
                longitude: lhs.placemark.coordinate.longitude
            )
            let right = CLLocation(
                latitude: rhs.placemark.coordinate.latitude,
                longitude: rhs.placemark.coordinate.longitude
            )

            return origin.distance(from: left)
                < origin.distance(from: right)
        }
    }

    private func localRegion(
        around coordinate: CLLocationCoordinate2D
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 35_000,
            longitudinalMeters: 35_000
        )
    }
}

enum SearchError: LocalizedError {
    case noResult

    var errorDescription: String? {
        "没有找到这个地点。"
    }
}
