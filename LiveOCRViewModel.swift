import SwiftUI
import Vision
import AVFoundation
import CoreVideo
import Combine

// MARK: - Static Spanish Processor (Singleton - Loads JSON ONCE)
final class StaticSpanishProcessor {
    static let shared = StaticSpanishProcessor()
    
    private var grammarRules: [String: Any] = [:]
    private var baseDictionary: [String: [String: Any]] = [:]
    private var lookupMap: [String: String] = [:]
    private var postprocessRules: [String: Any] = [:]
    private(set) var isLoaded = false
    
    private init() {
        loadSpanishData()
    }
    
    private func loadSpanishData() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            autoreleasepool {
                let candidates = [
                    ("es_final_with_rules_CLEANED", "json"),
                    ("es_final_with_rules_ENRICHED", "json"),
                    ("es_final_with_rules_CLEAN", "json"),
                    ("es_final_with_rules", "json")
                ]
                
                for (name, ext) in candidates {
                    if let url = Bundle.main.url(forResource: name, withExtension: ext),
                       let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        self?.grammarRules = json["rules"] as? [String: Any] ?? [:]
                        self?.baseDictionary = json["dictionary"] as? [String: [String: Any]] ?? [:]
                        self?.lookupMap = json["lookup"] as? [String: String] ?? [:]
                        self?.postprocessRules = (self?.grammarRules["postprocess_en"] as? [String: Any]) ?? [:]
                        
                        DispatchQueue.main.async {
                            self?.isLoaded = true
                            print("✅ Spanish data loaded ONCE: \(self?.baseDictionary.count ?? 0) entries")
                        }
                        break
                    }
                }
            }
        }
    }
    
    func interpretSpanishWithContext(_ text: String) -> String {
        guard isLoaded else { return text }
        
        // Your existing translation logic here - simplified for now
        var result = text
        
        // Apply basic translations from dictionary
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        var translated: [String] = []
        
        for word in words {
            var cleanWord = word.lowercased()
            // Remove punctuation for lookup
            cleanWord = cleanWord.trimmingCharacters(in: .punctuationCharacters)
            
            if let entry = baseDictionary[cleanWord] {
                if let trans = entry["translation"] as? String {
                    translated.append(trans)
                } else {
                    translated.append(word)
                }
            } else {
                translated.append(word)
            }
        }
        
        result = translated.joined(separator: " ")
        return result
    }
}

// MARK: - Zoom Camera Manager
class ZoomCameraManager: NSObject, ObservableObject {
    @Published var currentZoomLevel: CGFloat = 1.0
    
    private var captureDevice: AVCaptureDevice?
    private var initialZoomFactor: CGFloat = 1.0
    
    func setup(device: AVCaptureDevice) {
        self.captureDevice = device
    }
    
    func handlePinchGesture(_ scale: CGFloat) {
        guard let device = captureDevice else { return }
        
        let newZoomFactor = initialZoomFactor * scale
        let clampedZoom = max(1.0, min(newZoomFactor, min(device.maxAvailableVideoZoomFactor, 5.0)))
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedZoom
            device.unlockForConfiguration()
            
            DispatchQueue.main.async {
                self.currentZoomLevel = clampedZoom
            }
        } catch {
            print("Failed to set zoom: \(error)")
        }
    }
    
    func setPinchGestureStartZoom() {
        initialZoomFactor = captureDevice?.videoZoomFactor ?? 1.0
    }
}

// MARK: - Live OCR View Model
final class LiveOCRViewModel: NSObject, ObservableObject {
    // MARK: - Properties
    @Published var recognizedText: String = ""
    @Published var translatedText: String = ""
    @Published var isProcessing: Bool = false
    @Published var isTranslated: Bool = false  // NEW: Track translation state
    @Published var isUltraWide: Bool = false
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var isPinching: Bool = false
    
    weak var cameraPreviewRef: CameraPreviewView?
    weak var cameraPreviewView: CameraPreviewView?
    
    let cameraManager = ZoomCameraManager()
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var textRecognitionRequest: VNRecognizeTextRequest?
    private var lastProcessedTime = Date()
    private var currentLanguage: String?
    private var speechCompletionHandler: (() -> Void)?
    
    private var processInterval: TimeInterval {
        // Check if Spanish data is loaded
        if StaticSpanishProcessor.shared.isLoaded {
            switch DevicePerf.shared.tier {
            case .low:  return 1.5
            case .mid:  return 1.0
            case .high: return 0.75
            }
        } else {
            switch DevicePerf.shared.tier {
            case .low:  return 0.75
            case .mid:  return 0.50
            case .high: return 0.30
            }
        }
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupTextRecognition()
        speechSynthesizer.delegate = self
        
        // Ensure Spanish data starts loading
        _ = StaticSpanishProcessor.shared
    }
    
