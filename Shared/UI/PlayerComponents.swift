import AVKit
import SwiftUI

struct AlbumArtwork: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color(uiColor: .secondarySystemBackground)
                    Image(systemName: "music.note")
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(image == nil ? "Album artwork unavailable" : "Album artwork")
    }
}

struct NowPlayingMetadata: View {
    let item: ProgrammeItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let item {
                Text(item.title.isEmpty ? "KUSC FM 91.5" : item.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !item.composer.isEmpty {
                    Text(item.composer)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.performers.isEmpty {
                    Text(item.performers)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("KUSC FM 91.5")
                    .font(.title3.weight(.semibold))
                Text("Programme information is currently unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlayerControls: View {
    @EnvironmentObject private var model: AppModel
    let togglePlayback: () -> Void
    @State private var scrubTimestamp: Double?

    var body: some View {
        VStack(spacing: 7) {
            if model.settings.retentionMinutes > 0 {
                bufferSlider
            }
            HStack(alignment: .center, spacing: 24) {
                Button(action: togglePlayback) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 62, height: 56)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.kuscRed)
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                Button { model.goLive() } label: {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Jump to live")
            }
            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let sleep = model.sleepDescription {
                Label(sleep, systemImage: "moon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let schedule = model.scheduleDescription {
                Label(schedule, systemImage: "alarm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = model.notice, !notice.isEmpty {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var bufferSlider: some View {
        if let window = model.bufferWindow,
           window.live.timeIntervalSince(window.oldest) > 0.5 {
            let lower = window.oldest.timeIntervalSince1970
            let upper = window.live.timeIntervalSince1970
            VStack(spacing: 0) {
                Slider(value: Binding(
                    get: { min(upper, max(lower, scrubTimestamp ?? model.heardAt.timeIntervalSince1970)) },
                    set: { scrubTimestamp = $0 }
                ), in: lower...upper) { editing in
                    if !editing, let timestamp = scrubTimestamp {
                        if let currentWindow = model.bufferWindow {
                            model.seek(to: currentWindow.clamped(Date(timeIntervalSince1970: timestamp)))
                        }
                        scrubTimestamp = nil
                    }
                }
                .accessibilityLabel("Listening position in retained audio")
                HStack {
                    Text(window.oldest, style: .time)
                    Spacer()
                    if let timestamp = scrubTimestamp {
                        Text(Date(timeIntervalSince1970: timestamp), style: .time)
                        Spacer()
                    }
                    Text("Live")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        } else {
            Text("No retained audio yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct AudioOutputView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                AudioRoutePicker()
                    .frame(width: 64, height: 64)
                    .accessibilityLabel("Choose audio output")
                Text("Tap to choose an available audio output.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                Text("iPhone, Bluetooth, and AirPlay routes are managed by iOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Audio Output")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct AudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(Color.kuscRed)
        view.activeTintColor = UIColor(Color.kuscRed)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}
