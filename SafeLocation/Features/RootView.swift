import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct RootView: View {
    private enum MapTrackingMode {
        case free
        case centered
        case heading
    }

    private static let peekDetent: PresentationDetent = .height(76)
    private static let mediumDetent: PresentationDetent = .fraction(0.47)
    private static let joystickDetent: PresentationDetent = .height(278)

    @EnvironmentObject private var session: SpoofController
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var pairService: PairOnDeviceService
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var search = SearchController()
    @StateObject private var mapLocation = MapLocationProvider()

    @State private var position: MapCameraPosition = .automatic
    @State private var controlSheetPresented = false
    @State private var controlSheetVisible = false
    @State private var controlSheetRecoveryGeneration = 0
    @State private var searchExpansionGeneration = 0
    @State private var drawerDetent: PresentationDetent = Self.peekDetent
    @State private var detentBeforeSearch: PresentationDetent = Self.peekDetent

    @State private var showSettings = false
    @State private var showSetup = false
    @State private var showPlaces = false
    @State private var showProfiles = false
    @State private var showRoute = false
    @State private var showTimer = false

    @State private var showSearchResults = false
    @State private var isResolvingInput = false
    @State private var alertText: String?

    @FocusState private var searchFocused: Bool

    @State private var joystickMode = false
    @State private var followJoystick = true
    @State private var favoriteSaved = false
    @State private var suppressMapTapUntil = Date.distantPast
    @State private var isThreeD = false
    @State private var liveCamera: MapCamera?
    @State private var mapTrackingMode: MapTrackingMode = .free
    @State private var mapCoordinateSystem =
        MapCoordinateConverter.MapCoordinateSystem.gcj02

    private var searchMode: Bool {
        searchFocused || showSearchResults
    }

    private var activeDetents: Set<PresentationDetent> {
        if joystickMode {
            return [Self.joystickDetent]
        }

        return [
            Self.peekDetent,
            Self.mediumDetent,
            .large
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                mapLayer
                    .ignoresSafeArea()

                if !searchMode && drawerDetent != .large {
                    mapModeControls
                        .padding(.leading, 12)
                        .padding(
                            .bottom,
                            floatingControlBottomPadding(
                                screenHeight: proxy.size.height
                            )
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomLeading
                        )
                        .transition(.opacity.combined(with: .scale))

                    mapLocationButton
                        .padding(.trailing, 12)
                        .padding(
                            .bottom,
                            floatingControlBottomPadding(
                                screenHeight: proxy.size.height
                            )
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomTrailing
                        )
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.snappy(duration: 0.28), value: drawerDetent)
            .animation(.snappy(duration: 0.24), value: searchMode)
        }
        .onAppear {
            presentControlSheet()
        }
        .sheet(
            isPresented: $controlSheetPresented,
            onDismiss: {
                controlSheetVisible = false
                scheduleControlSheetRecovery()
            }
        ) {
            controlSheetContent
                .onAppear {
                    controlSheetVisible = true
                    controlSheetRecoveryGeneration += 1
                }
                .onDisappear {
                    // onDisappear also fires during legitimate UIKit
                    // presentation transitions. Never recreate from here.
                    controlSheetVisible = false
                }
                .presentationDetents(
                    activeDetents,
                    selection: $drawerDetent
                )
                .presentationDragIndicator(.visible)
                .presentationBackground {
                    AppleMapsSheetBackground()
                }
                .presentationBackgroundInteraction(.enabled)
                .presentationContentInteraction(.resizes)
                .interactiveDismissDisabled(true)
        }
        .alert(
            "Safe Location",
            isPresented: Binding(
                get: { alertText != nil || session.lastError != nil },
                set: {
                    if !$0 {
                        alertText = nil
                        session.lastError = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertText ?? session.lastError ?? "")
        }
        .task {
            session.requestLocationPermission()
            mapLocation.start()
            pairing.refresh()

            await refreshMapCoordinateSystem(
                recenterAfterChange: false
            )

            if !pairing.hasPairingFile {
                try? await Task.sleep(nanoseconds: 350_000_000)
                showSetup = true
            }

            await consumePendingImport()
        }
        .onReceive(NotificationCenter.default.publisher(for: PendingImportBridge.notification)) { _ in
            Task { await consumePendingImport() }
        }
        .onReceive(session.$simulatedCoordinate) { coordinate in
            refreshSearchCenter()

            guard joystickMode, followJoystick, let coordinate else { return }
            moveCamera(
                to: coordinate,
                latitudeDelta: 0.0055,
                animated: false
            )
        }
        .onReceive(session.$selectedCoordinate) { _ in
            refreshSearchCenter()
        }
        .onReceive(mapLocation.$location) { _ in
            refreshSearchCenter()
        }
        .onChange(of: position.positionedByUser) { _, positionedByUser in
            guard positionedByUser else { return }

            mapTrackingMode = .free

            if joystickMode {
                followJoystick = false
            }
        }
        .onChange(of: session.isSpoofing) { wasSpoofing, spoofing in
            ensureControlSheetPresented()
            mapTrackingMode = .free

            Task {
                await refreshMapCoordinateSystem(
                    recenterAfterChange: spoofing
                )

                if wasSpoofing && !spoofing {
                    await recenterAfterRealLocationRestore()
                }
            }
        }
        .onChange(of: searchFocused) { _, focused in
            guard !joystickMode else { return }

            searchExpansionGeneration += 1

            if focused {
                refreshSearchCenter()
                detentBeforeSearch = drawerDetent
                beginAppleMapsSearchExpansion(
                    generation: searchExpansionGeneration
                )
            } else if !showSearchResults {
                restoreDetentAfterSearch()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                pairing.refresh()
                mapLocation.refresh()
                session.checkAutoRestoreDeadline()
                session.recoverSessionIfNeeded(pairing: pairing)
                ensureControlSheetPresented()
                session.handleForegroundReturnFromExternalFlow(
                    pairing: pairing
                )

                Task {
                    await refreshMapCoordinateSystem(
                        recenterAfterChange: false
                    )
                    await consumePendingImport()
                }
            }
        }
    }

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $position) {
                // Use MapKit's native user-location rendering so the blue dot,
                // accuracy ring and device-heading cone match Apple Maps.
                UserAnnotation()

                if let selected = session.selectedCoordinate,
                   !coordinatesAlmostEqual(
                        selected,
                        session.simulatedCoordinate
                   ) {
                    Marker(
                        session.selectedName,
                        coordinate: mapDisplayCoordinate(
                            fromWGS84: selected
                        )
                    )
                    .tint(.blue)
                }

            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapScaleView()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                liveCamera = context.camera
                isThreeD = context.camera.pitch > 12

                if searchMode {
                    refreshSearchCenter()
                }
            }
            .onTapGesture { point in
                guard !searchMode, !joystickMode else { return }
                guard Date() >= suppressMapTapUntil else { return }

                if let coordinate = proxy.convert(
                    point,
                    from: .local
                ) {
                    selectMapPoint(coordinate)
                }
            }
        }
    }

    private var mapLocationButton: some View {
        ZStack {
            Circle()
                .fill(.clear)

            Image(
                systemName:
                    mapTrackingMode == .heading
                    ? "location.north.fill"
                    : "location.fill"
            )
                .font(
                    .system(
                        size: 18,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    mapTrackingMode == .free
                    ? Color.primary
                    : Color.blue
                )
        }
        .frame(width: 50, height: 50)
        .safeGlassInteractive(in: Circle())
        .contentShape(Circle())
        .shadow(
            color: .black.opacity(0.20),
            radius: 10,
            y: 4
        )
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    suppressMapTapUntil =
                        Date().addingTimeInterval(0.65)
                }
                .onEnded { _ in
                    suppressMapTapUntil =
                        Date().addingTimeInterval(0.65)
                    handleMapLocationButton()
                }
        )
        .accessibilityLabel("回到当前位置")
    }

    private var mapModeControls: some View {
        mapControlTextButton(
            isThreeD ? "2D" : "3D",
            accessibilityLabel: isThreeD
                ? "切换到二维地图"
                : "切换到三维地图"
        ) {
            toggleThreeD()
        }
    }

    private func mapControlTextButton(
        _ text: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        ZStack {
            Circle()
                .fill(.clear)

            Text(text)
                .font(.system(size: 16, weight: .bold))
        }
        .frame(width: 48, height: 48)
        .safeGlassInteractive(in: Circle())
        .contentShape(Circle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    suppressMapTapUntil =
                        Date().addingTimeInterval(0.65)
                }
                .onEnded { _ in
                    suppressMapTapUntil =
                        Date().addingTimeInterval(0.65)
                    action()
                }
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private var controlSheetContent: some View {
        Group {
            if joystickMode {
                joystickSheetContent
            } else {
                regularControlSheet
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(session)
                .environmentObject(pairing)
                .environmentObject(pairService)
        }
        .sheet(isPresented: $showSetup) {
            SetupView()
                .environmentObject(pairing)
                .environmentObject(pairService)
        }
        .sheet(isPresented: $showPlaces) {
            PlacesView { place in
                select(
                    place.coordinate,
                    name: place.name
                )
            }
            .environmentObject(session)
        }
        .sheet(isPresented: $showProfiles) {
            ProfilesView { profile in
                session.selectProfile(profile)
                moveCamera(to: profile.coordinate)
            }
            .environmentObject(session)
        }
        .sheet(isPresented: $showRoute) {
            RoutePlannerSheet()
                .environmentObject(session)
                .environmentObject(pairing)
        }
        .sheet(isPresented: $showTimer) {
            AutoRestoreSheet()
                .environmentObject(session)
        }
    }

    private var regularControlSheet: some View {
        let compactIdle =
            drawerDetent == Self.peekDetent &&
            !searchMode

        return VStack(spacing: 0) {
            // Only center the capsule while the drawer is truly idle. The
            // instant the field gains focus, remove the centering spacers
            // before the sheet starts expanding. This avoids the large empty
            // gray region seen when the old compact layout was carried into
            // the keyboard transition.
            if compactIdle {
                Spacer(minLength: 0)
            }

            bottomSearchBar
                .padding(
                    .horizontal,
                    compactIdle ? 20 : 16
                )
                .padding(
                    .top,
                    compactIdle ? 0 : 14
                )
                .padding(
                    .bottom,
                    compactIdle ? 0 : 12
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
                .layoutPriority(100)
                .zIndex(10)

            if compactIdle {
                Spacer(minLength: 0)
            } else if drawerDetent != Self.peekDetent || searchMode {
                Divider()
                    .opacity(0.35)

                if searchMode {
                    searchResultPanel
                } else {
                    ScrollView {
                        LazyVStack(
                            alignment: .leading,
                            spacing: 18
                        ) {
                            locationStatusSection
                            primaryActionSection
                            quickActionSection
                            secondaryActionSection
                            recentPlacesSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 28)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment:
                compactIdle
                ? .center
                : .top
        )
        .background(Color.clear)
    }

    private var bottomSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(
                "搜索地点、坐标或地图链接",
                text: $search.query
            )
            .focused($searchFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit {
                Task {
                    await resolveTypedInput(search.query)
                }
            }
            .onChange(of: search.query) { _, value in
                let hasQuery = !value
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty

                showSearchResults = hasQuery

                if hasQuery,
                   drawerDetent != .large {
                    withAnimation(.snappy(duration: 0.28)) {
                        drawerDetent = .large
                    }
                }
            }

            if isResolvingInput || search.isSearching {
                ProgressView()
                    .controlSize(.small)
            }

            if searchMode {
                Button("取消") {
                    cancelSearch()
                }
                .font(.subheadline.bold())
            } else {
                Button {
                    Task {
                        await pasteAndResolve()
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }

                Menu {
                    Button(
                        "位置与历史",
                        systemImage: "clock.arrow.circlepath"
                    ) {
                        showPlaces = true
                    }

                    Button(
                        "位置方案",
                        systemImage: "square.stack.3d.up"
                    ) {
                        showProfiles = true
                    }

                    Button(
                        "设置",
                        systemImage: "gearshape"
                    ) {
                        showSettings = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .safeGlassInteractive(in: Capsule())
        .contentShape(Capsule())
    }

    private var searchResultPanel: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if search.results.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")

                        Text(
                            search.query
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                            ? "输入地点开始搜索"
                            : "没有附近结果，继续输入或直接搜索。"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                } else {
                    ForEach(
                        Array(
                            search.results.enumerated()
                        ),
                        id: \.offset
                    ) { _, result in
                        Button {
                            let resolved = search.select(result)

                            selectMapCoordinate(
                                resolved.coordinate,
                                name: resolved.name
                            )

                            cancelSearch(
                                clearQuery: true
                            )
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            Color.blue.opacity(0.14)
                                        )
                                        .frame(
                                            width: 38,
                                            height: 38
                                        )

                                    Image(
                                        systemName: "mappin.and.ellipse"
                                    )
                                    .foregroundStyle(.blue)
                                }

                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(result.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer()

                                Image(
                                    systemName: "chevron.right"
                                )
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
        }
        .scrollIndicators(.visible)
        .scrollDismissesKeyboard(.interactively)
    }

    private var locationStatusSection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            sectionHeader("位置控制")

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            session.isSpoofing
                                ? Color.blue.opacity(0.18)
                                : Color.green.opacity(0.16)
                        )
                        .frame(
                            width: 48,
                            height: 48
                        )

                    Image(
                        systemName: session.isSpoofing
                            ? "location.fill"
                            : "location.circle.fill"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        session.isSpoofing
                            ? .blue
                            : .green
                    )
                }

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(session.status.title)
                        .font(.headline)

                    if let coordinate =
                        session.simulatedCoordinate
                        ?? mapLocation.coordinate
                        ?? session.selectedCoordinate {
                        Text(
                            SpoofController.coordinateLabel(
                                coordinate
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(
                    alignment: .trailing,
                    spacing: 4
                ) {
                    Label(
                        pairing.hasPairingFile
                            ? "已配对"
                            : "未配对",
                        systemImage:
                            pairing.hasPairingFile
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle"
                    )

                    Label(
                        LocalDevVPN.isConnected
                            ? "VPN 已连"
                            : "VPN 未连",
                        systemImage:
                            LocalDevVPN.isConnected
                            ? "network.badge.shield.half.filled"
                            : "network.slash"
                    )
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .safeGlass(
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
        }
    }

    private var primaryActionSection: some View {
        HStack(spacing: 10) {
            mainButton(
                session.isSpoofing
                    ? "移动到此处"
                    : "Teleport",
                icon: "location.fill",
                prominent: true
            ) {
                session.teleport(pairing: pairing)
            }

            mainButton(
                session.isRestoringRealLocation
                    ? "恢复中…"
                    : "恢复真实",
                icon:
                    session.isRestoringRealLocation
                    ? "arrow.clockwise"
                    : "location.slash",
                destructive: true
            ) {
                session.emergencyRestore(
                    pairingPath: pairing.pairingPath
                )
                ensureControlSheetPresented()
            }
            .disabled(session.isRestoringRealLocation)
        }
    }

    private var quickActionSection: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            sectionHeader("快捷功能")

            HStack(
                alignment: .top,
                spacing: 12
            ) {
                appleShortcut(
                    favoriteSaved ? "已收藏" : "收藏",
                    icon: favoriteSaved
                        ? "checkmark.circle.fill"
                        : "star.fill"
                ) {
                    saveFavorite()
                }

                appleShortcut(
                    "方案",
                    icon: "square.stack.3d.up.fill"
                ) {
                    showProfiles = true
                }

                appleShortcut(
                    "定时",
                    icon: "timer"
                ) {
                    showTimer = true
                }

                appleShortcut(
                    "摇杆",
                    icon: "gamecontroller.fill"
                ) {
                    enterJoystickMode()
                }
            }
        }
    }

    private var secondaryActionSection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            sectionHeader("更多")

            VStack(spacing: 0) {
                drawerRow(
                    "路线模拟",
                    subtitle: "道路路线与 GPX",
                    icon: "point.topleft.down.to.point.bottomright.curvepath"
                ) {
                    showRoute = true
                }

                Divider()
                    .padding(.leading, 52)

                drawerRow(
                    "LocalDevVPN",
                    subtitle:
                        LocalDevVPN.isConnected
                        ? "已连接"
                        : "点击打开连接",
                    icon: "network"
                ) {
                    LocalDevVPN.openOrInstall()
                }

                Divider()
                    .padding(.leading, 52)

                drawerRow(
                    "设置与诊断",
                    subtitle: "配对、Tunnel 与安全选项",
                    icon: "gearshape.fill"
                ) {
                    showSettings = true
                }
            }
            .safeGlass(
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
        }
    }

    @ViewBuilder
    private var recentPlacesSection: some View {
        if !session.recents.isEmpty {
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                HStack {
                    Text("最近位置")
                        .font(.headline)

                    Spacer()

                    Button("查看全部") {
                        showPlaces = true
                    }
                    .font(.caption.bold())
                }

                VStack(spacing: 0) {
                    ForEach(
                        Array(
                            session.recents.prefix(4)
                        )
                    ) { place in
                        Button {
                            select(
                                place.coordinate,
                                name: place.name
                            )

                            withAnimation(
                                .snappy(duration: 0.25)
                            ) {
                                drawerDetent =
                                    Self.peekDetent
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(
                                    systemName: "clock.fill"
                                )
                                .foregroundStyle(.secondary)
                                .frame(width: 28)

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(place.name)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(
                                        String(
                                            format:
                                                "%.5f, %.5f",
                                            place.latitude,
                                            place.longitude
                                        )
                                    )
                                    .font(
                                        .caption2.monospacedDigit()
                                    )
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(
                                    systemName: "chevron.right"
                                )
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if place.id != session.recents
                            .prefix(4)
                            .last?.id {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
                .safeGlass(
                    in: RoundedRectangle(
                        cornerRadius: 22,
                        style: .continuous
                    )
                )
            }
        }
    }

    private var joystickSheetContent: some View {
        VStack(spacing: 12) {
            HStack {
                Label(
                    "摇杆控制",
                    systemImage: "gamecontroller.fill"
                )
                .font(.headline)

                Spacer()

                Button {
                    followJoystick.toggle()

                    if followJoystick,
                       let coordinate =
                        session.simulatedCoordinate {
                        moveCamera(
                            to: coordinate,
                            latitudeDelta: 0.0055
                        )
                    }
                } label: {
                    Image(
                        systemName:
                            followJoystick
                            ? "scope"
                            : "map"
                    )
                    .frame(
                        width: 34,
                        height: 34
                    )
                }
                .buttonStyle(.bordered)

                Button {
                    exitJoystickMode()
                } label: {
                    Image(systemName: "xmark")
                        .frame(
                            width: 34,
                            height: 34
                        )
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 14) {
                JoystickPad { vector in
                    if !session.isJoystickActive {
                        session.startJoystick(
                            pairing: pairing
                        )
                    }

                    session.setJoystickVector(vector)
                } onEnd: {
                    session.setJoystickVector(.zero)
                }
                .frame(
                    width: 118,
                    height: 118
                )

                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {
                    Picker(
                        "速度",
                        selection: $session.travelMode
                    ) {
                        ForEach(
                            SpoofController
                                .TravelMode
                                .allCases
                        ) { mode in
                            Image(
                                systemName: mode.systemImage
                            )
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if let coordinate =
                        session.simulatedCoordinate {
                        Text("模拟位置")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(
                            SpoofController.coordinateLabel(
                                coordinate
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    }

                    Button {
                        recenterMap()
                    } label: {
                        Label(
                            "回到位置",
                            systemImage: "scope"
                        )
                    }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private func sectionHeader(
        _ title: String,
        trailing: String? = nil
    ) -> some View {
        HStack {
            Text(title)
                .font(.headline)

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func mainButton(
        _ title: String,
        icon: String,
        prominent: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) {
                Label(
                    title,
                    systemImage: icon
                )
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(
                destructive
                    ? .red
                    : .accentColor
            )
        } else {
            Button(action: action) {
                Label(
                    title,
                    systemImage: icon
                )
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 46)
            }
            .buttonStyle(.bordered)
            .tint(
                destructive
                    ? .red
                    : .accentColor
            )
        }
    }

    private func appleShortcut(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(
                            Color.blue.opacity(0.14)
                        )
                        .frame(
                            width: 56,
                            height: 56
                        )

                    Image(systemName: icon)
                        .font(.title3.bold())
                        .foregroundStyle(.blue)
                }

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func drawerRow(
        _ title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.blue)
                    .frame(
                        width: 36,
                        height: 36
                    )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(title)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func floatingControlBottomPadding(
        screenHeight: CGFloat
    ) -> CGFloat {
        if joystickMode {
            return 292
        }

        if drawerDetent == Self.mediumDetent {
            return max(
                330,
                screenHeight * 0.47 + 14
            )
        }

        return 112
    }

    private func enterJoystickMode() {
        cancelSearch(clearQuery: false)
        followJoystick = true

        if !session.isJoystickActive {
            session.startJoystick(pairing: pairing)
        }

        joystickMode = true

        DispatchQueue.main.async {
            drawerDetent = Self.joystickDetent
        }

        if let coordinate =
            session.simulatedCoordinate
            ?? session.selectedCoordinate
            ?? mapLocation.coordinate {
            moveCamera(
                to: coordinate,
                latitudeDelta: 0.0055
            )
        }
    }

    private func exitJoystickMode(
        stopSession: Bool = true
    ) {
        joystickMode = false

        if stopSession {
            session.stopJoystick()
        }

        DispatchQueue.main.async {
            withAnimation(
                .snappy(duration: 0.28)
            ) {
                drawerDetent =
                    Self.mediumDetent
            }
        }
    }

    private func recenterMap(
        forceNorth: Bool = false
    ) {
        suppressMapTapUntil =
            Date().addingTimeInterval(0.65)

        if let simulated = session.simulatedCoordinate {
            followJoystick = true

            moveCamera(
                to: simulated,
                latitudeDelta:
                    joystickMode
                    ? 0.0055
                    : 0.014,
                preserveView: true,
                headingOverride: forceNorth ? 0 : nil
            )
            return
        }

        if let real = mapLocation.bestRealCoordinate(
            maxAge: 8,
            maxHorizontalAccuracy: 80
        ) {
            moveCamera(
                to: real,
                latitudeDelta: 0.014,
                preserveView: true,
                headingOverride: forceNorth ? 0 : nil
            )
            return
        }

        mapLocation.refresh()

        Task { @MainActor in
            let waits: [UInt64] = [
                250_000_000,
                450_000_000,
                700_000_000
            ]

            for wait in waits {
                try? await Task.sleep(nanoseconds: wait)

                if let real = mapLocation.bestRealCoordinate(
                    maxAge: 5,
                    maxHorizontalAccuracy: 75
                ) {
                    moveCamera(
                        to: real,
                        latitudeDelta: 0.014,
                        preserveView: true,
                        headingOverride: forceNorth ? 0 : nil
                    )
                    return
                }
            }

            alertText =
                "暂时没有取得新的真实位置，请稍等几秒后再试。"
        }
    }

    @MainActor
    private func recenterAfterRealLocationRestore() async {
        mapLocation.refresh()

        let waits: [UInt64] = [
            180_000_000,
            320_000_000,
            520_000_000,
            800_000_000,
            1_200_000_000
        ]

        for wait in waits {
            try? await Task.sleep(
                nanoseconds: wait
            )

            if let real = mapLocation.bestRealCoordinate(
                maxAge: 4,
                maxHorizontalAccuracy: 120
            ) {
                mapTrackingMode = .centered

                let displayCoordinate =
                    mapDisplayCoordinate(
                        fromWGS84: real
                    )
                let camera = liveCamera
                let fallback = MapCameraPosition.camera(
                    MapCamera(
                        centerCoordinate: displayCoordinate,
                        distance: camera?.distance ?? 1_200,
                        heading: 0,
                        pitch: camera?.pitch ?? 0
                    )
                )

                withAnimation(
                    .snappy(duration: 0.32)
                ) {
                    position = .userLocation(
                        followsHeading: false,
                        fallback: fallback
                    )
                }
                return
            }

            mapLocation.refresh()
        }
    }

    private func handleMapLocationButton() {
        suppressMapTapUntil =
            Date().addingTimeInterval(0.65)

        switch mapTrackingMode {
        case .free:
            mapTrackingMode = .centered
            startUserLocationTracking(
                followsHeading: false
            )

        case .centered:
            mapTrackingMode = .heading
            startUserLocationTracking(
                followsHeading: true
            )

        case .heading:
            mapTrackingMode = .centered
            startUserLocationTracking(
                followsHeading: false
            )
        }
    }

    private func startUserLocationTracking(
        followsHeading: Bool
    ) {
        let fallbackCoordinate =
            session.simulatedCoordinate
            ?? mapLocation.bestCoordinate(
                maxAge: 10,
                maxHorizontalAccuracy: 120
            )
            ?? session.selectedCoordinate

        let fallback: MapCameraPosition

        if let fallbackCoordinate {
            let displayCoordinate = mapDisplayCoordinate(
                fromWGS84: fallbackCoordinate
            )
            let camera = liveCamera

            fallback = .camera(
                MapCamera(
                    centerCoordinate: displayCoordinate,
                    distance: camera?.distance ?? 1_200,
                    heading:
                        followsHeading
                        ? (mapLocation.bestDirectionDegrees ?? camera?.heading ?? 0)
                        : 0,
                    pitch: camera?.pitch ?? 0
                )
            )
        } else {
            fallback = .automatic
        }

        withAnimation(.snappy(duration: 0.30)) {
            position = .userLocation(
                followsHeading: followsHeading,
                fallback: fallback
            )
        }
    }

    private func toggleThreeD() {
        mapTrackingMode = .free

        let targetPitch: CGFloat = isThreeD ? 0 : 58

        guard let camera = liveCamera else {
            isThreeD.toggle()
            recenterMap()
            return
        }

        isThreeD.toggle()

        withAnimation(.snappy(duration: 0.34)) {
            position = .camera(
                MapCamera(
                    centerCoordinate: camera.centerCoordinate,
                    distance: camera.distance,
                    heading: camera.heading,
                    pitch: targetPitch
                )
            )
        }
    }

    private func presentControlSheet() {
        controlSheetRecoveryGeneration += 1

        guard !controlSheetPresented else {
            return
        }

        controlSheetPresented = true
    }

    private func ensureControlSheetPresented() {
        if controlSheetVisible {
            controlSheetRecoveryGeneration += 1
            return
        }

        if !controlSheetPresented {
            presentControlSheet()
            return
        }

        // A stale SwiftUI binding can say presented while the UIKit sheet is
        // actually gone. Wait for ordinary presentation animations to finish,
        // then repair that state exactly once.
        controlSheetRecoveryGeneration += 1
        let generation = controlSheetRecoveryGeneration

        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: 220_000_000
            )

            guard
                generation == controlSheetRecoveryGeneration,
                controlSheetPresented,
                !controlSheetVisible
            else {
                return
            }

            controlSheetPresented = false

            try? await Task.sleep(
                nanoseconds: 180_000_000
            )

            guard
                generation == controlSheetRecoveryGeneration
            else {
                return
            }

            controlSheetPresented = true
        }
    }

    private func scheduleControlSheetRecovery() {
        // Do not advance the generation here. ensureControlSheetPresented()
        // may intentionally toggle the stale binding to false; the resulting
        // onDismiss callback must not invalidate the very recovery that is
        // trying to present the Apple Maps drawer again.
        let generation = controlSheetRecoveryGeneration

        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: 260_000_000
            )

            guard
                generation == controlSheetRecoveryGeneration,
                !controlSheetVisible,
                !controlSheetPresented
            else {
                return
            }

            controlSheetPresented = true
        }
    }

    private func beginAppleMapsSearchExpansion(
        generation: Int
    ) {
        // Apple Maps does not jump directly from the collapsed search capsule
        // to a keyboard-compressed large sheet. It rises through an
        // intermediate detent while the keyboard appears, then completes the
        // expansion. Reproducing that sequence keeps the search field near the
        // top of the drawer instead of floating in the middle of a blank panel.
        if drawerDetent == Self.peekDetent {
            withAnimation(
                .snappy(duration: 0.24)
            ) {
                drawerDetent =
                    Self.mediumDetent
            }
        }

        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: 360_000_000
            )

            guard
                searchFocused,
                generation ==
                    searchExpansionGeneration
            else {
                return
            }

            withAnimation(
                .snappy(duration: 0.30)
            ) {
                drawerDetent = .large
            }
        }
    }

    private func cancelSearch(
        clearQuery: Bool = false
    ) {
        searchFocused = false
        showSearchResults = false

        if clearQuery {
            search.query = ""
        }

        UIApplication.shared.sendAction(
            #selector(
                UIResponder.resignFirstResponder
            ),
            to: nil,
            from: nil,
            for: nil
        )

        restoreDetentAfterSearch()
    }

    private func restoreDetentAfterSearch() {
        guard !joystickMode else { return }

        let target =
            detentBeforeSearch == .large
            ? Self.mediumDetent
            : detentBeforeSearch

        withAnimation(.snappy(duration: 0.28)) {
            drawerDetent = target
        }
    }

    private func select(
        _ coordinate: CLLocationCoordinate2D,
        name: String
    ) {
        session.select(
            coordinate,
            name: name
        )

        moveCamera(to: coordinate)
    }

    private func selectMapPoint(
        _ coordinate: CLLocationCoordinate2D
    ) {
        // MapKit may expose GCJ-02 coordinates on domestic Apple Maps while
        // the DVT location-simulation service expects WGS-84. Convert exactly
        // once at the map input boundary so the injected location lands on the
        // point the user actually tapped.
        selectMapCoordinate(
            coordinate,
            name: "地图选点",
            moveCameraAfterSelection: false
        )
    }

    private func selectMapCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        name: String,
        moveCameraAfterSelection: Bool = true
    ) {
        let canonical = MapCoordinateConverter.mapToWGS84(
            coordinate,
            system: mapCoordinateSystem
        )

        session.select(
            canonical,
            name: name
        )

        if moveCameraAfterSelection {
            moveCamera(to: canonical)
        }
    }

    private func selectResolvedLocation(
        _ result: ResolvedLocationInput
    ) {
        switch result.coordinateSpace {
        case .wgs84:
            select(
                result.coordinate,
                name: result.name
            )

        case .mapKit:
            selectMapCoordinate(
                result.coordinate,
                name: result.name
            )
        }
    }

    private func mapDisplayCoordinate(
        fromWGS84 coordinate: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        MapCoordinateConverter.wgs84ToMap(
            coordinate,
            system: mapCoordinateSystem
        )
    }

    @MainActor
    private func refreshMapCoordinateSystem(
        recenterAfterChange: Bool
    ) async {
        let detected =
            await MapCoordinateConverter
                .detectMapCoordinateSystem()

        guard detected != mapCoordinateSystem else {
            return
        }

        mapCoordinateSystem = detected

        guard recenterAfterChange else {
            return
        }

        if let coordinate =
            session.simulatedCoordinate
            ?? session.selectedCoordinate
            ?? mapLocation.coordinate {
            moveCamera(
                to: coordinate,
                latitudeDelta: 0.014,
                preserveView: true
            )
        }
    }

    private func saveFavorite() {
        guard session.addFavorite() else {
            alertText = "请先选择一个位置。"
            return
        }

        favoriteSaved = true
        UINotificationFeedbackGenerator()
            .notificationOccurred(.success)

        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: 1_100_000_000
            )
            favoriteSaved = false
        }
    }

    private func moveCamera(
        to coordinate: CLLocationCoordinate2D,
        latitudeDelta: CLLocationDegrees = 0.025,
        animated: Bool = true,
        preserveView: Bool = false,
        headingOverride: CLLocationDirection? = nil
    ) {
        mapTrackingMode = .free
        let current = liveCamera
        let estimatedDistance = max(
            260,
            latitudeDelta * 111_000 * 1.55
        )

        let targetDistance =
            preserveView
            ? (current?.distance ?? estimatedDistance)
            : estimatedDistance

        let targetHeading =
            headingOverride
            ?? (
                preserveView
                ? (current?.heading ?? 0)
                : (isThreeD ? (current?.heading ?? 0) : 0)
            )

        let targetPitch: CGFloat =
            isThreeD
            ? max(current?.pitch ?? 58, 48)
            : 0

        let update = {
            position = .camera(
                MapCamera(
                    centerCoordinate: mapDisplayCoordinate(
                        fromWGS84: coordinate
                    ),
                    distance: targetDistance,
                    heading: targetHeading,
                    pitch: targetPitch
                )
            )
        }

        if animated {
            withAnimation(
                .snappy(duration: 0.30)
            ) {
                update()
            }
        } else {
            update()
        }
    }

    private func refreshSearchCenter() {
        if let camera = liveCamera {
            search.setSearchContext(
                center: camera.centerCoordinate,
                visibleRadius: max(
                    6_000,
                    min(35_000, camera.distance * 1.35)
                )
            )
            return
        }

        let anchor =
            session.simulatedCoordinate
            ?? session.selectedCoordinate
            ?? mapLocation.bestRealCoordinate(
                maxAge: 30,
                maxHorizontalAccuracy: 250
            )

        guard let anchor else {
            search.setSearchContext(center: nil)
            return
        }

        search.setSearchContext(
            center: mapDisplayCoordinate(
                fromWGS84: anchor
            )
        )
    }

    private func coordinatesAlmostEqual(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D?
    ) -> Bool {
        guard let rhs else { return false }

        return
            abs(lhs.latitude - rhs.latitude)
                < 0.000001
            && abs(lhs.longitude - rhs.longitude)
                < 0.000001
    }

    @MainActor
    private func resolveTypedInput(
        _ input: String
    ) async {
        let text = input
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !text.isEmpty else { return }

        isResolvingInput = true
        defer {
            isResolvingInput = false
        }

        do {
            refreshSearchCenter()

            if LocationInputParser.parse(text) == nil,
               !text.contains("://"),
               let nearby = try await search.resolveAppleMapsStyleQuery(text) {
                selectMapCoordinate(
                    nearby.coordinate,
                    name: nearby.name
                )

                cancelSearch(clearQuery: true)

                withAnimation(.snappy(duration: 0.25)) {
                    drawerDetent = Self.peekDetent
                }
                return
            }

            if let result = try await MapLinkResolver.resolve(text) {
                selectResolvedLocation(result)

                cancelSearch(clearQuery: true)

                withAnimation(.snappy(duration: 0.25)) {
                    drawerDetent = Self.peekDetent
                }
            } else {
                alertText = "没有找到这个地点。"
            }
        } catch {
            alertText = error.localizedDescription
        }
    }

    @MainActor
    private func pasteAndResolve() async {
        guard
            let text =
                UIPasteboard.general.string,
            !text.isEmpty
        else {
            alertText =
                "剪贴板没有文本或地图链接。"
            return
        }

        search.query = text
        searchFocused = true

        await resolveTypedInput(text)
    }

    @MainActor
    private func consumePendingImport() async {
        guard
            let pending =
                PendingImportBridge.take()
        else {
            return
        }

        do {
            guard
                let result =
                    try await MapLinkResolver.resolve(
                        pending.input
                    )
            else {
                alertText =
                    "无法解析共享的位置。"
                return
            }

            selectResolvedLocation(result)

            if pending.shouldTeleport {
                session.teleport(
                    pairing: pairing
                )
            }

            withAnimation(
                .snappy(duration: 0.25)
            ) {
                drawerDetent =
                    Self.peekDetent
            }
        } catch {
            alertText =
                error.localizedDescription
        }
    }
}
