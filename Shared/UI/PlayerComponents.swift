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
            if model.settings.retentionMinutes > 0 {
                BufferPositionView(clock: model.transportClock)
            } else {
                playbackStatus
            }
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
        Menu {
            Button(action: showSleep) { Label("Sleep Timer", systemImage: "moon") }
            Button(action: showSchedule) { Label("Scheduled Start", systemImage: "alarm") }
            Button(action: showOutput) { Label("Audio Output", systemImage: "airplayaudio") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.kuscInk)
                .frame(width: auxiliarySize, height: auxiliarySize).kuscControlSurface(Circle())
        }
        .accessibilityLabel("More controls")
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

/// Only this small view follows the media observer; metadata/artwork stay at their own cadence.
private struct BufferPositionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var clock: PlaybackTransportClock
    @State private var scrub = BufferScrubState()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !clock.sample.isAdvancing || scrub.isEditing)) { _ in
            let sample = clock.sample
            if let currentWindow = sample.window, let confirmed = sample.heardAt,
               currentWindow.duration > 0.5 {
                let window = scrub.frozenWindow ?? currentWindow
                let lower = window.oldest.timeIntervalSince1970
                let upper = window.live.timeIntervalSince1970
                let elapsed = sample.isAdvancing ? min(sample.maximumExtrapolation, max(0, ProcessInfo.processInfo.systemUptime - sample.sampledAt)) : 0
                let heard = confirmed.addingTimeInterval(elapsed)
                let position = scrub.preview?.timeIntervalSince1970 ?? (sample.isAtLiveEdge && sample.isAdvancing ? upper : heard.timeIntervalSince1970)
                VStack(spacing: 0) {
                    RetainedAudioSlider(
                        value: (min(upper, max(lower, position)) - lower) / (upper - lower),
                        valueDescription: positionLabel(live: currentWindow.live, heard: heard),
                        onBegin: { scrub.begin(in: currentWindow) },
                        onChange: { fraction, tracking in
                            guard scenePhase == .active else { return }
                            let date = Date(timeIntervalSince1970: lower + fraction * (upper - lower))
                            if tracking {
                                scrub.begin(in: currentWindow)
                                _ = scrub.update(date, currentWindow: currentWindow)
                            } else {
                                commit(scrub.finishAdjustment(date, currentWindow: currentWindow))
                            }
                        },
                        onEnd: { commit(scrub.end()) },
                        onCancel: { scrub.cancel() }
                    )
                    .frame(minHeight: 44)
                    .overlay {
                        GeometryReader { geometry in
                            ForEach(Array(gaps(in: window).enumerated()), id: \.offset) { _, gap in
                                let start = (gap.lowerBound.timeIntervalSince1970 - lower) / (upper - lower)
                                let width = gap.upperBound.timeIntervalSince(gap.lowerBound) / (upper - lower)
                                Rectangle().fill(Color.kuscBackground)
                                    .overlay(Rectangle().stroke(Color.kuscSeparator, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                                    .frame(width: max(2, geometry.size.width * width), height: 5)
                                    .offset(x: geometry.size.width * start, y: (geometry.size.height - 5) / 2)
                            }
                        }.allowsHitTesting(false).accessibilityHidden(true)
                    }
                    // History is acquisition state, independent of a drag's
                    // frozen coordinates or the requested listening position.
                    labels(window: currentWindow, heard: heard)
                    if !gaps(in: window).isEmpty {
                        Text("Gaps skip to the next available audio").font(.caption2)
                            .foregroundStyle(.secondary).padding(.top, 5)
                    }
                    if sample.isSeeking {
                        Text("Seeking…").font(.caption).foregroundStyle(Color.kuscRed).padding(.top, 5)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Text(model.statusText).font(.caption)
                    Text(model.bufferFailureMessage ?? "Collecting audio for rewind…").font(.caption2)
                }.foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.settings.retentionMinutes) { _ in
            scrub.cancel()
        }
        .onChange(of: clock.sample.window == nil) { unavailable in
            if unavailable { scrub.cancel() }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { scrub.cancel() }
        }
        .onDisappear { scrub.cancel() }
    }

    private func labels(window: BufferWindow, heard: Date) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                historyLabel(window)
                Spacer(minLength: 0)
                Text(positionLabel(live: window.live, heard: heard))
                Spacer(minLength: 0)
                Text("Live")
            }
            VStack(spacing: 4) {
                HStack { historyLabel(window); Spacer(); Text("Live") }
                Text(positionLabel(live: window.live, heard: heard))
            }
        }
        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
    }

    private func historyLabel(_ window: BufferWindow) -> some View {
        Text("−" + duration(window.duration))
            .accessibilityIdentifier("retained-audio-history")
    }

    private func positionLabel(live: Date, heard: Date) -> String {
        if let preview = scrub.preview {
            return "Preview · −\(duration(live.timeIntervalSince(preview)))"
        }
        if clock.sample.isSeeking { return "Seeking…" }
        switch model.state {
        case .playingLive: return "At live edge"
        case .playingDelayed: return "−\(duration(live.timeIntervalSince(heard))) from live"
        default: return model.statusText
        }
    }

    private func commit(_ target: BufferScrubCommit?) {
        switch target {
        case .live: model.goLive()
        case .seek(let date): model.seek(to: date)
        case nil: break
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds).rounded(.down))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func gaps(in window: BufferWindow) -> [ClosedRange<Date>] {
        let ranges = clock.sample.playableRanges
        guard ranges.count > 1 else { return [] }
        return zip(ranges, ranges.dropFirst()).compactMap { previous, next in
            let start = max(window.oldest, previous.upperBound)
            let end = min(window.live, next.lowerBound)
            return end.timeIntervalSince(start) > 0.05 ? start...end : nil
        }
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

/// Keep UIKit's native slider and its actual touch lifecycle. SwiftUI's editing
/// callback can remain active after a normalized/accessibility value adjustment.
/// A control that is not tracking a touch must commit immediately, not preview.
private struct RetainedAudioSlider: UIViewRepresentable {
    let value: Double
    let valueDescription: String
    let onBegin: () -> Void
    let onChange: (Double, Bool) -> Void
    let onEnd: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TrackingSlider {
        let slider = TrackingSlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.isContinuous = true
        slider.accessibilityLabel = "Listening position in retained audio"
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.onBegin = { [weak coordinator = context.coordinator] in coordinator?.parent.onBegin() }
        slider.onEnd = { [weak coordinator = context.coordinator] in coordinator?.parent.onEnd() }
        slider.onCancel = { [weak coordinator = context.coordinator] in coordinator?.parent.onCancel() }
        return slider
    }

    func updateUIView(_ slider: TrackingSlider, context: Context) {
        context.coordinator.parent = self
        slider.tintColor = UIColor(Color.kuscRed)
        slider.accessibilityValue = valueDescription
        // Clock samples may arrive during a long drag. UIKit owns the thumb
        // until touch-end; the frozen station-time range maps its final value.
        if !slider.isTracking { slider.setValue(Float(value), animated: false) }
    }

    @MainActor final class Coordinator: NSObject {
        var parent: RetainedAudioSlider
        init(_ parent: RetainedAudioSlider) { self.parent = parent }
        @objc func changed(_ sender: UISlider) {
            parent.onChange(Double(sender.value), sender.isTracking)
        }
    }

    final class TrackingSlider: UISlider {
        var onBegin: (() -> Void)?
        var onEnd: (() -> Void)?
        var onCancel: (() -> Void)?

        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            let tracking = super.beginTracking(touch, with: event)
            if tracking { onBegin?() }
            return tracking
        }

        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            super.endTracking(touch, with: event)
            onEnd?()
        }

        override func cancelTracking(with event: UIEvent?) {
            super.cancelTracking(with: event)
            onCancel?()
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
