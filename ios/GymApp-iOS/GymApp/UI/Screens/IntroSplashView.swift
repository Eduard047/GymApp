import SwiftUI

/// Branded launch overlay matching the short Android in-app intro animation.
///
/// The brand mark stays fixed at the exact point the system launch screen
/// (`UILaunchScreen` in Info.plist, `BrandMark` / `LaunchBackground` in
/// Assets.xcassets) already renders it at — same image, same ~120pt size,
/// same centered position, same canvas color — so the handoff from launch
/// screen to this view shows no jump. Nothing added below the icon ever
/// moves it: the title/tagline and the spinner are anchored independently,
/// below a fixed gap from the icon's position.
public struct IntroSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textVisible = false
    @State private var spinnerVisible = false

    private let iconSize: CGFloat = 120
    private let iconToTextGap: CGFloat = GymTheme.Spacing.xLarge

    public init() {}

    public var body: some View {
        GymBackground {
            GeometryReader { proxy in
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

                ZStack(alignment: .top) {
                    // Matches the system launch screen's icon exactly: same
                    // image, same size, same point. It never animates or
                    // moves, so there is nothing to jump.
                    GymBrandMark(size: iconSize)
                        .position(center)

                    VStack(spacing: 8) {
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
                        .opacity(textVisible || reduceMotion ? 1 : 0)

                        if spinnerVisible {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(GymTheme.primary)
                                .accessibilityLabel("Preparing your session")
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: 440)
                    // Anchored a fixed gap below the icon's own position, not
                    // below its layout box, so the icon above never shifts.
                    .padding(.top, center.y + iconSize / 2 + iconToTextGap)
                    .accessibilityElement(children: .contain)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
        .task {
            if reduceMotion {
                textVisible = true
            } else {
                withAnimation(.easeOut(duration: 0.25)) {
                    textVisible = true
                }
            }

            // Only show the spinner if the splash is still on screen ~1s
            // later; a quick launch never shows it at all. `.task` cancels
            // this sleep the moment the view disappears.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            if reduceMotion {
                spinnerVisible = true
            } else {
                withAnimation(.easeOut(duration: 0.25)) {
                    spinnerVisible = true
                }
            }
        }
    }
}
