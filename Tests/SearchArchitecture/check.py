#!/usr/bin/env python3
from pathlib import Path

search = Path(
    "SafeLocation/Features/SearchController.swift"
).read_text()
root = Path(
    "SafeLocation/Features/RootView.swift"
).read_text()
resolver = Path(
    "SafeLocation/Support/MapLinkResolver.swift"
).read_text()
pipeline = Path(
    "SafeLocation/Support/CoordinatePipeline.swift"
).read_text()

required_search = [
    "MKLocalSearchCompleter",
    "MKLocalSearchCompleterDelegate",
    "completer.region =",
    "completer.regionPriority = .required",
    "completer.queryFragment = text",
    "suggestionTask?.cancel()",
    "currentGeneration == self.generation",
    "MKLocalSearch.Request(",
    "completion: result.completion",
    "resolveAppleMapsStyleQuery",
    "nearbyRadius",
    "120_000",
    "900_000",
    "priority: .required",
    "request.regionPriority = .default",
]

for token in required_search:
    assert token in search, f"missing search invariant: {token}"

assert "results.sort" not in search
assert ".sorted(" not in search
assert "search.select(result)" not in root
assert "await search.resolve(result)" in root
assert "center: camera.centerCoordinate" in root
assert (
    "session.simulatedCoordinate"
    in root
    and "session.selectedCoordinate" in root
    and "mapLocation.bestRealCoordinate" in root
)
assert "MapCoordinateConverter" not in root
assert "CoordinateSpace" not in resolver
assert "MapCoordinateConverter" not in resolver
assert "selectedFromMapKit" in pipeline
assert "dvtFromSelected" in pipeline

print("Search and coordinate architecture regression checks passed.")
