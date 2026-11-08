import SwiftUI
import UIKit

@MainActor
struct PlaybackDiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var diagnostics: PlaybackDiagnostics
    @State private var shareReport: DebugShareReport?
    @State private var preparingReport = false
    @State private var errorMessage: String?
    @State private var confirmingClear = false

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
                    Label("Last 24 Hours", systemImage: "clock")
                        .font(.headline).accessibilityIdentifier("debug-history-window")
                    if let status = diagnostics.historyStatus {
                        Text("\(status.eventCount) events · \(ByteCountFormatter.string(fromByteCount: Int64(status.bytes), countStyle: .file))")
                            .font(.subheadline).accessibilityIdentifier("debug-history-count")
                        if let date = status.oldest {
                            Text("Oldest: \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let error = status.storageError { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    }
                    NavigationLink("View Recent Logs") { DebugLogPreviewView(diagnostics: diagnostics) }
                        .frame(minHeight: 44).accessibilityIdentifier("debug-view-log")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(cardBackground)
            } footer: {
                Text("Playback and scheduling events are saved locally while the app runs, across app launches. Older records expire after 24 hours. No audio is recorded and nothing is uploaded automatically.")
            }
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
                Text("Detailed Capture")
            } footer: {
                Text("Optional detailed captures add per-second snapshots. The first failure freezes that focused capture; the 24-hour log continues recording failures and recovery. Starting or stopping a capture does not clear the history.")
            }

            if let failure = diagnostics.latestFailureSummary ?? diagnostics.failureSummary {
                Section("Latest failure") {
                    Text(failure)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(cardBackground)
                }
            }

            Section("Reproduce a playback issue") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("1. The standard log is already running. For extra detail, start a capture before reproducing the problem.")
                    Text("2. Return to Now Playing and tap Play. Repeat the actions that cause the problem, such as pausing, resuming or changing audio output.")
                    Text("3. Keep Philharmonic open for at least 45 seconds, or until the failure is captured.")
                    Text("4. Return here to share the full retained log, or copy its newest entries.")
                }
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(cardBackground)
            }

            Section("Report") {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        model.captureDebugSnapshot()
                        preparingReport = true
                        Task {
                            defer { preparingReport = false }
                            do { shareReport = DebugShareReport(url: try await diagnostics.makeHistoryReport()) }
                            catch { errorMessage = PlaybackDiagnosticLog.sanitizedError(error) }
                        }
                    } label: {
                        Label("Share Report", systemImage: "square.and.arrow.up")
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("debug-share-report")

                    Button {
                        Task {
                            do { UIPasteboard.general.string = try await diagnostics.recentHistory() }
                            catch { errorMessage = PlaybackDiagnosticLog.sanitizedError(error) }
                        }
                    } label: {
                        Label("Copy Recent Logs", systemImage: "doc.on.doc")
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("debug-copy-log")
                    Button("Clear Local Log", role: .destructive) { confirmingClear = true }
                        .frame(minHeight: 44).accessibilityIdentifier("debug-clear-log")
                }
                .buttonStyle(.borderless)
                .disabled(preparingReport)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.philharmonicBackground)
        .foregroundStyle(Color.philharmonicInk)
        .tint(.philharmonicRed)
        .navigationTitle("debug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.philharmonicBackground, for: .navigationBar)
        .task { model.captureDebugSnapshot(); await diagnostics.refreshHistory() }
        .refreshable { model.captureDebugSnapshot(); await diagnostics.refreshHistory() }
        .sheet(item: $shareReport) { DiagnosticsShareSheet(reportURL: $0.url) }
        .confirmationDialog("Clear the local debug log?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear Log", role: .destructive) {
                Task {
                    do { try await diagnostics.clearHistory() }
                    catch { errorMessage = PlaybackDiagnosticLog.sanitizedError(error) }
                }
            }
        }
        .alert("debug", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.philharmonicSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.philharmonicSeparator, lineWidth: 0.75)
            }
    }
}

private struct DebugShareReport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DebugLogPreviewView: View {
    @ObservedObject var diagnostics: PlaybackDiagnostics
    @State private var text = "Loading…"
    var body: some View {
        ScrollView {
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
        .background(Color.philharmonicBackground).foregroundStyle(Color.philharmonicInk)
        .navigationTitle("Recent Logs").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("debug-log-preview")
        .task {
            do { text = try await diagnostics.recentHistory() }
            catch { text = PlaybackDiagnosticLog.sanitizedError(error) }
        }
    }
}
