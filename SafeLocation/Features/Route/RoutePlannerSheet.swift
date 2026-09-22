import CoreLocation
import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct RoutePlannerSheet: View {
    @EnvironmentObject private var session: SpoofController
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var planner = RoutePlanner()
    @State private var showImporter = false
    @State private var importedTrack: GPXTrack?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("目标") {
                    if let coordinate = session.selectedCoordinate {
                        LabeledContent(session.selectedName) {
                            Text(SpoofController.coordinateLabel(coordinate))
                                .font(.caption.monospacedDigit())
                        }
                    } else {
                        Text("先在地图选择一个目的地。")
                            .foregroundStyle(.secondary)
                    }
                    Picker("路线类型", selection: $planner.transport) {
                        ForEach(RoutePlanner.Transport.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Button {
                        Task { await buildRoute() }
                    } label: {
                        if planner.isLoading { ProgressView().frame(maxWidth: .infinity) }
                        else { Label("规划道路路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath").frame(maxWidth: .infinity) }
                    }
                    .disabled(planner.isLoading || session.selectedCoordinate == nil || session.routeStartCoordinate == nil)
                }

                if let route = planner.route {
                    Section("路线") {
                        LabeledContent("距离", value: distanceString(route.distance))
                        LabeledContent("预计时间", value: durationString(route.expectedTravelTime))
                        Picker("模拟速度", selection: $session.travelMode) {
                            ForEach(SpoofController.TravelMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                            }
                        }
                        Button {
                            session.startRoute(route.coordinates, pairing: pairing)
                            dismiss()
                        } label: {
                            Label("开始路线模拟", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("GPX") {
                    Button("导入 GPX") { showImporter = true }
                    if let importedTrack {
                        LabeledContent("轨迹", value: importedTrack.name)
                        LabeledContent("轨迹点", value: "(importedTrack.coordinates.count)")
                        Picker("模拟速度", selection: $session.travelMode) {
                            ForEach(SpoofController.TravelMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        Button {
                            session.startRoute(importedTrack.coordinates, pairing: pairing)
                            dismiss()
                        } label: {
                            Label("播放 GPX", systemImage: "play.circle.fill")
                        }
                    }
                }

                if session.isRoutePlaying {
                    Section("当前路线") {
                        ProgressView(value: session.routeProgress)
                        Button("停止路线", role: .destructive) { session.stopRoute() }
                    }
                }
            }
            .navigationTitle("路线模拟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.xml, .data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                importedTrack = try GPXService.parse(data: data, fallbackName: url.deletingPathExtension().lastPathComponent)
            } catch {
                errorText = error.localizedDescription
            }
        }
        .alert("路线错误", isPresented: Binding(get: { errorText != nil || planner.errorMessage != nil }, set: { if !$0 { errorText = nil; planner.errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorText ?? planner.errorMessage ?? "未知错误")
        }
    }

    private func buildRoute() async {
        guard let start = session.routeStartCoordinate, let end = session.selectedCoordinate else {
            errorText = "无法取得路线起点，请先允许定位或先 Teleport 一次。"
            return
        }
        await planner.build(from: start, to: end, name: session.selectedName)
    }

    private func distanceString(_ meters: CLLocationDistance) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "(minutes) 分钟" }
        return "(minutes / 60) 小时 (minutes % 60) 分"
    }
}
