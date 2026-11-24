import SwiftUI

/// Sending… → Saved on iPhone (auto-closes after 2 s) | Will send when your iPhone is nearby (Done)
/// | iPhone did not accept this workout (Done; the item stays in Unsent).
struct ResultView: View {
    @EnvironmentObject private var model: WatchAppModel
    let state: WatchResultState

    var body: some View {
        VStack(spacing: 8) {
            switch state {
            case .sending:
                ProgressView()
                Text(model.text(.sending))
                    .font(.headline)
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(WatchTheme.success)
                    .accessibilityHidden(true)
                Text(model.text(.savedPhone))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        model.closeResult()
                    }
            case .deferred:
                Image(systemName: "iphone.slash")
                    .font(.system(size: 34))
                    .foregroundStyle(WatchTheme.warning)
                    .accessibilityHidden(true)
                Text(model.text(.sendLater))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(model.text(.done)) { model.closeResult() }
                    .buttonStyle(PrimaryButtonStyle())
            case .failed:
                // Rejected for good: not "later". The workout stays in Unsent until discarded.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(WatchTheme.destructive)
                    .accessibilityHidden(true)
                Text(model.text(.notAccepted))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Button(model.text(.done)) { model.closeResult() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scenePadding(.horizontal)
    }
}
