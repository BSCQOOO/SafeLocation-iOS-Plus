import AppIntents
import Foundation

/// Public App Intents bridges for the Shortcuts share sheet.
///
/// Users can create a shortcut that accepts shared text/URLs from Apple Maps
/// and passes Shortcut Input into either action below. The system opens Safe
/// Location, and RootView consumes the pending import using MapKit.
struct ImportLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "导入地图位置"
    static let description = IntentDescription("把地图链接、地点名称或坐标发送到 Safe Location。")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "地图链接、地点或坐标")
    var input: String

    static var parameterSummary: some ParameterSummary {
        Summary("导入 (.$input) 到 Safe Location")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingImportBridge.submit(input, shouldTeleport: false)
        return .result(dialog: "已发送到 Safe Location")
    }
}

struct TeleportLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "Teleport 到地图位置"
    static let description = IntentDescription("把地图链接、地点名称或坐标发送到 Safe Location，并在连接条件满足时直接 Teleport。")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "地图链接、地点或坐标")
    var input: String

    static var parameterSummary: some ParameterSummary {
        Summary("Teleport 到 (.$input)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingImportBridge.submit(input, shouldTeleport: true)
        return .result(dialog: "正在交给 Safe Location")
    }
}
