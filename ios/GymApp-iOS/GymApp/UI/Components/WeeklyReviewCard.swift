import SwiftUI

/// Memo key for the weekly review: store revision, week offset and the calendar day
/// (so a card left open across midnight still moves on).
struct WeeklyReviewMemoKey: Equatable {
    let revision: UInt64
    let accountStorageKey: String
    let offset: Int
    let day: Date
}

struct WeeklyReviewCard: View {
    @ObservedObject var store: WorkoutStore
    /// Current weekly streak, shown as a row on the current week only; 0 hides it.
    var weeklyStreakWeeks = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var offset = 0
    @State private var evidence: WeeklyReview.Insight?
    @State private var showsWeeklyTargetEditor = false
    @State private var reviewMemo = ProgressMemo<WeeklyReviewMemoKey, WeeklyReview>()
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
        let reviewKey = WeeklyReviewMemoKey(
            revision: store.derivedDataRevision,
            accountStorageKey: store.accountStorageKey,
            offset: offset,
            day: Calendar.current.startOfDay(for: Date())
        )
        let review = reviewMemo.value(for: reviewKey) {
            WeeklyReview.build(store.allExerciseHistory(), offset: offset, historySortedNewestFirst: true)
        }
        let trainingProfile = TrainingProfileStore().load(accountStorageKey: store.accountStorageKey)
        let target = trainingProfile.workoutsPerWeek
        let targetNoun = gymPlural(
            target,
            en: ("workout", "workouts"),
            uk: ("тренування", "тренувань", "тренувань"),
            ru: ("тренировки", "тренировок", "тренировок")
        )
        VStack(alignment: .leading, spacing: GymTheme.contentSpacing) {
            weekHeader(review)
            heroStats(review)
            goalGroup(review, target: target, targetNoun: targetNoun)
            if !review.insights.isEmpty {
                insightsGroup(review)
            }
            if !review.sessions.isEmpty {
                sessionsGroup(review)
            }
        }
        .gymTrackedPageSwipe(canGoPrevious: offset > -520, canGoNext: offset < 0) { direction in
            switch direction {
            case .previous: offset = max(-520, offset - 1)
            case .next: offset = min(0, offset + 1)
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
                    NavigationLink { WorkoutDetailView(store: store, workoutID: entry.workoutID).gymTopBannerInset() } label: {
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

    // MARK: Sections

    private func weekHeader(_ review: WeeklyReview) -> some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(offset == 0 ? t("This week", "Цей тиждень", "Эта неделя") : t("Week", "Тиждень", "Неделя"))
                    .font(.title2.bold())
                    .foregroundStyle(GymTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(gymFormattedDateRange(from: review.start, to: review.end))
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.textSecondary)
                    .accessibilityLabel(gymSpokenDateRange(from: review.start, to: review.end))
            }
            Spacer(minLength: 8)
            Button { offset = max(-520, offset - 1) } label: {
                Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(t("Previous week", "Попередній тиждень", "Предыдущая неделя"))
            Button { offset = min(0, offset + 1) } label: {
                Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(offset == 0)
            .accessibilityLabel(t("Next week", "Наступний тиждень", "Следующая неделя"))
        }
    }

    /// Workouts, sets and volume of the week: the one focal point, units always shown.
    private func heroStats(_ review: WeeklyReview) -> some View {
        let layout: AnyLayout = dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        let volume = max(0, review.volume.isFinite ? review.volume : 0)
        return layout {
            ProgressHeroStat(
                value: review.workoutCount.formatted(.number.locale(gymAppLocale())),
                label: t("Workouts", "Тренування", "Тренировки")
            )
            ProgressHeroStat(
                value: review.setCount.formatted(.number.locale(gymAppLocale())),
                label: t("Sets", "Підходи", "Подходы")
            )
            ProgressHeroStat(
                value: volume.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0))),
                unit: t("kg", "кг", "кг"),
                label: t("Volume", "Обсяг", "Объём")
            )
        }
    }

    private func goalGroup(_ review: WeeklyReview, target: Int, targetNoun: String) -> some View {
        ProgressGroup {
            Button { showsWeeklyTargetEditor = true } label: {
                ProgressRowLabel(
                    title: t("Weekly goal", "Ціль тижня", "Цель недели"),
                    value: t(
                        "\(review.trainingDays) of \(target) \(targetNoun)",
                        "\(review.trainingDays) з \(target) \(targetNoun)",
                        "\(review.trainingDays) из \(target) \(targetNoun)"
                    )
                )
            }
            .buttonStyle(.plain)
            if offset == 0, weeklyStreakWeeks > 0 {
                ProgressRowDivider()
                ProgressRowLabel(
                    title: t("Week streak", "Серія тижнів", "Серия недель"),
                    value: t(
                        "\(weeklyStreakWeeks) wk",
                        "\(weeklyStreakWeeks) тиж",
                        "\(weeklyStreakWeeks) нед"
                    ),
                    showsChevron: false
                )
            }
        }
    }

    /// Only with data: same weight, more or fewer reps than the week before.
    private func insightsGroup(_ review: WeeklyReview) -> some View {
        ProgressGroup(title: t("Against the week before", "Порівняно з минулим тижнем", "К прошлой неделе")) {
            ForEach(Array(review.insights.enumerated()), id: \.element.id) { index, insight in
                if index > 0 { ProgressRowDivider() }
                Button { evidence = insight } label: {
                    ProgressRowLabel(
                        title: gymExerciseName(insight.current.exerciseName),
                        subtitle: "\(gymWeightText(insight.current.weight)) · \(insight.previous.reps) → \(insight.current.reps) " + gymPlural(
                            insight.current.reps,
                            en: ("rep", "reps"),
                            uk: ("повтор", "повтори", "повторів"),
                            ru: ("повторение", "повторения", "повторений")
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sessionsGroup(_ review: WeeklyReview) -> some View {
        ProgressGroup(title: offset == 0
            ? t("Workouts this week", "Тренування цього тижня", "Тренировки этой недели")
            : t("Workouts that week", "Тренування того тижня", "Тренировки той недели")) {
            ForEach(Array(review.sessions.enumerated()), id: \.element.workoutID) { index, entry in
                if index > 0 { ProgressRowDivider() }
                NavigationLink {
                    WorkoutDetailView(store: store, workoutID: entry.workoutID).gymTopBannerInset()
                } label: {
                    ProgressRowLabel(title: gymShortDateTime(entry.sessionDate))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
