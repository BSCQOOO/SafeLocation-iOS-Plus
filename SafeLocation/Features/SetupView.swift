import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var pairService: PairOnDeviceService
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    checklist
                    pairingCard
                    vpnCard
                    finishCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("首次设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { pairing.refresh(); dismiss() }
                        .disabled(!pairing.hasPairingFile)
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data, .propertyList, .xml],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                try pairing.importPairing(from: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("设置失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: pairService.phase) { _, phase in
            if phase == .succeeded { pairing.refresh() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.viewfinder")
                .font(.system(size: 42, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text("Safe Location")
                .font(.title2.bold())
            Text("iOS 27 本机 DVT 定位模拟。无需越狱，也不使用 HTTPS MITM。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("开启 设置 → 隐私与安全性 → 开发者模式", systemImage: "1.circle.fill")
            Label("完成本机 Remote Pairing", systemImage: "2.circle.fill")
            Label("安装并连接 LocalDevVPN", systemImage: "3.circle.fill")
        }
        .font(.subheadline)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("本机配对", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                statusPill(pairing.hasPairingFile ? "已配对" : "未配对", ok: pairing.hasPairingFile)
            }

            phaseContent

            if !pairService.isBusy {
                Button {
                    pairService.start(pairingStore: pairing)
                } label: {
                    Label(pairing.hasPairingFile ? "重新本机配对" : "开始本机配对", systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            DisclosureGroup("高级：导入已有 RPPairing") {
                VStack(spacing: 10) {
                    Button("从文件导入") { showImporter = true }
                    Button("从剪贴板导入") {
                        do { try pairing.importPairingFromClipboard() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            .font(.footnote)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch pairService.phase {
        case .idle:
            Text("点“开始本机配对”，然后打开“设置 → 隐私与安全性 → 开发者模式 → Pair with Host”。")
                .foregroundStyle(.secondary)
        case .advertising:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView()
                Text("正在等待系统发现 Safe Location…")
                Text("现在切到系统设置里的 Pair with Host。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .deviceConnected:
            Label("系统已连接，正在生成 6 位配对码…", systemImage: "checkmark.circle")
        case .awaitingPIN(let pin):
            VStack(alignment: .leading, spacing: 8) {
                Text("配对码")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(pin)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                Text("在 iOS 的 Pair with Host 页面输入这个号码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .succeeded:
            Label("配对成功，RPPairing 已安全保存在本机。", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("配对失败", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("重置状态") { pairService.resetToIdle() }
            }
        }
    }

    private var vpnCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("LocalDevVPN", systemImage: "network")
                    .font(.headline)
                Spacer()
                statusPill(LocalDevVPN.isConnected ? "已连接" : (LocalDevVPN.isInstalled ? "已安装" : "未安装"), ok: LocalDevVPN.isConnected)
            }
            Text("它只提供本机开发者 Tunnel，让 Safe Location 能连接 iOS 的 DVT 服务。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                LocalDevVPN.openOrInstall()
            } label: {
                Label(LocalDevVPN.isInstalled ? "打开并连接 LocalDevVPN" : "安装 LocalDevVPN", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var finishCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("准备完成", systemImage: "checkmark.shield.fill")
                .font(.headline)
            Text("配对完成并连接 LocalDevVPN 后，回到地图选点，点击 Teleport。需要恢复时点“恢复真实”。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statusPill(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ok ? .green : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
