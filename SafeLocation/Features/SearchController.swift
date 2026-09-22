import CoreLocation
import Foundation
import MapKit

struct LocalSearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String

    fileprivate let completion: MKLocalSearchCompletion

    init(completion: MKLocalSearchCompletion) {
        self.completion = completion
        title = completion.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
        subtitle = completion.subtitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
        id = [
            title,
            subtitle,
            String(ObjectIdentifier(completion).hashValue)
        ].joined(separator: "|")
    }
}

struct ResolvedPlace: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let mapItem: MKMapItem

    var coordinate: CLLocationCoordinate2D {
        mapItem.placemark.coordinate
    }

    init(item: MKMapItem) {
        mapItem = item

        let coordinate = item.placemark.coordinate
        let itemTitle = item.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        title =
            (itemTitle?.isEmpty == false)
            ? itemTitle!
            : "地点"

        let address = item.placemark.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        subtitle =
            address == title
            ? ""
            : address

        id = String(
            format: "%.6f|%.6f|%@",
            coordinate.latitude,
            coordinate.longitude,
            title
        )
    }
}

@MainActor
final class SearchController:
    NSObject,
    ObservableObject,
    MKLocalSearchCompleterDelegate
{
    @Published var query: String = "" {
        didSet {
            scheduleSuggestionSearch()
        }
    }

    @Published private(set) var results: [LocalSearchResult] = []
    @Published private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()
    private var preferredCoordinate: CLLocationCoordinate2D?
    private var preferredRegion: MKCoordinateRegion?
    private var nearbyRadius: CLLocationDistance = 18_000
    private var suggestionTask: Task<Void, Never>?
    private var generation = 0
    private var activeCompleterGeneration = 0
    private var activeCompleterQuery = ""

    override init() {
        super.init()

        completer.delegate = self
        completer.resultTypes = [
            .address,
            .pointOfInterest
        ]
        completer.regionPriority = .required
    }

    func setSearchContext(
        center: CLLocationCoordinate2D?,
        visibleRadius: CLLocationDistance? = nil
    ) {
        let oldCenter = preferredCoordinate
        let oldRadius = nearbyRadius

        preferredCoordinate = center

        if let visibleRadius {
            nearbyRadius = min(
                30_000,
                max(5_000, visibleRadius)
            )
        }

        if let center {
            let updatedRegion = region(
                around: center,
                radius: nearbyRadius
            )
            preferredRegion = updatedRegion
            completer.region = updatedRegion
            completer.regionPriority = .required
        } else {
            preferredRegion = nil
        }

        let movedEnough: Bool

        if let oldCenter, let center {
            movedEnough =
                CLLocation(
                    latitude: oldCenter.latitude,
                    longitude: oldCenter.longitude
                )
                .distance(
                    from: CLLocation(
                        latitude: center.latitude,
                        longitude: center.longitude
                    )
                ) > max(250, nearbyRadius * 0.08)
        } else {
            movedEnough = oldCenter != nil || center != nil
        }

        let radiusChanged =
            abs(oldRadius - nearbyRadius)
                > max(400, nearbyRadius * 0.12)

        if movedEnough || radiusChanged {
            scheduleSuggestionSearch()
        }
    }

    func resolve(
        _ result: LocalSearchResult
    ) async throws -> ResolvedPlace {
        let request = MKLocalSearch.Request(
            completion: result.completion
        )
        request.resultTypes = [
            .address,
            .pointOfInterest
        ]

        if let preferredRegion {
            request.region = preferredRegion
            request.regionPriority = .default
        }

        let response = try await MKLocalSearch(
            request: request
        ).start()

        guard let item = response.mapItems.first else {
            throw SearchError.noResult
        }

        debugLogMapItem(
            item,
            stage: "Completion resolved"
        )

        return ResolvedPlace(item: item)
    }

    func resolveAppleMapsStyleQuery(
        _ rawQuery: String
    ) async throws -> ResolvedPlace? {
        let text = rawQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else { return nil }

        if let preferredCoordinate {
            let radii: [CLLocationDistance] = [
                nearbyRadius,
                120_000,
                900_000
            ]

            for radius in radii {
                let local = try await localSearch(
                    text,
                    center: preferredCoordinate,
                    radius: radius,
                    priority: .required
                )

                if let first = local.first {
                    debugLogMapItem(
                        first.mapItem,
                        stage: "Submitted local result"
                    )
                    return first
                }
            }
        }

        // Explicit submission is the only path allowed to leave the regional
        // search context. This lets a Tokyo viewport still find an explicit
        // distant query such as "北京", while live suggestions remain local.
        let global = try await globalSearch(text)

        if let first = global.first {
            debugLogMapItem(
                first.mapItem,
                stage: "Submitted global result"
            )
        }

        return global.first
    }

    private func scheduleSuggestionSearch() {
        generation += 1
        let currentGeneration = generation

        suggestionTask?.cancel()

        let text = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !text.isEmpty else {
            activeCompleterQuery = ""
            activeCompleterGeneration = currentGeneration
            completer.queryFragment = ""
            results = []
            isSearching = false
            return
        }

        guard let preferredRegion else {
            activeCompleterQuery = ""
            activeCompleterGeneration = currentGeneration
            completer.queryFragment = ""
            results = []
            isSearching = false
            return
        }

        suggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(
                nanoseconds: 200_000_000
            )

            guard
                !Task.isCancelled,
                currentGeneration == self.generation
            else {
                return
            }

            self.activeCompleterGeneration =
                currentGeneration
            self.activeCompleterQuery = text
            self.completer.region = preferredRegion
            self.completer.regionPriority = .required
            self.isSearching = true
            self.completer.queryFragment = text
        }
    }

    nonisolated func completerDidUpdateResults(
        _ completer: MKLocalSearchCompleter
    ) {
        let completions = completer.results

        Task { @MainActor [weak self] in
            self?.acceptCompletions(completions)
        }
    }

    nonisolated func completer(
        _ completer: MKLocalSearchCompleter,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription

        Task { @MainActor [weak self] in
            self?.acceptCompleterFailure(message)
        }
    }

    private func acceptCompletions(
        _ completions: [MKLocalSearchCompletion]
    ) {
        let currentText = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard
            activeCompleterGeneration == generation,
            currentText == activeCompleterQuery
        else {
            return
        }

        results = Array(
            completions
                .prefix(12)
                .map(LocalSearchResult.init)
        )
        isSearching = false
    }

    private func acceptCompleterFailure(
        _ message: String
    ) {
        guard
            activeCompleterGeneration == generation
        else {
            return
        }

        #if DEBUG
        print(
            "[SafeLocation][Search] completer failed: \(message)"
        )
        #endif

        results = []
        isSearching = false
    }

    private func localSearch(
        _ query: String,
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        priority: MKLocalSearchRegionPriority
    ) async throws -> [ResolvedPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [
            .address,
            .pointOfInterest
        ]
        request.region = region(
            around: center,
            radius: radius
        )
        request.regionPriority = priority

        let response = try await MKLocalSearch(
            request: request
        ).start()

        return response.mapItems
            .map(ResolvedPlace.init)
    }

    private func globalSearch(
        _ query: String
    ) async throws -> [ResolvedPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [
            .address,
            .pointOfInterest
        ]

        if let preferredCoordinate {
            request.region = region(
                around: preferredCoordinate,
                radius: 900_000
            )
            request.regionPriority = .default
        }

        let response = try await MKLocalSearch(
            request: request
        ).start()

        return response.mapItems
            .map(ResolvedPlace.init)
    }

    private func region(
        around coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
    }

    private func debugLogMapItem(
        _ item: MKMapItem,
        stage: String
    ) {
        #if DEBUG
        let coordinate = item.placemark.coordinate
        print(
            "[SafeLocation][Search] \(stage): "
            + String(
                format: "lat=%.8f lon=%.8f name=%@",
                coordinate.latitude,
                coordinate.longitude,
                item.name ?? ""
            )
        )
        #endif
    }
}

enum SearchError: LocalizedError {
    case noResult

    var errorDescription: String? {
        "没有找到这个地点。"
    }
}
