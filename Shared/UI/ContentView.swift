import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sheet: PlayerSheet?
    @State private var showingProgramme = false
    @State private var choosingPauseBehavior = false

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
            VStack(spacing: 0) {
                header
                if model.settings.minimalist {
                    ScrollView {
                        playbackControls
                            .frame(minHeight: max(0, geometry.size.height - 60))
                    }
                } else if showingProgramme {
                    ProgrammeView()
                        .transition(.opacity)
                        .simultaneousGesture(programmeGesture)
                    if dynamicTypeSize.isAccessibilitySize {
                        ScrollView { playbackControls }
                            .frame(maxHeight: geometry.size.height * 0.48)
                    } else {
                        playbackControls
                    }
                } else if geometry.size.width > geometry.size.height {
                    landscape(size: geometry.size)
                } else {
                    portrait(size: geometry.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
        }
        .tint(.kuscRed)
        .preferredColorScheme(colorScheme)
        .sheet(item: $sheet) { selected in
            switch selected {
            case .settings: SettingsView()
            case .sleep: SleepTimerView()
            case .schedule: ScheduledStartView()
            case .output: AudioOutputView()
            }
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
    }

    private var header: some View {
        HStack(spacing: 8) {
            if showingProgramme && !model.settings.minimalist {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showingProgramme = false }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Now playing")
            }
            Text("KUSC")
                .font(.headline)
                .foregroundStyle(Color.kuscRed)
            Spacer(minLength: 0)
            Menu {
                Button { sheet = .sleep } label: {
                    Label("Sleep Timer", systemImage: "moon")
                }
                Button { sheet = .schedule } label: {
                    Label("Scheduled Start", systemImage: "alarm")
                }
                Button { sheet = .output } label: {
                    Label("Audio Output", systemImage: "airplayaudio")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More controls")
            Button { sheet = .settings } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private func portrait(size: CGSize) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    AlbumArtwork(image: model.artwork)
                        .frame(width: min(size.width - 64, max(140, size.height * 0.38)),
                               height: min(size.width - 64, max(140, size.height * 0.38)))
                    NowPlayingMetadata(item: model.currentItem)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                if dynamicTypeSize.isAccessibilitySize {
                    playbackControls
                }
            }
            .simultaneousGesture(programmeGesture)
            if !dynamicTypeSize.isAccessibilitySize {
                playbackControls
            }
        }
    }

    private func landscape(size: CGSize) -> some View {
        HStack(alignment: .center, spacing: 24) {
            AlbumArtwork(image: model.artwork)
                .frame(width: max(96, min(size.width * 0.34, size.height - 76)),
                       height: max(96, min(size.width * 0.34, size.height - 76)))
            VStack(spacing: 0) {
                ScrollView {
                    NowPlayingMetadata(item: model.currentItem)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    if dynamicTypeSize.isAccessibilitySize {
                        playbackControls
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    playbackControls
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .simultaneousGesture(programmeGesture)
    }

    private var programmeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard !model.settings.minimalist,
                      abs(value.translation.width) > abs(value.translation.height) * 1.6 else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if value.translation.width > 65 { showingProgramme = true }
                    if value.translation.width < -65 { showingProgramme = false }
                }
            }
    }

    private var playbackControls: some View {
        PlayerControls {
            if model.isPlaying {
                choosingPauseBehavior = model.pauseFromApp()
            } else {
                model.play()
            }
        }
    }
}

extension Color {
    static let kuscRed = Color(red: 0.69, green: 0.035, blue: 0.095)
}
