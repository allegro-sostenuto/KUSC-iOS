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
                            AdvancedPlaybackSettingsView()
                        } label: {
                            Text("Advanced")
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
                    Text("Playback is live-only. Play returns to live after a pause.")
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
                Section("About") {
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"))")
                        .listRowBackground(cardBackground)
                }

            }
            .scrollContentBackground(.hidden)
            .background(Color.philharmonicBackground)
            .foregroundStyle(Color.philharmonicInk)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.philharmonicBackground, for: .navigationBar)
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
        .tint(.philharmonicRed)
        .philharmonicSheetBackground()
    }

    private var divider: some View {
        Rectangle().fill(Color.philharmonicSeparator).frame(height: 0.5)
            .accessibilityHidden(true)
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

private struct AdvancedPlaybackSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("Audio quality", selection: Binding(
                    get: { model.settings.audioQuality },
                    set: { model.setAudioQuality($0) }
                )) {
                    Text("Standard").tag(StationAudioQuality.standard)
                    Text("High").tag(StationAudioQuality.high)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 8)
                .listRowBackground(cardBackground)
            } header: {
                Text("Audio quality")
            } footer: {
                Text("Standard targets 96–128 kbps, similar to KUSC. High uses a higher-rate stream where available. Stations without a lower-rate source keep their available quality.")
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.selectedStation.name)
                    Text(model.selectedAudioSource.description)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("selected-audio-quality")
                }
                .padding(.vertical, 6)
                .listRowBackground(cardBackground)
            } header: {
                Text("Current station")
            } footer: {
                Text("Changing quality rejoins live. A paused player stays paused. Your choice applies to all stations and is saved for next time.")
            }
            Section {
                NavigationLink("Playback Diagnostics") {
                    PlaybackDiagnosticsView(diagnostics: model.diagnostics)
                }
                .listRowBackground(cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.philharmonicBackground)
        .foregroundStyle(Color.philharmonicInk)
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.philharmonicBackground, for: .navigationBar)
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
