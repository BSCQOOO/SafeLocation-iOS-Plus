import CoreLocation
import Foundation
import MapKit

struct LocalSearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    init(item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        let title = item.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.title =
            (title?.isEmpty == false)
            ? title!
            : "地点"

        let address = item.placemark.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        self.subtitle =
            address == self.title
            ? ""
            : address

        self.coordinate = coordinate
        self.id = String(
            format: "%.6f|%.6f|%@",
            coordinate.latitude,
            coordinate.longitude,
            self.title
        )
    }
}

@MainActor
final class SearchController: NSObject, ObservableObject {
    @Published var query: String = "" {
        didSet {
            scheduleSuggestionSearch()
        }
    }

    @Published private(set) var results: [LocalSearchResult] = []
    @Published private(set) var isSearching = false

    private var preferredCoordinate: CLLocationCoordinate2D?
    private var nearbyRadius: CLLocationDistance = 18_000
    private var suggestionTask: Task<Void, Never>?
    private var generation = 0

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

    func select(
        _ result: LocalSearchResult
    ) -> (
        coordinate: CLLocationCoordinate2D,
        name: String
    ) {
        (
            result.coordinate,
            result.title
        )
    }

    func resolveAppleMapsStyleQuery(
        _ rawQuery: String
    ) async throws -> LocalSearchResult? {
        let text = rawQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else { return nil }

        if let preferredCoordinate {
            let nearby = try await localSearch(
                text,
                center: preferredCoordinate,
                radius: nearbyRadius,
                priority: .required
            )

            if let first = nearby.first {
                return first
            }

            let metro = try await localSearch(
                text,
                center: preferredCoordinate,
                radius: 120_000,
                priority: .required
            )

            if let first = metro.first {
                return first
            }
        }

        // Only an explicit submitted search may fall back globally. Live
        // suggestions stay local so a Tokyo viewport never fills with China
        // results just because the query language is Chinese.
        return try await globalSearch(text).first
    }

    private func scheduleSuggestionSearch() {
        generation += 1
        let currentGeneration = generation

        suggestionTask?.cancel()

        let text = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !text.isEmpty else {
            results = []
            isSearching = false
            return
        }

        guard let center = preferredCoordinate else {
            results = []
            isSearching = false
            return
        }

        suggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(
                nanoseconds: 230_000_000
            )

            guard
                !Task.isCancelled,
                currentGeneration == self.generation
            else {
                return
            }

            self.isSearching = true
            defer {
                if currentGeneration == self.generation {
                    self.isSearching = false
                }
            }

            do {
                let nearby = try await self.localSearch(
                    text,
                    center: center,
                    radius: self.nearbyRadius,
                    priority: .required
                )

                guard
                    !Task.isCancelled,
                    currentGeneration == self.generation
                else {
                    return
                }

                if nearby.count >= 8 {
                    self.results = Array(nearby.prefix(12))
                    return
                }

                let metro = try await self.localSearch(
                    text,
                    center: center,
                    radius: 120_000,
                    priority: .required
                )

                guard
                    !Task.isCancelled,
                    currentGeneration == self.generation
                else {
                    return
                }

                self.results = self.merge(
                    nearby,
                    metro,
                    limit: 12
                )
            } catch {
                guard currentGeneration == self.generation else {
                    return
                }

                // Search suggestions are best-effort. Keep the UI clean instead
                // of surfacing transient MapKit network errors while typing.
                self.results = []
            }
        }
    }

    private func localSearch(
        _ query: String,
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        priority: MKLocalSearchRegionPriority
    ) async throws -> [LocalSearchResult] {
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
            .map(LocalSearchResult.init)
            .filter {
                contains(
                    $0.coordinate,
                    center: center,
                    radius: radius * 1.12
                )
            }
    }

    private func globalSearch(
        _ query: String
    ) async throws -> [LocalSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [
            .address,
            .pointOfInterest
        ]

        if let preferredCoordinate {
            request.region = region(
                around: preferredCoordinate,
                radius: 300_000
            )
            request.regionPriority = .default
        }

        let response = try await MKLocalSearch(
            request: request
        ).start()

        return response.mapItems
            .map(LocalSearchResult.init)
    }

    private func merge(
        _ first: [LocalSearchResult],
        _ second: [LocalSearchResult],
        limit: Int
    ) -> [LocalSearchResult] {
        var seen = Set<String>()
        var output: [LocalSearchResult] = []

        for item in first + second {
            let key = normalizedKey(item)

            guard seen.insert(key).inserted else {
                continue
            }

            output.append(item)

            if output.count >= limit {
                break
            }
        }

        return output
    }

    private func normalizedKey(
        _ result: LocalSearchResult
    ) -> String {
        [
            result.title,
            result.subtitle,
            String(format: "%.4f", result.coordinate.latitude),
            String(format: "%.4f", result.coordinate.longitude)
        ]
        .joined(separator: "|")
        .folding(
            options: [
                .caseInsensitive,
                .diacriticInsensitive,
                .widthInsensitive
            ],
            locale: .current
        )
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

    private func contains(
        _ coordinate: CLLocationCoordinate2D,
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) -> Bool {
        CLLocation(
            latitude: center.latitude,
            longitude: center.longitude
        )
        .distance(
            from: CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        ) <= radius
    }
}

enum SearchError: LocalizedError {
    case noResult

    var errorDescription: String? {
        "没有找到这个地点。"
    }
}
