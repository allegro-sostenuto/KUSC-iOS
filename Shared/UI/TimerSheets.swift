import SwiftUI

struct SleepTimerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var hours = 0
    @State private var minutes = 0

    private var totalMinutes: Int { min(720, hours * 60 + minutes) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Picker("Hours", selection: Binding(
                            get: { hours },
                            set: { value in
                                if value == 12 { minutes = 0 }
                                hours = value
                            }
                        )) {
                            ForEach(0...12, id: \.self) { value in
                                Text("\(value) \(value == 1 ? "hour" : "hours")").tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        Picker("Minutes", selection: $minutes) {
                            ForEach(0...(hours == 12 ? 0 : 59), id: \.self) { value in
                                Text("\(value) min").tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .disabled(hours == 12)
                    }
                    .frame(height: 180)
                    Button(totalMinutes == 0 ? "Turn timer off" : "Start sleep timer") {
                        model.startSleep(minutes: totalMinutes)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .fontWeight(.semibold)
                } footer: {
                    Text("At expiry, playback finishes the current piece if its known end is within 10 minutes. Otherwise playback fades out. Missing timing uses the next piece’s start when available.")
                }
                if let description = model.sleepDescription {
                    Section("Active timer") {
                        Text(description)
                        Button("Cancel sleep timer", role: .destructive) {
                            model.cancelSleep()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                let duration = min(720, max(0, model.settings.lastSleepMinutes))
                hours = duration / 60
                minutes = duration % 60
            }
        }
    }
}

struct ScheduledStartView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var createdAt = Date()
    @State private var selectedDate = Date().addingTimeInterval(300)
    @State private var isScheduling = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start time", selection: $selectedDate,
                               in: createdAt...createdAt.addingTimeInterval(24 * 60 * 60),
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                    Button {
                        isScheduling = true
                        Task { @MainActor in
                            do {
                                try await model.scheduleStart(at: selectedDate)
                                dismiss()
                            } catch {
                                failure = error.localizedDescription
                            }
                            isScheduling = false
                        }
                    } label: {
                        HStack {
                            Text("Schedule start")
                            Spacer()
                            if isScheduling { ProgressView() }
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(isScheduling)
                } header: {
                    Text("Once within the next 24 hours")
                } footer: {
                    Text("While charging, KUSC keeps a standby session for automatic playback when iOS permits. A notification remains as a fallback. On battery, tap the notification to start playback.")
                }
                if let description = model.scheduleDescription {
                    Section("Current schedule") {
                        Text(description)
                        Button("Cancel scheduled start", role: .destructive) {
                            model.cancelSchedule()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Scheduled Start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Unable to schedule", isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            )) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
        }
    }
}
