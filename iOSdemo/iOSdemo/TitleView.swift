import SwiftUI

struct TitleView: View {
    @State private var navigateToWorkoutSelection = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.8)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 40) {
                    Spacer()

                    // App logo/name section
                    VStack(spacing: 20) {
                        Image(systemName: "figure.run.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .foregroundColor(.white)

                        Text("ARGhost")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Perfect Your Form")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.9))
                    }

                    Spacer()

                    // Get Started button
                    NavigationLink(
                        destination: WorkoutSelectionView(),
                        isActive: $navigateToWorkoutSelection
                    ) {
                        EmptyView()
                    }

                    Button(action: {
                        navigateToWorkoutSelection = true
                    }) {
                        HStack {
                            Text("Get Started")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 60)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

#if DEBUG
struct TitleView_Previews: PreviewProvider {
    static var previews: some View {
        TitleView()
    }
}
#endif
