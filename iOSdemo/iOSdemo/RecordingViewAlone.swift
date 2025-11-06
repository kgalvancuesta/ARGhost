import SwiftUI
import AVFoundation

struct RecordingViewAlone: View {
    let workout: WorkoutType

    @State private var cameraPosition: AVCaptureDevice.Position = .front
    @State private var showGhost: Bool = true
    @State private var isRecording: Bool = false
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer?
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Full-screen camera feed with ghost overlay
                CameraPreviewWithGhost(
                    side: max(geo.size.width, geo.size.height),
                    cameraPosition: cameraPosition,
                    showGhost: showGhost
                )
                .frame(width: geo.size.width, height: geo.size.height)
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
                            Text("Show Ghost")
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

// MARK: - Camera Preview with Ghost Toggle

struct CameraPreviewWithGhost: View {
    let side: CGFloat
    let cameraPosition: AVCaptureDevice.Position
    let showGhost: Bool

    var body: some View {
        CameraPreview(
            side: side,
            cameraPosition: cameraPosition,
            showGhost: showGhost
        )
    }
}

#if DEBUG
struct RecordingViewAlone_Previews: PreviewProvider {
    static var previews: some View {
        RecordingViewAlone(workout: .squats)
    }
}
#endif
