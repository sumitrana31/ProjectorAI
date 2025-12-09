//
//  CameraManager.swift
//  ProjectorAI
//
//  Handles AVCaptureSession for camera capture and frame extraction
//

import AVFoundation
import UIKit
import SwiftUI

class CameraManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var currentResolution: String = "1920x1080"

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.projectorai.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "com.projectorai.camera.videoOutput")

    private var currentFrame: UIImage?
    private let frameLock = NSLock()

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    private func configureSession() {
        captureSession.beginConfiguration()

        // Set session preset for HD quality
        if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        } else if captureSession.canSetSessionPreset(.hd1280x720) {
            captureSession.sessionPreset = .hd1280x720
            DispatchQueue.main.async {
                self.currentResolution = "1280x720"
            }
        }

        // Add video input (back camera)
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("CameraManager: No back camera available")
            captureSession.commitConfiguration()
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                print("CameraManager: Could not add video input")
                captureSession.commitConfiguration()
                return
            }
        } catch {
            print("CameraManager: Error creating video input: \(error)")
            captureSession.commitConfiguration()
            return
        }

        // Configure video output
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)

            // Set video orientation
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
        } else {
            print("CameraManager: Could not add video output")
        }

        captureSession.commitConfiguration()

        // Create preview layer on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let layer = AVCaptureVideoPreviewLayer(session: self.captureSession)
            layer.videoGravity = .resizeAspectFill
            self.previewLayer = layer
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                DispatchQueue.main.async {
                    self.isRunning = true
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                DispatchQueue.main.async {
                    self.isRunning = false
                }
            }
        }
    }

    func captureCurrentFrame() -> UIImage? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return currentFrame
    }

    func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let image = UIImage(cgImage: cgImage)

        frameLock.lock()
        currentFrame = image
        frameLock.unlock()
    }
}

// MARK: - Camera Preview View
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        if let previewLayer = cameraManager.previewLayer {
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let previewLayer = cameraManager.previewLayer {
                previewLayer.frame = uiView.bounds
                if previewLayer.superlayer == nil {
                    uiView.layer.addSublayer(previewLayer)
                }
            }
        }
    }
}
