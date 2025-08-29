// ButtonPressDebouncer.swift
// Universal, modern, thread-safe button tap debouncer for pro apps
// Works in SwiftUI, UIKit, and async/await contexts (2025 style)

import Combine // Only Combine is required for ObservableObject conformance
import Foundation

final class ButtonPressDebouncer: ObservableObject {
    @Published private var dummy = false

    private var lastTapDate: Date = .distantPast
    private let minimumInterval: TimeInterval

    /// Create a new debouncer. Default = 500ms between taps.
    init(minimumInterval: TimeInterval = 0.5) {
        self.minimumInterval = minimumInterval
    }

    /// Returns true if enough time has passed since the last accepted press. Otherwise, returns false and ignores the tap.
    @MainActor
    func canPress() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastTapDate) > minimumInterval {
            lastTapDate = now
            return true
        }
        return false
    }
}

// Usage in a SwiftUI view:
// @StateObject private var debouncer = ButtonPressDebouncer()
// Button { if debouncer.canPress() { ... } } label: { Text("...") }
