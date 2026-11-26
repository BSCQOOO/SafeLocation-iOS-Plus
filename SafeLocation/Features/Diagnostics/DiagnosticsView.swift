import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var session: SpoofController
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var pairService: PairOnDeviceService
    @AppStorage(TunnelProvider.preferenceKey) private var provider: TunnelProvider = .localDevVPN
    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var probeResult: Bool?
    @State private var probing = false

    var body: some View {
        List {
            Section("快速检查") {
                diagnosticRow("RPPairing", ok: pairing.hasPairingFile, detail: pairing.hasPairingFile ? "已就绪" : "需要配对")
                LabeledContent(provider.title, value: provider.interfaceSummary)
                LabeledContent("设备 TCP 通道", value: probing ? "检测中…" : (probeResult.map { $0 ? "可达（未验证配对）" : "不可达" } ?? "待检测"))
                Button("检测设备通道") {
                    probing = true
                    Task {
                        probeResult = await provider.probeDeviceChannel()
                        probing = false
                    }
                }
                .disabled(probing || session.isSpoofing || session.isRestoringRealLocation)
                diagnosticRow("DVT 会话", ok: LocationEngine.isSessionActive, detail: LocationEngine.isSessionActive ? "活动" : "未建立")
                diagnosticRow("模拟状态", ok: session.isSpoofing, detail: session.status.title)
            }

            Section("Tunnel") {
                LabeledContent("设备 / Peer IP", value: TunnelConfig.effectiveIP)
                if provider == .localDevVPN {
                    if let interfaceIP = LocalDevVPN.detectedInterfaceIP {
                        LabeledContent("本机 Tunnel IP", value: interfaceIP)
                    }
                    TextField("设备 / Peer IP", text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存地址") { TunnelConfig.setTargetIP(tunnelIP); probeResult = nil }
                        .disabled(probing || session.isSpoofing || session.isRestoringRealLocation)
                }
                Text(provider.instructions).font(.caption)
                Button(provider.actionTitle) { provider.openClient() }
                    .disabled(provider == .shadowrocket && !provider.isInstalled)
            }

            Section("修复") {
                Button("恢复真实定位") { session.restoreRealLocation() }
                Button("重新本机配对") { pairService.start(pairingStore: pairing) }
                    .disabled(pairService.isBusy)
                Button("刷新配对状态") { pairing.refresh() }
            }

            Section("说明") {
                Text("这里检查的是 Safe Location 自身依赖。系统的 Developer Mode 没有公开 API 可以可靠直接读取；如果配对或 DVT 服务失败，请先确认开发者模式仍然开启。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("诊断")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func diagnosticRow(_ title: String, ok: Bool, detail: String) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(title)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
        }
    }
}
