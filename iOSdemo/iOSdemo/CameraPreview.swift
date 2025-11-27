import SwiftUI
import AVFoundation
import Vision
import UIKit

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

        // Add text layer for joint error feedback - centered at bottom
        let textLayer = context.coordinator.jointErrorLayer
        let textWidth: CGFloat = previewView.bounds.width - 80
        let textHeight: CGFloat = 150
        let textX = (previewView.bounds.width - textWidth) / 2
        let textY = previewView.bounds.height - textHeight - 260  // keep clear of record button

        textLayer.frame = CGRect(x: textX, y: textY, width: textWidth, height: textHeight)
        textLayer.font = UIFont.boldSystemFont(ofSize: 0)
        textLayer.fontSize = 24
        textLayer.foregroundColor = UIColor.systemRed.cgColor
        textLayer.backgroundColor = UIColor.black.withAlphaComponent(0.8).cgColor
        textLayer.cornerRadius = 12
        textLayer.alignmentMode = .center
        textLayer.contentsScale = UIScreen.main.scale  // For sharp text
        textLayer.isWrapped = true
        textLayer.isHidden = true  // Hidden by default
        textLayer.zPosition = 2
        pl.addSublayer(textLayer)


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
        let bboxLayer = context.coordinator.bboxLayer
        bboxLayer.frame = uiView.bounds

        // keep text sized/positioned
        let textLayer = context.coordinator.jointErrorLayer
        let textWidth: CGFloat = uiView.bounds.width - 80
        let textHeight: CGFloat = 150
        let textX = (uiView.bounds.width - textWidth) / 2
        let textY = uiView.bounds.height - textHeight - 260
        textLayer.frame = CGRect(x: textX, y: textY, width: textWidth, height: textHeight)

        // 🔑 Rotate the skeleton 180° on FRONT, keep BACK unchanged
        bboxLayer.setAffineTransform(
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

        // Text layer for displaying joint errors on screen
        fileprivate let jointErrorLayer = CATextLayer()

        // Vision
        private let poseRequest = VNDetectHumanBodyPoseRequest()

        // Frame buffer (kept for future batching, not used by Vision path here)
        private var isCapturingFrames = false
        private(set) var frameBuffer: [CVPixelBuffer] = []
        private let desiredFrameCount = 4

        // MARK: - HMM Squat Classification
        private var squatModel: HMMModel?

        // Rep detection state
        private enum SquatPhase {
            case idle
            case descending  // Going down
            case bottom      // At bottom
            case ascending   // Coming back up
        }

        private var currentPhase: SquatPhase = .idle
        private var repObservations: [VNHumanBodyPoseObservation] = []
        private var repJointSequence: [[VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]] = []
        private let minRepFrames = 20  // Minimum frames for a valid rep
        private let maxRepFrames = 180  // Maximum frames (3 seconds at 60fps)

        // Track consecutive frames with missing joints to be more tolerant of temporary Vision losses
        private var consecutiveMissingJointsFrames = 0
        private let maxConsecutiveMissingFrames = 20  // Allow up to 20 frames (~0.33s at 60fps) of missing data
                                                       // Balanced tolerance for unstable tracking

        // Visual feedback
        private var isErrorHighlightActive = false

        // Audio feedback
        private var errorPlayer: AVAudioPlayer?
        private var correctPlayer: AVAudioPlayer?

        init(parent: CameraPreview) {
            self.parent = parent
            self.currentPosition = parent.cameraPosition
            super.init()
            loadHMMModel()
            setupAudio()
            setupSession()
        }

        // MARK: - HMM Model Loading

        private func loadHMMModel() {
            guard let url = Bundle.main.url(forResource: "squat_hmm_model", withExtension: "json") else {
                print("⚠️ Could not find squat_hmm_model.json in bundle")
                return
            }
            do {
                let model = try HMMModel.load(from: url)
                self.squatModel = model
                print("✅ Squat HMM model loaded successfully")
            } catch {
                print("❌ Failed to load HMMModel: \(error)")
            }
        }

        // MARK: - Audio Setup

        private func setupAudio() {
            // Configure AVAudioSession for playback over camera audio
            do {
                let audioSession = AVAudioSession.sharedInstance()
                // Use ambient category to allow sounds to play while camera is running
                // and to play even when silent switch is on
                try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try audioSession.setActive(true)
                print("✅ AVAudioSession configured for playback")
            } catch {
                print("⚠️ Failed to configure AVAudioSession: \(error)")
            }

            // Try to load error sound
            if let errorURL = Bundle.main.url(forResource: "error_squat", withExtension: "wav") {
                do {
                    errorPlayer = try AVAudioPlayer(contentsOf: errorURL)
                    errorPlayer?.volume = 1.0  // Maximum volume
                    errorPlayer?.prepareToPlay()
                    print("✅ Error sound loaded from: \(errorURL.lastPathComponent)")
                } catch {
                    print("⚠️ Could not load error_squat.wav: \(error)")
                }
            } else {
                print("⚠️ error_squat.wav not found in bundle")
            }

            // Try to load correct sound
            if let correctURL = Bundle.main.url(forResource: "correct_squat", withExtension: "wav") {
                do {
                    correctPlayer = try AVAudioPlayer(contentsOf: correctURL)
                    correctPlayer?.volume = 1.0  // Maximum volume
                    correctPlayer?.prepareToPlay()
                    print("✅ Correct sound loaded from: \(correctURL.lastPathComponent)")
                } catch {
                    print("⚠️ Could not load correct_squat.wav: \(error)")
                }
            } else {
                print("⚠️ correct_squat.wav not found in bundle")
            }
        }

        // MARK: - Rep Detection & Classification

        // Frame counter for debug output throttling
        private var frameCount = 0

        /// Processes each frame to detect and track squat reps
        /// Called from captureOutput for every frame with a valid pose detection
        private func processSquatFrame(observation: VNHumanBodyPoseObservation) {
            frameCount += 1

            // DEBUG: Only process if we have the model loaded
            guard squatModel != nil else {
                if frameCount % 60 == 0 { // Log once per second at 60fps
                    print("⚠️ Squat model not loaded, skipping frame \(frameCount)")
                }
                return
            }

            // DEBUG: Get recognized points
            guard let points = try? observation.recognizedPoints(.all) else {
                if frameCount % 60 == 0 {
                    print("⚠️ Could not get recognized points, frame \(frameCount)")
                }
                return
            }

            // DEBUG: Check if we can extract squat features (all required joints present)
            guard SquatFeatureExtractor.featureVector(from: points) != nil else {
                // Missing required joints - increment counter
                consecutiveMissingJointsFrames += 1

                // Only reset if we've been missing joints for too many consecutive frames
                if currentPhase != .idle && consecutiveMissingJointsFrames > maxConsecutiveMissingFrames {
                    print("⚠️ Missing required joints for \(consecutiveMissingJointsFrames) consecutive frames, resetting from \(currentPhase)")
                    resetRep()
                    consecutiveMissingJointsFrames = 0
                } else if frameCount % 60 == 0 {
                    print("⚠️ Cannot extract features (missing joints), frame \(frameCount) - consecutive: \(consecutiveMissingJointsFrames)")
                }
                return
            }

            // Reset missing joints counter when we successfully get features
            if consecutiveMissingJointsFrames > 0 {
                if consecutiveMissingJointsFrames > 3 {
                    print("✅ Joints recovered after \(consecutiveMissingJointsFrames) missing frames")
                }
                consecutiveMissingJointsFrames = 0
            }

            // Calculate body positions to determine squat depth
            // Vision Y coordinates: 0 = bottom of image, 1 = top
            // Higher Y value = higher body position (closer to top of screen)
            let kneeY = averageKneeHeight(points: points)
            let ankleY = averageAnkleHeight(points: points)
            let hipY = averageHipHeight(points: points)

            // CORRECT squat depth metric: hip-ankle distance
            // When STANDING: hips are far above ankles (large distance)
            // When SQUATTING: hips are closer to ankles (small distance)
            let hipAnkleDist = abs(hipY - ankleY)

            // Also track hip-knee for reference
            let hipKneeDist = abs(hipY - kneeY)

            // DEBUG: Log squat metrics every 30 frames (twice per second at 60fps)
            if frameCount % 30 == 0 {
                print("🔍 Frame \(frameCount) - Phase: \(currentPhase), HipY: \(String(format: "%.3f", hipY)), AnkleY: \(String(format: "%.3f", ankleY)), HipAnkleDist: \(String(format: "%.3f", hipAnkleDist)), KneeY: \(String(format: "%.3f", kneeY)), BufferSize: \(repObservations.count)")
            }

            // Add to buffer BEFORE state checks (we want continuous tracking)
            repObservations.append(observation)
            repJointSequence.append(points)

            // Limit buffer size
            if repObservations.count > maxRepFrames {
                repObservations.removeFirst()
                repJointSequence.removeFirst()
            }

            // State machine for rep detection based on hip-ankle distance
            // STANDING: hip is far from ankles (person is upright)
            // SQUATTING: hip is close to ankles (person is low)
            // Thresholds calibrated from real data (typical range: 0.003-0.033):
            let isSquatting = hipAnkleDist < 0.012  // Hips very close to ankles = squatting
            let isStanding = hipAnkleDist > 0.022   // Hips farther from ankles = standing
            // Note: There's a "transition zone" (0.012-0.022) where neither flag is true

            let previousPhase = currentPhase

            switch currentPhase {
            case .idle:
                // Waiting for someone to start squatting
                if isSquatting {
                    currentPhase = .descending
                    repObservations = [observation]
                    repJointSequence = [points]
                    print("🟢 REP START: Detected squat descent (hipAnkleDist: \(String(format: "%.3f", hipAnkleDist)))")
                }

            case .descending:
                // Going down into squat
                if isSquatting {
                    // Reached bottom position
                    currentPhase = .bottom
                    if previousPhase != currentPhase {
                        print("🔵 REP BOTTOM: Reached squat depth (hipAnkleDist: \(String(format: "%.3f", hipAnkleDist)), frames: \(repObservations.count))")
                    }
                } else if isStanding {
                    // Stood back up without reaching bottom - invalid rep
                    print("❌ REP ABORTED: Stood up before reaching depth (hipAnkleDist: \(String(format: "%.3f", hipAnkleDist)), frames: \(repObservations.count))")
                    resetRep()
                }
                // else: in transition, keep accumulating

            case .bottom:
                // At the bottom of squat, waiting for ascent
                if isStanding {
                    // Started ascending
                    currentPhase = .ascending
                    print("🟡 REP ASCENDING: Starting to stand up (hipAnkleDist: \(String(format: "%.3f", hipAnkleDist)), frames: \(repObservations.count))")
                }
                // else: still at bottom or transitioning

            case .ascending:
                // Coming back up from squat
                if isSquatting {
                    // Went back down - might be starting another rep or just bobbing
                    currentPhase = .bottom
                    print("⚪️ REP RESUMED BOTTOM: Went back down (hipAnkleDist: \(String(format: "%.3f", hipAnkleDist)))")
                } else if isStanding && repObservations.count >= minRepFrames {
                    // Completed ascent with enough frames - CLASSIFY!
                    print("✅ REP COMPLETE: Standing up complete, classifying \(repObservations.count) frames (min: \(minRepFrames))")
                    classifyCompletedRep()
                    resetRep()
                } else if isStanding {
                    // Completed but not enough frames
                    print("⚠️ REP TOO SHORT: Only \(repObservations.count) frames (min: \(minRepFrames)), discarding")
                    resetRep()
                }
                // else: in transition, keep accumulating
            }
        }

        /// Calculate average knee Y position from left and right knees
        /// Vision Y coordinates: 0 = bottom of screen, 1 = top
        private func averageKneeHeight(points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> CGFloat {
            var sum: CGFloat = 0
            var count: CGFloat = 0
            if let lk = points[.leftKnee], lk.confidence > 0.3 {
                sum += CGFloat(lk.y)
                count += 1
            }
            if let rk = points[.rightKnee], rk.confidence > 0.3 {
                sum += CGFloat(rk.y)
                count += 1
            }
            return count > 0 ? sum / count : 0.5
        }

        /// Calculate average ankle Y position from left and right ankles
        private func averageAnkleHeight(points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> CGFloat {
            var sum: CGFloat = 0
            var count: CGFloat = 0
            if let la = points[.leftAnkle], la.confidence > 0.3 {
                sum += CGFloat(la.y)
                count += 1
            }
            if let ra = points[.rightAnkle], ra.confidence > 0.3 {
                sum += CGFloat(ra.y)
                count += 1
            }
            return count > 0 ? sum / count : 0.5
        }

        /// Calculate average hip Y position from left and right hips
        private func averageHipHeight(points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> CGFloat {
            var sum: CGFloat = 0
            var count: CGFloat = 0
            if let lh = points[.leftHip], lh.confidence > 0.3 {
                sum += CGFloat(lh.y)
                count += 1
            }
            if let rh = points[.rightHip], rh.confidence > 0.3 {
                sum += CGFloat(rh.y)
                count += 1
            }
            return count > 0 ? sum / count : 0.5
        }

        /// Classify a completed rep using the HMM model and provide feedback
        /// This is the main classification pipeline:
        /// 1. Run HMM Viterbi algorithm on the buffered pose sequence
        /// 2. Check if log-likelihood is within acceptable range (isCorrect)
        /// 3. Provide visual feedback (red skeleton) and audio feedback
        /// 4. Log detailed results including joint-level errors
        private func classifyCompletedRep() {
            guard let model = squatModel else {
                print("❌ Cannot classify: model is nil")
                return
            }

            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🔬 CLASSIFYING REP with \(repJointSequence.count) frames...")

            // Run HMM classification on the pose sequence
            let result = model.classify(poseSequence: repJointSequence)

            print("📊 Rep classified: \(result.isCorrect ? "✅ CORRECT" : "❌ INCORRECT")")
            print("   Log-likelihood: \(String(format: "%.2f", result.logLike))")
            print("   Viterbi states: \(result.states.prefix(10))...\(result.states.suffix(5)) (total: \(result.states.count) frames)")
            print("   Model mean: \(String(format: "%.2f", model.meanLogLikelihood)), std: \(String(format: "%.2f", model.stdLogLikelihood))")

            let zScore = (result.logLike - model.meanLogLikelihood) / model.stdLogLikelihood
            print("   Z-score: \(String(format: "%.2f", zScore)) (threshold: -\(model.thresholdSigma)σ)")

            if result.isCorrect {
                // ✅ CORRECT SQUAT - play success sound
                print("   🎉 Good form! Playing success sound...")
                DispatchQueue.main.async {
                    if let player = self.correctPlayer {
                        // Ensure sound plays at full volume
                        player.volume = 1.0
                        player.currentTime = 0  // Reset to start
                        let didPlay = player.play()
                        print("   🔊 Success sound \(didPlay ? "PLAYING" : "FAILED") (player: \(player))")
                    } else {
                        print("   ⚠️ correctPlayer is nil! Cannot play success sound.")
                    }
                }
            } else {
                // ❌ INCORRECT SQUAT - show visual and audio feedback
                print("   ⚠️ Form issues detected! Showing error feedback...")

                DispatchQueue.main.async {
                    // Set error highlight (skeleton turns red)
                    self.isErrorHighlightActive = true
                    print("   🔴 Error highlight activated")

                    let errorText = """
                    ⚠️ Focus On ⚠️

                    Left Knee Alignment
                    """
                    self.jointErrorLayer.string = errorText
                    self.jointErrorLayer.isHidden = false
                    print("   📱 Displaying fixed left knee guidance")

                    // Play error sound
                    if let player = self.errorPlayer {
                        // Ensure sound plays at full volume
                        player.volume = 1.0
                        player.currentTime = 0  // Reset to start
                        let didPlay = player.play()
                        print("   🔊 Error sound \(didPlay ? "PLAYING" : "FAILED") (player: \(player))")
                    } else {
                        print("   ⚠️ errorPlayer is nil! Cannot play error sound.")
                    }

                    // Clear error highlight and text after 1 second
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.isErrorHighlightActive = false
                        self.jointErrorLayer.isHidden = true
                        print("   ✅ Error highlight and joint errors cleared")
                    }
                }

                // Log problematic joints for debugging
                print("   Showing left knee guidance for demo mode.")
            }
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        }

        /// Reset rep tracking state machine back to idle
        private func resetRep() {
            print("🔄 Resetting rep tracker (was in \(currentPhase), had \(repObservations.count) frames)")
            currentPhase = .idle
            repObservations.removeAll()
            repJointSequence.removeAll()
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
                self.switchCamera(to: self.currentPosition) {
                    self.session.startRunning()
                }
            }
        }

        func switchCamera(to position: AVCaptureDevice.Position, completion: (() -> Void)? = nil) {
            // Avoid redundant switches
            if position == currentPosition && !session.inputs.isEmpty {
                completion?()
                return
            }

            sessionQueue.async { [weak self] in
                guard let self = self else { return }

                var shouldRunCompletion = false

                self.session.beginConfiguration()
                defer {
                    self.session.commitConfiguration()
                    if shouldRunCompletion {
                        completion?()
                    }
                }

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
                shouldRunCompletion = true

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

            let isMirrored = self.previewLayer?.connection?.isVideoMirrored ?? false
            // Vision pose request (lightweight and fast)
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: self.vnOrientation(for: connection.videoOrientation, mirrored: isMirrored)
            )

            do {
                try handler.perform([poseRequest])

                // Clear overlay if ghost is disabled
                if !showGhost {
                    DispatchQueue.main.async { self.bboxLayer.path = nil }
                    return
                }

                guard let observations = poseRequest.results as? [VNHumanBodyPoseObservation], !observations.isEmpty else {
                    // Clear overlay when no pose is found
                    DispatchQueue.main.async { self.bboxLayer.path = nil }
                    return
                }

                // Use first pose (extend to multiple if you like)
                if let first = observations.first {
                    // Process for squat rep detection and classification
                    self.processSquatFrame(observation: first)
                    // Draw the skeleton
                    self.drawPose(observation: first)
                }
            } catch {
                // Don't spam logs; skip frame on errors
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

            // Commit drawing with color based on error state
            // This is where the visual feedback happens:
            // - Green skeleton = normal state or correct rep
            // - Red skeleton = incorrect rep detected (for 1 second)
            // The isErrorHighlightActive flag is set in classifyCompletedRep()
            DispatchQueue.main.async {
                self.bboxLayer.path = path.cgPath
                // Set color based on error highlight state
                self.bboxLayer.strokeColor = self.isErrorHighlightActive
                    ? UIColor.systemRed.cgColor
                    : UIColor.systemGreen.cgColor
            }
        }

        // Convert Vision normalized point to layer coordinates using previewLayer,
        // which accounts for rotation, mirroring, and aspect-fill cropping.
        private func convert(_ rp: VNRecognizedPoint, in previewLayer: AVCaptureVideoPreviewLayer) -> CGPoint? {
            // Vision gives normalized coords in a Cartesian space, origin bottom-left.
            // AVCapture expects "device" normalized with origin top-left.
            
            let deviceNorm = CGPoint(x: CGFloat(rp.x), y: 1.0 - CGFloat(rp.y))
            return previewLayer.layerPointConverted(fromCaptureDevicePoint: deviceNorm)
        }


        // Map AVCapture orientation to Vision orientation, considering mirroring
        private func vnOrientation(for vo: AVCaptureVideoOrientation, mirrored _: Bool) -> CGImagePropertyOrientation {
            switch vo {
            case .portrait:           return .right
            case .portraitUpsideDown: return .left
            case .landscapeRight:     return .up
            case .landscapeLeft:      return .down
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
