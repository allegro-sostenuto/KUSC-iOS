import AVKit
import SwiftUI

extension Color {
    static let kuscBackground = adaptive(light: 0xFAF9F7, dark: 0x000000)
    static let kuscSurface = adaptive(light: 0xFFFFFF, dark: 0x000000)
    static let kuscInk = adaptive(light: 0x171719, dark: 0xF4F2EF)
    static let kuscRed = adaptive(light: 0xAC1B31, dark: 0xF26A7C)
    static let kuscSeparator = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.28) : UIColor.black.withAlphaComponent(0.12)
    })

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

extension View {
    func kuscControlSurface<S: InsettableShape>(_ shape: S) -> some View {
        background(Color.kuscSurface, in: shape)
            .overlay(shape.strokeBorder(Color.kuscSeparator, lineWidth: 0.75))
    }

    @ViewBuilder func kuscSheetBackground() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(Color.kuscBackground)
        } else {
            self.background(Color.kuscBackground.ignoresSafeArea())
        }
    }
}

struct KUSCPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(colorScheme == .dark ? Color.kuscRed : .white)
            .background(colorScheme == .dark ? Color.black : Color.kuscRed, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.kuscRed, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
    }
}

struct SheetCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 16))
                .foregroundStyle(Color.kuscInk)
                .frame(width: 44, height: 44).kuscControlSurface(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel("Close")
    }
}

struct AlbumArtwork: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let image: UIImage?
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ZStack {
                    Color.kuscSurface
                    VStack(spacing: 14) {
                        Image(systemName: "music.note").font(.system(size: 48, weight: .ultraLight))
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("Artwork unavailable").font(.caption)
                        }
                    }.foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.kuscSeparator, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(image == nil ? "Album artwork unavailable" : "Album artwork")
        .accessibilityIdentifier("player-artwork")
    }
}

struct NowPlayingMetadata: View {
    let item: ProgrammeItem?
    @ScaledMetric(relativeTo: .title2) private var workSize = 25
    @ScaledMetric(relativeTo: .title3) private var movementSize = 20
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let item {
                Text(item.work.isEmpty ? "KUSC FM 91.5" : item.work)
                    .font(.system(size: workSize, weight: .semibold)).tracking(-0.6)
                if let movement = item.movement, !movement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(movement).font(.system(size: movementSize))
                }
                if !item.composer.isEmpty {
                    Text(item.composer).font(.body).padding(.top, 6)
                }
                if !item.performers.isEmpty {
                    Text(item.performers).font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Text("KUSC FM 91.5").font(.system(size: workSize, weight: .semibold))
                Text("Programme information is currently unavailable.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlayerControls: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let landscape: Bool
    let togglePlayback: () -> Void
    let showSleep: () -> Void
    let showSchedule: () -> Void
    let showOutput: () -> Void

    private var minimalist: Bool { model.settings.minimalist }
    private var playSize: CGFloat { minimalist ? (landscape ? 96 : 112) : (landscape ? 68 : 74) }
    private var auxiliarySize: CGFloat { minimalist ? 60 : 48 }

    var body: some View {
        VStack(spacing: minimalist ? 24 : 14) {
            playbackStatus
            if minimalist && !landscape {
                playButton
                HStack(spacing: 16) { liveButton; moreButton }
            } else {
                ZStack {
                    HStack {
                        liveButton
                        Spacer(minLength: playSize + 16)
                        moreButton
                    }
                    playButton
                }
            }
            if let sleep = model.sleepDescription {
                Label(sleep, systemImage: "moon").font(.caption).foregroundStyle(.secondary)
            }
            if let schedule = model.scheduleDescription {
                Label(schedule, systemImage: "alarm").font(.caption).foregroundStyle(.secondary)
            }
            if let notice = model.notice, !notice.isEmpty {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, landscape ? 0 : 32)
        .padding(.top, 8).padding(.bottom, 4)
    }

    private var playButton: some View {
        Button(action: togglePlayback) {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: minimalist ? 40 : 28, weight: .semibold))
                .offset(x: model.isPlaying ? 0 : 2)
                .frame(width: playSize, height: playSize)
                .foregroundStyle(colorScheme == .dark ? Color.kuscInk : Color.white)
                .background(colorScheme == .dark ? Color.black : Color.kuscInk, in: Circle())
                .overlay(Circle().strokeBorder(Color.kuscInk.opacity(colorScheme == .dark ? 0.8 : 0), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
    }

    private var liveButton: some View {
        Button { model.goLive() } label: {
            HStack(spacing: 6) {
                Circle().frame(width: 5, height: 5)
                Text("LIVE").font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Color.kuscRed)
            .padding(.horizontal, 17).frame(minHeight: auxiliarySize)
            .kuscControlSurface(Capsule())
        }
        .buttonStyle(.plain).accessibilityLabel("Jump to live")
    }

    private var moreButton: some View {
        StablePlayerMenu(diameter: auxiliarySize, showSleep: showSleep, showSchedule: showSchedule, showOutput: showOutput)
            .frame(width: auxiliarySize, height: auxiliarySize)
    }

    private var playbackStatus: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Color.kuscRed).frame(width: 4, height: 4)
                Text(model.state == .playingLive ? "Listening live" : model.statusText)
                    .foregroundStyle(.secondary)
            }.font(.caption)
            if case .reconnecting(let since) = model.state {
                ProgressView(value: min(60, max(0, Date().timeIntervalSince(since))), total: 60)
                    .tint(.kuscRed).accessibilityLabel("Reconnection time used")
            }
        }
    }
}

