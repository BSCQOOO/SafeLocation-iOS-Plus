import SwiftUI

@main
struct PanelHarnessApp: App {
    var body: some Scene { WindowGroup { PanelHarnessView().preferredColorScheme(.dark) } }
}

private enum Page: String, Identifiable, CaseIterable {
    case settings, places, profiles, route, timer, setup
    var id: String { rawValue }
}

private struct PanelHarnessView: View {
    @State private var drawer = DrawerState()
    @State private var query = ""
    @State private var page: Page?
    @State private var updates = 0
    @State private var mapTaps = 0

    var body: some View {
        MapPanelWorkspace(state: $drawer) {
            Color.blue.opacity(0.25)
                .overlay(alignment: .top) { Text("Map taps: \(mapTaps)").accessibilityIdentifier("map.taps") }
                .onTapGesture { mapTaps += 1 }
        } controls: {
            HStack {
                Button("3D") { updates += 1 }.accessibilityIdentifier("map.control")
                Spacer()
                Text("Updates: \(updates)")
            }
        } header: {
            if !drawer.isJoystick {
                MapSearchHeader(state: $drawer, query: $query, onSubmit: {}, onCancel: cancel) {
                    Menu("更多") {
                        ForEach(Page.allCases) { item in
                            Button(item.rawValue) { page = item }
                        }
                    }
                    .accessibilityIdentifier("drawer.more")
                }
            }
        } content: { bottomInset in
            if drawer.isSearching {
                ScrollView {
                    VStack {
                        ForEach(0..<30) { index in
                            Text("Result \(index)").frame(maxWidth: .infinity).frame(height: 44)
                        }
                        Button("Last result") { cancel() }.accessibilityIdentifier("search.last")
                    }
                }
                .accessibilityIdentifier("search.results")
                .scrollDismissesKeyboard(.interactively)
            } else if drawer.isJoystick {
                Button("退出摇杆") { drawer.leaveJoystick() }.accessibilityIdentifier("joystick.exit")
            } else {
                ScrollView {
                    VStack(spacing: 22) {
                        Button("Publish session update") { updates += 1 }.accessibilityIdentifier("session.update")
                        Button("Joystick") { drawer.enterJoystick() }.accessibilityIdentifier("joystick.enter")
                        ForEach(Page.allCases) { item in
                            Button(item.rawValue) { page = item }.accessibilityIdentifier("open.\(item.rawValue)")
                        }
                    }
                    .padding(.bottom, bottomInset)
                }
            }
        }
        .sheet(item: $page) { item in TestSecondaryPage(name: item.rawValue) }
    }

    private func cancel() { withAnimation(.smooth(duration: 0.32)) { drawer.endSearch() } }
}

private struct TestSecondaryPage: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var showNested = false

    var body: some View {
        NavigationStack {
            Button("Open nested") { showNested = true }.accessibilityIdentifier("secondary.nested")
                .navigationTitle(name)
                .toolbar {
                    Button("Done") { dismiss() }.accessibilityIdentifier("secondary.done")
                }
        }
        .sheet(isPresented: $showNested) {
            Button("Close nested") { showNested = false }.accessibilityIdentifier("nested.done")
        }
    }
}
