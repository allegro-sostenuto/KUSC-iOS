import SwiftUI
import UIKit

@MainActor
struct PlaybackDiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var diagnostics: PlaybackDiagnostics

    private var status: String {
        if diagnostics.failureSummary != nil { return "Failure captured" }
        return diagnostics.isRecording ? "Recording" : "Ready"
    }

    private var statusSymbol: String {
        if diagnostics.failureSummary != nil { return "exclamationmark.circle" }
        return diagnostics.isRecording ? "record.circle" : "waveform.path.ecg"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(status, systemImage: statusSymbol)
                        .font(.headline)
                        .accessibilityIdentifier("playback-diagnostics-status")

                    Button("Start New Capture") {
                        model.startPlaybackDiagnostics()
                    }
                    .frame(minHeight: 44)
                    .disabled(diagnostics.isRecording)

                    Button("Stop Capture") {
                        model.stopPlaybackDiagnostics()
                    }
                    .frame(minHeight: 44)
                    .disabled(!diagnostics.isRecording)
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(cardBackground)
            } header: {
                Text("Capture")
            } footer: {
                Text("Captures stay on this device for the current app launch, including reconnects. No audio is recorded and nothing is uploaded automatically. The first failure freezes the report. Start New Capture replaces the previous report.")
            }

            if let failure = diagnostics.failureSummary {
                Section("Latest failure") {
                    Text(failure)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(cardBackground)
                }
            }

            Section("Reproduce the buffer issue") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("1. Set the rolling buffer to 5 minutes in Settings, then start a new capture here.")
                    Text("2. Return to Now Playing and tap Play. Once you hear audio and history appears, pause before the left label reaches −00:14. If it fails sooner, save that report anyway.")
                    Text("3. Keep KUSC open and the screen unlocked for 45 seconds, or until the history disappears.")
                    Text("4. After the problem occurs, return here to share or copy the report.")
                }
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(cardBackground)
            }

            Section("Report") {
                VStack(alignment: .leading, spacing: 12) {
                    ShareLink(item: diagnostics.report) {
                        Label("Share Report", systemImage: "square.and.arrow.up")
                    }
                    .frame(minHeight: 44)

                    Button {
                        UIPasteboard.general.string = diagnostics.report
                    } label: {
                        Label("Copy Report", systemImage: "doc.on.doc")
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .disabled(diagnostics.report.isEmpty)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.kuscBackground)
        .foregroundStyle(Color.kuscInk)
        .tint(.kuscRed)
        .navigationTitle("Playback Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kuscBackground, for: .navigationBar)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.kuscSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.kuscSeparator, lineWidth: 0.75)
            }
    }
}
