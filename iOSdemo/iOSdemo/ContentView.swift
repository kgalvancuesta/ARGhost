import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var cameraPosition: AVCaptureDevice.Position = .back

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)

            ZStack {
                // Square, centered live camera feed
                CameraPreview(
                    side: side,
                    cameraPosition: cameraPosition
                )
                .frame(width: side, height: side)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Camera toggle control (front/back)
                VStack {
                    Spacer()
                    HStack {
                        Button(action: {
                            cameraPosition = (cameraPosition == .front) ? .back : .front
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: side * 0.07))
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding([.leading, .bottom], 20)

                        Spacer()
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}
