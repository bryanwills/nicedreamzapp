import SwiftUI
import Combine
import AVFoundation
import Vision
import MemoryManager

@MainActor
struct OCRView: View {
    @StateObject private var ocrProcessor = OCRProcessor()
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    private var memoryObservers: [NSObjectProtocol] = []
    
    var body: some View {
        VStack {
            CameraPreviewView(session: ocrProcessor.captureSession)
                .overlay(Text(ocrProcessor.recognizedText).padding().background(Color.black.opacity(0.5)).foregroundColor(.white), alignment: .bottom)
            Button("Speak") {
                ocrProcessor.speakText()
            }
            .padding()
        }
        .onAppear {
            ocrProcessor.start()
            
            let reduceQualityObserver = NotificationCenter.default.addObserver(forName: .reduceQualityForMemory, object: nil, queue: .main) { _ in
                ocrProcessor.clearCacheAndBuffers()
            }
            let reduceFrameRateObserver = NotificationCenter.default.addObserver(forName: .reduceFrameRate, object: nil, queue: .main) { _ in
                ocrProcessor.reduceOCRFrequencyTemporarily()
            }
            memoryObservers.append(contentsOf: [reduceQualityObserver, reduceFrameRateObserver])
        }
        .onDisappear {
            ocrProcessor.stop()
            for observer in memoryObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            memoryObservers.removeAll()
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
}

@MainActor
final class OCRProcessor: NSObject, ObservableObject {
    @Published var recognizedText: String = ""
    
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private var requests = [VNRequest]()
    private var lastOCRTime = Date.distantPast
    private var ocrInterval: TimeInterval = 0.1 // default OCR frequency
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    private var textCache: [String] = []
    private var imageCache: [CGImage] = []
    
    override init() {
        super.init()
        configureCaptureSession()
        setupVision()
    }
    
    func start() {
        sessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }
    
    func stop() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }
    
    private func configureCaptureSession() {
        captureSession.beginConfiguration()
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoDeviceInput) else {
            return
        }
        captureSession.addInput(videoDeviceInput)
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        guard captureSession.canAddOutput(videoOutput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addOutput(videoOutput)
        captureSession.commitConfiguration()
    }
    
    private func setupVision() {
        let textRecognitionRequest = VNRecognizeTextRequest(completionHandler: self.handleDetectedText)
        textRecognitionRequest.recognitionLevel = .accurate
        textRecognitionRequest.usesLanguageCorrection = true
        self.requests = [textRecognitionRequest]
    }
    
    private func handleDetectedText(request: VNRequest, error: Error?) {
        guard error == nil else { return }
        guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
        let maximumCandidates = 1
        var detectedText = ""
        for observation in observations {
            guard let candidate = observation.topCandidates(maximumCandidates).first else { continue }
            detectedText += candidate.string + "\n"
        }
        DispatchQueue.main.async {
            self.recognizedText = detectedText
            self.textCache.append(detectedText)
        }
    }
    
    func speakText() {
        let utterance = AVSpeechUtterance(string: recognizedText)
        speechSynthesizer.speak(utterance)
    }
    
    func clearCacheAndBuffers() {
        // Clear cached images and text
        textCache.removeAll()
        imageCache.removeAll()
        
        // Force aggressive CoreML/Metal buffer cleanup
        // As realistic as possible: reset requests and recreate Vision requests
        
        self.requests.removeAll()
        setupVision()
        
        // Additional Metal buffer cleanup can be added here if applicable
        // No duplicate emergency cleanup logic here, now handled by MemoryManager
    }
    
    func reduceOCRFrequencyTemporarily() {
        // Temporarily reduce OCR frequency for memory pressure
        
        // If OCR frequency cannot be reduced, this is a no-op to maintain API uniformity
        // Here, we reduce OCR frequency by increasing interval to 0.5 seconds temporarily
        
        ocrInterval = 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.ocrInterval = 0.1
        }
    }
}

extension OCRProcessor: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastOCRTime) >= ocrInterval else { return }
        lastOCRTime = now
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Cache CGImage for potential future use/cleanup
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            imageCache.append(cgImage)
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            // Ignore error
        }
    }
}

extension Notification.Name {
    static let reduceQualityForMemory = Notification.Name("reduceQualityForMemory")
    static let reduceFrameRate = Notification.Name("reduceFrameRate")
}
