import CoreLocation
import Foundation

enum LocationInputParser {
    static func parse(_ raw: String) -> CLLocationCoordinate2D? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let coordinate = parsePlain(text) { return coordinate }

        // geo:35.681236,139.767125 and similar URI forms.
        if text.lowercased().hasPrefix("geo:"),
           let coordinate = parsePlain(String(text.dropFirst(4)).components(separatedBy: "?").first ?? "") {
            return coordinate
        }

        if let url = URL(string: text),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for key in ["ll", "sll", "coordinate", "center", "q", "query", "daddr", "saddr"] {
                if let value = components.queryItems?.first(where: { $0.name.lowercased() == key })?.value,
                   let coordinate = parsePlain(value) {
                    return coordinate
                }
            }
        }

        // Google Maps-style /@lat,lon,zoom and shared text containing @lat,lon.
        if let regex = try? NSRegularExpression(pattern: "@(-?\\d+(?:\\.\\d+)?),(-?\\d+(?:\\.\\d+)?)"),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let latRange = Range(match.range(at: 1), in: text),
           let lonRange = Range(match.range(at: 2), in: text),
           let lat = Double(text[latRange]),
           let lon = Double(text[lonRange]) {
            return valid(lat: lat, lon: lon)
        }

        // Last-resort coordinate pair embedded in otherwise descriptive text.
        if let regex = try? NSRegularExpression(pattern: "(?<![\\d.])(-?\\d{1,2}(?:\\.\\d+)?)[,，\\s]+(-?\\d{1,3}(?:\\.\\d+)?)(?![\\d.])"),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let latRange = Range(match.range(at: 1), in: text),
           let lonRange = Range(match.range(at: 2), in: text),
           let lat = Double(text[latRange]),
           let lon = Double(text[lonRange]) {
            return valid(lat: lat, lon: lon)
        }

        return nil
    }

    private static func parsePlain(_ text: String) -> CLLocationCoordinate2D? {
        let normalized = text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: ";", with: ",")
        let pieces = normalized.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard pieces.count == 2,
              let lat = Double(pieces[0]),
              let lon = Double(pieces[1]) else { return nil }
        return valid(lat: lat, lon: lon)
    }

    private static func valid(lat: Double, lon: Double) -> CLLocationCoordinate2D? {
        guard (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
