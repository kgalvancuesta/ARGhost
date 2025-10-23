import SwiftUI
import AVFoundation
import Vision

struct CameraPreview: UIViewRepresentable {
    typealias UIViewType = PreviewView

    let side: CGFloat
    let cameraPosition: AVCaptureDevice.Position

    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            // Keep overlay sized with the preview
            if let sublayers = layer.sublayers {
                for sl in sublayers where sl is CAShapeLayer {
                    sl.frame = bounds
                }
            }
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let previewView = PreviewView()
        let pl = previewView.videoPreviewLayer

        // UI view set up
        pl.session = context.coordinator.session
        pl.videoGravity = .resizeAspectFill
        pl.frame = previewView.bounds
        pl.needsDisplayOnBoundsChange = true

        // Add overlay above camera
        context.coordinator.bboxLayer.frame = previewView.bounds
        context.coordinator.bboxLayer.strokeColor = UIColor.systemGreen.cgColor
        context.coordinator.bboxLayer.fillColor = UIColor.clear.cgColor
        context.coordinator.bboxLayer.lineWidth = 3
        pl.addSublayer(context.coordinator.bboxLayer)
        context.coordinator.bboxLayer.setAffineTransform(CGAffineTransform(rotationAngle: .pi))

        context.coordinator.previewLayer = pl
        if let c = pl.connection {
            if c.isVideoOrientationSupported { c.videoOrientation = .portrait }
            c.isVideoMirrored = (cameraPosition == .front)
        }

        return previewView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.switchCamera(to: cameraPosition)
        // keep overlay sized
        context.coordinator.bboxLayer.frame = uiView.bounds
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private let parent: CameraPreview

        let session = AVCaptureSession()
        private let videoOutput = AVCaptureVideoDataOutput()
        private let sessionQueue = DispatchQueue(label: "CameraSessionQueue")
        fileprivate let bboxLayer = CAShapeLayer()
        fileprivate var previewLayer: AVCaptureVideoPreviewLayer?
        private var currentPosition: AVCaptureDevice.Position = .front

        // Vision
        private let poseRequest = VNDetectHumanBodyPoseRequest()

        // Frame buffer (kept for future batching, not used by Vision path here)
        private var isCapturingFrames = false
        private(set) var frameBuffer: [CVPixelBuffer] = []
        private let desiredFrameCount = 4

        init(parent: CameraPreview) {
            self.parent = parent
            self.currentPosition = parent.cameraPosition
            super.init()
            setupSession()
        }