    private func setupTextRecognition() {
        textRecognitionRequest = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            if let error = error {
                print("Text recognition error: \(error)")
                request.cancel()
                return
            }
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                request.cancel()
                return
            }
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            let fullText = recognizedStrings.joined(separator: " ")
            DispatchQueue.main.async {
                self.recognizedText = fullText
                self.isProcessing = false
                // Reset translation state when new text is detected
                if self.isTranslated && fullText != self.recognizedText {
                    self.isTranslated = false
                    self.translatedText = ""
                }
            }
        }
        // Configure recognition level based on device
        let tier = DevicePerf.shared.tier
        switch tier {
        case .low:
            textRecognitionRequest?.recognitionLevel = .fast
            textRecognitionRequest?.usesLanguageCorrection = false
            textRecognitionRequest?.minimumTextHeight = 0.03
        case .mid:
            textRecognitionRequest?.recognitionLevel = .accurate
            textRecognitionRequest?.usesLanguageCorrection = true
            textRecognitionRequest?.minimumTextHeight = 0.02
        case .high:
            textRecognitionRequest?.recognitionLevel = .accurate
            textRecognitionRequest?.usesLanguageCorrection = true
            textRecognitionRequest?.minimumTextHeight = 0.015
        }
    }
    
    // MARK: - Frame Processing (OCR Only, No Translation)
    func processFrame(_ pixelBuffer: CVPixelBuffer, mode: OCRMode) {
        autoreleasepool {
            print("processFrame start - pixelBuffer retain count: \(CFGetRetainCount(pixelBuffer))")
            if CFGetRetainCount(pixelBuffer) > 2 {
                print("⚠️ Warning: pixelBuffer retain count > 2 at start")
            }
            
            defer {
                // Buffer release point - unlock base address
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                // pixelBuffer is a function parameter; cannot be set to nil
                print("processFrame end - pixelBuffer retain count: \(CFGetRetainCount(pixelBuffer))")
                if CFGetRetainCount(pixelBuffer) > 2 {
                    print("⚠️ Warning: pixelBuffer retain count > 2 at end")
                }
            }
            
            guard !isPinching else { return }
            
            let now = Date()
            guard now.timeIntervalSince(lastProcessedTime) >= processInterval else { return }
            lastProcessedTime = now
            
            guard !isProcessing else { return }
            
            // Only set language if it changed
            let targetLanguage = (mode == .spanishToEnglish) ? "es-ES" : "en-US"
            if currentLanguage != targetLanguage {
                currentLanguage = targetLanguage
                
                if mode == .spanishToEnglish {
                    textRecognitionRequest?.recognitionLanguages = ["es-ES", "es"]
                } else {
                    textRecognitionRequest?.recognitionLanguages = ["en-US", "en"]
                }
            }
            
            DispatchQueue.main.async {
                self.isProcessing = true
            }
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self, let request = self.textRecognitionRequest else { return }
                
                autoreleasepool {
                    do {
                        try handler.perform([request])
                    } catch {
                        print("Failed to perform text recognition: \(error)")
                        DispatchQueue.main.async {
                            self.isProcessing = false
                        }
                    }
                    // Cleanup after request
                    request.cancel()
                }
            }
        }
    }
    
    // MARK: - On-Demand Translation (NEW)
    func translateSpanishText(completion: @escaping (Bool) -> Void) {
        guard !recognizedText.isEmpty else {
            completion(false)
            return
        }
        
        // Translate in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            let translated = StaticSpanishProcessor.shared.interpretSpanishWithContext(self.recognizedText)
            
            DispatchQueue.main.async {
                self.translatedText = translated
                self.isTranslated = true
                completion(true)
            }
        }
    }
    
    // MARK: - Reset Translation (NEW)
    func resetTranslation() {
        isTranslated = false
        translatedText = ""
    }
    
    // MARK: - Speech
    func speak(text: String, voiceIdentifier: String, completion: @escaping () -> Void) {
        guard !text.isEmpty else {
            completion()
            return
        }
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        self.speechCompletionHandler = completion
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let utterance = AVSpeechUtterance(string: text)
            if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
                utterance.voice = voice
            }
            utterance.rate = 0.5
            utterance.volume = 0.9
            self.speechSynthesizer.speak(utterance)
        }
    }
    
    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    // MARK: - Text Management
    func copyText(_ text: String) {
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        SettingsOverlayView.addToCopyHistory(text)
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    func clearText() {
        recognizedText = ""
        translatedText = ""
        isTranslated = false
    }
    
    // MARK: - Camera Controls
    func toggleCameraZoom() {
        isUltraWide.toggle()
        print("📷 Toggled camera zoom: ultraWide = \(isUltraWide)")
    }
    
    func flipCamera() {
        cameraPosition = cameraPosition == .back ? .front : .back
        if cameraPosition == .front {
            isUltraWide = false
        }
        print("📷 Flipped camera: position = \(cameraPosition)")
    }
    
    func setCameraPreview(_ preview: CameraPreviewView) {
        self.cameraPreviewView = preview
    }
    
    // MARK: - Session Management
    func startSession() {
        print("🎬 OCR session started")
    }
    
    func stopSession() {
        stopSpeaking()
        print("🛑 OCR session stopped")
    }
    
    func shutdown() {
        print("🧹 LiveOCRViewModel shutdown starting")
        cameraPreviewView?.stopSession()
        stopSession()
        clearText()
        print("🧹 LiveOCRViewModel shutdown complete")
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension LiveOCRViewModel: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.speechCompletionHandler?()
            self.speechCompletionHandler = nil
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.speechCompletionHandler?()
            self.speechCompletionHandler = nil
        }
    }
}
