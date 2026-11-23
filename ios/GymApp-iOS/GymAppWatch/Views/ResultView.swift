import SwiftUI

/// Sending… → Saved on phone (auto-closes after 2 s) | Will send when the phone is nearby (Done).
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scenePadding(.horizontal)
    }
}
