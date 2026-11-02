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

}
