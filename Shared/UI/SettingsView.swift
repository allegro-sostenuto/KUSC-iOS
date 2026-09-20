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
                Section("Playback") {
                    Toggle("Auto-play on launch", isOn: preference(\.autoplay))
                    Picker("Resume after pause", selection: preference(\.resumeWherePaused)) {
                        Text("Resume Live").tag(false)
                        Text("Resume Where Paused").tag(true)
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    Picker("Rolling buffer duration", selection: preference(\.retentionMinutes)) {
                        ForEach(0...15, id: \.self) { minutes in
                            Text(minutes == 0 ? "Off" : "\(minutes) \(minutes == 1 ? "minute" : "minutes")")
                                .tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(minHeight: 150, maxHeight: 180)
                } header: {
                    Text("Rolling buffer")
                } footer: {
                    Text("Retains up to 15 minutes for rewind. If a paused position expires, Resume Where Paused starts at the oldest retained audio. Buffering can continue while paused when iOS permits.")
                }

                Section("Interface") {
                    Toggle("Minimalist UI", isOn: preference(\.minimalist))
                    Picker("Appearance", selection: preference(\.appearance)) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
