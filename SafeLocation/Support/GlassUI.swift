import SwiftUI

/// Uses Apple's native Liquid Glass where available, while keeping the project
/// deployable to older iOS versions supported by Safe Location.
extension View {
    @ViewBuilder
    func safeGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func safeGlassInteractive<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .safeGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct SafeGlassContainer<Content: View>: View {
    let spacing: CGFloat?
    let content: Content

    init(spacing: CGFloat? = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}


struct AppleMapsPanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Rectangle()
                    .fill(Color.clear)
                    .glassEffect(.regular, in: Rectangle())
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(
                                    colorScheme == .dark ? 0.055 : 0.12
                                ),
                                Color.white.opacity(
                                    colorScheme == .dark ? 0.018 : 0.035
                                )
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    }
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
    }
}


struct AppleMapsSheetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Rectangle()
                    .fill(Color.clear)
                    .glassEffect(.regular, in: Rectangle())
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(
                                    colorScheme == .dark ? 0.055 : 0.12
                                ),
                                Color.white.opacity(
                                    colorScheme == .dark ? 0.018 : 0.035
                                )
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    }
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
        .ignoresSafeArea()
    }
}
