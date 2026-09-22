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
                    Text("纯 4G/5G 模式需要两个系统快捷指令。默认名称为“SafeLocation Airplane On”和“SafeLocation Airplane Off”。前者只添加“设置飞行模式：打开”，后者只添加“设置飞行模式：关闭”。不要使用“关闭蜂窝数据”动作；Developer Tunnel 的无 Wi-Fi 路径需要先保留蜂窝数据建立 LocalDevVPN，再切到飞行模式。")
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

                Section("导入与快捷调用") {
                    Text("主界面搜索框右侧的剪贴板按钮可直接读取经纬度、Apple 地图链接、Google 地图链接或普通地点名称。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("快捷指令仍可使用 safelocation:// URL Scheme；1.1 还支持 timer 和 panic 命令。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("安全与恢复") {
                    Button("立即恢复真实定位", role: .destructive) { session.emergencyRestore() }
                    if session.autoRestoreDisplay != nil {
                        Button("取消自动恢复", role: .destructive) {
                            session.configureAutoRestore(minutes: nil)
                        }
                    }
                    Button("删除本机 RPPairing", role: .destructive) { confirmRemovePairing = true }
                    Text("RPPairing 只保存在 App 的 Application Support 目录，并设置为当前 App 私有文件。不要把 pairing 文件分享给他人。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("兼容性") {
                    Text("Safe Location 使用 Apple Developer DVT LocationSimulation。它不是硬件 GNSS 伪装；部分 App 能识别软件模拟定位。本项目不隐藏模拟标记，也不绕过第三方风控或反作弊。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("关于") {
                    LabeledContent("版本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                    if let commit = Bundle.main.object(forInfoDictionaryKey: "SafeLocationCommit") as? String {
                        LabeledContent("构建", value: String(commit.prefix(12)))
                    }
                    LabeledContent("最低系统", value: "iOS 18")
                    LabeledContent("Liquid Glass", value: "iOS 26+ 原生 / 旧版兼容")
                    LabeledContent("重点适配", value: "iOS 27")
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
