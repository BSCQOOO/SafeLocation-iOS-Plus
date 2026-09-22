import Foundation
import MapKit

@MainActor
final class SearchController: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" {
        didSet {
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                completer.queryFragment = query
            } else {
                results = []
            }
        }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let newResults = Array(completer.results.prefix(12))
        Task { @MainActor in self.results = newResults }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> (coordinate: CLLocationCoordinate2D, name: String) {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw SearchError.noResult }
        return (item.placemark.coordinate, item.name ?? completion.title)
    }
}

enum SearchError: LocalizedError {
    case noResult
    var errorDescription: String? { "没有找到这个地点。" }
}
