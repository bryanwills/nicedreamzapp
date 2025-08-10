import AVFoundation

class CameraManager {
    private var captureSession: AVCaptureSession?
    private var currentDevice: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    
    func startSession() {
        captureSession?.startRunning()
    }
    
    func stopSession() {
        captureSession?.stopRunning()
    }
    
    func setup(device: AVCaptureDevice) {
        currentDevice = device
        captureSession = AVCaptureSession()
        captureSession?.beginConfiguration()
        
        if let captureSession = captureSession {
            captureSession.sessionPreset = .high
            
            if let input = try? AVCaptureDeviceInput(device: device), captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            videoOutput = AVCaptureVideoDataOutput()
            if let videoOutput = videoOutput, captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            captureSession.commitConfiguration()
        }
    }
    
    func switchToUltraWide(_ useUltraWide: Bool) {
        stopSession()
        let position: AVCaptureDevice.Position = .back
        let deviceType: AVCaptureDevice.DeviceType = useUltraWide ? .builtInUltraWideCamera : .builtInWideAngleCamera
        if let device = AVCaptureDevice.default(deviceType, for: .video, position: position) {
            setup(device: device)
        }
        startSession()
    }
}
