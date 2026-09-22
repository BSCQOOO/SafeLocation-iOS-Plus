import SwiftUI
import UIKit

/// Shared by the real map screen and the simulator interaction tests.
struct MapPanelWorkspace<MapContent: View, Controls: View, Header: View, Content: View>: View {
    @Binding var state: DrawerState
    @State private var keyboardOverlap: CGFloat = 0
    @ViewBuilder let map: () -> MapContent
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { proxy in
            let fullHeight = proxy.size.height + proxy.safeAreaInsets.bottom
            let layout = DrawerLayout(availableHeight: fullHeight, bottomInset: proxy.safeAreaInsets.bottom)
            ZStack(alignment: .bottom) {
                map().ignoresSafeArea()
                if !state.isSearching && state.detent != .expanded {
                    controls()
                        .padding(.horizontal, 12)
                        .padding(.bottom, layout.height(for: state) + 12)
                }
                PersistentMapPanel(state: $state, layout: layout, keyboardOverlap: keyboardOverlap, header: header) {
                    content(proxy.safeAreaInsets.bottom)
                }
            }
            .frame(width: proxy.size.width, height: fullHeight, alignment: .bottom)
            .background {
                KeyboardFrameReader { overlap, animation in
                    guard keyboardOverlap != overlap else { return }
                    withAnimation(animation) { keyboardOverlap = overlap }
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .ignoresSafeArea(.keyboard)
    }
}

/// A permanent sibling of the map, not a presented view controller. Its only
/// moving dimension is height; keyboard layout cannot move its top/header.
struct PersistentMapPanel<Header: View, Content: View>: View {
    @Binding var state: DrawerState
    let layout: DrawerLayout
    let keyboardOverlap: CGFloat
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var translation: CGFloat = 0

    private var visibleHeight: CGFloat {
        let drag = state.isSearching || state.isJoystick ? 0 : translation
        return layout.clampedHeight(layout.height(for: state) - drag)
    }

    private var searchHeaderRegionHeight: CGFloat {
        guard !state.isJoystick else { return 0 }

        // Apple Maps keeps the collapsed search capsule visually centered in
        // the glass drawer above the home-indicator area. In larger detents
        // the same header instance snaps back to the compact top region.
        let collapsedSafeArea =
            state.detent == .collapsed && !state.isSearching
            ? layout.bottomInset
            : 0

        return DrawerLayout.searchHeaderHeight + collapsedSafeArea
    }

    private var contentHeight: CGFloat {
        let chromeHeight =
            DrawerLayout.grabberHeight +
            searchHeaderRegionHeight
        let bottomAvoidance =
            state.isSearching
            ? max(keyboardOverlap, layout.bottomInset)
            : 0
        return max(
            0,
            visibleHeight - chromeHeight - bottomAvoidance
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.45))
                .frame(width: 34, height: 4)
                .frame(maxWidth: .infinity)
                .frame(height: DrawerLayout.grabberHeight)
                .contentShape(Rectangle())
                .gesture(resizeGesture)
                .accessibilityLabel("调整功能面板高度")
                .accessibilityIdentifier("drawer.handle")
#if DEBUG
                .accessibilityValue("mode=\(state.detent.rawValue) overlap=\(keyboardOverlap) height=\(visibleHeight) content=\(contentHeight)")
#endif
                .accessibilityAdjustableAction { direction in
                    guard !state.isJoystick else { return }
                    let detents = DrawerState.Detent.allCases
                    let index = detents.firstIndex(of: state.detent) ?? 0
                    let next = direction == .increment ? min(index + 1, 2) : max(index - 1, 0)
                    move(to: detents[next])
                }

            // Never switch this header between separate collapsed/expanded
            // branches: doing so destroys the focused UITextField.
            header()
                .frame(
                    height: searchHeaderRegionHeight,
                    alignment: .center
                )

            // Only the result viewport follows the keyboard. Its parent and
            // header keep their geometry, and all content stays in SwiftUI.
            // Propose the final viewport size directly to the scroll view.
            // An intermediate full-height GeometryReader leaves a larger
            // scrolling/accessibility container behind the keyboard.
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .frame(height: contentHeight, alignment: .top)
                .clipped()
            .opacity(visibleHeight > layout.collapsedHeight + 1 || state.isJoystick ? 1 : 0)
            .allowsHitTesting(state.detent != .collapsed || state.isJoystick)
            .accessibilityHidden(state.detent == .collapsed && !state.isJoystick)
        }
        .frame(height: visibleHeight, alignment: .top)
        .background {
            AppleMapsPanelBackground()
                // Empty glass areas consume taps instead of selecting the map.
                .contentShape(Rectangle())
                .onTapGesture {}
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, y: -2)
        .padding(.horizontal, 8)
    }

    private var resizeGesture: some Gesture {
        // The grabber moves during this gesture. Measure in the fixed window
        // space so its own movement cannot feed back into the translation.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($translation) { value, translation, _ in
                guard !state.isJoystick, !state.isSearching else { return }
                translation = value.translation.height
            }
            .onEnded { value in
                guard !state.isJoystick else { return }
                if state.isSearching {
                    // Search stays anchored while the keyboard is active.
                    // A deliberate downward grab exits search once.
                    if value.translation.height > 44 {
                        withAnimation(panelAnimation(reduceMotion: reduceMotion)) { state.endSearch() }
                    }
                    return
                }
                let proposed = layout.height(for: state) - value.predictedEndTranslation.height
                move(to: layout.nearestDetent(to: proposed))
            }
    }

    private func move(to detent: DrawerState.Detent) {
        withAnimation(panelAnimation(reduceMotion: reduceMotion)) { state.browse(detent) }
    }
}

