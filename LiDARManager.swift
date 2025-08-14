// LiDARManager.swift - Fixed with proper main thread updates and disparity inversion
import Foundation
import AVFoundation
import CoreVideo
import Combine
import UIKit

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

/// Simple LiDAR state manager - actual depth comes from CameraViewModel
final class LiDARManager: NSObject, ObservableObject {
    // MARK: - Singleton
    static let shared = LiDARManager()

    // MARK: - Public state
        @Published private(set) var isSupported: Bool = false  // Device capability
        @Published private(set) var isRunning: Bool = false    // Actually processing
        @Published private(set) var isEnabled: Bool = false    // User toggle state
        @Published private(set) var isAvailable: Bool = false  // Current camera supports it
        
        // Simple active state
        var isActive: Bool {
            return isEnabled && isAvailable
        }

    // MARK: - Private
    private var latestDepthData: AVDepthData?
    private let processingQueue = DispatchQueue(label: "lidar.processing", qos: .userInitiated)
    private var depthHistory: [UUID: [Double]] = [:]
    private let maxHistorySize = 7    
    // MARK: - Init
    private override init() {
        super.init()
        checkSupport()
        
        // Observe memory reduction notifications
        NotificationCenter.default.addObserver(self, selector: #selector(handleReduceQualityForMemory), name: .reduceQualityForMemory, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleReduceFrameRate), name: .reduceFrameRate, object: nil)
    }
    
    @objc private func handleReduceQualityForMemory() {
        // Release cached depth data and clear depth histories to reduce memory footprint
        DispatchQueue.main.async { [weak self] in
            self?.latestDepthData = nil
            self?.depthHistory.removeAll()
            print("LiDARManager: Reduced quality for memory - cleared depth data and histories")
        }
    }
    
    @objc private func handleReduceFrameRate() {
        // Optional: Pause non-essential processing or reduce background work if applicable.
        // Currently no extra processing to reduce; this is a no-op.
        print("LiDARManager: Received reduceFrameRate notification - no action taken")
    }
    
    private func checkSupport() {
        // Check if device supports depth capture
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInLiDARDepthCamera,
                .builtInTrueDepthCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .back
        )
        
        for device in discoverySession.devices {
            // Check if device has any depth format support
            if !device.activeFormat.supportedDepthDataFormats.isEmpty {
                isSupported = true
                break
            }
            
            // Also check for devices that support depth even without explicit formats
            if device.deviceType == .builtInLiDARDepthCamera ||
               device.deviceType == .builtInTrueDepthCamera ||
               device.deviceType == .builtInDualCamera ||
               device.deviceType == .builtInDualWideCamera ||
               device.deviceType == .builtInTripleCamera {
                isSupported = true
                break
            }
        }
        
        print("LiDAR Support Check: \(isSupported)")
    }

    // LiDARManager.swift

        // MARK: - Control
        func setEnabled(_ enabled: Bool) {
            // FIXED: Ensure UI updates happen on main thread
            DispatchQueue.main.async { [weak self] in
                self?.isEnabled = enabled
                self?.isRunning = enabled
            }
        }
        
