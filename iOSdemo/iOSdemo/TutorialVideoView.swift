import SwiftUI
import AVFoundation
import AVKit

struct TutorialVideoView: View {
    let workout: WorkoutType

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.blue.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Top bar
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    }

                    Spacer()

                    Text("\(workout.rawValue) Tutorial")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    // Spacer button to keep title centered
                    Color.clear
                        .frame(width: 34, height: 34)
                }
                .padding(.top, 40)

                VStack(spacing: 12) {
                    Text("Watch the professional demonstration video to study perfect form before recording yourself.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Video player
                ProfessionalVideoPlayer(workout: workout, isPlaying: true)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .navigationBarHidden(true)
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

                            Text("Add Resources/\(workout.videoFileName) to the app bundle")
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
        guard let videoURL = Bundle.main.url(
            forResource: workout.videoResourceName,
            withExtension: workout.videoFileExtension
        ) else {
            videoNotFound = true
            return
        }

        player = AVPlayer(url: videoURL)
        player?.isMuted = true

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
struct TutorialVideoView_Previews: PreviewProvider {
    static var previews: some View {
        TutorialVideoView(workout: .squats)
    }
}
#endif
