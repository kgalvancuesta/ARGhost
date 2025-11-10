import SwiftUI
import AVFoundation
import MLKitPoseDetection
import MLKitVision

struct CameraPreview: UIViewRepresentable {
    typealias UIViewType = PreviewView

    let side: CGFloat
    let cameraPosition: AVCaptureDevice.Position
    var showGhost: Bool = true

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
        if cameraPosition == .front {
            context.coordinator.bboxLayer.setAffineTransform(CGAffineTransform(rotationAngle: .pi))
        } else {
            context.coordinator.bboxLayer.setAffineTransform(.identity)
        }


        context.coordinator.previewLayer = pl
        if let c = pl.connection {
            if c.isVideoOrientationSupported { c.videoOrientation = .portrait }
            c.isVideoMirrored = false
        }

        return previewView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.switchCamera(to: cameraPosition)
        context.coordinator.showGhost = showGhost

        // keep overlay sized
        let layer = context.coordinator.bboxLayer
        layer.frame = uiView.bounds

        // 🔑 Rotate the skeleton 180° on FRONT, keep BACK unchanged
        layer.setAffineTransform(
            cameraPosition == .front
            ? CGAffineTransform(rotationAngle: .pi)
            : .identity
        )
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
        var showGhost: Bool = true

        // MLKit Pose Detector with accurate mode for better tracking
        private lazy var poseDetector: PoseDetector = {
            let options = PoseDetectorOptions()
            options.detectorMode = .stream  // Optimized for video streaming
            return PoseDetector.poseDetector(options: options)
        }()

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
                        connection.isVideoMirrored = (position == .front)
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

            // Clear overlay if ghost is disabled
            if !showGhost {
                DispatchQueue.main.async { self.bboxLayer.path = nil }
                return
            }

            // Create MLKit VisionImage
            let visionImage = VisionImage(buffer: sampleBuffer)
            visionImage.orientation = imageOrientation(
                deviceOrientation: .portrait,
                cameraPosition: currentPosition
            )

            // Detect poses using MLKit
            var poses: [Pose] = []
            do {
                poses = try poseDetector.results(in: visionImage)
            } catch {
                // Skip frame on error
                DispatchQueue.main.async { self.bboxLayer.path = nil }
                return
            }

            // Clear overlay if no pose detected
            guard let pose = poses.first else {
                DispatchQueue.main.async { self.bboxLayer.path = nil }
                return
            }

