// ScannerService.swift
// Live camera frame processing, AVCaptureSession lifecycle, and Vision OCR card number recognition.

import AVFoundation
import Vision
import UIKit
import SwiftUI

@Observable
public final class ScannerService: NSObject, @unchecked Sendable {

    public var recognizedNumber: String?
    public var recognizedCardCandidate: String?
    public var lastRawText: String = ""
    public var isScanning: Bool = false
    public var isTorchOn: Bool = false
    public var cameraPermissionGranted: Bool = false

    public let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.pokemontracker.cameraSessionQueue", qos: .userInitiated)

    private var frameCounter: Int = 0
    private var consecutiveHits: [String: Int] = [:]
    private let hitThreshold: Int = 2
    private var lastRecognizedTimestamp: Date = .distantPast

    public override init() {
        super.init()
    }

    public func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.cameraPermissionGranted = granted
                    if granted {
                        self?.setupCamera()
                    }
                }
            }
        default:
            cameraPermissionGranted = false
        }
    }

    public func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.captureSession.isRunning else { return }

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .hd1920x1080

            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
                self.captureSession.commitConfiguration()
                return
            }

            if self.captureSession.canAddInput(videoInput) {
                self.captureSession.addInput(videoInput)
            }

            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]

            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }

            self.captureSession.commitConfiguration()
        }
    }

    public func startScanning() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isScanning = true
            }
        }
    }

    public func stopScanning() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isScanning = false
            }
        }
    }

    public func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = isTorchOn ? .off : .on
            device.unlockForConfiguration()
            isTorchOn.toggle()
        } catch {
            print("[Scanner] Torch error: \(error)")
        }
    }

    public func resetRecognition() {
        recognizedNumber = nil
        recognizedCardCandidate = nil
        consecutiveHits.removeAll()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ScannerService: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCounter += 1
        // Process 1 frame every 4 frames (approx. 7-8 FPS) to conserve battery and CPU
        guard frameCounter % 4 == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNRecognizeTextRequest { [weak self] req, err in
            guard let self = self, err == nil else { return }
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
            self.processTextObservations(observations)
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["de-DE", "en-US"]
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
    }

    private func processTextObservations(_ observations: [VNRecognizedTextObservation]) {
        let bottomObservations = observations.filter { $0.boundingBox.minY < 0.35 }
        let targetObservations = bottomObservations.isEmpty ? observations : bottomObservations

        let fractionPattern = #"\b([A-Za-z0-9]{1,5})\s*[\/|Il!\]]\s*([A-Za-z0-9]{1,5})\b"#
        let singleNumPattern = #"\b(?:NO\.|NR\.|#)?\s*(\d{1,4})\b"#

        var detectedCandidates: [String] = []

        for obs in targetObservations {
            guard let candidate = obs.topCandidates(1).first?.string else { continue }

            if let regex = try? NSRegularExpression(pattern: fractionPattern, options: .caseInsensitive) {
                let range = NSRange(candidate.startIndex..., in: candidate)
                let matches = regex.matches(in: candidate, options: [], range: range)
                for m in matches {
                    if let r1 = Range(m.range(at: 1), in: candidate) {
                        let num = String(candidate[r1]).trimmingCharacters(in: .whitespaces)
                        if num.count >= 1 && num.count <= 4 {
                            detectedCandidates.append(num)
                        }
                    }
                }
            }

            if detectedCandidates.isEmpty {
                if let regex = try? NSRegularExpression(pattern: singleNumPattern, options: .caseInsensitive) {
                    let range = NSRange(candidate.startIndex..., in: candidate)
                    let matches = regex.matches(in: candidate, options: [], range: range)
                    for m in matches {
                        if let r1 = Range(m.range(at: 1), in: candidate) {
                            let num = String(candidate[r1]).trimmingCharacters(in: .whitespaces)
                            if num.count >= 1 && num.count <= 3 {
                                detectedCandidates.append(num)
                            }
                        }
                    }
                }
            }
        }

        let allLines = observations.compactMap { $0.topCandidates(1).first?.string }
        guard !allLines.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastRawText = allLines.joined(separator: " | ")

            for candidate in detectedCandidates {
                let hits = (self.consecutiveHits[candidate] ?? 0) + 1
                self.consecutiveHits[candidate] = hits

                if hits >= self.hitThreshold {
                    if self.recognizedNumber != candidate {
                        self.recognizedNumber = candidate
                        self.lastRecognizedTimestamp = Date()
                    }
                    break
                }
            }
        }
    }
}
