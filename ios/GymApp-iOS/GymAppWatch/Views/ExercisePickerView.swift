import SwiftUI

/// Plan (plan order, done/total) then All exercises (synced catalog, alphabetical).
struct ExercisePickerView: View {
    @EnvironmentObject private var model: WatchAppModel
    let onSelect: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !progress.isEmpty {
                    Section(model.text(.sectionPlan)) {
                        ForEach(progress, id: \.name) { item in
                            Button { onSelect(item.name) } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(item.name).lineLimit(3)
                                    Spacer(minLength: 4)
                                    Text(verbatim: "\(item.done)/\(item.total)")
                                        .monospacedDigit()
                                        .foregroundStyle(WatchTheme.textSecondary)
                                }
                            }
                            .listRowBackground(item.name == model.workout?.exerciseName ? WatchTheme.accentTonal : WatchTheme.surface)
                            .id("plan-" + item.name)
                        }
                    }
                }
                if !catalog.isEmpty {
                    Section(model.text(.sectionAll)) {
                        ForEach(catalog, id: \.self) { name in
                            Button { onSelect(name) } label: { Text(name).lineLimit(3) }
                                .listRowBackground(name == model.workout?.exerciseName ? WatchTheme.accentTonal : WatchTheme.surface)
                        }
                    }
                }
                if progress.isEmpty && catalog.isEmpty {
                    Text(model.text(.noExercises))
                        .font(.footnote)
                        .foregroundStyle(WatchTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .onAppear {
                // The first row needs no scroll; scrolling to it hides the section header under the bar.
                if let workout = model.workout, let first = WatchWorkoutModel.firstUnfinishedPlanExercise(workout),
                   first != workout.plan.first?.name {
                    proxy.scrollTo("plan-" + first, anchor: .top)
                }
            }
        }
        .navigationTitle(model.text(.exercise))
    }

    private var progress: [WatchPlanProgress] {
        model.workout.map(WatchWorkoutModel.planProgress) ?? []
    }

    private var catalog: [String] {
        let locale = Locale(identifier: model.language)
        return Array(Set(model.bound?.exercises ?? [])).sorted {
            $0.compare($1, options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending
        }
    }
}
