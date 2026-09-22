import Foundation

/// The main panel has no dismissed state. Modal presentation and keyboard
/// visibility are deliberately not part of its lifetime.
struct DrawerState: Equatable {
    enum Detent: String, CaseIterable {
        case collapsed, normal, expanded
    }

    enum Mode: Equatable {
        case browsing(Detent)
        case searching(returnTo: Detent)
        case joystick
    }

    private(set) var mode: Mode = .browsing(.collapsed)

    var isSearching: Bool {
        if case .searching = mode { return true }
        return false
    }

    var isJoystick: Bool { mode == .joystick }

    var detent: Detent {
        switch mode {
        case .browsing(let detent): return detent
        case .searching: return .expanded
        case .joystick: return .normal
        }
    }

    mutating func beginSearch() {
        guard case .browsing(let detent) = mode else { return }
        mode = .searching(returnTo: detent)
    }

    mutating func endSearch() {
        guard case .searching(let previous) = mode else { return }
        mode = .browsing(previous)
    }

    mutating func browse(_ detent: Detent) {
        mode = .browsing(detent)
    }

    mutating func enterJoystick() { mode = .joystick }
    mutating func leaveJoystick() { mode = .browsing(.normal) }
}

/// All positions are relative to the containing view, never UIScreen bounds.
struct DrawerLayout {
    static let grabberHeight: CGFloat = 22
    static let searchHeaderHeight: CGFloat = 66
    static let headerHeight: CGFloat =
        grabberHeight + searchHeaderHeight
    let availableHeight: CGFloat
    let bottomInset: CGFloat

    var collapsedHeight: CGFloat { min(availableHeight, Self.headerHeight + bottomInset) }
    var expandedHeight: CGFloat { max(collapsedHeight, availableHeight - 8) }

    func height(for state: DrawerState) -> CGFloat {
        if state.isJoystick { return min(expandedHeight, 278 + bottomInset) }
        return height(for: state.detent)
    }

    func height(for detent: DrawerState.Detent) -> CGFloat {
        switch detent {
        case .collapsed: return collapsedHeight
        case .normal: return min(expandedHeight, max(collapsedHeight, availableHeight * 0.47))
        case .expanded: return expandedHeight
        }
    }

    func clampedHeight(_ height: CGFloat) -> CGFloat {
        min(expandedHeight, max(collapsedHeight, height))
    }

    func nearestDetent(to height: CGFloat) -> DrawerState.Detent {
        DrawerState.Detent.allCases.min {
            abs(self.height(for: $0) - height) < abs(self.height(for: $1) - height)
        } ?? .collapsed
    }
}
