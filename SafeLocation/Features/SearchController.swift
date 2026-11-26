import Foundation
import MapKit

@MainActor
final class SearchController: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var revision = 0
    private var completer: MKLocalSearchCompleter?
    private var searchTask: Task<Void, Never>?
    private var region: MKCoordinateRegion?

    func setRegion(_ region: MKCoordinateRegion?) {
        self.region = region
    }

    private func scheduleSearch() {
        revision += 1
        let currentRevision = revision
        searchTask?.cancel()
        completer?.cancel()
        completer = nil
        results = []
        let fragment = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fragment.isEmpty else { return }
        searchTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            guard let self, !Task.isCancelled, self.revision == currentRevision else { return }
            let instance = MKLocalSearchCompleter()
            instance.delegate = self
            instance.resultTypes = [.address, .pointOfInterest]
            if let region = self.region { instance.region = region }
            self.completer = instance
            instance.queryFragment = fragment
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let newResults = Array(completer.results.prefix(12))
        Task { @MainActor in
            guard self.completer === completer, !self.query.isEmpty else { return }
            self.results = newResults
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.completer === completer else { return }
            self.results = []
        }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> ResolvedLocationInput {
        let request = MKLocalSearch.Request(completion: completion)
        if let region { request.region = region }
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw SearchError.noResult }
        return ResolvedLocationInput(coordinate: item.placemark.coordinate,
                                     name: item.name ?? completion.title,
                                     coordinateSpace: .mapKit,
                                     countryCode: item.placemark.isoCountryCode)
    }
}

enum SearchError: LocalizedError {
    case noResult
    var errorDescription: String? { "没有找到这个地点。" }
}
