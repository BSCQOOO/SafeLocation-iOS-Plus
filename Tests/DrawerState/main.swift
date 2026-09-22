import Foundation

// Exercise transitions that used to corrupt the saved detent or start another
// presentation. A second focus/cancel must be idempotent, at every detent.
for startingDetent in DrawerState.Detent.allCases {
    var state = DrawerState()
    state.browse(startingDetent)
    for _ in 0..<1000 {
        state.beginSearch()
        state.beginSearch()
        precondition(state.isSearching && state.detent == .expanded)
        state.endSearch()
        state.endSearch()
        precondition(state.detent == startingDetent && !state.isSearching)
    }
    state.enterJoystick()
    state.beginSearch()
    state.endSearch()
    precondition(state.isJoystick)
    state.leaveJoystick()
    precondition(state.mode == .browsing(.normal))
}

for height in [CGFloat(320), 568, 667, 724, 780, 844, 932, 1200] {
    for inset in [CGFloat(0), 21, 34] {
        let layout = DrawerLayout(availableHeight: height, bottomInset: inset)
        for detent in DrawerState.Detent.allCases {
            var state = DrawerState()
            state.browse(detent)
            let h = layout.height(for: state)
            precondition(h >= DrawerLayout.headerHeight && h <= height)
            precondition(layout.nearestDetent(to: h) == detent)
            state.beginSearch()
            precondition(layout.height(for: state) == layout.expandedHeight)
            state.endSearch()
            precondition(layout.height(for: state) == h)
        }
        precondition(layout.clampedHeight(-10000) == layout.collapsedHeight)
        precondition(layout.clampedHeight(10000) == layout.expandedHeight)
    }
}
print("Drawer state/geometry passed: 3,000 rapid search/cancel cycles and 24 viewport configurations")
