import CoreLocation
import Foundation

struct GPXTrack {
    let name: String
    let coordinates: [CLLocationCoordinate2D]
}

enum GPXServiceError: LocalizedError {
    case noTrackPoints
    case invalidXML

    var errorDescription: String? {
        switch self {
        case .noTrackPoints: return "GPX 中没有可用的轨迹点。"
        case .invalidXML: return "无法解析 GPX 文件。"
        }
    }
}

enum GPXService {
    static func parse(data: Data, fallbackName: String = "GPX 路线") throws -> GPXTrack {
        let parser = XMLParser(data: data)
        let delegate = GPXParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else { throw GPXServiceError.invalidXML }
        guard delegate.coordinates.count >= 2 else { throw GPXServiceError.noTrackPoints }
        return GPXTrack(name: delegate.trackName ?? fallbackName, coordinates: delegate.coordinates)
    }

    static func export(name: String, coordinates: [CLLocationCoordinate2D]) -> Data {
        let safeName = name.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Safe Location" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>\(safeName)</name><trkseg>
        """
        for point in coordinates {
            xml += "\n    <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"></trkpt>"
        }
        xml += "\n  </trkseg></trk>\n</gpx>\n"
        return Data(xml.utf8)
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var coordinates: [CLLocationCoordinate2D] = []
    var trackName: String?
    private var activeElement: String?
    private var textBuffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        activeElement = elementName
        textBuffer = ""
        if elementName == "trkpt" || elementName == "rtept" || elementName == "wpt" {
            if let latText = attributeDict["lat"], let lonText = attributeDict["lon"],
               let lat = Double(latText), let lon = Double(lonText),
               (-90...90).contains(lat), (-180...180).contains(lon) {
                coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "name", trackName == nil {
            let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { trackName = value }
        }
        activeElement = nil
        textBuffer = ""
    }
}
