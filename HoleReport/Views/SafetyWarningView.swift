import SwiftUI

struct SafetyWarningView: View {
    var onAccept: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Warning icon
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.15))
                        .frame(width: 110, height: 110)
                    Circle()
                        .strokeBorder(Color.yellow.opacity(0.5), lineWidth: 2)
                        .frame(width: 110, height: 110)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundColor(.yellow)
                }
                .scaleEffect(appeared ? 1.0 : 0.6)
                .opacity(appeared ? 1.0 : 0)
                .padding(.bottom, 28)

                // Title
                Text(loc("Safety Warning"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(appeared ? 1.0 : 0)
                    .padding(.bottom, 20)

                // Warning items
                VStack(alignment: .leading, spacing: 14) {
                    WarningRow(icon: "car.fill",
                               text: loc("Do not use this app while driving"))
                    WarningRow(icon: "eye.slash.fill",
                               text: loc("Keep your eyes on the road at all times"))
                    WarningRow(icon: "figure.stand",
                               text: loc("Use AR measurement mode only when stationary"))
                    WarningRow(icon: "iphone.slash",
                               text: loc("Mount your phone safely before starting the Drive tab"))
                }
                .padding(.horizontal, 32)
                .opacity(appeared ? 1.0 : 0)

                Spacer()

                // Disclaimer
                Text(loc("This app is for road documentation purposes only. The developer is not responsible for accidents caused by improper use."))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                    .opacity(appeared ? 1.0 : 0)

                // Accept button
                Button(action: onAccept) {
                    Text(loc("I Understand — Continue"))
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.yellow, in: Capsule())
                        .padding(.horizontal, 32)
                }
                .opacity(appeared ? 1.0 : 0)
                .padding(.bottom, 52)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }
}

private struct WarningRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.yellow)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.88))
        }
    }
}
