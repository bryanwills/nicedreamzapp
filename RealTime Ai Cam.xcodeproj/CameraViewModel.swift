//
//  CameraViewModel.swift
//  MachineLearningSample
//
//  Created by Hiroshi Hashiguchi on 2019/11/24.
//  Copyright © 2019 Hashiguchi Hiroshi. All rights reserved.
//

import AVFoundation
import UIKit

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var yoloProcessor: YoloProcessor?
    var captureSession: AVCaptureSession?
    var videoOutput: AVCaptureVideoDataOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var updateTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        yoloProcessor = YoloProcessor()
    }

    func setupCamera() {
        captureSession = AVCaptureSession()
        guard let captureSession else { return }

        captureSession.sessionPreset = .high

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                        for: .video,
                                                        position: .back)
        else {
            return
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }

        videoOutput = AVCaptureVideoDataOutput()
        guard let videoOutput else { return }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
            kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        guard let previewLayer else { return }
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        captureSession.startRunning()

        updateTimer = Timer.scheduledTimer(timeInterval: 1.0,
                                           target: self,
                                           selector: #selector(updateUI),
                                           userInfo: nil,
                                           repeats: true)
    }

    @objc func updateUI() {
        // Update UI elements
    }

    func shutdown() {
        updateTimer?.invalidate()
        updateTimer = nil

        captureSession?.stopRunning()
        captureSession = nil

        videoOutput = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil

        yoloProcessor = nil
    }

    func captureOutput(_: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from _: AVCaptureConnection)
    {
        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            defer {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            }

            let retainCountYoloProcessor = CFGetRetainCount(yoloProcessor as AnyObject)
            print("YOLO Processor retain count after capture: \(retainCountYoloProcessor)")
            if retainCountYoloProcessor > 2 {
                print("⚠️ YOLO Processor retain count is high")
            }

            yoloProcessor?.processFrame(pixelBuffer: pixelBuffer)

            let retainCountPixelBuffer = CVPixelBufferGetRetainCount(pixelBuffer)
            print("PixelBuffer retain count after processing: \(retainCountPixelBuffer)")
            if retainCountPixelBuffer > 2 {
                print("⚠️ PixelBuffer retain count is high")
            }
        }
    }
}