/// Playback publishes frequently. Keep UIKit's presented menu and action colors
/// stable instead of replacing a SwiftUI Menu while it is on screen.
private struct StablePlayerMenu: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let diameter: CGFloat
    let showSleep: () -> Void
    let showSchedule: () -> Void
    let showOutput: () -> Void

    final class Coordinator {
        var actions: StablePlayerMenu
        var appearance: ColorScheme?
        init(_ actions: StablePlayerMenu) { self.actions = actions }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)), for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = "More controls"
        button.tintAdjustmentMode = .normal
        let coordinator = context.coordinator
        button.menu = UIMenu(children: [
            UIAction(title: "Sleep Timer", image: UIImage(systemName: "moon")) { _ in coordinator.actions.showSleep() },
            UIAction(title: "Scheduled Start", image: UIImage(systemName: "alarm")) { _ in coordinator.actions.showSchedule() },
            UIAction(title: "Audio Output", image: UIImage(systemName: "airplayaudio")) { _ in coordinator.actions.showOutput() }
        ])
        button.layer.borderWidth = 0.75
        button.layer.cornerRadius = 24
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.actions = self
        button.layer.cornerRadius = diameter / 2
        guard context.coordinator.appearance != colorScheme else { return }
        context.coordinator.appearance = colorScheme
        let dark = colorScheme == .dark
        button.overrideUserInterfaceStyle = dark ? .dark : .light
        button.tintColor = dark ? UIColor(white: 0.95, alpha: 1) : UIColor(white: 0.09, alpha: 1)
        button.backgroundColor = dark ? .black : .white
        button.layer.borderColor = (dark ? UIColor.white.withAlphaComponent(0.28) : UIColor.black.withAlphaComponent(0.12)).cgColor
    }
}

struct AudioOutputView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Audio Output").font(.title2.weight(.semibold))
                Spacer()
                SheetCloseButton { dismiss() }
            }
            HStack(spacing: 16) {
                Image(systemName: "speaker.wave.2").foregroundStyle(Color.kuscRed)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current output").font(.caption).foregroundStyle(.secondary)
                    Text(model.currentOutputName).font(.body.weight(.medium))
                }
                Spacer()
                AudioRoutePicker().frame(width: 52, height: 52)
            }.padding(16).kuscControlSurface(RoundedRectangle(cornerRadius: 18))
            Text("Choose an available output using the system picker. Selecting an output changes the current audio route.")
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(24)
        .foregroundStyle(Color.kuscInk)
        .background(Color.kuscBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

/// The native indicator follows pull distance, then stays spinning for the async
/// operation. Keeping this on the content scroll views leaves transport gestures alone.
struct PlayerRefreshModifier: ViewModifier {
    @EnvironmentObject private var model: AppModel

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            refreshable(content).scrollBounceBehavior(.always, axes: .vertical)
        } else {
            refreshable(content)
        }
    }

    private func refreshable(_ content: Content) -> some View {
        content
            .refreshable { await model.refreshMetadata() }
            .accessibilityAction(named: Text("Refresh artwork and programme")) {
                Task { await model.refreshMetadata() }
            }
    }
}

struct AudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(Color.kuscRed)
        view.activeTintColor = UIColor(Color.kuscRed)
        view.prioritizesVideoDevices = false
        view.accessibilityLabel = "Choose audio output"
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = UIColor(Color.kuscRed)
        uiView.activeTintColor = UIColor(Color.kuscRed)
    }
}
