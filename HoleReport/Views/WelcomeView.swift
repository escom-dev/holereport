import SwiftUI

struct WelcomeView: View {
    var onContinue: () -> Void

    @State private var logoScale: CGFloat = 0.7
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.09, blue: 0.15),
                         Color(red: 0.05, green: 0.12, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App icon / logo
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 140, height: 140)
                    Circle()
                        .strokeBorder(Color.yellow.opacity(0.4), lineWidth: 2)
                        .frame(width: 140, height: 140)
                    Image(systemName: "camera.metering.center.weighted")
                        .font(.system(size: 58, weight: .light))
                        .foregroundStyle(
                            LinearGradient(colors: [.white, Color.yellow.opacity(0.8)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .padding(.bottom, 32)

                // Title
                VStack(spacing: 8) {
                    Text("Hole Report")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("AR Measurements + GPS Photo Log")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
                .opacity(textOpacity)
                .padding(.bottom, 48)

                // Feature bullets
                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "ruler",
                               title: "AR Measurements",
                               detail: "Measure real-world distances with your camera")
                    FeatureRow(icon: "location.fill",
                               title: "GPS Tagging",
                               detail: "Every photo stamped with exact coordinates")
                    FeatureRow(icon: "arrow.up.to.line",
                               title: "Server Upload",
                               detail: "Sync photos to your Hole Report server")
                }
                .opacity(textOpacity)
                .padding(.horizontal, 40)
                .padding(.bottom, 52)

                Spacer()

                // Get started button
                Button(action: onContinue) {
                    HStack(spacing: 10) {
                        Text("Get Started")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow, in: Capsule())
                    .padding(.horizontal, 40)
                }
                .opacity(buttonOpacity)
                .padding(.bottom, 52)
            }
        }
        .onAppear { animate() }
    }

    private func animate() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.65).delay(0.1)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
            textOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
            buttonOpacity = 1.0
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.yellow)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }
}
