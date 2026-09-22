import CoreLocation
import Foundation

struct LocationProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var subtitle: String
    var symbol: String
    var latitude: Double
    var longitude: Double
    var travelModeRaw: String
    var autoRestoreMinutes: Int?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String = "",
        symbol: String = "mappin.circle.fill",
        latitude: Double,
        longitude: Double,
        travelModeRaw: String = "步行",
        autoRestoreMinutes: Int? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.symbol = symbol
        self.latitude = latitude
        self.longitude = longitude
        self.travelModeRaw = travelModeRaw
        self.autoRestoreMinutes = autoRestoreMinutes
        self.createdAt = createdAt
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var restoreDescription: String {
        guard let autoRestoreMinutes, autoRestoreMinutes > 0 else { return "不自动恢复" }
        if autoRestoreMinutes >= 60, autoRestoreMinutes % 60 == 0 {
            return "(autoRestoreMinutes / 60) 小时后恢复"
        }
        return "(autoRestoreMinutes) 分钟后恢复"
    }
}

enum LocationProfileStore {
    static let defaultsKey = "safeLocation.profiles.v1"

    static let builtIns: [LocationProfile] = [
        LocationProfile(name: "东京站", subtitle: "Tokyo, Japan", symbol: "tram.fill", latitude: 35.681236, longitude: 139.767125),
        LocationProfile(name: "首尔市厅", subtitle: "Seoul, Korea", symbol: "building.2.fill", latitude: 37.566295, longitude: 126.977945),
        LocationProfile(name: "香港中环", subtitle: "Central, Hong Kong", symbol: "building.columns.fill", latitude: 22.281874, longitude: 114.158888),
        LocationProfile(name: "澳门议事亭前地", subtitle: "Macau", symbol: "flag.fill", latitude: 22.193267, longitude: 113.539457),
        LocationProfile(name: "新加坡滨海湾", subtitle: "Singapore", symbol: "water.waves", latitude: 1.283404, longitude: 103.860724),
        LocationProfile(name: "时代广场", subtitle: "New York, USA", symbol: "sparkles", latitude: 40.758000, longitude: -73.985500),
        LocationProfile(name: "伦敦塔桥", subtitle: "London, UK", symbol: "bridge.fill", latitude: 51.505456, longitude: -0.075356)
    ]

    static func load() -> [LocationProfile] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode([LocationProfile].self, from: data) else {
            return []
        }
        return value
    }

    static func save(_ profiles: [LocationProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
