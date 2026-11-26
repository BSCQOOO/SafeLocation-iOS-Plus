import SwiftUI
import UniformTypeIdentifiers

/// Phase-0/1 implementation: real read-only checks and staging. A signing
/// engine is deliberately not simulated, and no Apple credentials are accepted.
struct SigningManagementView: View {
    @EnvironmentObject private var session: SpoofController
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var pairService: PairOnDeviceService
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(TunnelProvider.preferenceKey) private var provider: TunnelProvider = .localDevVPN
    @AppStorage(ExpiryReminder.enabledKey) private var remindersEnabled = false
    @State private var profile: ProfileMetadata?
    @State private var packages: [StagedPackage] = []
    @State private var report: InstallationServiceProbe.Report?
    @State private var probing = false
    @State private var importing = false
    @State private var showingImporter = false
    @State private var checkingRelease = false
    @State private var release: ReleaseCatalog.Release?
    @State private var releaseStatus = "尚未检查"
    @State private var message: String?
    @State private var deleteCandidate: StagedPackage?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    var body: some View {
        Form {
            Section {
                Label("3.0 技术验证版", systemImage: "hammer")
                    .foregroundStyle(.orange)
                Text("本页提供实际描述文件读取、安装服务检查、IPA 暂存和版本查询。尚未接入 Apple 账号认证、证书签发或签名安装引擎，不能续签应用。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("SafeLocation 当前签名") {
                LabeledContent("版本", value: version)
                if let profile {
                    LabeledContent("描述文件到期") {
                        Text(profile.expiration.formatted(date: .abbreviated, time: .shortened))
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("剩余有效时间", value: remaining(profile.expiration))
                    if let team = profile.teamIdentifier {
                        LabeledContent("Team", value: "…"+String(team.suffix(4)))
                    }
                    Text("仅解析本机描述文件中的元数据，不代表验证证书、CMS 签名或吊销状态。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("未找到可解析的 embedded.mobileprovision。未签名包或部分签名方式可能没有该文件。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("重新读取描述文件") { profile = ProfileMetadata.current() }
                Button("设置到期通知（3 天、1 天、6 小时）") {
                    guard let profile else { return }
                    Task {
                        do {
                            let count = try await ExpiryReminder.schedule(expiration: profile.expiration)
                            remindersEnabled = UserDefaults.standard.bool(forKey: ExpiryReminder.enabledKey)
                            message = count > 0 ? "已安排 \(count) 条通知。" : "没有可安排的未来提醒，或未取得通知权限。"
                        } catch { message = error.localizedDescription }
                    }
                }
                .disabled(profile == nil)
                if remindersEnabled {
                    Button("关闭到期通知") {
                        remindersEnabled = false
                        ExpiryReminder.clear()
                    }
                }
            }

            Section("本机安装通道") {
                LabeledContent("当前隧道", value: provider.title)
                LabeledContent("RPPairing 文件", value: pairing.hasPairingFile ? "存在" : "未配置")
                if InstallationServiceProbe.initialAFCStatus == .unavailable {
                    Text("当前底层库缺少 AFC 实现，暂不能测试文件传输。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if InstallationServiceProbe.initialInstallationStatus == .unavailable {
                    Text("当前底层库缺少 InstallationProxy 实现，暂不能测试安装服务。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    report = nil
                    probing = true
                    Task {
                        report = await session.probeInstallation(pairing: pairing)
                        probing = false
                    }
                } label: {
                    HStack {
                        Text("检查 RSD / AFC / InstallationProxy")
                        if probing { Spacer(); ProgressView() }
                    }
                }
                .disabled(probing || !pairing.hasPairingFile || pairService.isBusy || !session.canProbeInstallation)
                if let report {
                    checkRow("读取 RPPairing", report.pairingRead)
                    checkRow("认证后的 RSD 隧道", report.authenticatedTunnel)
                    LabeledContent("AFC 服务连接", value: report.afc.rawValue)
                    LabeledContent("InstallationProxy 服务连接", value: report.installationProxy.rawValue)
                    Text(report.detail).font(.caption).foregroundStyle(.secondary)
                }
                Text("先恢复真实定位，再运行检查。检查只连接服务，不上传 IPA、不修改设备应用或配对记录。底层调用可能耗时，离开页面不会取消正在执行的 FFI 调用。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("IPA 暂存区") {
                Button {
                    showingImporter = true
                } label: {
                    HStack {
                        Label("导入 IPA", systemImage: "plus")
                        if importing { Spacer(); ProgressView() }
                    }
                }.disabled(importing)
                if packages.isEmpty { Text("暂无暂存包").foregroundStyle(.secondary) }
                ForEach(packages) { package in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(package.name).font(.subheadline.weight(.medium))
                        Text(ByteCountFormatter.string(fromByteCount: package.bytes, countStyle: .file)).font(.caption)
                        Text("SHA-256: " + package.sha256)
                            .font(.caption2.monospaced()).textSelection(.enabled)
                        Button("移除暂存包", role: .destructive) { deleteCandidate = package }
                            .font(.caption).disabled(importing)
                    }
                }
                Text("最多暂存 4 个包、单包 512 MB、总计 1 GB。当前仅检查 ZIP 文件头并计算哈希，不验证 IPA 内容、签名或可安装性。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("软件更新") {
                Button {
                    checkingRelease = true
                    release = nil
                    releaseStatus = "查询中…"
                    Task {
                        defer { checkingRelease = false }
                        do {
                            let value = try await ReleaseCatalog.latest()
                            release = value
                            if let newer = ReleaseCatalog.isNewer(value.tag_name, than: version) {
                                releaseStatus = newer ? "发现新版本" : "没有更高版本号"
                            } else { releaseStatus = "发布标签无法自动比较" }
                        } catch { releaseStatus = error.localizedDescription }
                    }
                } label: {
                    HStack {
                        Text("检查 GitHub 正式版本")
                        if checkingRelease { Spacer(); ProgressView() }
                    }
                }.disabled(checkingRelease)
                LabeledContent("状态", value: releaseStatus)
                if let release {
                    LabeledContent("发布标签", value: release.tag_name)
                    Link("查看该版本及资源", destination: release.html_url)
                    ForEach(Array(release.assets.enumerated()), id: \.offset) { _, asset in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(asset.name)
                            Text(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file)).font(.caption)
                            if let digest = asset.digest {
                                Text(digest).font(.caption2.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                }
                Link("打开官方 Releases", destination: ReleaseCatalog.releasesPage)
                Text("当前只查询正式发布与列出资源。自动下载、可信清单校验和覆盖安装尚未启用。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("签名引擎（未接入）") {
                LabeledContent("Apple Account", value: "未实现")
                LabeledContent("证书与描述文件申请", value: "未实现")
                LabeledContent("本地重新签名", value: "未实现")
                LabeledContent("自身续签与更新安装", value: "未实现")
                Text("在真机安装通道验证、依赖许可证审查和签名引擎接入完成之前，不收集账号密码，也不展示虚假的续签成功状态。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("签名与应用管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { profile = ProfileMetadata.current() }
            else { report = nil }
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
                      allowsMultipleSelection: false) { result in
            importing = true
            Task {
                defer { importing = false }
                do {
                    guard let url = try result.get().first else { return }
                    _ = try await PackageVault.shared.stage(url)
                    packages = try await PackageVault.shared.list()
                } catch { message = error.localizedDescription }
            }
        }
        .confirmationDialog("移除这个暂存包？不会卸载设备上的应用。", isPresented: Binding(
            get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }
        ), titleVisibility: .visible, presenting: deleteCandidate) { candidate in
            Button("移除", role: .destructive) {
                Task {
                    do {
                        try await PackageVault.shared.remove(candidate.id)
                        packages = try await PackageVault.shared.list()
                    } catch { message = error.localizedDescription }
                }
            }
        }
        .alert("签名管理", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func reload() async {
        profile = ProfileMetadata.current()
        do { packages = try await PackageVault.shared.list() }
        catch { message = error.localizedDescription }
    }

    private func remaining(_ expiration: Date) -> String {
        let seconds = expiration.timeIntervalSinceNow
        guard seconds > 0 else { return "已到期" }
        let hours = Int(ceil(seconds / 3600))
        return "\(hours / 24) 天 \(hours % 24) 小时"
    }

    private func checkRow(_ name: String, _ ok: Bool) -> some View {
        LabeledContent(name, value: ok ? "已连接/已读取" : "未通过或未执行")
    }
}
