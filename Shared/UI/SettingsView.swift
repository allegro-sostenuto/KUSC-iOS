import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private func preference<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in
                model.settings[keyPath: keyPath] = value
                model.updateSettings()
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 0) {
                        Toggle("Auto-play on launch", isOn: preference(\.autoplay))
                            .padding(.vertical, 10)
                        divider
                        NavigationLink {
                            resumePreferences
                        } label: {
                            HStack(spacing: 12) {
                                Text("Resume after pause")
                                Spacer(minLength: 8)
                                Text(model.settings.resumeWherePaused ? "Where Paused" : "Live")
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        divider
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Rolling buffer")
                            Spacer(minLength: 8)
                            Text(durationLabel)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 14)
                        divider
                        Picker("Rolling buffer duration", selection: preference(\.retentionMinutes)) {
                            ForEach(0...15, id: \.self) { minutes in
                                Text("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
                                    .tag(minutes)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)
                        .clipped()
                        divider
                        NavigationLink {
                            PlaybackDiagnosticsView(diagnostics: model.diagnostics)
                        } label: {
                            Text("Playback Diagnostics")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(cardBackground)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Retain up to 15 minutes of audio. At 0, playback stays live. An expired paused position resumes at the oldest retained audio; retention while paused depends on iOS.")
                }

                Section("Interface") {
                    VStack(alignment: .leading, spacing: 0) {
                        Toggle("Minimalist UI", isOn: preference(\.minimalist))
                            .padding(.vertical, 10)
                        divider
                        Text("Appearance")
                            .padding(.top, 14)
                            .padding(.bottom, 10)
                        Picker("Appearance", selection: preference(\.appearance)) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 10)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.kuscBackground)
            .foregroundStyle(Color.kuscInk)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kuscBackground, for: .navigationBar)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .confirmationAction) {
                        SheetCloseButton { dismiss() }
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        SheetCloseButton { dismiss() }
                    }
                }
            }
        }
        .tint(.kuscRed)
        .kuscSheetBackground()
    }

    private var durationLabel: String {
        let minutes = model.settings.retentionMinutes
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }

    private var divider: some View {
        Rectangle().fill(Color.kuscSeparator).frame(height: 0.5)
            .accessibilityHidden(true)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.kuscSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.kuscSeparator, lineWidth: 0.75)
            }
    }

    private var resumePreferences: some View {
        List {
            Picker("Resume after pause", selection: preference(\.resumeWherePaused)) {
                Text("Resume Live").tag(false)
                Text("Resume Where Paused").tag(true)
            }
            .pickerStyle(.inline)
            .listRowBackground(Color.kuscSurface)
        }
        .scrollContentBackground(.hidden)
        .background(Color.kuscBackground)
        .navigationTitle("Resume after pause")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kuscBackground, for: .navigationBar)
    }
}
