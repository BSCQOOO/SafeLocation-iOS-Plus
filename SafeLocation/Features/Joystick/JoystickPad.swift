import SwiftUI

struct JoystickPad: View {
    let onVectorChanged: (CGVector) -> Void
    let onEnd: () -> Void

    @State private var knobOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side * 0.34

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: side * 0.38, height: side * 0.38)
                    .offset(knobOffset)
                    .shadow(radius: 10, y: 5)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        var dx = value.location.x - center.x
                        var dy = value.location.y - center.y
                        let distance = hypot(dx, dy)
                        if distance > radius {
                            dx = dx / distance * radius
                            dy = dy / distance * radius
                        }
                        knobOffset = CGSize(width: dx, height: dy)
                        onVectorChanged(CGVector(dx: dx / radius, dy: dy / radius))
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.76)) {
                            knobOffset = .zero
                        }
                        onVectorChanged(.zero)
                        onEnd()
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("虚拟摇杆")
    }
}
