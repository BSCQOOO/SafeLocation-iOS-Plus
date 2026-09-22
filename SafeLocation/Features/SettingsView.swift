import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SpoofController
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var pairService: PairOnDeviceService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cellularBridge = CellularTunnelBridge.shared

    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var turnOffShortcut = CellularTunnelBridge.shared.turnOffShortcutName
    @State private var turnOnShortcut = CellularTunnelBridge.shared.turnOnShortcutName
    @State private var showSetup = false
    @State private var confirmRemovePairing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("状态") {
                    LabeledContent("模拟定位", value: session.status.title)
                    LabeledContent("RPPairing", value: pairing.hasPairingFile ? "已就绪" : "未配置")
                    LabeledContent("LocalDevVPN", value: LocalDevVPN.isConnected ? "已连接" : "未连接")
                    LabeledContent("DVT 会话", value: LocationEngine.isSessionActive ? "活动" : "未建立")
                    if let coordinate = session.simulatedCoordinate {
                        LabeledContent("当前模拟坐标") {
                            Text(SpoofController.coordinateLabel(coordinate)).monospacedDigit()
                        }
                    }
                    if let timer = session.autoRestoreDisplay {
                        LabeledContent("自动恢复", value: timer)
                    }
                    NavigationLink("打开完整诊断") {
                        DiagnosticsView()
                            .environmentObject(session)
                            .environmentObject(pairing)
                            .environmentObject(pairService)
                    }
                }

                Section("连接") {
                    TextField("Tunnel IP", text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存 Tunnel IP") { TunnelConfig.setTargetIP(tunnelIP) }
                    Button(LocalDevVPN.isInstalled ? "打开 LocalDevVPN" : "安装 LocalDevVPN") {
                        LocalDevVPN.openOrInstall()
                    }
                    Button("重新运行首次设置") { showSetup = true }
                }

                Section("纯蜂窝实验") {
                    LabeledContent("当前网络", value: cellularBridge.networkKind.rawValue)
                    LabeledContent("桥接状态", value: cellularBridge.stage.title)
                    TextField("开启飞行模式快捷指令", text: $turnOffShortcut)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("关闭飞行模式快捷指令", text: $turnOnShortcut)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存快捷指令名称") {
                        cellularBridge.setShortcutNames(
                            turnOff: turnOffShortcut,
                            turnOn: turnOnShortcut
                        )
                    }
                    Button("打开“快捷指令”创建页面") {
                        _ = cellularBridge.openShortcutCreator()
                    }
                    Text("需要两个飞行模式快捷指令。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("移动默认值") {
                    Picker("默认速度", selection: $session.travelMode) {
                        ForEach(SpoofController.TravelMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    LabeledContent("自定义位置方案", value: "\(session.customProfiles.count) 个")
                }

                Section("安全与恢复") {
                    Button("立即恢复真实定位", role: .destructive) { session.emergencyRestore() }
                    if session.autoRestoreDisplay != nil {
                        Button("取消自动恢复", role: .destructive) {
                            session.configureAutoRestore(minutes: nil)
                        }
                    }
                    Button("删除本机 RPPairing", role: .destructive) { confirmRemovePairing = true }
                }

                Section("关于") {
                    LabeledContent("版本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                    if let commit = Bundle.main.object(forInfoDictionaryKey: "SafeLocationCommit") as? String {
                        LabeledContent("构建", value: String(commit.prefix(12)))
                    }
                    Link("底层开源项目 Locus", destination: URL(string: "https://github.com/ChrisMack32/Locus")!)
                    Link("LocalDevVPN", destination: URL(string: "https://github.com/jkcoxson/LocalDevVPN")!)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
        .sheet(isPresented: $showSetup) {
            SetupView().environmentObject(pairing).environmentObject(pairService)
        }
        .confirmationDialog("删除配对文件？", isPresented: $confirmRemovePairing, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                session.emergencyRestore()
                try? pairing.removePairing()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后需要重新执行 iOS 27 本机 Remote Pairing。")
        }
    }
}
