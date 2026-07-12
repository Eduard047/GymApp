import SwiftUI

/// Branded launch overlay matching the short Android in-app intro animation.
public struct IntroSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init() {}

    public var body: some View {
        GymBackground {
            VStack(spacing: 22) {
                GymBrandMark(size: 96)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                    .opacity(appeared || reduceMotion ? 1 : 0)

                VStack(spacing: 8) {
                    Text("GymApp")
                        .font(.largeTitle.bold())
                        .foregroundStyle(GymTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Text("Build strength with focus and consistency.")
                        .font(.headline)
                        .foregroundStyle(GymTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .offset(y: appeared || reduceMotion ? 0 : 10)
                .opacity(appeared || reduceMotion ? 1 : 0)

                ProgressView()
                    .controlSize(.regular)
                    .tint(GymTheme.primary)
                    .accessibilityLabel("Preparing your session")
            }
            .padding(32)
            .frame(maxWidth: 440)
            .accessibilityElement(children: .contain)
        }
        .task {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }
}
