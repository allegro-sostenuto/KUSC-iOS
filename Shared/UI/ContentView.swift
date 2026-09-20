import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sheet: PlayerSheet?
    @State private var showingProgramme = false
    @State private var choosingPauseBehavior = false
    @State private var accessibleControlsHeight: CGFloat = 0

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
                header
                if model.settings.minimalist {
                    ScrollView {
                        playbackControls(landscape: landscape)
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 60))
                    }
                } else if showingProgramme {
                    ProgrammeView()
                        .transition(.opacity)
                        .simultaneousGesture(programmeGesture)
                    anchoredControls(landscape: landscape, height: geometry.size.height)
                    pageIndicators
                } else if landscape {
                    landscapePlayer(size: geometry.size)
                } else {
                    portrait(size: geometry.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kuscBackground.ignoresSafeArea())
        }
        .foregroundStyle(Color.kuscInk)
        .tint(.kuscRed)
        .preferredColorScheme(colorScheme)
        .sheet(item: $sheet) { selected in
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
            if enabled { showingProgramme = false }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.onForeground() }
        }
        #if DEBUG
        .onAppear {
            guard let fixture = UIFixture.state else { return }
            showingProgramme = ["programme", "unavailable-programme"].contains(fixture)
            switch fixture {
            case "settings": sheet = .settings
            case "sleep": sheet = .sleep
            case "schedule", "schedule-output": sheet = .schedule
            case "output", "unavailable-output": sheet = .output
            case "paused": choosingPauseBehavior = true
            default: break
            }
        }
        #endif
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if showingProgramme && !model.settings.minimalist {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showingProgramme = false }
                } label: {
                    Label("Now Playing", systemImage: "chevron.left")
                        .font(.subheadline).frame(minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(Color.kuscRed)
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
            // Paging belongs to content only. Slider/control gestures never reach it.
            .simultaneousGesture(programmeGesture)
            anchoredControls(landscape: false, height: size.height)
            pageIndicators
        }
    }

    private func landscapePlayer(size: CGSize) -> some View {
        let artworkSide = max(96, min(size.width * 0.34, size.height - 84))
        return HStack(alignment: .center, spacing: 32) {
            AlbumArtwork(image: model.artwork).frame(width: artworkSide, height: artworkSide)
                .simultaneousGesture(programmeGesture)
            VStack(spacing: 0) {
                ScrollView {
                    NowPlayingMetadata(item: model.currentItem).padding(.top, 8).padding(.bottom, 12)
                }
                .simultaneousGesture(programmeGesture)
                anchoredControls(landscape: true, height: size.height)
                pageIndicators
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

    private var pageIndicators: some View {
        HStack(spacing: 0) {
            pageIndicator(programme: true)
            pageIndicator(programme: false)
        }.frame(height: 44)
    }

    private func pageIndicator(programme: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showingProgramme = programme }
        } label: {
            Circle().fill(Color.kuscInk.opacity(showingProgramme == programme ? 0.65 : 0.2))
                .frame(width: 5, height: 5).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(programme ? "Programme" : "Now Playing")
        .accessibilityAddTraits(showingProgramme == programme ? [.isSelected] : [])
    }

    private var programmeGesture: some Gesture {
        DragGesture(minimumDistance: 40).onEnded { value in
            guard !model.settings.minimalist,
                  abs(value.translation.width) > abs(value.translation.height) * 1.6 else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                if value.translation.width > 65 { showingProgramme = true }
                if value.translation.width < -65 { showingProgramme = false }
            }
        }
    }

    private func playbackControls(landscape: Bool) -> some View {
        PlayerControls(landscape: landscape, togglePlayback: {
            if model.isPlaying { choosingPauseBehavior = model.pauseFromApp() }
            else { model.play() }
        }, showSleep: { sheet = .sleep }, showSchedule: { sheet = .schedule }, showOutput: { sheet = .output })
    }
}

private struct ControlsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
