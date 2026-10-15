import SwiftUI

struct WeeklyReviewCard: View {
    @ObservedObject var store: WorkoutStore
    @State private var offset = 0
    @State private var evidence: WeeklyReview.Insight?
    @State private var showsWeeklyTargetEditor = false
    private func t(_ en: String, _ uk: String, _ ru: String) -> String {
        gymText(en, uk, ru, languageCode: gymCurrentLanguageCode())
    }
    private func trainingProfileBinding(current: TrainingProfile) -> Binding<TrainingProfile> {
        Binding(
            get: { current },
            set: { newValue in
                TrainingProfileStore().save(newValue, accountStorageKey: store.accountStorageKey)
            }
        )
    }
    var body: some View {
        let review = WeeklyReview.build(store.allExerciseHistory(), offset: offset)
        let trainingProfile = TrainingProfileStore().load(accountStorageKey: store.accountStorageKey)
        let target = trainingProfile.workoutsPerWeek
        let targetNoun = gymPlural(
            target,
            en: ("workout", "workouts"),
            uk: ("тренування", "тренувань", "тренувань"),
            ru: ("тренировки", "тренировок", "тренировок")
        )
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(t("Weekly review", "Підсумок тижня", "Итог недели")).font(.title3.bold())
                HStack {
                    Button { offset = max(-520, offset - 1) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel(t("Previous week", "Попередній тиждень", "Предыдущая неделя"))
                    Spacer()
                    Text(gymFormattedDateRange(from: review.start, to: review.end)).font(.caption)
                    Spacer()
                    Button { offset = min(0, offset + 1) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }
                        .disabled(offset == 0).accessibilityLabel(t("Next week", "Наступний тиждень", "Следующая неделя"))
                }
                if review.partial { Text(t("Week in progress", "Тиждень триває", "Неделя ещё идёт")).font(.caption).foregroundStyle(GymTheme.textSecondary) }
                Text(t(
                    "\(review.trainingDays) of \(target) \(targetNoun)",
                    "\(review.trainingDays) з \(target) \(targetNoun)",
                    "\(review.trainingDays) из \(target) \(targetNoun)"
                )).font(.headline)
                Button {
                    showsWeeklyTargetEditor = true
                } label: {
                    Text(t("Training settings", "Налаштування тренувань", "Настройки тренировок") + " · " + t("edit", "змінити", "изменить"))
                        .font(.caption)
                        .foregroundStyle(GymTheme.primary)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                ForEach(review.insights) { insight in
                    Button { evidence = insight } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(gymExerciseName(insight.current.exerciseName)).font(.headline)
                            Text("\(gymWeightText(insight.current.weight)) · \(insight.previous.reps) → \(insight.current.reps) " + gymPlural(
                                insight.current.reps,
                                en: ("rep", "reps"),
                                uk: ("повтор", "повтори", "повторів"),
                                ru: ("повторение", "повторения", "повторений")
                            ))
                        }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }.buttonStyle(GymSecondaryButtonStyle())
                }
                if review.insights.isEmpty {
                    Text(review.comparableCount == 0
                         ? t(
                             "Comparison with previous weeks appears after a couple of weeks of training.",
                             "Порівняння з минулими тижнями з'явиться після кількох тижнів тренувань.",
                             "Сравнение с прошлыми неделями появится после пары недель тренировок."
                           )
                         : t("Best reps at matching weights are unchanged.", "Найкращі повтори з тією самою вагою не змінилися.", "Лучшие повторы с тем же весом не изменились."))
                        .font(.subheadline).foregroundStyle(GymTheme.textSecondary)
                }
                DisclosureGroup(t("Workouts this week", "Тренування цього тижня", "Тренировки этой недели")) {
                    ForEach(review.sessions, id: \.workoutID) { entry in
                        NavigationLink { WorkoutDetailView(store: store, workoutID: entry.workoutID) } label: {
                            Text(gymShortDateTime(entry.sessionDate)).frame(minHeight: 44)
                        }
                    }
                }
            }
        }
#if DEBUG
        .task {
            // UI-audit: presents the target editor / first evidence sheet. Nothing is saved.
            guard let route = UIAuditRouter.shared.consume(anyOf: [.weeklyTargetEditor, .weeklyEvidence]) else { return }
            try? await Task.sleep(for: .milliseconds(700))
            switch route {
            case .weeklyTargetEditor:
                showsWeeklyTargetEditor = true
            case .weeklyEvidence:
                // Newest week (looking back up to 12 weeks) that has a comparison to show.
                let history = store.allExerciseHistory()
                for candidate in 0...12 {
                    let week = WeeklyReview.build(history, offset: -candidate)
                    if let first = week.insights.first {
                        offset = -candidate
                        evidence = first
                        return
                    }
                }
                UIAuditLaunch.log("weekly-evidence: no week in the last 12 has comparison insights")
            default:
                break
            }
        }
#endif
        .sheet(isPresented: $showsWeeklyTargetEditor) {
            TrainingSettingsSheet(
                profile: trainingProfileBinding(current: trainingProfile),
                scrollToWorkoutsPerWeek: true
            )
        }
        .sheet(item: $evidence) { insight in
            NavigationStack {
                List([insight.previous, insight.current], id: \.setID) { entry in
                    NavigationLink { WorkoutDetailView(store: store, workoutID: entry.workoutID) } label: {
                        VStack(alignment: .leading) {
                            Text(gymShortDate(entry.sessionDate))
                            Text("\(entry.weight.formatted(.number.locale(gymAppLocale()))) \(t("kg", "кг", "кг")) × \(entry.reps)")
                        }
                    }
                }.navigationTitle(t("Comparison", "Порівняння", "Сравнение"))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("Done", "Готово", "Готово")) { evidence = nil } } }
            }
            .gymSheetPresentation()
        }
    }
}
