import CoreLocation
import Foundation
import MapKit

struct SearchSuggestion: Identifiable {
    enum Scope {
        case nearby
        case broader
    }

    let completion: MKLocalSearchCompletion
    let scope: Scope

    var id: String {
        [
            scope == .nearby ? "nearby" : "broader",
            completion.title,
            completion.subtitle
        ].joined(separator: "|")
    }

    var title: String { completion.title }
    var subtitle: String { completion.subtitle }
}

@MainActor
final class SearchController: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" {
        didSet {
            updateQuery()
        }
    }

    @Published private(set) var results: [SearchSuggestion] = []

    private let nearbyCompleter = MKLocalSearchCompleter()
    private let broaderCompleter = MKLocalSearchCompleter()

    private var nearbyResults: [MKLocalSearchCompletion] = []
    private var broaderResults: [MKLocalSearchCompletion] = []

    private var preferredCoordinate: CLLocationCoordinate2D?
    private var nearbyRadius: CLLocationDistance = 20_000

    override init() {
        super.init()

        configure(
            nearbyCompleter,
            priority: .required
        )
        configure(
            broaderCompleter,
            priority: .default
        )
    }

    func setSearchContext(
        center: CLLocationCoordinate2D?,
        visibleRadius: CLLocationDistance? = nil
    ) {
        preferredCoordinate = center

        if let visibleRadius {
            nearbyRadius = min(
                35_000,
                max(6_000, visibleRadius)
            )
        }

        guard let center else {
            nearbyCompleter.regionPriority = .default
            broaderCompleter.regionPriority = .default
            return
        }

        nearbyCompleter.region = region(
            around: center,
            radius: nearbyRadius
        )
        nearbyCompleter.regionPriority = .required

        broaderCompleter.region = region(
            around: center,
            radius: max(120_000, nearbyRadius * 5)
        )
        broaderCompleter.regionPriority = .default

        restartCompletersIfNeeded()
    }

    nonisolated func completerDidUpdateResults(
        _ completer: MKLocalSearchCompleter
    ) {
        let incoming = Array(completer.results.prefix(12))

        Task { @MainActor in
            if completer === self.nearbyCompleter {
                self.nearbyResults = incoming
            } else if completer === self.broaderCompleter {
                self.broaderResults = incoming
            }

            self.publishMergedResults()
        }
    }

    nonisolated func completer(
        _ completer: MKLocalSearchCompleter,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            if completer === self.nearbyCompleter {
                self.nearbyResults = []
            } else if completer === self.broaderCompleter {
                self.broaderResults = []
            }

            self.publishMergedResults()
        }
    }

    func resolve(
        _ suggestion: SearchSuggestion
    ) async throws -> (
        coordinate: CLLocationCoordinate2D,
        name: String
    ) {
        if suggestion.scope == .nearby,
           let preferredCoordinate,
           let item = try await search(
                completion: suggestion.completion,
                center: preferredCoordinate,
                radius: nearbyRadius,
                priority: .required
           ) {
            return resolved(item, fallback: suggestion.title)
        }

        let request = MKLocalSearch.Request(
            completion: suggestion.completion
        )

        if let preferredCoordinate {
            request.region = region(
                around: preferredCoordinate,
                radius: max(120_000, nearbyRadius * 5)
            )
            request.regionPriority = .default
        }

        let response = try await MKLocalSearch(
            request: request
        ).start()

        guard let item = response.mapItems.first else {
            throw SearchError.noResult
        }

        return resolved(item, fallback: suggestion.title)
    }

    func resolveAppleMapsStyleQuery(
        _ rawQuery: String
    ) async throws -> (
        coordinate: CLLocationCoordinate2D,
        name: String
    )? {
        let text = rawQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else { return nil }

        guard let preferredCoordinate else {
            return try await broadSearch(text)
        }

        // 1. Search the visible/nearby area strictly. This keeps same-name
        // businesses and POIs near the current map context above remote ones.
        if let item = try await search(
            query: text,
            center: preferredCoordinate,
            radius: nearbyRadius,
            priority: .required
        ) {
            return resolved(item, fallback: text)
        }

        // 2. Match Apple Maps' progressive broadening: nearby city/metro area
        // before falling all the way back to unrestricted results.
        if let item = try await search(
            query: text,
            center: preferredCoordinate,
            radius: 120_000,
            priority: .required
        ) {
            return resolved(item, fallback: text)
        }

        // 3. Final fallback allows MapKit's server relevance model to return
        // a remote well-known place when there truly is no useful local match.
        return try await broadSearch(text)
    }

    private func configure(
        _ completer: MKLocalSearchCompleter,
        priority: MKLocalSearchRegionPriority
    ) {
        completer.delegate = self
        completer.resultTypes = [
            .address,
            .pointOfInterest,
            .query
        ]
        completer.regionPriority = priority
    }

    private func updateQuery() {
        let trimmed = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else {
            nearbyCompleter.cancel()
            broaderCompleter.cancel()
            nearbyCompleter.queryFragment = ""
            broaderCompleter.queryFragment = ""
            nearbyResults = []
            broaderResults = []
            results = []
            return
        }

        nearbyCompleter.queryFragment = query
        broaderCompleter.queryFragment = query
    }

    private func restartCompletersIfNeeded() {
        let trimmed = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return }

        nearbyCompleter.queryFragment = ""
        broaderCompleter.queryFragment = ""
        nearbyCompleter.queryFragment = query
        broaderCompleter.queryFragment = query
    }

    private func publishMergedResults() {
        var seen = Set<String>()
        var merged: [SearchSuggestion] = []

        func append(
            _ completions: [MKLocalSearchCompletion],
            scope: SearchSuggestion.Scope
        ) {
            for completion in completions {
                let key = normalizedKey(
                    title: completion.title,
                    subtitle: completion.subtitle
                )

                guard seen.insert(key).inserted else {
                    continue
                }

                merged.append(
                    SearchSuggestion(
                        completion: completion,
                        scope: scope
                    )
                )

                if merged.count >= 12 {
                    return
                }
            }
        }

        append(nearbyResults, scope: .nearby)

        if merged.count < 12 {
            append(broaderResults, scope: .broader)
        }

        results = merged
    }

    private func search(
        query: String,
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        priority: MKLocalSearchRegionPriority
    ) async throws -> MKMapItem? {
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

        // Preserve MapKit's semantic ordering. The previous implementation
        // re-sorted everything by distance, which could promote a weak textual
        // match over the result Apple considers more relevant.
        return response.mapItems.first
    }

    private func search(
        completion: MKLocalSearchCompletion,
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        priority: MKLocalSearchRegionPriority
    ) async throws -> MKMapItem? {
        let request = MKLocalSearch.Request(
            completion: completion
        )
        request.region = region(
            around: center,
            radius: radius
        )
        request.regionPriority = priority

        let response = try await MKLocalSearch(
            request: request
        ).start()

        return response.mapItems.first
    }

    private func broadSearch(
        _ query: String
    ) async throws -> (
        coordinate: CLLocationCoordinate2D,
        name: String
    )? {
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

        guard let item = response.mapItems.first else {
            return nil
        }

        return resolved(item, fallback: query)
    }

    private func resolved(
        _ item: MKMapItem,
        fallback: String
    ) -> (
        coordinate: CLLocationCoordinate2D,
        name: String
    ) {
        (
            item.placemark.coordinate,
            item.name ?? fallback
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

    private func normalizedKey(
        title: String,
        subtitle: String
    ) -> String {
        (title + "|" + subtitle)
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: .current
            )
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }
}

enum SearchError: LocalizedError {
    case noResult

    var errorDescription: String? {
        "没有找到这个地点。"
    }
}
