import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: PlayerSheet?
    @State private var choosingStation = false
    @State private var showingProgramme = false
    @State private var choosingPauseBehavior = false
    @State private var accessibleControlsHeight: CGFloat = 0
    @State private var panelSwipe = PanelSwipeState()
    @State private var panelOffset: CGFloat = 0
    @State private var panelTransition: PanelTransition?
    @State private var draggingPanel = false

    private struct PanelTransition {
        let id = UUID()
        let switchesPanel: Bool
    }

    private enum PlayerSheet: String, Identifiable {
        case settings, sleep, schedule, output
        var id: String { rawValue }
    }

    private var colorScheme: ColorScheme? {
        switch model.settings.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing: 0) {
                header(width: geometry.size.width, landscape: landscape)
                if model.settings.minimalist {
                    ScrollView {
                        playbackControls(landscape: landscape)
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 60))
                    }
                    .modifier(PlayerRefreshModifier())
                } else {
                    panels(size: geometry.size)
                    if !landscape {
                        VStack(spacing: 0) {
                            anchoredControls(landscape: false, height: geometry.size.height)
                            pageIndicators(width: geometry.size.width)
                        }
                        .scrollDisabled(isSwipingPanel)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.philharmonicBackground.ignoresSafeArea())
            .onChange(of: geometry.size) { dimensions in
                resetPanelDrag()
                if dimensions.width > dimensions.height { showingProgramme = false }
                #if DEBUG
                if dimensions.width < dimensions.height {
                    applyPanelRevealFixture(width: dimensions.width)
                }
                #endif
            }
        }
        .foregroundStyle(Color.philharmonicInk)
        .tint(.philharmonicRed)
        .preferredColorScheme(colorScheme)
        .fullScreenCover(isPresented: $choosingStation) {
            StationPickerView()
                .environmentObject(model)
                .preferredColorScheme(colorScheme)
        }
        .sheet(item: $sheet, onDismiss: { model.clearScheduleManagementRequest() }) { selected in
            Group {
                switch selected {
                case .settings: SettingsView()
                case .sleep: SleepTimerView()
                case .schedule: ScheduledStartView()
                case .output: AudioOutputView()
                }
            }
            #if DEBUG
            .modifier(UIFixtureTextSize())
            #endif
            .preferredColorScheme(colorScheme)
            .philharmonicSheetBackground()
        }
        .confirmationDialog("Sleep timer", isPresented: $choosingPauseBehavior, titleVisibility: .visible) {
            Button("Keep counting") { model.choosePausedTimer(.keepCounting) }
            Button("Pause timer") { model.choosePausedTimer(.pauseTimer) }
            Button("Cancel timer", role: .destructive) { model.choosePausedTimer(.cancelTimer) }
        } message: {
            Text("Playback is paused. Choose what happens to the sleep timer.")
        }
        .onChange(of: showingProgramme) { visible in
            PlayerOrientation.setProgrammeVisible(visible)
        }
        .onChange(of: model.settings.minimalist) { enabled in
            resetPanelDrag()
            if enabled { showingProgramme = false }
        }
        .onChange(of: model.scheduleManagementRequest) { request in
            if request != nil { choosingPauseBehavior = false; sheet = .schedule }
        }
        .onAppear {
            PlayerOrientation.setProgrammeVisible(showingProgramme)
            PlayerOrientation.refresh()
            if model.scheduleManagementRequest != nil { sheet = .schedule }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.onForeground(); PlayerOrientation.refresh() }
            else { resetPanelDrag() }
        }
        .onDisappear { resetPanelDrag(); PlayerOrientation.setProgrammeVisible(false) }
        #if DEBUG
        .onAppear {
            guard let fixture = UIFixture.state else { return }
            showingProgramme = ["programme", "unavailable-programme", "reveal-programme-right"].contains(fixture)
            switch fixture {
            case "settings": sheet = .settings
            case "sleep": sheet = .sleep
            case "schedule", "schedule-output", "schedule-power": sheet = .schedule
            case "output", "unavailable-output": sheet = .output
            case "paused": choosingPauseBehavior = true
            default: break
            }
        }
        #endif
    }

    private func header(width: CGFloat, landscape: Bool) -> some View {
        let progress = landscape ? 0 : (showingProgramme ? 1 : 0) + panelOffset / max(1, width)
        return HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .leading) {
                RollingChannelHeader(progress: progress, showingProgramme: showingProgramme,
                                     station: model.selectedStation)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                Button {
                    resetPanelDrag()
                    PlayerOrientation.setProgrammeVisible(false)
                    choosingStation = true
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!showingProgramme)
                .accessibilityHidden(showingProgramme)
                .accessibilityLabel("Choose station, \(model.selectedStation.name)")
                .accessibilityIdentifier("choose-station")
            }
            .frame(height: 44)
            Spacer(minLength: 8)
            Button { sheet = .settings } label: {
                Image(systemName: "gearshape").font(.system(size: 19))
                    .frame(width: 44, height: 44).philharmonicControlSurface(Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Settings")
        }
        .padding(.horizontal, 26).padding(.vertical, 6)
    }

    private func panels(size: CGSize) -> some View {
        let transitionID = panelTransition?.id
        return GeometryReader { viewport in
            if size.width > size.height {
                // Keep the established artwork-left / details-right layout.
                // Program and its recognizer do not exist in landscape.
                landscapePlayer(size: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.philharmonicBackground)
            } else {
                ZStack {
                    // Keep both layers mounted; a first drag must not replace its
                    // own ScrollView or recognizer when Program appears underneath.
                    panel(programme: true, size: size, height: viewport.size.height)
                        .allowsHitTesting(showingProgramme && panelTransition == nil)
                        .accessibilityHidden(!showingProgramme)
                    panel(programme: false, size: size, height: viewport.size.height)
                        .overlay(alignment: .leading) {
                            if isSwipingPanel {
                                Rectangle().fill(Color.philharmonicSeparator).frame(width: 1)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .offset(x: showingProgramme ? viewport.size.width + panelOffset : panelOffset)
                        .modifier(PanelOffsetCompletion(offset: panelOffset) {
                            finishPanelTransition(id: transitionID)
                        })
                        .allowsHitTesting(!showingProgramme && panelTransition == nil)
                        .accessibilityHidden(showingProgramme)
                }
                .background {
                    PanelPanGesture(enabled: panelTransition == nil && !model.settings.minimalist &&
                                        sheet == nil && !choosingPauseBehavior && scenePhase == .active,
                                    opening: !showingProgramme,
                                    changed: { panelDragChanged($0, width: viewport.size.width) },
                                    ended: { x, velocity, cancelled in
                                        panelDragEnded(x, velocity: velocity, cancelled: cancelled,
                                                       width: viewport.size.width)
                                    })
                    .accessibilityHidden(true)
                }
                .coordinateSpace(name: "player-panels")
                .clipped()
            }
        }
        #if DEBUG
        .onAppear {
            if size.width < size.height { applyPanelRevealFixture(width: size.width) }
        }
        #endif
    }

    #if DEBUG
    private func applyPanelRevealFixture(width: CGFloat) {
        // XCTest rotates after launch. Reapply only the held layout fixture;
        // real gestures still reset when the viewport changes dimensions.
        guard let fixture = UIFixture.state else { return }
        if ["reveal-left", "reveal-right"].contains(fixture) { panelOffset = width * 0.44 }
        if fixture == "reveal-programme-right" { panelOffset = -width * 0.44 }
    }
    #endif

    private var isSwipingPanel: Bool {
        draggingPanel || panelOffset != 0 || panelTransition != nil
    }

    private func panel(programme: Bool, size: CGSize, height: CGFloat) -> some View {
        Group {
            if programme {
                ProgrammeView()
            } else if size.width > size.height {
                landscapePlayer(size: size)
            } else {
                portrait(size: size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opaque surfaces reveal the other panel rather than crossfading text.
        // philharmonicBackground remains pure black in dark appearance.
        .background(Color.philharmonicBackground)
    }

    private func portrait(size: CGSize) -> some View {
        let artworkSide = min(dynamicTypeSize.isAccessibilitySize ? 144 : 306,
                              size.width - 80, max(140, (size.height - 240) * 0.62))
        return ScrollView {
            VStack(spacing: 22) {
                AlbumArtwork(image: model.artwork).frame(width: artworkSide, height: artworkSide)
                NowPlayingMetadata(item: model.currentItem)
            }
            .frame(maxWidth: .infinity).padding(.horizontal, 32)
            .padding(.top, 24).padding(.bottom, 16)
        }
        .accessibilityIdentifier("now-playing-scroll")
        .modifier(PlayerRefreshModifier())
    }

    private func landscapePlayer(size: CGSize) -> some View {
        // Restore the landscape proportions used from September 20 to October 22.
        let artworkSide = max(96, min(size.width * 0.34, size.height - 84))
        return HStack(alignment: .center, spacing: 32) {
            AlbumArtwork(image: model.artwork).frame(width: artworkSide, height: artworkSide)
            VStack(spacing: 0) {
                ScrollView {
                    NowPlayingMetadata(item: model.currentItem).padding(.top, 8).padding(.bottom, 12)
                }
                .accessibilityIdentifier("now-playing-scroll")
                .modifier(PlayerRefreshModifier())
                anchoredControls(landscape: true, height: size.height)
                // Keep the historical bottom spacing without landscape page controls.
                Color.clear.frame(height: 44).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 32).padding(.bottom, 8)
    }

    @ViewBuilder private func anchoredControls(landscape: Bool, height: CGFloat) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                playbackControls(landscape: landscape)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: ControlsHeightKey.self, value: geometry.size.height)
                        }
                    }
            }
            .frame(height: min(accessibleControlsHeight > 0 ? accessibleControlsHeight : height * 0.48,
                               height * 0.48))
            .onPreferenceChange(ControlsHeightKey.self) { accessibleControlsHeight = $0 }
        } else {
            playbackControls(landscape: landscape)
        }
    }

    private func pageIndicators(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            pageIndicator(programme: true, width: width)
            pageIndicator(programme: false, width: width)
        }.frame(height: 44)
    }

    private func pageIndicator(programme: Bool, width: CGFloat) -> some View {
        Button {
            selectPanel(programme: programme, width: width)
        } label: {
            Circle().fill(Color.philharmonicInk.opacity(showingProgramme == programme ? 0.65 : 0.2))
                .frame(width: 5, height: 5).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(programme ? "Programme" : "Now Playing")
        .accessibilityIdentifier(programme ? "programme-page" : "now-playing-page")
        .accessibilityAddTraits(showingProgramme == programme ? [.isSelected] : [])
    }

    private func panelDragChanged(_ x: CGFloat, width: CGFloat) {
        guard !model.settings.minimalist, panelTransition == nil else { return }
        draggingPanel = true
        if let offset = panelSwipe.translation(x: Double(x), y: 0, width: Double(width)) {
            let allowed = showingProgramme ? min(0, offset) : max(0, offset)
            panelOffset = CGFloat(PanelSwipeState.resistedTranslation(allowed, width: Double(width)))
        }
    }

    private func panelDragEnded(_ x: CGFloat, velocity: CGFloat, cancelled: Bool, width: CGFloat) {
        guard panelTransition == nil else { return }
        draggingPanel = false
        let predicted = x + velocity * 0.18
        let direction = cancelled ? nil : panelSwipe.releaseDirection(
            x: Double(x), predictedX: Double(predicted), width: Double(width))
        let allowedDirection = showingProgramme ? -1 : 1
        let selected = direction == allowedDirection ? direction : nil
        let remaining = abs((selected.map { CGFloat($0) * width } ?? 0) - panelOffset)
        let signedSpeed = velocity * CGFloat(selected ?? 0)
        // Carry a modest release velocity into the spring without overshoot.
        let normalized = selected == nil || remaining < 1 ? 0 :
            min(4, max(0, Double(signedSpeed / remaining)))
        settlePanel(direction: selected, width: width, velocity: normalized)
    }

    private func selectPanel(programme: Bool, width: CGFloat) {
        guard programme != showingProgramme, panelTransition == nil else { return }
        settlePanel(direction: programme ? 1 : -1, width: width)
    }

    private func settlePanel(direction: Int?, width: CGFloat, velocity: Double = 0) {
        panelSwipe = PanelSwipeState()
        let target = direction.map { CGFloat($0) * width } ?? 0
        guard panelOffset != target else {
            if direction != nil { showingProgramme.toggle() }
            resetPanelDrag()
            return
        }
        panelTransition = PanelTransition(switchesPanel: direction != nil)
        // m = 1, k = 380, c = 2√(mk): critical damping slows gently without bounce.
        let motion: Animation = reduceMotion ? .easeOut(duration: 0.12)
            : .interpolatingSpring(mass: 1, stiffness: 380, damping: 2 * sqrt(380), initialVelocity: velocity)
        withAnimation(motion) { panelOffset = target }
    }

    private func finishPanelTransition(id: UUID?) {
        guard let transition = panelTransition, transition.id == id else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if transition.switchesPanel { showingProgramme.toggle() }
            resetPanelDrag()
        }
    }

    private func resetPanelDrag() {
        panelTransition = nil
        panelSwipe = PanelSwipeState()
        draggingPanel = false
        panelOffset = 0
    }

    private func playbackControls(landscape: Bool) -> some View {
        PlayerControls(landscape: landscape, togglePlayback: {
            if model.isPlaying { choosingPauseBehavior = model.pauseFromApp() }
            else { model.play() }
        }, showSleep: { sheet = .sleep }, showSchedule: { sheet = .schedule }, showOutput: { sheet = .output })
    }
}

