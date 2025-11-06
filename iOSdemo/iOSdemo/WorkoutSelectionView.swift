import SwiftUI

struct WorkoutSelectionView: View {
    @State private var selectedWorkout: WorkoutType?
    @State private var navigateToModeSelection = false

    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // Title section
                VStack(spacing: 8) {
                    Text("Choose Your Workout")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Select an exercise to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                // Horizontal scrolling workout cards
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(WorkoutType.allCases) { workout in
                                WorkoutCard(workout: workout)
                                    .id(workout.id)
                                    .onTapGesture {
                                        selectedWorkout = workout
                                        navigateToModeSelection = true
                                    }
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 20)
                    }
                }
                .frame(height: 320)

                Spacer()

                // Instructions
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "hand.tap.fill")
                            .foregroundColor(.blue)
                        Text("Tap a workout to continue")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "arrow.left.and.right")
                            .foregroundColor(.blue)
                        Text("Swipe to see all exercises")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 40)
            }

            // Navigation link (hidden)
            NavigationLink(
                destination: Group {
                    if let workout = selectedWorkout {
                        ModeSelectionView(workout: workout)
                    } else {
                        EmptyView()
                    }
                },
                isActive: $navigateToModeSelection
            ) {
                EmptyView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Workout Card Component

struct WorkoutCard: View {
    let workout: WorkoutType

    var body: some View {
        VStack(spacing: 16) {
            // Workout image/thumbnail
            if let uiImage = UIImage(named: workout.imageName) {
                // Use actual workout image if available
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            } else {
                // Fallback to SF Symbol with gradient if image not found
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
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
                        .frame(width: 200, height: 200)

                    VStack(spacing: 12) {
                        Image(systemName: workout.systemImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.white)

                        Text("Add Image")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            }

            // Workout name
            Text(workout.rawValue)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            // Description
            Text(workout.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 200)
        }
        .frame(width: 220, height: 300)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

#if DEBUG
struct WorkoutSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WorkoutSelectionView()
        }
    }
}

struct WorkoutCard_Previews: PreviewProvider {
    static var previews: some View {
        WorkoutCard(workout: .squats)
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
#endif
