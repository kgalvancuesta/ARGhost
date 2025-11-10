import SwiftUI
import AVFoundation
import AVKit

struct RecordingViewPartner: View {
    let workout: WorkoutType

    @State private var cameraPosition: AVCaptureDevice.Position = .front
    @State private var showGhost: Bool = true
    @State private var isRecording: Bool = false
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var videoLoadingError: Bool = false
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        GeometryReader { geo in
            let halfHeight = geo.size.height / 2

            ZStack {
                // Split-screen layout (vertical stacking)
                VStack(spacing: 0) {
                    // Top: Live camera feed
                    ZStack {
                        CameraPreview(
                            side: max(geo.size.width, halfHeight),
                            cameraPosition: cameraPosition
                        )
                        .frame(width: geo.size.width, height: halfHeight)

                        // Label overlay
                        VStack {
                            Text("You")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(12)
                                .padding(.top, 60)

                            Spacer()
                        }
                    }

                    // Divider line
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 2)

                    // Bottom: Professional video
                    ZStack {
                        ProfessionalVideoPlayer(workout: workout, isPlaying: isRecording)
                            .frame(width: geo.size.width, height: halfHeight)

                        // Label overlay
                        VStack {
                            Text("Professional")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(12)
                                .padding(.top, 60)

                            Spacer()
                        }

                        // Error state
                        if videoLoadingError {
                            VStack(spacing: 16) {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white.opacity(0.7))

                                Text("Video Coming Soon")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                Text("Professional video not available")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(20)
                        }
                    }
                }
                .ignoresSafeArea()

                // Top controls overlay
                VStack {
                    HStack {
                        // Back button
                        Button(action: {
                            stopRecording()
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.4))
                                        .frame(width: 40, height: 40)
                                )
                        }
                        .padding(.leading, 20)

                        Spacer()

                        // Workout name
                        Text(workout.rawValue)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(20)

                        Spacer()

                        // Camera flip button
                        Button(action: {
                            cameraPosition = (cameraPosition == .front) ? .back : .front
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                )
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.top, 50)

                    Spacer()

                    // Bottom controls
                    VStack(spacing: 20) {
                        // Timer (only shown when recording)
                        if isRecording {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)

                                Text(formatTime(recordingTime))
                                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(25)
                        }

                        // Ghost toggle
                        HStack {
                            Text("Show Ghost Overlay")
                                .font(.headline)
                                .foregroundColor(.white)

                            Toggle("", isOn: $showGhost)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(30)

                        // Record/Stop button
                        Button(action: {
                            if isRecording {
                                stopRecording()
                            } else {
                                startRecording()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: 80, height: 80)

                                Circle()
                                    .fill(isRecording ? Color.red : Color.red)
                                    .frame(width: 60, height: 60)

                                if isRecording {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white)
                                        .frame(width: 24, height: 24)
                                }
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Recording Controls

    private func startRecording() {
        isRecording = true
        recordingTime = 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
        }
    }

    private func stopRecording() {
        isRecording = false
        timer?.invalidate()
        timer = nil
        recordingTime = 0
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let deciseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, deciseconds)
    }
}

// MARK: - Professional Video Player

struct ProfessionalVideoPlayer: View {
    let workout: WorkoutType
    let isPlaying: Bool

    @State private var player: AVPlayer?
    @State private var videoNotFound: Bool = false

    var body: some View {
        ZStack {
            Color.black

            if let player = player, !videoNotFound {
                VideoPlayer(player: player)
                    .disabled(true) // Disable user controls
                    .onAppear {
                        if isPlaying {
                            player.play()
                        }
                    }
                    .onChange(of: isPlaying) { playing in
                        if playing {
                            player.seek(to: .zero)
                            player.play()
                        } else {
                            player.pause()
                        }
                    }
            } else {
                // Placeholder when video is not available
                VStack(spacing: 20) {
                    Image(systemName: workout.systemImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.white.opacity(0.5))

                    if videoNotFound {
                        VStack(spacing: 8) {
                            Text("Video Not Available")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))

                            Text("Add \(workout.videoFileName) to Resources")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
            }
        }
        .onAppear {
            loadVideo()
        }
    }

    private func loadVideo() {
        // Try to load video from bundle
        guard let videoURL = Bundle.main.url(forResource: workout.videoFileName.replacingOccurrences(of: ".mp4", with: ""), withExtension: "mp4") else {
            videoNotFound = true
            return
        }

        player = AVPlayer(url: videoURL)

        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            if isPlaying {
                player?.play()
            }
        }
    }
}

#if DEBUG
struct RecordingViewPartner_Previews: PreviewProvider {
    static var previews: some View {
        RecordingViewPartner(workout: .squats)
    }
}
#endif