/// The animatable input is the panel's progress, so the nonlinear roll is
/// evaluated on every rendered frame as well as on every finger movement.
private struct RollingChannelHeader: View, Animatable {
    var progress: CGFloat
    let showingProgramme: Bool
    let station: RadioStation
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let rowHeight: CGFloat = 44
        let roll = CGFloat(PanelSwipeState.headerProgress(Double(progress)))
        let font = Font.system(size: 25, weight: .semibold)
        ZStack(alignment: .topLeading) {
            Group {
                if station.id == "kusc" {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(station.name).font(font).tracking(-1.2)
                        if let subtitle = station.subtitle {
                            Text(subtitle).font(.system(size: 10, weight: .medium)).tracking(1.4)
                                .foregroundStyle(Color.philharmonicRed)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(station.name).font(font).tracking(-0.7)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if let subtitle = station.subtitle {
                            Text(subtitle).font(.system(size: 10, weight: .medium))
                                .lineLimit(1).foregroundStyle(Color.philharmonicRed)
                        }
                    }
                }
            }
            .frame(height: rowHeight)
            .offset(y: -roll * rowHeight)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("station-header")
            .accessibilityHidden(showingProgramme)

            Text("Program")
                .font(font).tracking(-1.2)
                .foregroundStyle(Color.philharmonicRed)
                .frame(height: rowHeight)
                .offset(y: (1 - roll) * rowHeight)
                .accessibilityIdentifier("programme-header")
                .accessibilityHidden(!showingProgramme)
        }
        .frame(height: rowHeight, alignment: .topLeading)
        .clipped()
    }
}

/// iOS 16-compatible completion tied to the rendered offset, not a timer.
private struct PanelOffsetCompletion: AnimatableModifier {
    var animatableData: CGFloat {
        didSet {
            // Do not block the next swipe while waiting for a spring's
            // invisible subpixel tail to reach exact floating-point equality.
            if abs(animatableData - target) < 0.5 {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }
    private let target: CGFloat
    private let completion: () -> Void

    init(offset: CGFloat, completion: @escaping () -> Void) {
        target = offset
        animatableData = offset
        self.completion = completion
    }

    func body(content: Content) -> some View { content }
}

private struct ControlsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