func panelAnimation(reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : .smooth(duration: 0.32)
}

/// Focus is an adapter to the drawer state, not a second detent controller.
/// Losing focus (interactive keyboard dismissal, backgrounding, modal) never
/// collapses the panel. Only an explicit cancel/selection/drag ends search.
struct MapSearchHeader<Actions: View>: View {
    @Binding var state: DrawerState
    @Binding var query: String
    var isResolving = false
    let onSubmit: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let actions: () -> Actions
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var horizontalInset: CGFloat {
        state.detent == .collapsed && !state.isSearching
            ? 20
            : 16
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索地点、坐标或地图链接", text: $query)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("drawer.search")
                .onSubmit(onSubmit)

            if isResolving { ProgressView().controlSize(.small) }
            if state.isSearching {
                Button("取消", action: onCancel)
                    .font(.subheadline.bold())
                    .accessibilityIdentifier("drawer.cancel")
            } else {
                actions()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .safeGlassInteractive(in: Capsule())
        .contentShape(Capsule())
        .padding(.horizontal, horizontalInset)
        .frame(height: DrawerLayout.searchHeaderHeight)
        .onChange(of: focused) { _, isFocused in
            guard isFocused, !state.isSearching else { return }
            withAnimation(panelAnimation(reduceMotion: reduceMotion)) { state.beginSearch() }
        }
        .onChange(of: state.isSearching) { _, searching in
            focused = searching
        }
    }
}

/// A passive, permanently mounted reader. It measures system keyboard frames
/// in this workspace's coordinate space, including window/rotation offsets.
/// It never presents a controller, changes focus or writes to DrawerState.
private struct KeyboardFrameReader: UIViewRepresentable {
    let onChange: (CGFloat, Animation?) -> Void

    func makeUIView(context: Context) -> KeyboardFrameView {
        KeyboardFrameView(onChange: onChange)
    }

    func updateUIView(_ view: KeyboardFrameView, context: Context) {
        view.onChange = onChange
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: KeyboardFrameView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

@MainActor
private final class KeyboardFrameView: UIView {
    var onChange: (CGFloat, Animation?) -> Void
    private var keyboardFrame: CGRect?
    private var lastOverlap: CGFloat?

    init(onChange: @escaping (CGFloat, Animation?) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        isUserInteractionEnabled = false
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-panel-layout-diagnostics") {
            isAccessibilityElement = true
            accessibilityIdentifier = "panel.keyboardGeometry"
        }
#endif
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

#if DEBUG
    override var accessibilityValue: String? {
        get {
            guard isAccessibilityElement, let window else { return super.accessibilityValue }
            var pending: [UIView] = [window]
            var scrolls: [String] = []
            while let view = pending.popLast() {
                pending.append(contentsOf: view.subviews)
                if let scroll = view as? UIScrollView, scroll.bounds.height > 50 {
                    scrolls.append("frame=\(scroll.convert(scroll.bounds, to: window)) content=\(scroll.contentSize) inset=\(scroll.contentInset) adjusted=\(scroll.adjustedContentInset) offset=\(scroll.contentOffset)")
                }
            }
            return (super.accessibilityValue ?? "") + " scrolls=" + scrolls.joined(separator: "; ")
        }
        set { super.accessibilityValue = newValue }
    }
#endif

    override func layoutSubviews() {
        super.layoutSubviews()
        reportOverlap(animation: nil)
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let info = notification.userInfo,
              let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        keyboardFrame = frame.cgRectValue
        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
        let curve = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.intValue ?? 0
        let animation: Animation?
        if duration == 0 || UIAccessibility.isReduceMotionEnabled {
            animation = nil
        } else {
            switch curve {
            case 1: animation = .easeIn(duration: duration)
            case 2: animation = .easeOut(duration: duration)
            case 3: animation = .linear(duration: duration)
            default: animation = .easeInOut(duration: duration)
            }
        }
        reportOverlap(animation: animation)
    }

    private func reportOverlap(animation: Animation?) {
        guard let window else { return }
        var overlap: CGFloat = 0
        if let keyboardFrame {
            // This workspace is anchored to its window's bottom edge. UIKit
            // geometry on a SwiftUI representable can be transformed during
            // layout; the containing window is the stable coordinate owner.
            let local = window.convert(keyboardFrame, from: window.screen.coordinateSpace)
            let intersection = window.bounds.intersection(local)
            // An undocked/floating keyboard must not collapse the entire list.
            if !intersection.isNull,
               intersection.width >= window.bounds.width - 0.5,
               local.maxY >= window.bounds.maxY - 0.5 {
                overlap = intersection.height
            }
        }
#if DEBUG
        if isAccessibilityElement {
            accessibilityValue = "reader=\(bounds) window=\(window.bounds) keyboard=\(String(describing: keyboardFrame)) overlap=\(overlap)"
        }
#endif
        let scale = window.screen.scale
        overlap = (overlap * scale).rounded() / scale
        guard lastOverlap != overlap else { return }
        lastOverlap = overlap
        // Deliver outside a UIKit layout pass. Reader bounds are independent
        // of this value, so this is a one-way geometry update, not a layout loop.
        // No delay, retry, polling or view recreation is involved.
        DispatchQueue.main.async { [weak self] in
            self?.onChange(overlap, animation)
        }
    }
}
