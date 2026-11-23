import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: WatchAppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.phase {
            case .start:
                NavigationStack {
                    #if DEBUG
                    if WatchDebugSeed.isScreen("outbox-list") { OutboxView() } else { StartView() }
                    #else
                    StartView()
                    #endif
                }
            case .workout:
                WorkoutPagerView()
            case .summary:
                NavigationStack { SummaryView() }
            case .result(let state):
                ResultView(state: state)
            }
        }
        .tint(WatchTheme.accent)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.becameActive() }
        }
    }
}
