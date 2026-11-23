import SwiftUI

/// Horizontal pages [Pause, Dashboard]; swiping right from the dashboard pauses.
struct WorkoutPagerView: View {
    @EnvironmentObject private var model: WatchAppModel
    @State private var page = 1

    var body: some View {
        TabView(selection: $page) {
            PauseView(onResume: { page = 1 })
                .tag(0)
            DashboardView()
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear {
            if let workout = model.workout, WatchWorkoutModel.isPaused(workout) { page = 0 }
        }
        .onChange(of: page) { _, newPage in
            if newPage == 0 { model.pause() } else { model.resume() }
        }
    }
}
