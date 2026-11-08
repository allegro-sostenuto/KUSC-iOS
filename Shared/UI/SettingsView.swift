import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var bitrateWidth: CGFloat = 80

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
                    Toggle("Auto-play on launch", isOn: preference(\.autoplay))
                        .modifier(SettingsRow(first: true, last: false))
                    NavigationLink {
                        PlaybackDiagnosticsView(diagnostics: model.diagnostics)
                    } label: {
                        Text("debug")
                    }
                    .accessibilityIdentifier("debug-settings-link")
                    .modifier(SettingsRow(first: false, last: true))
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Playback is live-only. Play returns to live after a pause.")
                }

                Section {
                    qualityPresets
                        .modifier(SettingsRow(first: true, last: false))
                    ForEach(model.orderedStations) { station in
                        qualityRow(station)
                        .modifier(SettingsRow(first: false,
                                              last: station.id == model.orderedStations.last?.id))
                    }
                } header: {
                    Text("Quality")
                } footer: {
                    Text("Presets apply to all stations. Balanced chooses the available bitrate closest to KUSC (\(StationCatalog.defaultStation.defaultAudioSource.bitrateKbps) kbps), favouring the lower rate in a tie. Tap a station's bitrate to adjust it individually.")
                }

                Section("Interface") {
                    Toggle("Minimalist UI", isOn: preference(\.minimalist))
                        .modifier(SettingsRow(first: true, last: false))
                    Picker("Appearance", selection: preference(\.appearance)) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("appearance-picker")
                    .modifier(SettingsRow(first: false, last: true))
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
                        .modifier(SettingsRow(first: true, last: false))
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
                        .modifier(SettingsRow(first: false, last: true))
                }
            }
            .environment(\.defaultMinListRowHeight, 52)
            .scrollContentBackground(.hidden)
            .background(colorScheme == .dark ? Color.black : Color(uiColor: .systemGroupedBackground))
            .foregroundStyle(Color.philharmonicInk)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(colorScheme == .dark ? Color.black : Color(uiColor: .systemGroupedBackground), for: .navigationBar)
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

    private var qualityPresets: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(StationQualityPreset.allCases) { preset in
                Button { model.applyAudioQualityPreset(preset) } label: {
                    Text(preset.title).lineLimit(1)
                        .font(.subheadline.weight(.medium))
                        .padding(.vertical, 6).frame(maxWidth: .infinity, minHeight: 44)
                        .philharmonicControlSurface(Capsule())
                        .overlay(Capsule().inset(by: 0.5).strokeBorder(
                            model.matchesAudioQualityPreset(preset) ? Color.philharmonicRed : .clear,
                            lineWidth: 1))
                }
                .buttonStyle(.plain).foregroundStyle(Color.philharmonicRed)
                .accessibilityIdentifier("quality-preset-\(preset.rawValue)")
                .accessibilityLabel("\(preset.title) quality for all stations")
                .accessibilityAddTraits(model.matchesAudioQualityPreset(preset) ? [.isSelected] : [])
            }
        }.padding(.vertical, 4)
    }

    @ViewBuilder private func qualityRow(_ station: RadioStation) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(station: station)
                qualityMenu(station).frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                Text(station: station).frame(maxWidth: .infinity, alignment: .leading)
                qualityMenu(station)
            }
        }
    }

    private func qualityMenu(_ station: RadioStation) -> some View {
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
            HStack(alignment: .center, spacing: 6) {
                Text("\(model.settings.audioSource(for: station).bitrateKbps) kbps")
                    .monospacedDigit()
                    .lineLimit(1).frame(width: bitrateWidth, alignment: .trailing)
                ZStack {
                    if station.audioSources.count == 1 {
                        Text("ø").font(.system(size: 13)).offset(y: -1)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .frame(width: 14, height: 14, alignment: .center)
            }
            .fixedSize()
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(station.name) quality")
        .accessibilityValue(model.settings.audioSource(for: station).description)
        .accessibilityIdentifier("quality-menu-\(station.id)")
        .disabled(station.audioSources.count == 1)
    }
}

/// Native Form rows own text, control placement and separators. The background
/// draws just the outside of their shared group, safely inside Form's mask.
private struct SettingsRow: ViewModifier {
    let first: Bool
    let last: Bool

    func body(content: Content) -> some View {
        content
            .frame(minHeight: 44)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparatorTint(Color.philharmonicSeparator)
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparator(last ? .hidden : .visible, edges: .bottom)
            .listRowBackground(SettingsGroupBackground(first: first, last: last))
    }
}

private struct SettingsGroupBackground: View {
    let first: Bool
    let last: Bool

    var body: some View {
        Color.philharmonicSurface.overlay {
            GeometryReader { geometry in
                // Extend unused ends beyond this row. Adjacent rows meet at
                // straight edges; only the first/last own the group's corners.
                let above: CGFloat = first ? 0 : 56
                let below: CGFloat = last ? 0 : 56
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .inset(by: 1)
                    .strokeBorder(Color.philharmonicSeparator, lineWidth: 0.75)
                    .frame(width: geometry.size.width, height: geometry.size.height + above + below)
                    .offset(y: -above)
            }
        }.clipped()
    }
}
