import SwiftUI

struct JoystickSheet: View {
    @EnvironmentObject private var session: SpoofController
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("速度", selection: $session.travelMode) {
                    ForEach(SpoofController.TravelMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if let coordinate = session.simulatedCoordinate {
                    VStack(spacing: 4) {
                        Text(session.status.title).font(.headline)
                        Text(SpoofController.coordinateLabel(coordinate))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("摇杆会从当前选中位置或真实位置开始。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                JoystickPad { vector in
                    if !session.isJoystickActive { session.startJoystick(pairing: pairing) }
                    session.setJoystickVector(vector)
                } onEnd: {
                    session.setJoystickVector(.zero)
                }
                .frame(maxWidth: 260)

                HStack(spacing: 12) {
                    Button {
                        if session.isJoystickActive { session.stopJoystick() }
                        else { session.startJoystick(pairing: pairing) }
                    } label: {
                        Label(session.isJoystickActive ? "暂停摇杆" : "启动摇杆", systemImage: session.isJoystickActive ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if session.isSpoofing {
                        Button(role: .destructive) {
                            session.restoreRealLocation()
                            dismiss()
                        } label: {
                            Label("恢复", systemImage: "location.slash.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("摇杆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }
}
