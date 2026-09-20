import SwiftUI
import UIKit

struct ProgrammeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(nonempty(model.programmeName) ?? "Programme")
                        .font(.title2.weight(.semibold))
                    if let host = nonempty(model.hostName) {
                        Text(host).font(.body).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("Listening at")
                        Text(model.heardAt, style: .time)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if model.bufferWindow != nil {
                    Text("Hold a retained piece to play from its beginning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                programmeSection("Previous", items: Array(model.previousItems.prefix(5)),
                                 emptyMessage: "Previous pieces are unavailable.")
                if let current = model.currentItem {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeading("Now heard")
                        row(current)
                    }
                }
                programmeSection("Upcoming", items: Array(model.upcomingItems.prefix(10)),
                                 emptyMessage: "Upcoming pieces have not been published.")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    private func programmeSection(_ title: String, items: [ProgrammeItem], emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(title)
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.id) { item in
                    row(item)
                    Divider()
                }
            }
        }
    }

    private func row(_ item: ProgrammeItem) -> some View {
        let canSeek = model.settings.retentionMinutes > 0 &&
            model.bufferWindow?.contains(item.start) == true &&
            item.start <= Date()
        return VStack(alignment: .leading, spacing: 5) {
            Text(item.title.isEmpty ? "Untitled work" : item.title)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if !item.composer.isEmpty {
                Text(item.composer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(item.start, style: .time)
                if canSeek {
                    Image(systemName: "waveform")
                        .accessibilityLabel("Audio retained")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .overlay {
            HapticSeekOverlay(isEnabled: canSeek) {
                // Recheck because the retained boundary can advance during the hold.
                guard model.bufferWindow?.contains(item.start) == true else { return }
                model.seek(to: item.start)
            }
            .allowsHitTesting(canSeek)
            .accessibilityHidden(true)
        }
    }
}

/// Uses the recognizer's native default timing and movement tolerance.
/// Single taps have no playback action; scrolling cancels the hold.
private struct HapticSeekOverlay: UIViewRepresentable {
    let isEnabled: Bool
    let action: () -> Void

    func makeUIView(context: Context) -> HoldView {
        let view = HoldView(frame: .zero)
        view.action = action
        view.isHoldEnabled = isEnabled
        return view
    }

    func updateUIView(_ uiView: HoldView, context: Context) {
        uiView.action = action
        uiView.isHoldEnabled = isEnabled
    }

    final class HoldView: UIView {
        var action: (() -> Void)?
        var isHoldEnabled = false {
            didSet {
                hold.isEnabled = isHoldEnabled
                if !isHoldEnabled { cancelFeedback() }
            }
        }
        private let hold = UILongPressGestureRecognizer()
        private let onset = UIImpactFeedbackGenerator(style: .soft)
        private let middle = UIImpactFeedbackGenerator(style: .medium)
        private let completion = UIImpactFeedbackGenerator(style: .heavy)
        private var feedbackWork: [DispatchWorkItem] = []
        private var origin: CGPoint?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isAccessibilityElement = false
            hold.addTarget(self, action: #selector(held(_:)))
            hold.cancelsTouchesInView = false
            addGestureRecognizer(hold)
        }

        required init?(coder: NSCoder) { return nil }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            guard isHoldEnabled else { return }
            cancelFeedback()
            origin = touches.first?.location(in: self)
            onset.prepare()
            middle.prepare()
            completion.prepare()
            stageFeedback(after: hold.minimumPressDuration * 0.2) { [weak self] in
                self?.onset.impactOccurred(intensity: 0.45)
            }
            stageFeedback(after: hold.minimumPressDuration * 0.6) { [weak self] in
                self?.middle.impactOccurred(intensity: 0.7)
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            if let origin, let point = touches.first?.location(in: self),
               hypot(point.x - origin.x, point.y - origin.y) > hold.allowableMovement {
                cancelFeedback()
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            cancelFeedback()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            cancelFeedback()
        }

        @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                cancelFeedback()
                completion.impactOccurred()
                action?()
            case .cancelled, .failed, .ended:
                cancelFeedback()
            default:
                break
            }
        }

        private func stageFeedback(after delay: TimeInterval, action: @escaping () -> Void) {
            let work = DispatchWorkItem(block: action)
            feedbackWork.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func cancelFeedback() {
            feedbackWork.forEach { $0.cancel() }
            feedbackWork.removeAll()
            origin = nil
        }

        deinit { feedbackWork.forEach { $0.cancel() } }
    }
}
