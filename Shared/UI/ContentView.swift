import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: PlayerSheet?
    @State private var showingProgramme = false
    @State private var choosingPauseBehavior = false
    @State private var accessibleControlsHeight: CGFloat = 0
    @State private var panelSwipe = PanelSwipeState()
    @State private var panelOffset: CGFloat = 0
    @State private var panelTransition: PanelTransition?
    @GestureState private var draggingPanel = false

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
                header(width: geometry.size.width)
                if model.settings.minimalist {
                    ScrollView {
                        playbackControls(landscape: landscape)
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 60))
                    }
                    .modifier(PlayerRefreshModifier())
                } else {
                    panels(size: geometry.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kuscBackground.ignoresSafeArea())
            .onChange(of: geometry.size) { _ in resetPanelDrag() }
        }
        .foregroundStyle(Color.kuscInk)
        .tint(.kuscRed)
        .preferredColorScheme(colorScheme)
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
            .kuscSheetBackground()
        }
        .confirmationDialog("Sleep timer", isPresented: $choosingPauseBehavior, titleVisibility: .visible) {
            Button("Keep counting") { model.choosePausedTimer(.keepCounting) }
            Button("Pause timer") { model.choosePausedTimer(.pauseTimer) }
            Button("Cancel timer", role: .destructive) { model.choosePausedTimer(.cancelTimer) }
        } message: {
            Text("Playback is paused. Choose what happens to the sleep timer.")
        }
        .onChange(of: model.settings.minimalist) { enabled in
            resetPanelDrag()
            if enabled { showingProgramme = false }
        }
        .onChange(of: draggingPanel) { dragging in
            guard !dragging else { return }
            // Cancellation does not call onEnded. Defer until a successful
            // release has had a chance to start its settling animation.
            DispatchQueue.main.async {
                if panelSwipe.axis != nil && panelTransition == nil {
                    settlePanel(direction: nil, width: 0)
                }
            }
        }
        .onChange(of: model.scheduleManagementRequest) { request in
            if request != nil { choosingPauseBehavior = false; sheet = .schedule }
        }
        .onAppear {
            if model.scheduleManagementRequest != nil { sheet = .schedule }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.onForeground() }
            else { resetPanelDrag() }
        }
        .onDisappear { resetPanelDrag() }
        #if DEBUG
        .onAppear {
            guard let fixture = UIFixture.state else { return }
            showingProgramme = ["programme", "unavailable-programme"].contains(fixture)
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

    private func header(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if showingProgramme && !model.settings.minimalist {
                Button {
                    selectPanel(programme: false, width: width)
                } label: {
                    Text("Now Playing")
                        .font(.subheadline).frame(minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(Color.kuscRed)
                .accessibilityIdentifier("now-playing-header")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("KUSC").font(.system(size: 25, weight: .semibold)).tracking(-1.2)
                    Text("91.5 FM").font(.system(size: 10, weight: .medium)).tracking(1.4)
                        .foregroundStyle(Color.kuscRed)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 8)
            Button { sheet = .settings } label: {
                Image(systemName: "gearshape").font(.system(size: 19))
                    .frame(width: 44, height: 44).kuscControlSurface(Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Settings")
        }
        .padding(.horizontal, 26).padding(.vertical, 6)
    }

    private func panels(size: CGSize) -> some View {
        let transitionID = panelTransition?.id
        return ZStack {
            if panelOffset != 0 || panelTransition != nil {
                panel(programme: !showingProgramme, size: size)
                    .transition(.identity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            panel(programme: showingProgramme, size: size)
                .offset(x: panelOffset)
                .modifier(PanelOffsetCompletion(offset: panelOffset) {
                    finishPanelTransition(id: transitionID)
                })
                .allowsHitTesting(panelTransition == nil)
        }
        .coordinateSpace(name: "player-panels")
        .clipped()
        #if DEBUG
        .onAppear {
            if UIFixture.state == "reveal-left" { panelOffset = -size.width * 0.44 }
            if UIFixture.state == "reveal-right" { panelOffset = size.width * 0.44 }
        }
        #endif
    }

    private func panel(programme: Bool, size: CGSize) -> some View {
        Group {
            if programme {
                VStack(spacing: 0) {
                    ProgrammeView()
                        .simultaneousGesture(programmeGesture(width: size.width))
                    anchoredControls(landscape: size.width > size.height, height: size.height)
                    pageIndicators(width: size.width)
                }
            } else if size.width > size.height {
                landscapePlayer(size: size)
            } else {
                portrait(size: size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opaque surfaces reveal the other panel rather than crossfading text.
        // kuscBackground remains pure black in dark appearance.
        .background(Color.kuscBackground)
    }

    private func portrait(size: CGSize) -> some View {
        let artworkSide = min(dynamicTypeSize.isAccessibilitySize ? 144 : 306,
                              size.width - 80, max(140, (size.height - 240) * 0.62))
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    AlbumArtwork(image: model.artwork).frame(width: artworkSide, height: artworkSide)
                    NowPlayingMetadata(item: model.currentItem)
                }
                .frame(maxWidth: .infinity).padding(.horizontal, 32)
                .padding(.top, 24).padding(.bottom, 16)
            }
            .accessibilityIdentifier("now-playing-scroll")
            .modifier(PlayerRefreshModifier())
            // Paging belongs to content only. Slider/control gestures never reach it.
            .simultaneousGesture(programmeGesture(width: size.width))
            anchoredControls(landscape: false, height: size.height)
            pageIndicators(width: size.width)
        }
    }

    private func landscapePlayer(size: CGSize) -> some View {
        let artworkSide = max(96, min(size.width * 0.34, size.height - 84))
        return HStack(alignment: .center, spacing: 32) {
            AlbumArtwork(image: model.artwork).frame(width: artworkSide, height: artworkSide)
                .simultaneousGesture(programmeGesture(width: size.width))
            VStack(spacing: 0) {
                ScrollView {
                    NowPlayingMetadata(item: model.currentItem).padding(.top, 8).padding(.bottom, 12)
                }
                .accessibilityIdentifier("now-playing-scroll")
                .modifier(PlayerRefreshModifier())
                .simultaneousGesture(programmeGesture(width: size.width))
                anchoredControls(landscape: true, height: size.height)
                pageIndicators(width: size.width)
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
            Circle().fill(Color.kuscInk.opacity(showingProgramme == programme ? 0.65 : 0.2))
                .frame(width: 5, height: 5).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(programme ? "Programme" : "Now Playing")
        .accessibilityAddTraits(showingProgramme == programme ? [.isSelected] : [])
    }

    private func programmeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("player-panels"))
            .updating($draggingPanel) { _, dragging, _ in dragging = true }
            .onChanged { value in
                guard !model.settings.minimalist, panelTransition == nil else { return }
                if let offset = panelSwipe.translation(x: Double(value.translation.width),
                                                      y: Double(value.translation.height), width: Double(width)) {
                    panelOffset = CGFloat(offset)
                }
            }
            .onEnded { value in
                guard !model.settings.minimalist, panelTransition == nil else { return }
                let direction = panelSwipe.releaseDirection(x: Double(value.translation.width),
                    predictedX: Double(value.predictedEndTranslation.width), width: Double(width))
                settlePanel(direction: direction, width: width)
            }
    }

    private func selectPanel(programme: Bool, width: CGFloat) {
        guard programme != showingProgramme, panelTransition == nil else { return }
        settlePanel(direction: programme ? 1 : -1, width: width)
    }

    private func settlePanel(direction: Int?, width: CGFloat) {
        panelSwipe = PanelSwipeState()
        let target = direction.map { CGFloat($0) * width } ?? 0
        guard panelOffset != target else {
            if direction != nil { showingProgramme.toggle() }
            resetPanelDrag()
            return
        }
        panelTransition = PanelTransition(switchesPanel: direction != nil)
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.26)) {
            panelOffset = target
        }
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
        panelOffset = 0
    }

    private func playbackControls(landscape: Bool) -> some View {
        PlayerControls(landscape: landscape, togglePlayback: {
            if model.isPlaying { choosingPauseBehavior = model.pauseFromApp() }
            else { model.play() }
        }, showSleep: { sheet = .sleep }, showSchedule: { sheet = .schedule }, showOutput: { sheet = .output })
    }
}

/// iOS 16-compatible completion tied to the rendered offset, not a timer.
private struct PanelOffsetCompletion: AnimatableModifier {
    var animatableData: CGFloat {
        didSet {
            if animatableData == target {
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
