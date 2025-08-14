// MemoryManager.swift
// Centralizes all memory cleanup, system warning observers, and app-wide memory-related notifications.

import Foundation
import UIKit

/// Singleton for global memory management. Performs cleanup and notifies observers on system memory warnings.
final class MemoryManager: ObservableObject {
    static let shared = MemoryManager()

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Returns the current process memory usage (MB).
    static func currentMemoryUsageMB() -> Float {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return Float(info.resident_size) / 1024.0 / 1024.0
    }

    /// Emergency cleanup for caches and memory pressure. Posts notifications for all listeners to reduce usage.
    @objc private func handleMemoryWarning() {
        print("🚨 MemoryManager: System memory warning received. Broadcasting cleanup notifications.")
        autoreleasepool {
            URLCache.shared.removeAllCachedResponses()
            // Small allocation trick to trigger further GC.
            var dummy: [Data] = []
            for _ in 0..<100 { dummy.append(Data(count: 1024)) }
            dummy.removeAll()
        }
        // Notify all components to reduce memory, lower quality, reduce frame rate, etc.
        NotificationCenter.default.post(name: .reduceQualityForMemory, object: nil)
        NotificationCenter.default.post(name: .reduceFrameRate, object: nil)
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let reduceQualityForMemory = Notification.Name("reduceQualityForMemory")
    static let reduceFrameRate = Notification.Name("reduceFrameRate")
}
