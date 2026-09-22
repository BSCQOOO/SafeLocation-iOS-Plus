import SwiftUI

struct AutoRestoreSheet: View {
    @EnvironmentObject private var session: SpoofController
    @Environment(\.dismiss) private var dismiss
    @State private var customMinutes = 90

    var body: some View {
        NavigationStack {
            List {
                if let display = session.autoRestoreDisplay {
                    Section("当前") {
                        HStack {
                            Label(session.isSpoofing ? "自动恢复倒计时" : "下次 Teleport", systemImage: "timer")
                            Spacer()
                            Text(display).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Button("取消自动恢复", role: .destructive) {
                            session.configureAutoRestore(minutes: nil)
                        }
                    }
                }

                Section("快捷时间") {
                    ForEach([15, 30, 60, 120, 240], id: \.self) { minutes in
                        Button {
                            session.configureAutoRestore(minutes: minutes)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "clock.badge.checkmark")
                                Text(label(for: minutes))
                                Spacer()
                            }
                        }
                    }
                }

                Section("自定义") {
                    Stepper(value: $customMinutes, in: 5...720, step: 5) {
                        Text("\(customMinutes) 分钟")
                    }
                    Button("应用自定义时间") {
                        session.configureAutoRestore(minutes: customMinutes)
                        dismiss()
                    }
                }

            }
            .navigationTitle("自动恢复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }

    private func label(for minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }
}