            // Draw the detected pose
            drawMLKitPose(pose: pose)
        }

        // MARK: - Drawing MLKit Pose

        private func drawMLKitPose(pose: Pose) {
            guard let pl = self.previewLayer else { return }
            let layerBounds = pl.bounds

            // Helper to get landmark point if confidence is good
            func getLandmark(_ type: PoseLandmarkType) -> CGPoint? {
                let landmark = pose.landmark(ofType: type)
                guard landmark.inFrameLikelihood > 0.5 else { return nil }
                return convertMLKitPoint(landmark.position, in: layerBounds)
            }

            // Get all landmarks (MLKit provides 33 points for detailed tracking)
            let nose = getLandmark(.nose)
            let leftEyeInner = getLandmark(.leftEyeInner)
            let leftEye = getLandmark(.leftEye)
            let leftEyeOuter = getLandmark(.leftEyeOuter)
            let rightEyeInner = getLandmark(.rightEyeInner)
            let rightEye = getLandmark(.rightEye)
            let rightEyeOuter = getLandmark(.rightEyeOuter)
            let leftEar = getLandmark(.leftEar)
            let rightEar = getLandmark(.rightEar)
            let mouthLeft = getLandmark(.mouthLeft)
            let mouthRight = getLandmark(.mouthRight)

            let leftShoulder = getLandmark(.leftShoulder)
            let rightShoulder = getLandmark(.rightShoulder)
            let leftElbow = getLandmark(.leftElbow)
            let rightElbow = getLandmark(.rightElbow)
            let leftWrist = getLandmark(.leftWrist)
            let rightWrist = getLandmark(.rightWrist)
            let leftThumb = getLandmark(.leftThumb)
            let rightThumb = getLandmark(.rightThumb)

            let leftHip = getLandmark(.leftHip)
            let rightHip = getLandmark(.rightHip)
            let leftKnee = getLandmark(.leftKnee)
            let rightKnee = getLandmark(.rightKnee)
            let leftAnkle = getLandmark(.leftAnkle)
            let rightAnkle = getLandmark(.rightAnkle)
            let leftHeel = getLandmark(.leftHeel)
            let rightHeel = getLandmark(.rightHeel)

            let path = UIBezierPath()

            // Helper to draw line between two points
            func drawLine(from: CGPoint?, to: CGPoint?) {
                guard let from = from, let to = to else { return }
                path.move(to: from)
                path.addLine(to: to)
            }

            // Face structure (more detailed)
            drawLine(from: nose, to: leftEyeInner)
            drawLine(from: leftEyeInner, to: leftEye)
            drawLine(from: leftEye, to: leftEyeOuter)
            drawLine(from: leftEyeOuter, to: leftEar)

            drawLine(from: nose, to: rightEyeInner)
            drawLine(from: rightEyeInner, to: rightEye)
            drawLine(from: rightEye, to: rightEyeOuter)
            drawLine(from: rightEyeOuter, to: rightEar)

            drawLine(from: nose, to: mouthLeft)
            drawLine(from: nose, to: mouthRight)
            drawLine(from: mouthLeft, to: mouthRight)

            // Torso (shoulders & hips)
            drawLine(from: leftShoulder, to: rightShoulder)
            drawLine(from: leftHip, to: rightHip)
            drawLine(from: leftShoulder, to: leftHip)
            drawLine(from: rightShoulder, to: rightHip)

            // Left arm (including hand details)
            drawLine(from: leftShoulder, to: leftElbow)
            drawLine(from: leftElbow, to: leftWrist)
            drawLine(from: leftWrist, to: leftThumb)

            // Right arm (including hand details)
            drawLine(from: rightShoulder, to: rightElbow)
            drawLine(from: rightElbow, to: rightWrist)
            drawLine(from: rightWrist, to: rightThumb)

            // Left leg (including foot details)
            drawLine(from: leftHip, to: leftKnee)
            drawLine(from: leftKnee, to: leftAnkle)
            drawLine(from: leftAnkle, to: leftHeel)

            // Right leg (including foot details)
            drawLine(from: rightHip, to: rightKnee)
            drawLine(from: rightKnee, to: rightAnkle)
            drawLine(from: rightAnkle, to: rightHeel)

            // Commit drawing on main thread
            DispatchQueue.main.async {
                self.bboxLayer.path = path.cgPath
            }
        }

        // Convert MLKit 3D point to 2D screen coordinates
        private func convertMLKitPoint(_ position: Vision3DPoint, in bounds: CGRect) -> CGPoint {
            // MLKit returns points in image coordinates
            // We need to convert to preview layer coordinates
            let x = CGFloat(position.x)
            let y = CGFloat(position.y)

            // Transform based on camera position (mirror for front camera)
            if currentPosition == .front {
                return CGPoint(x: bounds.width - x, y: y)
            } else {
                return CGPoint(x: x, y: y)
            }
        }

        // Get image orientation for MLKit based on device and camera position
        private func imageOrientation(
            deviceOrientation: UIDeviceOrientation,
            cameraPosition: AVCaptureDevice.Position
        ) -> UIImage.Orientation {
            switch deviceOrientation {
            case .portrait:
                return cameraPosition == .front ? .leftMirrored : .right
            case .landscapeLeft:
                return cameraPosition == .front ? .downMirrored : .up
            case .portraitUpsideDown:
                return cameraPosition == .front ? .rightMirrored : .left
            case .landscapeRight:
                return cameraPosition == .front ? .upMirrored : .down
            default:
                return cameraPosition == .front ? .leftMirrored : .right
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
