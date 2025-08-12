import AVFoundation
import Combine
import UIKit
import SwiftUI

// MARK: - Depth Data Delegate (Must be outside @MainActor class)
final class DepthDataDelegate: NSObject, AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput,
                        didOutput depthData: AVDepthData,
                        timestamp: CMTime,
                        connection: AVCaptureConnection) {
        print("DepthDataDelegate: Received depth data")
        // Send to LiDARManager on main thread
        DispatchQueue.main.async {
            LiDARManager.shared.updateDepthData(depthData)
        }
    }
}

// MARK: - LiDAR Protocol
protocol LiDARDepthProviding: AnyObject {
    /// Normalized point in [0,1] x [0,1] image space (same as detection.rect)
    func depthInMeters(at normalizedPoint: CGPoint) -> Float?
    /// True when device supports scene depth
    var isAvailable: Bool { get }
    /// Manager can pause/resume internally based on this toggle
    var isEnabled: Bool { get set }
}

// MARK: - Camera Permission Alert
struct CameraPermissionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let openSettings: () -> Void
}

// MARK: - Voice Gender Enum
enum AVSpeechSynthesisVoiceGender {
    case unspecified, male, female
}

// MARK: - OCR Delegate Protocol
protocol CameraViewModelOCRDelegate: AnyObject {
    func cameraViewModel(_ viewModel: CameraViewModel, didOutputPixelBuffer pixelBuffer: CVPixelBuffer)
}

// MARK: - Device Orientation Extension
extension UIDeviceOrientation {
    var isPortrait: Bool {
        self == .portrait || self == .portraitUpsideDown || !self.isValidInterfaceOrientation
    }
}

// Make CameraViewModel conform to AVSpeechSynthesizerDelegate
extension CameraViewModel: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
        }
    }
}

class CameraViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // MARK: - Constants
    private enum Constants {
        static let sessionQueue = "AVCaptureSessionQueue"
        static let videoQueue = "videoQueue"
        static let speechCooldown: TimeInterval = 45.0
        static let minAnnouncementInterval: TimeInterval = 3.0
        static let maxFrameSamples = 15
        static let defaultVoiceKey = "selectedVoice"
    }
    
    // MARK: - Thermal Management
    private var thermalState: ProcessInfo.ThermalState = .nominal
    private var thermalObserver: NSObjectProtocol?
    private var lastMemoryWarning = Date.distantPast
    private var degradedPerformanceCounter = 0
    
    // MARK: - Published Properties
    @Published var currentOrientation: UIDeviceOrientation = .portrait
    @Published var isTorchOn = false
    @Published var torchLevel: Float = 0.0
    @Published var isUltraWide = false
    @Published var isSpeechEnabled = true
    @Published var speechVoiceGender: AVSpeechSynthesisVoiceGender = .unspecified
    @Published var detections: [YOLODetection] = []
    @Published var framesPerSecond: Double = 0
    @Published var filterMode = "all"
    @Published var confidenceThreshold: Float = 0.75
    @Published var frameRate = 30 { didSet { updateFrameProcessingRate() } }
    @Published var currentZoomLevel: CGFloat = 1.0
    @Published var selectedVoiceIdentifier: String {
        didSet { UserDefaults.standard.set(selectedVoiceIdentifier, forKey: Constants.defaultVoiceKey) }
    }
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    
    // ==== NEW: LiDAR flags (safe defaults) ====
    @Published var useLiDAR: Bool = false {
        didSet { lidar?.isEnabled = useLiDAR }
    }
    @Published var isLiDARSupported: Bool = false  // set later by LiDARManager
    
    // ==== NEW: LiDAR enabled flag and last distances ====
    @Published var isLiDAREnabled: Bool = false  // user-controllable; default off
    private var lastDistancesFeet: [UUID: Int] = [:] // detection.id -> rounded feet
    
    @Published var cameraPermissionAlert: CameraPermissionAlert?
    
    var detectedObjectCount: Int { detections.count }
    
    var availableEnglishVoices: [AVSpeechSynthesisVoice] {
        let preferredLanguages = ["en-US", "en-GB", "en-AU", "en-IE", "en-ZA"]
        let preferredNames = ["Samantha", "Daniel", "Moira", "Karen", "Tessa", "Serena"]
        
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { preferredLanguages.contains($0.language) }
            .filter { voice in
                let id = voice.identifier.lowercased()
                return id.contains("premium") || id.contains("enhanced") || preferredNames.contains(voice.name)
            }
            .sorted { $0.name < $1.name }
            .prefix(6)
            .map { $0 }
    }
    
    // MARK: - Internal Properties
    weak var ocrDelegate: CameraViewModelOCRDelegate?
    
    // ==== NEW: LiDAR bridge ====
    weak var lidar: LiDARDepthProviding? {
        didSet {
            isLiDARSupported = lidar?.isAvailable ?? false
            lidar?.isEnabled = useLiDAR
        }
    }
    
    internal let session = AVCaptureSession()
    internal lazy var previewLayer = AVCaptureVideoPreviewLayer(session: session)
    internal lazy var yoloProcessor: YOLOv8Processor? = {
        let tier = DevicePerf.shared.tier
        let side: Int
        switch tier {
        case .low:  side = 352
        case .mid:  side = 512
        case .high: side = 640
        }
        if let proc = try? YOLOv8Processor(targetSide: side) {
            return proc
        } else {
            let fallback = try? YOLOv8Processor()
            fallback?.configureTargetSide(side)
            return fallback
        }
    }()
    
    // MARK: - Private Properties
    private var frameCounter = 0
    private var isProcessing = false
    
    private var depthDataOutput: AVCaptureDepthDataOutput?
    private var depthDelegate: Any?
    
    private static let sessionQueue = DispatchQueue(label: Constants.sessionQueue)
    private let videoQueue = DispatchQueue(label: Constants.videoQueue, qos: .userInitiated)
    
    private var isSessionConfigured = false
    private var currentDevice: AVCaptureDevice?
    private var processEveryNFrames = 1
    private var videoConnection: AVCaptureConnection?
    
    // Speech properties
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenTime: [String: Date] = [:]
    private var lastAnnouncementTime = Date.distantPast
    private var isSpeaking = false
    
    // FPS tracking
    private var lastFrameTimestamps: [CFTimeInterval] = []
    
    // Observers
    private var orientationObserver: NSObjectProtocol?
    private var rotationCoordinator: Any?  // No @available attribute
    
    // Zoom
    var initialZoomFactor: CGFloat = 1.0
    private var minimumZoomFactor: CGFloat = 1.0  // Track the minimum zoom for current camera
    private var maximumZoomFactor: CGFloat = 5.0  // Track the maximum zoom for current camera
    
    // MARK: - Initialization
    override init() {
        self.selectedVoiceIdentifier = UserDefaults.standard.string(forKey: Constants.defaultVoiceKey)
        ?? AVSpeechSynthesisVoice(language: "en-US")?.identifier ?? ""
        super.init()
        
        // Set delegate immediately after super.init
        speechSynthesizer.delegate = self
        
        setupInitialState()
        
        switch DevicePerf.shared.tier {
        case .low:
            self.frameRate = 15
            self.setSessionPresetIfAvailable(.hd1280x720)
        case .mid:
            self.frameRate = 30
            self.setSessionPresetIfAvailable(.hd1920x1080)
        case .high:
            self.frameRate = 60
            self.setSessionPresetIfAvailable(.hd1920x1080)
        }
    }
    
    func setSessionPresetIfAvailable(_ preset: AVCaptureSession.Preset) {
        if session.canSetSessionPreset(preset) {
            session.beginConfiguration()
            session.sessionPreset = preset
            session.commitConfiguration()
        }
    }
    
    private func setupInitialState() {
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.deviceOrientationDidChange()
        }
        
        currentOrientation = UIDevice.current.orientation
        if !currentOrientation.isValidInterfaceOrientation {
            currentOrientation = .portrait
        }
        
        // Add thermal state monitoring
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThermalStateChange()
        }
        // Add memory warning observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        updateFrameProcessingRate()
    }
    
    deinit {
        cleanup()
        if let thermal = thermalObserver {
            NotificationCenter.default.removeObserver(thermal)
        }
    }
    
    private func cleanup() {
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        if #available(iOS 17.0, *) {
            (rotationCoordinator as? AVCaptureDevice.RotationCoordinator)?.removeObserver(self, forKeyPath: "videoRotationAngleForHorizonLevelCapture")
        }
        
        stopSpeech()
        stopSession()
        
        DispatchQueue.main.async {
            self.detections = []
        }
    }
    
    // MARK: - Orientation Handling
    @objc private func deviceOrientationDidChange() {
        let newOrientation = UIDevice.current.orientation
        
        if newOrientation.isValidInterfaceOrientation && newOrientation != .portraitUpsideDown {
            currentOrientation = newOrientation
        }
        
        updateVideoRotation()
    }
    
    private func handleThermalStateChange() {
        thermalState = ProcessInfo.processInfo.thermalState
        switch thermalState {
        case .nominal:
            frameRate = 30
            processEveryNFrames = 1
        case .fair:
            frameRate = 15
            processEveryNFrames = 2
        case .serious:
            frameRate = 10
            processEveryNFrames = 3
        case .critical:
            // Pause for 2 seconds
            pauseCameraAndProcessing()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.resumeCameraAndProcessing()
            }
        @unknown default:
            break
        }
        print("📱 Thermal state: \(thermalState), FPS: \(frameRate)")
    }
    
    private func updateFrameProcessingRate() {
        processEveryNFrames = 1
    }
    
    // MARK: - Zoom Control
    func handlePinchGesture(_ scale: CGFloat) {
        guard let device = currentDevice else { return }
        
        // Calculate the target zoom
        let targetZoom = initialZoomFactor * scale
        
        // Clamp to valid range for this camera
        let clampedZoom = max(minimumZoomFactor, min(targetZoom, maximumZoomFactor))
        
        // Only update if the zoom actually changed (prevents unnecessary updates)
        if abs(device.videoZoomFactor - clampedZoom) > 0.01 {
            configureDevice(device) { dev in
                // Check if the zoom factor is supported by the device
                let finalZoom = min(dev.activeFormat.videoMaxZoomFactor, max(1.0, clampedZoom))
                dev.videoZoomFactor = finalZoom
                DispatchQueue.main.async {
                    self.currentZoomLevel = finalZoom
                    // Update initial zoom if we're at the limits to prevent snap-back
                    if finalZoom <= self.minimumZoomFactor || finalZoom >= self.maximumZoomFactor {
                        self.initialZoomFactor = finalZoom
                    }
                }
            }
        }
    }
    
    func setPinchGestureStartZoom() {
        // Always use the current zoom level as the starting point
        if let device = currentDevice {
            initialZoomFactor = device.videoZoomFactor
        } else {
            initialZoomFactor = currentZoomLevel
        }
    }
    
    // MARK: - Camera Setup
    private func setupCamera() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return
        }
        
        session.beginConfiguration()
        configureSessionPreset()
        
        guard let device = selectCamera() else {
            session.commitConfiguration()
            return
        }
        
        currentDevice = device
        configureCamera(device)
        setupRotationCoordinator()
        setupCameraInput(device: device)
    }
    
    private func configureSessionPreset() {
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
    }
    
    private func selectCamera() -> AVCaptureDevice? {
        if cameraPosition == .front {
            DispatchQueue.main.async {
                self.isUltraWide = false
                // LiDAR not available on front camera
                LiDARManager.shared.setAvailable(false)
            }
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        } else {
            // Check ultra-wide FIRST before LiDAR
            if isUltraWide {
                if let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
                    // LiDAR not available on ultra-wide
                    DispatchQueue.main.async {
                        LiDARManager.shared.setAvailable(false)
                    }
                    return ultraWide
                } else {
                    DispatchQueue.main.async { self.isUltraWide = false }
                }
            }
            
            // Then try LiDAR camera if not ultra-wide
            if !isUltraWide, let lidarCamera = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) {
                // LiDAR IS available on this camera
                DispatchQueue.main.async {
                    LiDARManager.shared.setAvailable(true)
                }
                return lidarCamera
            }
            
            // Fall back to regular wide camera - check if it supports depth
            if let wideCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                // Check if this camera supports depth
                let supportsDepth = !wideCamera.activeFormat.supportedDepthDataFormats.isEmpty
                DispatchQueue.main.async {
                    LiDARManager.shared.setAvailable(supportsDepth)
                }
                return wideCamera
            }
            
            return nil
        }
    }
    
    private func configureCamera(_ camera: AVCaptureDevice) {
        configureDevice(camera) { device in
            // Track zoom limits for this camera
            if device.deviceType == .builtInUltraWideCamera {
                // Ultra-wide camera: use device's actual minimum (usually ~0.5)
                self.minimumZoomFactor = device.minAvailableVideoZoomFactor
            } else if device.deviceType == .builtInLiDARDepthCamera {
                // LiDAR camera: Force allow zoom out to 0.5x and in to 10x
                // The LiDAR camera sometimes reports 1.0 as minimum but actually supports digital zoom
                self.minimumZoomFactor = 0.5
            } else {
                // Regular wide camera: allow digital zoom out to 0.5x
                self.minimumZoomFactor = max(0.5, device.minAvailableVideoZoomFactor)
            }
            
            // Set maximum zoom
            let deviceMax = device.maxAvailableVideoZoomFactor
            if device.deviceType == .builtInLiDARDepthCamera {
                // LiDAR camera: ensure we get good zoom range
                self.maximumZoomFactor = min(deviceMax, 10.0)
            } else {
                // Other cameras
                self.maximumZoomFactor = min(deviceMax * 0.95, 10.0)
            }
            
            let needsDepth = LiDARManager.shared.isSupported && self.cameraPosition == .back
            let targetFPS: Double = 60.0
            var selectedFormat: AVCaptureDevice.Format?
            var selectedMaxFrameRate: Double = 0  // DECLARE IT HERE, OUTSIDE THE LOOP
            
            for format in device.formats {
                let desc = format.formatDescription
                let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
                
                let matchesPreset = (self.session.sessionPreset == .hd1920x1080 && dimensions.width == 1920 && dimensions.height == 1080) ||
                (self.session.sessionPreset == .hd1280x720 && dimensions.width == 1280 && dimensions.height == 720)
                
                if !matchesPreset { continue }
                
                // Check if format supports depth if needed
                if needsDepth && format.supportedDepthDataFormats.isEmpty {
                    continue
                }
                
                for range in format.videoSupportedFrameRateRanges {
                    let maxFPS = range.maxFrameRate
                    if maxFPS >= targetFPS && maxFPS > selectedMaxFrameRate {
                        selectedFormat = format
                        selectedMaxFrameRate = maxFPS  // NOW THIS IS JUST AN ASSIGNMENT, NOT A DECLARATION
                    } else if selectedFormat == nil && maxFPS > selectedMaxFrameRate {
                        selectedFormat = format
                        selectedMaxFrameRate = maxFPS  // SAME HERE
                    }
                }
            }
            
            // Rest of your method continues...
            // If no format with depth was found but depth is needed, find any format with depth
            if selectedFormat == nil && needsDepth {
                for format in device.formats {
                    if !format.supportedDepthDataFormats.isEmpty {
                        selectedFormat = format
                        break
                    }
                }
            }
            
            // If no format with depth was found but depth is needed, find any format with depth
            if selectedFormat == nil && needsDepth {
                for format in device.formats {
                    if !format.supportedDepthDataFormats.isEmpty {
                        selectedFormat = format
                        break
                    }
                }
            }
            
            if let format = selectedFormat {
                device.activeFormat = format
                
                // Select appropriate depth format if available
                if !format.supportedDepthDataFormats.isEmpty {
                    // Choose the best depth format (usually the first one is fine)
                    if let depthFormat = format.supportedDepthDataFormats.first {
                        device.activeDepthDataFormat = depthFormat
                        print("CameraViewModel: Set depth data format")
                    }
                }
                
                let duration = CMTime(value: 1, timescale: Int32(targetFPS))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }
            
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            // Set initial zoom based on camera type
            if device.deviceType == .builtInUltraWideCamera {
                // For ultra-wide, start at minimum zoom to show full wide view
                device.videoZoomFactor = self.minimumZoomFactor
                DispatchQueue.main.async {
                    self.currentZoomLevel = self.minimumZoomFactor
                    self.initialZoomFactor = self.minimumZoomFactor
                }
            } else {
                // For regular and LiDAR cameras, start at 1.0
                device.videoZoomFactor = 1.0
                DispatchQueue.main.async {
                    self.currentZoomLevel = 1.0
                    self.initialZoomFactor = 1.0
                }
            }
        }
    }
    
    private func setupRotationCoordinator() {
        guard let device = currentDevice else { return }
        
        if #available(iOS 17.0, *) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            coordinator.addObserver(self, forKeyPath: "videoRotationAngleForHorizonLevelCapture", options: [.new], context: nil)
            rotationCoordinator = coordinator
            updateVideoRotation()
        } else {
            if let connection = previewLayer.connection {
                connection.videoOrientation = .portrait
            }
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if #available(iOS 17.0, *) {
            if keyPath == "videoRotationAngleForHorizonLevelCapture" {
                updateVideoRotation()
            } else {
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            }
        } else {
            // Handle iOS 16 and earlier
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    private func updateVideoRotation() {
        if #available(iOS 17.0, *) {
            guard let coordinator = rotationCoordinator as? AVCaptureDevice.RotationCoordinator,
                  let connection = videoConnection else { return }
            
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            
            previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        } else {
            if let connection = videoConnection {
                if connection.isVideoOrientationSupported {
                    switch currentOrientation {
                    case .landscapeLeft:
                        connection.videoOrientation = .landscapeRight
                    case .landscapeRight:
                        connection.videoOrientation = .landscapeLeft
                    default:
                        connection.videoOrientation = .portrait
                    }
                }
            }
        }
    }
    
    private func setupCameraInput(device: AVCaptureDevice) {
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            session.inputs.forEach { session.removeInput($0) }
            
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                session.commitConfiguration()
                return
            }
        } catch {
            session.commitConfiguration()
            return
        }
        
        setupVideoOutput()
    }
    
    private func setupVideoOutput() {
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: videoQueue)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        
        session.outputs.forEach { session.removeOutput($0) }
        
        if session.canAddOutput(output) {
            session.addOutput(output)
            
            if let connection = output.connection(with: .video) {
                videoConnection = connection
                updateVideoRotation()
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = (cameraPosition == .front)
                }
            }
        }
        
        // No depth output setup here - removed as per instructions
        
        session.commitConfiguration()
        isSessionConfigured = true
    }
    
    // MARK: - Session Control
    func startSession() {
        checkAndHandleCameraPermission()
        
        Self.sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.isSessionConfigured {
                if !self.session.isRunning {
                    self.session.startRunning()
                    DispatchQueue.main.async { self.updateVideoRotation() }
                    // Check if LiDAR should be enabled
                    if LiDARManager.shared.isActive && self.cameraPosition == .back {
                        self.toggleDepthCapture(enabled: true)
                    }
                    if self.isLiDAREnabled {
                        LiDARManager.shared.setEnabled(true)
                        LiDARManager.shared.start()
                    }
                }
            } else {
                self.setupCamera()
                if self.isSessionConfigured && !self.session.isRunning {
                    self.session.startRunning()
                    DispatchQueue.main.async { self.updateVideoRotation() }
                    // Check if LiDAR should be enabled
                    if LiDARManager.shared.isActive && self.cameraPosition == .back {
                        self.toggleDepthCapture(enabled: true)
                    }
                    if self.isLiDAREnabled {
                        LiDARManager.shared.setEnabled(true)
                        LiDARManager.shared.start()
                    }
                }
            }
        }
    }
    
    func stopSession() {
        print("🛑 STOPPING CAMERA SESSION")
        Self.sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async { self.detections = [] }
                LiDARManager.shared.stop()
            }
        }
    }
    
    func toggleDepthCapture(enabled: Bool) {
        Self.sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.session.beginConfiguration()
            
            if enabled && self.cameraPosition == .back {
                // Remove existing depth output if any
                if let existingDepth = self.depthDataOutput {
                    self.session.removeOutput(existingDepth)
                    self.depthDataOutput = nil
                    self.depthDelegate = nil
                }
                
                // Create depth delegate if needed
                if self.depthDelegate == nil {
                    self.depthDelegate = DepthDataDelegate()
                }
                
                // Add new depth output
                let depthOutput = AVCaptureDepthDataOutput()
                if let delegate = self.depthDelegate as? AVCaptureDepthDataOutputDelegate {
                    depthOutput.setDelegate(delegate, callbackQueue: self.videoQueue)
                }
                depthOutput.isFilteringEnabled = true
                
                if self.session.canAddOutput(depthOutput) {
                    self.session.addOutput(depthOutput)
                    self.depthDataOutput = depthOutput
                    
                    // Configure connection
                    if let connection = depthOutput.connection(with: .depthData) {
                        connection.isEnabled = true
                        // Set video orientation to match camera
                        if #available(iOS 17.0, *) {
                            if connection.isVideoRotationAngleSupported(0) {
                                connection.videoRotationAngle = 0
                            }
                        } else {
                            if connection.isVideoOrientationSupported {
                                connection.videoOrientation = .portrait
                            }
                        }
                    }
                    
                    print("CameraViewModel: Depth output added successfully")
                } else {
                    print("CameraViewModel: Cannot add depth output - checking for alternative setup")
                    
                    // Try with a different configuration
                    self.tryAlternativeDepthSetup()
                }
            } else if !enabled {
                // Only remove if explicitly disabled
                if let depthOutput = self.depthDataOutput {
                    self.session.removeOutput(depthOutput)
                    self.depthDataOutput = nil
                    self.depthDelegate = nil
                    print("CameraViewModel: Depth output removed")
                }
            }
            
            self.session.commitConfiguration()
        }
    }
    
    private func tryAlternativeDepthSetup() {
        // Try to find a format that supports depth
        guard let device = currentDevice else { return }
        
        let formats = device.formats
        var depthFormat: AVCaptureDevice.Format?
        
        for format in formats {
            let depthFormats = format.supportedDepthDataFormats
            if !depthFormats.isEmpty {
                depthFormat = format
                break
            }
        }
        
        if let format = depthFormat {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.unlockForConfiguration()
                
                print("CameraViewModel: Set device format with depth support")
                
                // Try adding depth output again
                if depthDelegate == nil {
                    depthDelegate = DepthDataDelegate()
                }
                
                let depthOutput = AVCaptureDepthDataOutput()
                if let delegate = depthDelegate as? AVCaptureDepthDataOutputDelegate {
                    depthOutput.setDelegate(delegate, callbackQueue: videoQueue)
                }
                depthOutput.isFilteringEnabled = true
                
                if session.canAddOutput(depthOutput) {
                    session.addOutput(depthOutput)
                    depthDataOutput = depthOutput
                    
                    if let connection = depthOutput.connection(with: .depthData) {
                        connection.isEnabled = true
                    }
                    
                    print("CameraViewModel: Depth output added with alternative format")
                }
            } catch {
                print("CameraViewModel: Failed to configure depth format: \(error)")
            }
        }
    }
    
    func onLiDARToggled() {
        // Read the current state directly from LiDARManager
        let isEnabled = LiDARManager.shared.isEnabled
        print("CameraViewModel: LiDAR toggled, enabling depth: \(isEnabled)")
        toggleDepthCapture(enabled: isEnabled)
    }
    
    // MARK: - Torch Control
    func setTorchLevel(_ level: Float) {
        guard let device = currentDevice ?? session.inputs.compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first,
              device.hasTorch else {
            return
        }
        
        configureDevice(device) { dev in
            if level > 0 {
                try? dev.setTorchModeOn(level: level)
                DispatchQueue.main.async {
                    self.torchLevel = level
                    self.isTorchOn = true
                }
            } else {
                dev.torchMode = .off
                DispatchQueue.main.async {
                    self.torchLevel = 0.0
                    self.isTorchOn = false
                }
            }
        }
    }
    
    func toggleTorch() {
        setTorchLevel(torchLevel > 0 ? 0.0 : 1.0)
    }
    
    // MARK: - Camera Controls
    func toggleCameraZoom() {
        DispatchQueue.main.async { self.isUltraWide.toggle() }
        reconfigureCamera()
    }
    
    func flipCamera() {
        DispatchQueue.main.async {
            self.cameraPosition = self.cameraPosition == .back ? .front : .back
        }
        reconfigureCamera()
    }
    
    private func reconfigureCamera() {
        Self.sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.session.isRunning {
                self.session.stopRunning()
            }
            
            // Store LiDAR state before reconfiguring
            let wasLiDARActive = LiDARManager.shared.isActive
            
            // Clear depth output reference when reconfiguring
            self.depthDataOutput = nil
            self.depthDelegate = nil
            
            DispatchQueue.main.async {
                self.detections = []
                self.currentZoomLevel = 1.0
                if self.cameraPosition == .front {
                    self.isUltraWide = false
                    // Stop LiDAR when switching to front camera
                    if LiDARManager.shared.isActive {
                        LiDARManager.shared.stop()
                    }
                }
            }
            
            self.isSessionConfigured = false
            self.setupCamera()
            
            if self.isSessionConfigured {
                self.session.startRunning()
                
                // Re-enable depth if LiDAR was active and we're on back camera
                if wasLiDARActive && self.cameraPosition == .back {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.toggleDepthCapture(enabled: true)
                    }
                }
            }
        }
    }
    
    // MARK: - Speech Control
    func stopSpeech() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.speechSynthesizer.stopSpeaking(at: .immediate)
            self.isSpeaking = false
            self.lastSpokenTime.removeAll()
            self.lastAnnouncementTime = .distantPast
        }
    }
    
    func clearDetections() {
        DispatchQueue.main.async { [weak self] in
            self?.detections = []
        }
    }
    
    func pauseCameraAndProcessing() {
        Self.sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async { self.detections = [] }
                LiDARManager.shared.stop()
            }
            
            self.stopSpeech()
        }
    }
    
    func resumeCameraAndProcessing() {
        Self.sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning {
                if !self.isSessionConfigured {
                    self.setupCamera()
                }
                if self.isSessionConfigured {
                    self.session.startRunning()
                    if self.isLiDAREnabled {
                        LiDARManager.shared.setEnabled(true)
                        LiDARManager.shared.start()
                    }
                }
            }
        }
    }
    
    // MARK: - Frame Processing
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            frameCounter += 1
            
            // Add periodic memory cleanup every 600 frames (~30 seconds at 20fps)
            if frameCounter % 600 == 0 {
                autoreleasepool {
                    // Force YOLO reset
                    yoloProcessor?.reset()
                    // Clear detection history
                    lastSpokenTime.removeAll()
                    detections = []
                    // Clear LiDAR histories
                    LiDARManager.shared.cleanupOldHistories(currentDetectionIds: Set())
                }
                print("🧹 Periodic memory cleanup at frame \(frameCounter)")
            }
            
            // Adaptive frame skipping based on thermal state
            let skipFrames = thermalState == .serious ? 4 :
                             thermalState == .fair ? 2 :
                             processEveryNFrames
            guard frameCounter % skipFrames == 0 else { return }
            
            updateFPS()
            
            // Detect performance degradation
            if framesPerSecond < 10 && frameCounter > 100 {
                degradedPerformanceCounter += 1
                if degradedPerformanceCounter > 30 {
                    print("⚠️ Performance degraded, forcing reset")
                    reinitialize()
                    degradedPerformanceCounter = 0
                }
            } else {
                degradedPerformanceCounter = max(0, degradedPerformanceCounter - 1)
            }
            
            guard !isProcessing else { return }
            guard session.isRunning else {
                DispatchQueue.main.async { self.detections = [] }
                return
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            ocrDelegate?.cameraViewModel(self, didOutputPixelBuffer: pixelBuffer)
            guard let yoloProcessor = yoloProcessor else {
                return
            }
            isProcessing = true
            yoloProcessor.predict(
                image: pixelBuffer,
                isPortrait: currentOrientation.isPortrait,
                filterMode: filterMode,
                confidenceThreshold: confidenceThreshold
            ) { [weak self] results in
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    self?.detections = results
                    // === LiDAR distance sampling (optional) ===
                    if let self = self, self.isLiDAREnabled, !results.isEmpty {
                        let pts: [(id: UUID, point: CGPoint)] = results.map { det in
                            let center = CGPoint(x: det.rect.midX, y: det.rect.midY)
                            return (det.id, center)
                        }
                        let metersByID = LiDARManager.shared.distancesInMeters(for: pts)
                        var feetByID: [UUID: Int] = [:]
                        for det in results {
                            if let m = metersByID[det.id] {
                                feetByID[det.id] = LiDARManager.roundedFeet(fromMeters: m)
                            }
                        }
                        self.lastDistancesFeet = feetByID
                    } else {
                        self?.lastDistancesFeet.removeAll()
                    }
                    // === Speech ===
                    if self?.isSpeechEnabled == true && !results.isEmpty {
                        self?.processDetectionsForSpeech(results)
                    }
                }
            }
        }
    }
    
    private func updateFPS() {
        let timestamp = CACurrentMediaTime()
        lastFrameTimestamps.append(timestamp)
        if lastFrameTimestamps.count > Constants.maxFrameSamples {
            lastFrameTimestamps.removeFirst()
        }
        if lastFrameTimestamps.count > 1 {
            let timeSpan = lastFrameTimestamps.last! - lastFrameTimestamps.first!
            let fps = Double(lastFrameTimestamps.count - 1) / max(timeSpan, 0.001)
            DispatchQueue.main.async { self.framesPerSecond = fps }
        }
    }
    
    // MARK: - Speech Processing (FIXED WITH LIDAR)
    private func processDetectionsForSpeech(_ detections: [YOLODetection]) {
        let now = Date()
        guard !isSpeaking,
              now.timeIntervalSince(lastAnnouncementTime) >= Constants.minAnnouncementInterval else { return }
        
        let bestDetections = detections.reduce(into: [String: YOLODetection]()) { result, detection in
            let className = normalizeClassName(detection.className)
            if let existing = result[className] {
                if detection.score > existing.score {
                    result[className] = detection
                }
            } else {
                result[className] = detection
            }
        }
        
        let sortedDetections = bestDetections.values.sorted { d1, d2 in
            (d1.rect.width * d1.rect.height) > (d2.rect.width * d2.rect.height)
        }
        
        for detection in sortedDetections {
            let className = normalizeClassName(detection.className)
            let lastSpoken = lastSpokenTime[className] ?? .distantPast
            if now.timeIntervalSince(lastSpoken) >= Constants.speechCooldown {
                
                // Get LiDAR distance if available and enabled
                var spokenText = className
                if LiDARManager.shared.isActive && LiDARManager.shared.isSupported {
                    // Check if object is good candidate for depth measurement
                    let detectionArea = detection.rect.width * detection.rect.height
                    
                    if detectionArea > 0.05 && detectionArea < 0.30 {
                        let center = CGPoint(x: detection.rect.midX, y: detection.rect.midY)
                        
                        // Use smoothed distance for more reliable speech
                        if let feet = LiDARManager.shared.smoothedDistanceFeet(for: detection.id, at: center) {
                            // Only announce distance if it's reasonable for indoor use
                            if feet >= 1 && feet <= 15 {
                                let side = LiDARManager.horizontalBucket(forNormalizedX: detection.rect.midX)
                                let sideWord = (side == "L" ? "left" : side == "R" ? "right" : "center")
                                spokenText = "\(className), \(feet) feet, \(sideWord)"
                            }
                        }
                    }
                }
                
                announceObject(spokenText)
                lastSpokenTime[className] = now
                lastAnnouncementTime = now
                break
            }
        }
    }
    
    private func normalizeClassName(_ className: String) -> String {
        let normalized = className.lowercased()
        let personVariants = ["person", "man", "woman", "human face", "human head", "human body"]
        if personVariants.contains(where: normalized.contains) {
            return "person"
        }
        let tvVariants = ["television", "tv"]
        if tvVariants.contains(normalized) {
            return "TV"
        }
        if normalized.contains("glasses") || normalized.contains("sunglasses") {
            return "glasses"
        }
        return className
    }
    
    // ==== NEW: side letter L/R/C from bbox center thirds ====
    private func sideLetter(for detection: YOLODetection) -> String {
        let mid = detection.rect.midX
        if mid < 0.33 { return "L" }
        if mid > 0.67 { return "R" }
        return "C"
    }
    
    // ==== NEW: compute feet if LiDAR is enabled/supported ====
    private func computeDistanceFeetIfEnabled(for detection: YOLODetection) -> Int? {
        guard useLiDAR, let lidar = lidar, lidar.isAvailable else { return nil }
        let p = CGPoint(x: detection.rect.midX, y: detection.rect.midY)
        guard let meters = lidar.depthInMeters(at: p), meters.isFinite, meters > 0 else { return nil }
        let feet = meters * 3.28084
        return Int((feet).rounded())  // nearest foot
    }
    
    // ==== UPDATED: announceObject to handle string directly ====
    private func announceObject(_ text: String) {
        guard !isSpeaking else { return }
        
        let utterance = AVSpeechUtterance(string: text)
        if let chosenVoice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            utterance.voice = chosenVoice
        }
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.9
        
        isSpeaking = true
        speechSynthesizer.stopSpeaking(at: .immediate)
        speechSynthesizer.speak(utterance)
    }
    
    private func createNaturalDescription(for className: String) -> String {
        let descriptions: [String: String] = [
            "person": "person", "man": "man", "woman": "woman",
            "human face": "person", "human head": "person",
            "dog": "dog", "cat": "cat", "bird": "bird",
            "chair": "chair", "desk": "desk", "table": "table",
            "couch": "couch", "sofa": "sofa",
            "television": "TV", "tv": "TV",
            "computer monitor": "monitor", "monitor": "monitor",
            "mobile phone": "phone", "phone": "phone",
            "laptop": "laptop", "book": "book", "books": "book",
            "bottle": "bottle", "cup": "cup", "mug": "mug",
            "plant": "plant", "flower": "flower",
            "clock": "clock", "door": "door", "window": "window"
        ]
        return descriptions[className.lowercased()] ?? className.replacingOccurrences(of: "_", with: " ")
    }
    
    func announceSpeechEnabled() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let utterance = AVSpeechUtterance(string: "Speech enabled")
            if let chosenVoice = AVSpeechSynthesisVoice(identifier: self.selectedVoiceIdentifier) {
                utterance.voice = chosenVoice
            }
            utterance.rate = 0.52
            utterance.volume = 0.9
            self.speechSynthesizer.speak(utterance)
        }
    }
    
    // MARK: - Helper Methods
    private func configureDevice(_ device: AVCaptureDevice, _ configuration: (AVCaptureDevice) throws -> Void) {
        do {
            try device.lockForConfiguration()
            try configuration(device)
            device.unlockForConfiguration()
        } catch {
        }
    }
    
    // ==== NEW: LiDAR enable/disable helper ====
    func setLiDAR(enabled: Bool) {
        isLiDAREnabled = enabled
        if enabled {
            LiDARManager.shared.setEnabled(true)
            LiDARManager.shared.start()
        } else {
            LiDARManager.shared.stop()
        }
    }
    
    // MARK: - Cleanup Methods
    func shutdown() {
        // Stop all active sessions
        stopSession()
        stopSpeech()
        clearDetections()
        
        // Clear YOLO processor
        yoloProcessor = nil
        
        // Remove all observers
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
            orientationObserver = nil
        }
        
        if #available(iOS 17.0, *) {
            if let coordinator = rotationCoordinator as? AVCaptureDevice.RotationCoordinator {
                coordinator.removeObserver(self, forKeyPath: "videoRotationAngleForHorizonLevelCapture")
            }
            rotationCoordinator = nil
        }
        
        // Clear depth delegate
        depthDelegate = nil
        depthDataOutput = nil
        
        // Clear camera device
        currentDevice = nil
        
        // Force cleanup
        autoreleasepool {
            // Release retained objects
        }
    }
    
    // MARK: - Camera Permission Handling
    func checkAndHandleCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if !granted {
                        self.presentCameraDeniedAlert()
                    }
                }
            }
        case .denied, .restricted:
            presentCameraDeniedAlert()
        @unknown default:
            break
        }
    }
    
    private func presentCameraDeniedAlert() {
        cameraPermissionAlert = CameraPermissionAlert(
            title: "Camera Access Needed",
            message: "This app requires access to your camera to function. Please allow camera access in Settings.",
            openSettings: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        )
    }
    
    // MARK: - Reinitialization Method (SAFER VERSION)
    func reinitialize() {
        // Stop current session without destroying it
        stopSession()
        stopSpeech()
        clearDetections()
        
        // Reset state properties to defaults
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Reset camera settings (but don't destroy camera)
            self.currentOrientation = .portrait
            self.isTorchOn = false
            self.torchLevel = 0.0
            self.isUltraWide = false
            self.currentZoomLevel = 1.0
            self.minimumZoomFactor = 1.0
            self.maximumZoomFactor = 5.0
            self.initialZoomFactor = 1.0
            
            // Reset detection settings
            self.detections = []
            self.framesPerSecond = 0
            self.filterMode = "all"
            self.confidenceThreshold = 0.75
            self.frameRate = 30
            
            // Reset speech settings (keep voice selection)
            self.isSpeechEnabled = true
            self.speechVoiceGender = .unspecified
            
            // Reset LiDAR
            self.useLiDAR = false
            self.isLiDAREnabled = false
            self.lastDistancesFeet = [:]
            
            // Clear FPS tracking
            self.lastFrameTimestamps = []
            
            // Reset processing state
            self.frameCounter = 0
            self.isProcessing = false
            self.processEveryNFrames = 1
            self.lastSpokenTime = [:]
            self.lastAnnouncementTime = Date.distantPast
            self.isSpeaking = false
            
            // Keep camera position at back (don't change it)
            self.cameraPosition = .back
        }
        
        // Clear LiDAR Manager state
        LiDARManager.shared.stop()
        LiDARManager.shared.setEnabled(false)
        
        // Force memory cleanup
        autoreleasepool {
            // This helps release any retained objects
        }
    }
    
    // MARK: - Memory Management
    @objc private func handleMemoryWarning() {
        let now = Date()
        guard now.timeIntervalSince(lastMemoryWarning) > 5 else { return }
        lastMemoryWarning = now
        print("⚠️ Memory warning received")
        // Clear caches
        autoreleasepool {
            detections = []
            lastSpokenTime.removeAll()
            yoloProcessor?.reset()
            LiDARManager.shared.cleanupOldHistories(currentDetectionIds: Set())
        }
        // Reduce frame rate temporarily
        frameRate = 15
        processEveryNFrames = 3
        // Restore after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.frameRate = 30
            self?.processEveryNFrames = 1
        }
    }
}
