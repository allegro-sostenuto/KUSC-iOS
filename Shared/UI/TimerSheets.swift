import SwiftUI

struct SleepTimerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hours = 0
    @State private var minutes = 0

    private var totalMinutes: Int { min(720, hours * 60 + minutes) }

    var body: some View {
        TimerSheetLayout(title: "Sleep Timer") {
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
                .clipped()
                Picker("Minutes", selection: $minutes) {
                    ForEach(0...(hours == 12 ? 0 : 59), id: \.self) { value in
                        Text("\(value) min").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
                .disabled(hours == 12)
            }
            .frame(height: 180)

            Text("At the end, finish the current movement if its known end is within 10 minutes. Otherwise, fade out over 1 minute. If timing is missing, use the next piece’s start when available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let description = model.sleepDescription {
                TimerStatusCard(title: "Active timer", message: description, symbol: "moon.zzz")
            }

            if model.sleepDescription != nil {
                Button("Cancel Sleep Timer", role: .destructive) {
                    model.cancelSleep()
                    dismiss()
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        } footer: {
            Button(totalMinutes == 0 ? "Turn Timer Off" : "Start Timer") {
                model.startSleep(minutes: totalMinutes)
                dismiss()
            }
            .buttonStyle(KUSCPrimaryButtonStyle())
            .accessibilityIdentifier("timer-primary-action")
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            let duration = min(720, max(0, model.settings.lastSleepMinutes))
            hours = duration / 60
            minutes = duration % 60
        }
    }
}

struct ScheduledStartView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var createdAt = Date()
    @State private var selectedDate = Date().addingTimeInterval(300)
    @State private var prefersSpecificOutput = false
    @State private var preferredRoute: ObservedAudioRoute?
    @State private var fallback: ScheduleFallback = .notifyOnly
    @State private var isScheduling = false
    @State private var failure: String?

    private var outputPreference: ScheduledOutputPreference {
        prefersSpecificOutput
            ? ScheduledOutputPreference(route: preferredRoute, fallback: fallback)
            : .currentOutput
    }

    var body: some View {
        TimerSheetLayout(title: "Scheduled Start") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start once")
                    .font(.headline)
                Text("Within the next 24 hours")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                DatePicker("Reach normal volume at", selection: $selectedDate,
                           in: createdAt...createdAt.addingTimeInterval(24 * 60 * 60),
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityLabel("Reach normal volume at")
                    .disabled(isScheduling)
            }

            Text("Starts silently 1 minute early. Fades in during the last 10 seconds to reach normal volume at the selected time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            outputControls
                .disabled(isScheduling)
                .id("scheduled-output")

            TimerStatusCard(
                title: "Automatic start & notification",
                message: "Automatic start is best effort while charging, with a brief grace period after unplugging. Otherwise, tap the notification to start. A backup notification remains scheduled.",
                symbol: "bell"
            )

            if let description = model.scheduleDescription {
                TimerStatusCard(title: "Current schedule", message: description, symbol: "clock")
            }

            if model.scheduleDescription != nil {
                Button("Cancel Scheduled Start", role: .destructive) {
                    model.cancelSchedule()
                    dismiss()
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isScheduling)
            }
        } footer: {
            Button {
                isScheduling = true
                Task { @MainActor in
                    do {
                        try await model.scheduleStart(at: selectedDate, output: outputPreference)
                        dismiss()
                    } catch {
                        failure = error.localizedDescription
                    }
                    isScheduling = false
                }
            } label: {
                HStack(spacing: 10) {
                    if isScheduling { ProgressView().tint(Color.kuscInk) }
                    Text(isScheduling ? "Scheduling…" : "Schedule Start")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(KUSCPrimaryButtonStyle())
            .accessibilityIdentifier("schedule-primary-action")
            .disabled(isScheduling || (prefersSpecificOutput && preferredRoute == nil))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            model.refreshCurrentOutput()
            if let route = model.scheduledOutput.route {
                prefersSpecificOutput = true
                preferredRoute = route
                fallback = model.scheduledOutput.fallback
            }
            #if DEBUG
            if UIFixture.state == "schedule-output", model.currentOutputRoute.isIdentifiable {
                prefersSpecificOutput = true
                preferredRoute = model.currentOutputRoute
            }
            #endif
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

    private var outputControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Output")
                .font(.headline)
            Picker("Output policy", selection: $prefersSpecificOutput) {
                Text("Current output").tag(false)
                Text("Selected output").tag(true)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Currently selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.currentOutputName)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                AudioRoutePicker()
                    .frame(width: 48, height: 48)
                    .background(Color.kuscSurface, in: Circle())
                    .overlay { Circle().strokeBorder(Color.kuscSeparator, lineWidth: 0.75) }
                    .accessibilityLabel("Choose audio output")
            }

            Text("Choosing an output changes the system route immediately.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if prefersSpecificOutput {
                Button {
                    // Read the real route at confirmation; opening or dismissing
                    // Apple's picker is not proof that an output changed.
                    model.refreshCurrentOutput()
                    guard model.currentOutputRoute.isIdentifiable else { return }
                    preferredRoute = model.currentOutputRoute
                } label: {
                    Label("Use Current Selection for This Start", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .disabled(!model.currentOutputRoute.isIdentifiable)

                if let preferredRoute {
                    Text("Planned output: \(preferredRoute.name)")
                        .font(.subheadline.weight(.medium))
                    if !preferredRoute.matches(model.currentOutputRoute) {
                        Label("The planned output is not currently selected.", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(Color.kuscRed)
                    }
                } else {
                    Text(model.currentOutputRoute.isIdentifiable
                         ? "Confirm the actual selected output above before scheduling."
                         : "This output cannot be identified reliably. Choose another output or use Current output.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("If the output is unavailable", selection: $fallback) {
                    Text("Notify only").tag(ScheduleFallback.notifyOnly)
                    Text("Use current output").tag(ScheduleFallback.currentOutput)
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44)

                Text(fallback == .notifyOnly
                     ? "If the planned output is unavailable or no longer selected, scheduled audio stays silent and a notification remains."
                     : "If the planned output is unavailable or no longer selected, playback may use the current output, including the iPhone speaker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Keep the planned output available and selected. KUSC cannot reconnect Bluetooth or choose an AirPlay destination automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("At start time, use whichever output the system has selected, including the iPhone speaker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.kuscSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.kuscSeparator, lineWidth: 0.75)
        }
    }
}

private struct TimerSheetLayout<Content: View, Footer: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let content: Content
    let footer: Footer

    init(title: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Text(title)
                    .font(.title.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                SheetCloseButton { dismiss() }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                #if DEBUG
                .onAppear {
                    if UIFixture.state == "schedule-output" {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            proxy.scrollTo("scheduled-output", anchor: .top)
                        }
                    }
                }
                #endif
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(Color.kuscSurface)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.kuscSeparator).frame(height: 0.5)
                }
        }
        .foregroundStyle(Color.kuscInk)
        .background(Color.kuscSurface.ignoresSafeArea())
        .tint(.kuscRed)
        .kuscSheetBackground()
    }
}

private struct TimerStatusCard: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.kuscRed)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.kuscBackground, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.kuscSeparator, lineWidth: 0.75)
        }
    }
}