        private func setupSession() {
            sessionQueue.async { [weak self] in
                guard let self = self else { return }

                // Configure video settings
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                    let outputQueue = DispatchQueue(label: "VideoDataOutputQueue")
                    self.videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
                }

                // Add the initial camera input
                self.switchCamera(to: self.currentPosition)

                // Start the session
                self.session.startRunning()
            }
        }

        func switchCamera(to position: AVCaptureDevice.Position) {
            // Avoid redundant switches
            if position == currentPosition && !session.inputs.isEmpty { return }

            sessionQueue.async { [weak self] in
                guard let self = self else { return }

                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }

                // Remove the current camera in order to switch (if one exists)
                if let currentInput = self.session.inputs.first as? AVCaptureDeviceInput {
                    self.session.removeInput(currentInput)
                }

                var newVideoDevice: AVCaptureDevice?

                if position == .back {
                    // Prefer telephoto if available (no dual/triple/wide)
                    if let tele = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) {
                        newVideoDevice = tele
                        print("Using Telephoto Camera.")
                    } else {
                        // Fallback only if you *want* to allow wide on devices without tele
                        newVideoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                        print("Telephoto not available — using Wide Angle as fallback.")
                    }
                } else {
                    // Front camera (no alternative lens)
                    newVideoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                    print("Using Front Camera.")
                }

                guard let finalDevice = newVideoDevice else {
                    print("Error: Could not find a suitable camera for position \(position).")
                    return
                }

                do {
                    let newVideoInput = try AVCaptureDeviceInput(device: finalDevice)
                    guard self.session.canAddInput(newVideoInput) else {
                        print("Could not add new video input to session.")
                        return
                    }
                    self.session.addInput(newVideoInput)

                    // Reset zoom and set focus/exposure center
                    try finalDevice.lockForConfiguration()
                    finalDevice.videoZoomFactor = 1.0
                    finalDevice.unlockForConfiguration()
                    self.focus(at: CGPoint(x: 0.5, y: 0.5))

                    // Reconfigure new device for best format
                    if let fmt = self.findFormat(device: finalDevice, minWidth: 1080, minHeight: 1080, maxFPS: 60) {
                        try finalDevice.lockForConfiguration()
                        finalDevice.activeFormat = fmt
                        finalDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                        finalDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
                        finalDevice.unlockForConfiguration()
                    } else {
                        print("High-speed format not available for \(position) camera.")
                    }
                } catch {
                    print("Error creating AVCaptureDeviceInput: \(error)")
                    return
                }

                self.currentPosition = position

                DispatchQueue.main.async {
                    guard let connection = self.previewLayer?.connection else { return }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false   // no mirroring, even on front camera
                    }
                }
            }
        }

        private func focus(at point: CGPoint) {
            sessionQueue.async {
                guard let deviceInput = self.session.inputs.first as? AVCaptureDeviceInput else { return }
                let device = deviceInput.device

                do {
                    try device.lockForConfiguration()

                    // Set Focus
                    if device.isFocusPointOfInterestSupported {
                        device.focusPointOfInterest = point
                        device.focusMode = .continuousAutoFocus
                    }

                    // Set Exposure
                    if device.isExposurePointOfInterestSupported {
                        device.exposurePointOfInterest = point
                        device.exposureMode = .autoExpose
                    }

                    device.unlockForConfiguration()
                } catch {
                    print("Could not lock device for configuration: \(error)")
                }
            }
        }

        // Find the best format for capturing camera feed
        private func findFormat(
            device: AVCaptureDevice,
            minWidth: Int,
            minHeight: Int,
            maxFPS: Double
        ) -> AVCaptureDevice.Format? {
            for format in device.formats {
                let desc = format.formatDescription
                let dims = CMVideoFormatDescriptionGetDimensions(desc)
                let maxRate = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 0
                if maxRate >= maxFPS && dims.width >= minWidth && dims.height >= minHeight {
                    return format
                }
            }
            return nil
        }

        // Keep frame buffer functionality for future pose processing
        private func startCaptureBurst() {
            guard !isCapturingFrames else { return }
            isCapturingFrames = true
            frameBuffer.removeAll()
        }

        private func stopCaptureBurst() {
            isCapturingFrames = false
        }

        // MARK: - Capture Delegate (Pose)

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            // Buffering for future batching (kept)
            if isCapturingFrames {
                frameBuffer.append(pixelBuffer)
                if frameBuffer.count >= desiredFrameCount { stopCaptureBurst() }
            }

            // Vision pose request (lightweight and fast)
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: self.vnOrientation(for: connection.videoOrientation, mirrored: (currentPosition == .front))
            )

            do {
                try handler.perform([poseRequest])
                guard let observations = poseRequest.results as? [VNHumanBodyPoseObservation], !observations.isEmpty else {
                    // Clear overlay when no pose is found
                    DispatchQueue.main.async { self.bboxLayer.path = nil }
                    return
                }

                // Use first pose (extend to multiple if you like)
                if let first = observations.first {
                    self.drawPose(observation: first)
                }
            } catch {
                // Don’t spam logs; skip frame on errors
            }
        }

        // MARK: - Drawing

        private func drawPose(observation: VNHumanBodyPoseObservation) {
            guard let pl = self.previewLayer else { return }
            let layerBounds = pl.bounds
            let mirrored = (currentPosition == .front)

            // Get all recognized points with a decent confidence
            guard let points = try? observation.recognizedPoints(.all) else {
                DispatchQueue.main.async { self.bboxLayer.path = nil }
                return
            }

            // Helper to fetch a point by name if confidence is OK
            func p(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                guard let rp = points[name], rp.confidence > 0.3, let pl = self.previewLayer else { return nil }
                return self.convert(rp, in: pl)
            }

            // Common joints (Apple Vision set)
            let nose = p(.nose)
            let leftEye = p(.leftEye)
            let rightEye = p(.rightEye)
            let leftEar = p(.leftEar)
            let rightEar = p(.rightEar)

            let leftShoulder = p(.leftShoulder)
            let rightShoulder = p(.rightShoulder)
            let leftElbow = p(.leftElbow)
            let rightElbow = p(.rightElbow)
            let leftWrist = p(.leftWrist)
            let rightWrist = p(.rightWrist)

            let leftHip = p(.leftHip)
            let rightHip = p(.rightHip)
            let leftKnee = p(.leftKnee)
            let rightKnee = p(.rightKnee)
            let leftAnkle = p(.leftAnkle)
            let rightAnkle = p(.rightAnkle)

            let path = UIBezierPath()

            // Head/face (optional lines)
            if let n = nose, let le = leftEye { path.move(to: n); path.addLine(to: le) }
            if let n = nose, let re = rightEye { path.move(to: n); path.addLine(to: re) }
            if let le = leftEye, let leStrap = leftEar { path.move(to: le); path.addLine(to: leStrap) }
            if let re = rightEye, let reStrap = rightEar { path.move(to: re); path.addLine(to: reStrap) }

            // Torso (shoulders & hips)
            if let ls = leftShoulder, let rs = rightShoulder { path.move(to: ls); path.addLine(to: rs) }
            if let lh = leftHip, let rh = rightHip { path.move(to: lh); path.addLine(to: rh) }
            if let ls = leftShoulder, let lh = leftHip { path.move(to: ls); path.addLine(to: lh) }
            if let rs = rightShoulder, let rh = rightHip { path.move(to: rs); path.addLine(to: rh) }

            // Arms
            if let ls = leftShoulder, let le = leftElbow { path.move(to: ls); path.addLine(to: le) }
            if let le = leftElbow, let lw = leftWrist { path.move(to: le); path.addLine(to: lw) }

            if let rs = rightShoulder, let re = rightElbow { path.move(to: rs); path.addLine(to: re) }
            if let re = rightElbow, let rw = rightWrist { path.move(to: re); path.addLine(to: rw) }

            // Legs
            if let lh = leftHip, let lk = leftKnee { path.move(to: lh); path.addLine(to: lk) }
            if let lk = leftKnee, let la = leftAnkle { path.move(to: lk); path.addLine(to: la) }

            if let rh = rightHip, let rk = rightKnee { path.move(to: rh); path.addLine(to: rk) }
            if let rk = rightKnee, let ra = rightAnkle { path.move(to: rk); path.addLine(to: ra) }

            // Commit drawing
            DispatchQueue.main.async {
                self.bboxLayer.path = path.cgPath
            }
        }

        // Convert Vision normalized point to layer coordinates using previewLayer,
        // which accounts for rotation, mirroring, and aspect-fill cropping.
        private func convert(_ rp: VNRecognizedPoint, in previewLayer: AVCaptureVideoPreviewLayer) -> CGPoint? {
            // Vision gives normalized coords in a Cartesian space, origin bottom-left.
            // AVCapture expects "device" normalized with origin top-left.
            let deviceNorm = CGPoint(x: CGFloat(rp.x), y: CGFloat(rp.y))
            return previewLayer.layerPointConverted(fromCaptureDevicePoint: deviceNorm)
        }


        // Map AVCapture orientation to Vision orientation, considering mirroring
        private func vnOrientation(for vo: AVCaptureVideoOrientation, mirrored: Bool) -> CGImagePropertyOrientation {
            switch vo {
            case .portrait:           return mirrored ? .leftMirrored  : .right
            case .portraitUpsideDown: return mirrored ? .rightMirrored : .left
            case .landscapeRight:     return mirrored ? .downMirrored  : .up
            case .landscapeLeft:      return mirrored ? .upMirrored    : .down
            @unknown default:         return .right
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
