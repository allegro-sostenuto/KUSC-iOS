import Foundation

public enum BufferScrubCommit: Equatable {
    case live
    case seek(Date)
}

/// A drag freezes only its coordinate range. Published history remains live,
/// and an adjustment outside a drag must never leave a pending preview behind.
public struct BufferScrubState {
    public private(set) var frozenWindow: BufferWindow?
    public private(set) var preview: Date?
    private var lastCommittedValue: Date?

    public init() {}
    public var isEditing: Bool { frozenWindow != nil }

    public mutating func begin(in window: BufferWindow) {
        guard !isEditing else { return }
        frozenWindow = window
        preview = nil
        lastCommittedValue = nil
    }

    public mutating func update(_ value: Date, currentWindow: BufferWindow) -> BufferScrubCommit? {
        if let frozenWindow {
            preview = frozenWindow.clamped(value)
            return nil
        }
        // Native accessibility adjustments and a final value delivered after
        // editing ended are commits, not the beginning of another drag.
        return commit(value, in: currentWindow)
    }

    public mutating func end() -> BufferScrubCommit? {
        let window = frozenWindow
        let value = preview
        frozenWindow = nil
        preview = nil
        guard let window, let value else { return nil }
        return commit(value, in: window)
    }

    /// Accessibility/value-setting events do not have to deliver a matching
    /// touch-end callback. A non-tracking value is already a complete action.
    public mutating func finishAdjustment(_ value: Date, currentWindow: BufferWindow) -> BufferScrubCommit? {
        let window = frozenWindow ?? currentWindow
        frozenWindow = nil
        preview = nil
        return commit(value, in: window)
    }

    public mutating func cancel() {
        frozenWindow = nil
        preview = nil
        lastCommittedValue = nil
    }

    private mutating func commit(_ value: Date, in window: BufferWindow) -> BufferScrubCommit? {
        let target = window.clamped(value)
        // Some native controls deliver their last value again after editing-end.
        // Do not turn that duplicate into a second seek or a frozen preview.
        guard target != lastCommittedValue else { return nil }
        lastCommittedValue = target
        return target >= window.live.addingTimeInterval(-0.5) ? .live : .seek(target)
    }
}
