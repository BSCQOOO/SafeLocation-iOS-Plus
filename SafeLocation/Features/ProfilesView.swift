import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var session: SpoofController
    @Environment(\.dismiss) private var dismiss
    let onSelect: (LocationProfile) -> Void

    @State private var showCreate = false

    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionTitle("快捷城市", subtitle: "选择后回到地图，再点击 Teleport")
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(LocationProfileStore.builtIns) { profile in
                            profileCard(profile, custom: false)
                        }
                    }

                    sectionTitle("我的位置方案", subtitle: "可保存移动方式和自动恢复时间")
                    if session.customProfiles.isEmpty {
                        ContentUnavailableView(
                            "还没有自定义方案",
                            systemImage: "square.stack.3d.up",
                            description: Text("先在地图上选一个位置，再点右上角 + 保存。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(session.customProfiles) { profile in
                                profileCard(profile, custom: true)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("位置方案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                        .disabled(session.selectedCoordinate == nil)
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateProfileSheet()
                .environmentObject(session)
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func profileCard(_ profile: LocationProfile, custom: Bool) -> some View {
        Button {
            onSelect(profile)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: profile.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .safeGlass(in: Circle())
                    Spacer()
                    if custom {
                        Menu {
                            Button("删除方案", role: .destructive) { session.removeProfile(profile) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name).font(.subheadline.bold()).lineLimit(1)
                    Text(profile.subtitle.isEmpty ? SpoofController.coordinateLabel(profile.coordinate) : profile.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Image(systemName: "clock")
                    Text(profile.restoreDescription)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 134, alignment: .leading)
            .safeGlassInteractive(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CreateProfileSheet: View {
    @EnvironmentObject private var session: SpoofController
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var restoreMinutes = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("当前位置") {
                    LabeledContent("名称", value: session.selectedName)
                    if let coordinate = session.selectedCoordinate {
                        LabeledContent("坐标") {
                            Text(SpoofController.coordinateLabel(coordinate)).monospacedDigit()
                        }
                    }
                }

                Section("方案") {
                    TextField("方案名称", text: $name)
                    Picker("移动方式", selection: $session.travelMode) {
                        ForEach(SpoofController.TravelMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    Picker("自动恢复", selection: $restoreMinutes) {
                        Text("关闭").tag(0)
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                        Text("1 小时").tag(60)
                        Text("2 小时").tag(120)
                        Text("4 小时").tag(240)
                    }
                }
            }
            .navigationTitle("保存位置方案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        session.saveCurrentAsProfile(
                            name: name.isEmpty ? session.selectedName : name,
                            autoRestoreMinutes: restoreMinutes == 0 ? nil : restoreMinutes
                        )
                        dismiss()
                    }
                    .disabled(session.selectedCoordinate == nil)
                }
            }
        }
    }
}
