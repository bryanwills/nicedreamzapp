import AVFoundation
import UIKit

class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var captureSession: AVCaptureSession?
    var videoOutput: AVCaptureVideoDataOutput?
    var videoConnection: AVCaptureConnection?
    var currentPixelBuffer: CVPixelBuffer?
    var currentSampleBuffer: CMSampleBuffer?

    func startSession() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high

        guard let captureDevice = AVCaptureDevice.default(for: .video) else { return }

        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }
        } catch {
            print("Error setting device video input: \(error)")
            return
        }

        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.alwaysDiscardsLateVideoFrames = true
        videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))

        if let videoOutput, captureSession?.canAddOutput(videoOutput) == true {
            captureSession?.addOutput(videoOutput)
        }

        videoConnection = videoOutput?.connection(with: .video)

        captureSession?.startRunning()
    }

    func stopSession() {
        // Stop running session
        captureSession?.stopRunning()

        // Clean up video connection
        if let videoConnection {
            // No explicit release needed but clearing reference
            print("Releasing videoConnection: \(CFGetRetainCount(videoConnection))")
            self.videoConnection = nil
        }

        // Clean up video output
        if let videoOutput {
            print("Releasing videoOutput: \(CFGetRetainCount(videoOutput))")
            self.videoOutput = nil
        }

        // Clean up current sample buffer
        if let currentSampleBuffer {
            print("Releasing currentSampleBuffer")
            if let pixelBuffer = CMSampleBufferGetImageBuffer(currentSampleBuffer) {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            }
            self.currentSampleBuffer = nil
        }

        // Clean up current pixel buffer
        if let currentPixelBuffer {
            print("Releasing currentPixelBuffer")
            CVPixelBufferUnlockBaseAddress(currentPixelBuffer, [])
            self.currentPixelBuffer = nil
        }

        // Clean up capture session
        if let captureSession {
            print("Releasing captureSession: \(CFGetRetainCount(captureSession))")
            self.captureSession = nil
        }
    }

    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            // Lock the base address of the pixel buffer
            CVPixelBufferLockBaseAddress(pixelBuffer, [])

            // Defer unlocking and nil-ing pixelBuffer
            defer {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            }

            // Defer nil-ing sampleBuffer (no explicit release function)
            defer {
                // sampleBuffer being a CMSampleBufferRef is managed by ARC, no manual release needed
                // Just nil-ing currentSampleBuffer to break potential retain cycles
                self.currentSampleBuffer = nil
            }

            // Keep references to buffers for cleanup
            self.currentPixelBuffer = pixelBuffer
            self.currentSampleBuffer = sampleBuffer

            // Process the pixel buffer here
            // Example: convert to UIImage, filter, etc.
        }
    }
}
