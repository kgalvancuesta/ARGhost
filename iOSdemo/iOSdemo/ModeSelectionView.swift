import SwiftUI

struct ModeSelectionView: View {
    let workout: WorkoutType

    @State private var selectedMode: WorkoutMode?
    @State private var navigateToRecording = false

    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // Workout info header
                VStack(spacing: 16) {
                    // Workout icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.blue.opacity(0.7),
                                        Color.purple.opacity(0.7)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)

                        Image(systemName: workout.systemImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                    }
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)

                    Text(workout.rawValue)
                        .font(.title)
                        .fontWeight(.bold)
                }
                .padding(.top, 40)

                // Mode selection title
                VStack(spacing: 8) {
                    Text("Choose Your Mode")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("How would you like to train?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                // Mode buttons
                VStack(spacing: 20) {
                    ModeButton(mode: .alone) {
                        selectedMode = .alone
                        navigateToRecording = true
                    }

                    ModeButton(mode: .tutorial) {
                        selectedMode = .tutorial
                        navigateToRecording = true
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }

            // Navigation links (hidden)
            NavigationLink(
                destination: Group {
                    if let mode = selectedMode {
                        if mode == .alone {
                            RecordingViewAlone(workout: workout)
                        } else {
                            TutorialVideoView(workout: workout)
                        }
                    } else {
                        EmptyView()
                    }
                },
                isActive: $navigateToRecording
            ) {
                EmptyView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Mode Button Component

struct ModeButton: View {
    let mode: WorkoutMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                // Icon
                Image(systemName: mode.systemImageName)
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                    .frame(width: 60)

                // Text content
                VStack(alignment: .leading, spacing: 6) {
                    Text(mode.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(mode.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Arrow indicator
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 110)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#if DEBUG
struct ModeSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ModeSelectionView(workout: .squats)
        }
    }
}

struct ModeButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ModeButton(mode: .alone) { }
            ModeButton(mode: .tutorial) { }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