        func toggle() {
            // Toggle on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Toggle the state
                let newState = !self.isEnabled
                self.isEnabled = newState
                self.isRunning = newState
                print("LiDAR toggled: isEnabled = \(self.isEnabled), isRunning = \(self.isRunning)")
                // Clear depth data when disabled
                if !newState {
                    self.latestDepthData = nil
                }
            }
        }

        // MARK: - Availability Check     <--- ADD THIS SECTION HERE
        func setAvailable(_ available: Bool) {
            DispatchQueue.main.async { [weak self] in
                self?.isAvailable = available
                // If not available but enabled, we need to pause
                if !available && self?.isEnabled == true {
                    self?.isRunning = false
                } else if available && self?.isEnabled == true {
                    self?.isRunning = true
                }
            }
        }

        func start() {
            // FIXED: Ensure UI updates happen on main thread
            DispatchQueue.main.async { [weak self] in
                self?.isEnabled = true
                self?.isRunning = true
                print("LiDAR started")
            }
        }
        
        // ... rest of the file continues

    func stop() {
        // FIXED: Ensure UI updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            self?.isEnabled = false
            self?.isRunning = false
            self?.latestDepthData = nil
            print("LiDAR stopped")
        }
    }
    
    // MARK: - Depth Data Update (called by CameraViewModel)
    func updateDepthData(_ depthData: AVDepthData) {
        guard isEnabled else {
            print("LiDAR: Depth data received but LiDAR is disabled")
            return
        }
        self.latestDepthData = depthData
        let depthMap = depthData.depthDataMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        print("LiDAR: Depth data updated - size: \(width)x\(height)")
    }

    // MARK: - Public API

    /// Diagnostic version: Sample a 5x5 grid and use median depth
    func distanceInMeters(atNormalizedPoint pt: CGPoint) -> Double? {
        guard isEnabled, let depthData = latestDepthData else {
            print("LiDAR: No depth data available")
            return nil
        }
        
        // Sample a 5x5 grid instead of just 5 points
        var allDepths: [Double] = []
        
        for yOffset in stride(from: -0.04, through: 0.04, by: 0.02) {
            for xOffset in stride(from: -0.04, through: 0.04, by: 0.02) {
                let samplePoint = CGPoint(
                    x: max(0, min(1, pt.x + xOffset)),
                    y: max(0, min(1, pt.y + yOffset))
                )
                if let depth = sampleSinglePoint(samplePoint, from: depthData) {
                    if depth > 0.3 && depth < 10.0 && depth.isFinite {
                        allDepths.append(depth)
                    }
                }
            }
        }
        
        guard !allDepths.isEmpty else {
            print("LiDAR: No valid samples found")
            return nil
        }
        
        // Sort depths
        allDepths.sort()
        
        // Take the median depth (middle value) instead of minimum
        let medianDepth = allDepths[allDepths.count / 2]
        
        // Log for debugging
        print("LiDAR: Sampled \(allDepths.count) points, depths range from \(allDepths.first!)m to \(allDepths.last!)m, using median: \(medianDepth)m = \(Int(medianDepth * 3.28))ft")
        
        return medianDepth
    }

    // MARK: - Multi-point sampling helper (pixel buffer read) - FIXED DISPARITY INVERSION
    private func sampleSinglePoint(_ pt: CGPoint, from depthData: AVDepthData) -> Double? {
        let depthMap = depthData.depthDataMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0 else { return nil }
        let x = Int((pt.x * CGFloat(width)).rounded(.toNearestOrAwayFromZero))
        let y = Int((pt.y * CGFloat(height)).rounded(.toNearestOrAwayFromZero))
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        var depthValue: Float = 0
        
        switch pixelFormat {
        case kCVPixelFormatType_DisparityFloat32:
            // DISPARITY: Needs to be inverted to get actual depth
            let rowData = baseAddress + y * CVPixelBufferGetBytesPerRow(depthMap)
            let depthPointer = rowData.assumingMemoryBound(to: Float32.self)
            let disparity = depthPointer[x]
            // Invert disparity to get depth (with scaling factor)
            // The scaling factor may need adjustment based on your device
            depthValue = 1.0 / disparity
            
        case kCVPixelFormatType_DepthFloat32:
            // DEPTH: Already in correct format
            let rowData = baseAddress + y * CVPixelBufferGetBytesPerRow(depthMap)
            let depthPointer = rowData.assumingMemoryBound(to: Float32.self)
            depthValue = depthPointer[x]
            
        case kCVPixelFormatType_DisparityFloat16:
            // DISPARITY: Needs to be inverted to get actual depth
            let rowData = baseAddress + y * CVPixelBufferGetBytesPerRow(depthMap)
            let depthPointer = rowData.assumingMemoryBound(to: Float16.self)
            let disparity = Float(depthPointer[x])
            // Invert disparity to get depth (with scaling factor)
            depthValue = 1.0 / disparity
            
        case kCVPixelFormatType_DepthFloat16:
            // DEPTH: Already in correct format
            let rowData = baseAddress + y * CVPixelBufferGetBytesPerRow(depthMap)
            let depthPointer = rowData.assumingMemoryBound(to: Float16.self)
            depthValue = Float(depthPointer[x])
            
        default:
            print("LiDAR: Unsupported depth format: \(pixelFormat)")
            return nil
        }
        
        guard depthValue > 0, depthValue.isFinite else {
            print("LiDAR: Invalid depth value: \(depthValue)")
            return nil
        }
        return Double(depthValue)
    }

    /// Returns temporally smoothed distance (meters) for detection ID at point
    func smoothedDistanceInMeters(for detectionId: UUID, at normalizedPoint: CGPoint) -> Double? {
        guard let newDepth = distanceInMeters(atNormalizedPoint: normalizedPoint) else { return nil }
        var history = depthHistory[detectionId] ?? []
        history.append(newDepth)
        if history.count > maxHistorySize {
            history.removeFirst(history.count - maxHistorySize)
        }
        depthHistory[detectionId] = history
        // Compute mean and stddev
        let n = Double(history.count)
        let mean = history.reduce(0, +) / n
        let variance = history.reduce(0) { $0 + pow($1 - mean, 2) } / n
        let stddev = sqrt(variance)
        print("LiDAR: ID \(detectionId) depth history = \(history), mean = \(mean), stddev = \(stddev)")
        if stddev < 0.15 {
            return mean
        } else {
            return newDepth
        }
    }

    /// Returns smoothed distance in feet for detection ID
    func smoothedDistanceFeet(for detectionId: UUID, at normalizedPoint: CGPoint) -> Int? {
        guard let meters = smoothedDistanceInMeters(for: detectionId, at: normalizedPoint) else { return nil }
        return LiDARManager.roundedFeet(fromMeters: meters)
    }

    /// Cleans up history for detections no longer present
    func cleanupOldHistories(currentDetectionIds: Set<UUID>) {
        depthHistory.keys.filter { !currentDetectionIds.contains($0) }.forEach { depthHistory.removeValue(forKey: $0) }
    }
    
    /// Convenience method to get distance in feet
    func distanceFeet(at normalizedPoint: CGPoint) -> Int? {
        guard let meters = distanceInMeters(atNormalizedPoint: normalizedPoint) else {
            return nil
        }
        let feet = LiDARManager.roundedFeet(fromMeters: meters)
        print("LiDAR: Distance = \(feet) feet")
        return feet
    }

    /// Batch variant
    func distancesInMeters<ID: Hashable>(for points: [(id: ID, point: CGPoint)]) -> [ID: Double] {
        var results: [ID: Double] = [:]
        for (id, point) in points {
            if let meters = distanceInMeters(atNormalizedPoint: point) {
                results[id] = meters
            }
        }
        return results
    }

    /// Convenience: rounds meters to nearest foot
    static func roundedFeet(fromMeters meters: Double) -> Int {
        let feet = meters * 3.280839895
        return Int((feet + 0.5).rounded(.down))
    }

    /// Convenience: left/center/right label from normalized X
    static func horizontalBucket(forNormalizedX x: CGFloat) -> String {
        if x < 0.33 { return "L" }
        if x > 0.66 { return "R" }
        return "C"
    }
}

