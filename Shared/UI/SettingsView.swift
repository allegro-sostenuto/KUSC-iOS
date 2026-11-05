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
                    Text("Playback is live-only. Play returns to live after a pause.")
                }

                Section {
                    VStack(spacing: 0) {
                        ForEach(model.orderedStations) { station in
                            if station.id != model.orderedStations.first?.id { divider }
                            HStack(spacing: 12) {
                                Text(station.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Menu {
                                    ForEach(station.audioSources) { source in
                                        Button {
                                            model.setAudioSource(source.id, for: station.id)
                                        } label: {
                                            if model.settings.audioSource(for: station).id == source.id {
                                                Label(source.description, systemImage: "checkmark")
                                            } else {
                                                Text(source.description)
                                            }
                                        }
                                        .accessibilityIdentifier("audio-source-\(source.id)")
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("\(model.settings.audioSource(for: station).bitrateKbps) kbps")
                                            .monospacedDigit()
                                        if station.audioSources.count == 1 {
                                            Text("ø").font(.caption2)
                                        } else {
                                            Image(systemName: "chevron.down").font(.caption2)
                                        }
                                    }
                                    .fixedSize()
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .accessibilityLabel("\(station.name) quality")
                                .accessibilityValue(model.settings.audioSource(for: station).description)
                                .accessibilityIdentifier("quality-menu-\(station.id)")
                                .disabled(station.audioSources.count == 1)
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(cardBackground)
                } header: {
                    Text("Quality")
                } footer: {
                    Text("Tap a bitrate to choose that channel's quality. Defaults are near 96–128 kbps where available. Each channel's choice is saved. Changing the playing channel's quality rejoins live; a paused player stays paused.")
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
