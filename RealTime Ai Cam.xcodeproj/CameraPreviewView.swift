import AVFoundation

class VideoProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var videoConnection: AVCaptureConnection?
    
    private var currentPixelBuffer: CVPixelBuffer?
    private var currentSampleBuffer: CMSampleBuffer?
    
    func startSession() {
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        
        let videoDevice = AVCaptureDevice.default(for: .video)
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice!), captureSession.canAddInput(videoDeviceInput) else { return }
        captureSession.addInput(videoDeviceInput)
        
        videoOutput = AVCaptureVideoDataOutput()
        guard let videoOutput = videoOutput, captureSession.canAddOutput(videoOutput) else { return }
        captureSession.addOutput(videoOutput)
        
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        videoConnection = videoOutput.connection(with: .video)
        
        captureSession.startRunning()
    }
    
    func stopSession() {
        // Stop the capture session
        captureSession?.stopRunning()
        
        // Release video connection
        if let connection = videoConnection {
            print("Releasing videoConnection: retainCount = \(CFGetRetainCount(connection))")
            videoConnection = nil // Release video connection
        }
        
        // Release video output
        if let output = videoOutput {
            print("Releasing videoOutput: retainCount = \(CFGetRetainCount(output))")
            videoOutput = nil // Release video output
        }
        
        // Release capture session
        if let session = captureSession {
            print("Releasing captureSession: retainCount = \(CFGetRetainCount(session))")
            captureSession = nil // Release capture session
        }
        
        // Release current sample buffer
        if let sampleBuffer = currentSampleBuffer {
            print("Releasing currentSampleBuffer")
            currentSampleBuffer = nil
        }
        
        // Release current pixel buffer
        if let pixelBuffer = currentPixelBuffer {
            print("Releasing currentPixelBuffer")
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            currentPixelBuffer = nil
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            // Lock and retain the sample buffer
            currentSampleBuffer = sampleBuffer
            defer {
                // Release current sample buffer
                if let sampleBuffer = currentSampleBuffer {
                    currentSampleBuffer = nil
                }
            }
            
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            currentPixelBuffer = pixelBuffer
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            defer {
                // Unlock and release pixel buffer
                if let pixelBuffer = currentPixelBuffer {
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                    currentPixelBuffer = nil
                }
            }
            
            // Process the pixelBuffer here...
        }
    }
}
