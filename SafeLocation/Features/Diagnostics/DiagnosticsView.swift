import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var session: SpoofController
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var pairService: PairOnDeviceService
    @State private var tunnelIP = TunnelConfig.targetIP

    var body: some View {
        List {
            Section("快速检查") {
                diagnosticRow("RPPairing", ok: pairing.hasPairingFile, detail: pairing.hasPairingFile ? "已就绪" : "需要配对")
                diagnosticRow("LocalDevVPN", ok: LocalDevVPN.isConnected, detail: LocalDevVPN.isConnected ? "已连接 · \(LocalDevVPN.detectedInterfaceIP ?? "已检测")" : "未连接")
                diagnosticRow("DVT 会话", ok: LocationEngine.isSessionActive, detail: LocationEngine.isSessionActive ? "活动" : "未建立")
                diagnosticRow("模拟状态", ok: session.isSpoofing, detail: session.status.title)
            }

            Section("Tunnel") {
                LabeledContent("设备 / Peer IP", value: tunnelIP)
                if let interfaceIP = LocalDevVPN.detectedInterfaceIP {
                    LabeledContent("本机 Tunnel IP", value: interfaceIP)
                }
                TextField("设备 / Peer IP", text: $tunnelIP)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("保存并重新检测") { TunnelConfig.setTargetIP(tunnelIP) }
                Button(LocalDevVPN.isInstalled ? "打开 LocalDevVPN" : "安装 LocalDevVPN") { LocalDevVPN.openOrInstall() }
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
