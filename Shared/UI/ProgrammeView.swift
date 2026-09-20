import SwiftUI
import UIKit

struct ProgrammeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var timeColumnWidth: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(nonempty(model.programmeName) ?? "Programme")
                        .font(.title.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let host = nonempty(model.hostName) {
                        Text(host)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                programmeSection("Previous", items: Array(model.previousItems.prefix(5).reversed()),
                                 emptyMessage: "Previous pieces are unavailable.")
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("Now playing")
                    if let current = model.currentItem {
                        row(current, isCurrent: true)
                            .padding(14)
                            .background(Color.kuscSurface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.kuscSeparator, lineWidth: 0.75)
                            }
                    } else {
                        Text("Current piece information is unavailable.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                programmeSection("Upcoming", items: Array(model.upcomingItems.prefix(10)),
                                 emptyMessage: "Upcoming pieces have not been published.")
                if model.bufferWindow != nil {
                    Text("Hold a retained piece to play from its beginning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.kuscInk)
        .background(Color.kuscBackground)
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.medium))
            .tracking(1)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func programmeSection(_ title: String, items: [ProgrammeItem], emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeading(title)
                Spacer()
                if !items.isEmpty {
                    Text("\(items.count) \(items.count == 1 ? "piece" : "pieces")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(items, id: \.id) { item in
                        row(item)
                            .padding(.vertical, 12)
                        Rectangle()
                            .fill(Color.kuscSeparator)
                            .frame(height: 0.5)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func row(_ item: ProgrammeItem, isCurrent: Bool = false) -> some View {
        let canSeek = model.canSeek(to: item.start)
        return rowContent(item, isCurrent: isCurrent, canSeek: canSeek)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .overlay {
                HapticSeekOverlay(isEnabled: canSeek) {
                    // A retained boundary or gap can change during the hold.
                    guard model.canSeek(to: item.start) else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    model.seek(to: item.start)
                }
                .allowsHitTesting(canSeek)
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityActions {
                if canSeek {
                    Button("Play from beginning") {
                        guard model.canSeek(to: item.start) else { return }
                        model.seek(to: item.start)
                    }
                }
            }
    }

    @ViewBuilder
    private func rowContent(_ item: ProgrammeItem, isCurrent: Bool, canSeek: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                timeLabel(item, isCurrent: isCurrent, canSeek: canSeek)
                pieceLabel(item, isCurrent: isCurrent)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                timeLabel(item, isCurrent: isCurrent, canSeek: canSeek)
                    .frame(width: timeColumnWidth, alignment: .leading)
                    .padding(.top, 3)
                pieceLabel(item, isCurrent: isCurrent)
            }
        }
    }

    private func timeLabel(_ item: ProgrammeItem, isCurrent: Bool, canSeek: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.start, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                .monospacedDigit()
                .accessibilityLabel(item.start.formatted(date: .omitted, time: .shortened))
            if canSeek {
                Image(systemName: "waveform")
                    .accessibilityLabel("Audio retained")
            }
        }
        .font(.caption)
        .foregroundStyle(isCurrent ? Color.kuscRed : Color.secondary)
    }

    private func pieceLabel(_ item: ProgrammeItem, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(nonempty(item.work) ?? "Untitled work")
                .font(.body.weight(isCurrent ? .semibold : .regular))
            if let movement = nonempty(item.movement) {
                Text(movement).font(.subheadline)
            }
            if let composer = nonempty(item.composer) {
                Text(composer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Native timing and movement tolerance; scrolling cancels the hold.
/// A normal tap remains informational and produces no feedback or playback action.
private struct HapticSeekOverlay: UIViewRepresentable {
    let isEnabled: Bool
    let action: () -> Void

    func makeUIView(context: Context) -> HoldView {
        let view = HoldView(frame: .zero)
        view.action = action
        view.hold.isEnabled = isEnabled
        return view
    }

    func updateUIView(_ uiView: HoldView, context: Context) {
        uiView.action = action
        uiView.hold.isEnabled = isEnabled
    }

    final class HoldView: UIView {
        var action: (() -> Void)?
        let hold = UILongPressGestureRecognizer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isAccessibilityElement = false
            hold.addTarget(self, action: #selector(held(_:)))
            hold.cancelsTouchesInView = false
            addGestureRecognizer(hold)
        }

        required init?(coder: NSCoder) { return nil }

        @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state == .began { action?() }
        }
    }
}
