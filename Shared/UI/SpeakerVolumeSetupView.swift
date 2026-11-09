import SwiftUI
import MediaPlayer

struct SpeakerVolumeSetupView: View {
    @ObservedObject var setup: SpeakerVolumeSetup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if setup.phase == .preparing || setup.phase == .restoring || setup.phase == .idle {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(setup.phase == .restoring ? "Restoring audio output…" : "Preparing iPhone speaker…")
                        }
                        .accessibilityIdentifier("speaker-volume-progress")
                    }
                    if setup.phase == .adjusting {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("iPhone speaker", systemImage: "speaker.wave.2")
                                .font(.headline)
                            HStack {
                                Text("Volume")
                                Spacer()
                                Text(setup.volume.formatted(.percent.precision(.fractionLength(0))))
                                    .monospacedDigit().accessibilityIdentifier("speaker-volume-value")
                            }
                            NativeSystemVolumeControl()
                                .frame(height: 44)
                                .accessibilityIdentifier("scheduled-native-volume")
                            if setup.volume == 0 {
                                Label("Speaker volume is zero. Scheduled radio will be silent at this level.", systemImage: "speaker.slash")
                                    .font(.subheadline).foregroundStyle(Color.philharmonicRed)
                            }
                        }
                        Text("Adjust the slider or use the volume buttons, then tap Done. This sets speaker volume now; later volume changes still apply.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if setup.phase == .restoreOutput {
                        Text("Restore previous output").font(.headline)
                        Text(setup.previousRoute.name).font(.body)
                        HStack {
                            Text("Current output: \(setup.currentRoute.name)").fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            AudioRoutePicker().frame(width: 48, height: 48)
                        }
                        Text("Choose your previous output using the system picker. Philharmonic stays paused if you finish without restoring it.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Continue") { Task { await setup.finish(save: false) } }
                            .buttonStyle(PhilharmonicPrimaryButtonStyle())
                            .disabled(!setup.previousOutputRestored)
                            .accessibilityIdentifier("speaker-volume-restore-continue")
                        Button("Finish Without Resuming") { setup.closeWithoutResuming() }
                            .frame(minHeight: 44)
                    }
                    if let message = setup.message {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(Color.philharmonicRed)
                            .accessibilityIdentifier("speaker-volume-message")
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.philharmonicBackground.ignoresSafeArea())
            .foregroundStyle(Color.philharmonicInk)
            .navigationTitle("Scheduled Start Volume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(setup.phase == .finished ? "Close" : "Cancel") {
                        if setup.phase == .finished { dismiss() }
                        else { Task { await setup.finish(save: false) } }
                    }
                    .disabled(setup.phase == .restoring || setup.phase == .restoreOutput)
                    .accessibilityIdentifier("speaker-volume-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if setup.phase == .adjusting {
                        Button("Done") { Task { await setup.finish(save: true) } }
                            .disabled(!setup.canSave)
                            .accessibilityIdentifier("speaker-volume-done")
                    }
                }
            }
        }
        .tint(Color.philharmonicRed)
        .presentationDetents([.large])
        .interactiveDismissDisabled(setup.phase != .finished)
        .task { await setup.begin() }
        .onChange(of: setup.phase) { phase in
            if phase == .finished, setup.message == nil { dismiss() }
        }
        .onDisappear { Task { await setup.finish(save: false, allowRoutePicker: false, permitResume: false) } }
    }
}

/// The visible, user-operated Apple control. No hidden slider, programmatic
/// value mutation, private API or background system-volume write is used.
private struct NativeSystemVolumeControl: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.tintColor = UIColor(Color.philharmonicRed)
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ view: MPVolumeView, context: Context) {
        view.tintColor = UIColor(Color.philharmonicRed)
    }
}
