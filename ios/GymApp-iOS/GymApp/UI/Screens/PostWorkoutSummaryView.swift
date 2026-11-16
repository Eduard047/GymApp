import SwiftUI

struct PostWorkoutRewardDelta: Equatable {
    let completedMissions: [MissionSnapshot]
    let unlockedBadges: [BadgeSnapshot]

    static let empty = PostWorkoutRewardDelta(completedMissions: [], unlockedBadges: [])
}

struct PostWorkoutAttribution {
    let current: WorkoutSessionSummary
    let sessionsThroughCurrent: [WorkoutSessionSummary]
    let previousSessions: [WorkoutSessionSummary]
    let afterSnapshot: GamificationSnapshot
    /// Level before this workout's XP; with `afterSnapshot` it drives the level-up pill.
    let previousLevel: Int
    let weeklyStreakWeeks: Int
    let rewards: PostWorkoutRewardDelta
}

/// The "Level up! N → M" pill's content: non-nil only when the workout raised the level.
func postWorkoutLevelUp(previousLevel: Int, currentLevel: Int) -> (from: Int, to: Int)? {
    currentLevel > previousLevel ? (from: previousLevel, to: currentLevel) : nil
}

private func isPostWorkoutEarlier(
    candidateDate: Date,
    candidateID: UUID,
    currentDate: Date,
    currentID: UUID
) -> Bool {
    if candidateDate != currentDate {
        return candidateDate < currentDate
    }
    return candidateID.uuidString < currentID.uuidString
}

func postWorkoutAttribution(
    sessions: [WorkoutSessionSummary],
    workoutID: UUID,
    targetTrainingDays: Int,
    calendar: Calendar
) -> PostWorkoutAttribution? {
    guard let current = sessions.first(where: { $0.workoutID == workoutID }) else {
        return nil
    }

    let isEarlierThanCurrent: (WorkoutSessionSummary) -> Bool = { candidate in
        isPostWorkoutEarlier(
            candidateDate: candidate.date,
            candidateID: candidate.workoutID,
            currentDate: current.date,
            currentID: current.workoutID
        )
    }
    let sessionsThroughCurrent = sessions
        .filter { $0.workoutID == workoutID || isEarlierThanCurrent($0) }
        .sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.workoutID.uuidString < $1.workoutID.uuidString
        }
    let previousSessions = sessionsThroughCurrent.filter(isEarlierThanCurrent)

    let after = GamificationEngine.buildSnapshot(
        sessions: sessionsThroughCurrent,
        targetTrainingDays: targetTrainingDays,
        now: current.date,
        calendar: calendar
    )
    let before = GamificationEngine.buildSnapshot(
        sessions: previousSessions,
        targetTrainingDays: targetTrainingDays,
        now: current.date,
        calendar: calendar
    )
    let completedMissionIDsBefore = Set(
        before.missions.all.lazy.filter(\.completed).map(\.id)
    )
    let unlockedBadgeIDsBefore = Set(before.unlockedBadges.lazy.map(\.id))
    let rewards = PostWorkoutRewardDelta(
        completedMissions: after.missions.all.filter {
            $0.completed && !completedMissionIDsBefore.contains($0.id)
        },
        unlockedBadges: after.unlockedBadges.filter {
            !unlockedBadgeIDsBefore.contains($0.id)
        }
    )

    return PostWorkoutAttribution(
        current: current,
        sessionsThroughCurrent: sessionsThroughCurrent,
        previousSessions: previousSessions,
        afterSnapshot: after,
        previousLevel: before.progression.level,
        weeklyStreakWeeks: WeeklyStreakCalculator.current(
            sessions: sessionsThroughCurrent,
            targetTrainingDays: targetTrainingDays,
            now: current.date,
            calendar: calendar
        ),
        rewards: rewards
    )
}

func postWorkoutRewardDelta(
    sessions: [WorkoutSessionSummary],
    workoutID: UUID,
    targetTrainingDays: Int,
    calendar: Calendar
) -> PostWorkoutRewardDelta {
    postWorkoutAttribution(
        sessions: sessions,
        workoutID: workoutID,
        targetTrainingDays: targetTrainingDays,
        calendar: calendar
    )?.rewards ?? .empty
}

func postWorkoutPreviousHistory(
    _ history: [ExerciseHistoryEntry],
    current: WorkoutSessionSummary
) -> [ExerciseHistoryEntry] {
    history.filter { entry in
        isPostWorkoutEarlier(
            candidateDate: entry.sessionDate,
            candidateID: entry.workoutID,
            currentDate: current.date,
            currentID: current.workoutID
        )
    }
}

/// The hero chip for the finished workout, or nil when it is not the biggest (shared/biggest-workout-v1.json).
/// Earlier workouts use the same ordering as the rest of the summary (date, then stored id).
func biggestWorkoutBadge(
    summaries: [WorkoutSessionSummary],
    workoutID: UUID,
    calendar: Calendar
) -> BiggestWorkoutBadge? {
    guard let current = summaries.first(where: { $0.workoutID == workoutID }) else { return nil }
    let earlier = summaries
        .filter {
            isPostWorkoutEarlier(
                candidateDate: $0.date,
                candidateID: $0.workoutID,
                currentDate: current.date,
                currentID: current.workoutID
            )
        }
        .map { BiggestWorkoutSession(date: $0.date, volume: $0.totalVolume) }
    return GymBiggestWorkout.badge(
        earlier: earlier,
        current: BiggestWorkoutSession(date: current.date, volume: current.totalVolume),
        calendar: calendar
    )
}

/// One resolved row of the "Compared with last time" card (title in the app language).
struct SummaryVsLastRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let status: VsLastStatus
    let basis: VsLastBasis?
    let delta: Double?
    let best: VsLastSet
    let previousBest: VsLastSet?
}

/// The comparison with the previous workout is shown only when this workout is comparable with it:
/// at least 80% of the previous workout's logged sets (shared/vs-last-comparable-v1.json, the same
/// cases Android runs). With no previous workout, or an unfinished one, it is hidden entirely, so an
/// incomplete session never shows a large negative change.
func postWorkoutComparisonIsShown(currentSetCount: Int, previousSetCount: Int) -> Bool {
    previousSetCount > 0 && currentSetCount * 100 >= previousSetCount * 80
}

/// Logged sets (reps > 0) of a workout, from the exercise history.
func postWorkoutLoggedSetCount(history: [ExerciseHistoryEntry], workoutID: UUID) -> Int {
    history.lazy.filter { $0.workoutID == workoutID && $0.reps > 0 }.count
}

/// Logged set count of the latest earlier workout that shares at least one exercise with the
/// finished one (the workout the comparison is measured against); 0 when there is none.
func postWorkoutPreviousSetCount(
    history: [ExerciseHistoryEntry],
    workoutID: UUID,
    currentDate: Date
) -> Int {
    let currentExercises = Set(history.lazy.filter { $0.workoutID == workoutID }.map(\.exerciseID))
    guard !currentExercises.isEmpty else { return 0 }
    var latest: (date: Date, id: UUID)?
    for entry in history where entry.workoutID != workoutID && currentExercises.contains(entry.exerciseID) {
        guard isPostWorkoutEarlier(
            candidateDate: entry.sessionDate,
            candidateID: entry.workoutID,
            currentDate: currentDate,
            currentID: workoutID
        ) else { continue }
        if let known = latest,
           !isPostWorkoutEarlier(
               candidateDate: known.date, candidateID: known.id,
               currentDate: entry.sessionDate, currentID: entry.workoutID
           ) { continue }
        latest = (entry.sessionDate, entry.workoutID)
    }
    guard let latest else { return 0 }
    return postWorkoutLoggedSetCount(history: history, workoutID: latest.id)
}

/// One "By exercise" row: the blocks of an exercise are merged; the best set is the heaviest
/// (more reps on a tie) among the sets with reps.
struct PostWorkoutExerciseRow: Identifiable, Equatable {
    var id: UUID { exerciseID }
    let exerciseID: UUID
    let title: String
    let setCount: Int
    let best: VsLastSet?
}

func postWorkoutExerciseRows(
    blocks: [WorkoutExercise],
    title: (UUID) -> String?
) -> [PostWorkoutExerciseRow] {
    var order: [UUID] = []
    var setsByExercise: [UUID: [WorkoutSet]] = [:]
    for block in blocks where !block.sets.isEmpty {
        if setsByExercise[block.exerciseID] == nil { order.append(block.exerciseID) }
        setsByExercise[block.exerciseID, default: []].append(contentsOf: block.sets)
    }
    return order.compactMap { exerciseID in
        guard let sets = setsByExercise[exerciseID], let name = title(exerciseID) else { return nil }
        let best = sets.filter { $0.reps > 0 }.max { lhs, rhs in
            lhs.weight != rhs.weight ? lhs.weight < rhs.weight : lhs.reps < rhs.reps
        }
        return PostWorkoutExerciseRow(
            exerciseID: exerciseID,
            title: name,
            setCount: sets.count,
            best: best.map { VsLastSet(weight: $0.weight, reps: $0.reps) }
        )
    }
}

@MainActor
struct PostWorkoutSummaryView: View {
    @ObservedObject private var store: WorkoutStore
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var feedbackErrorMessage: String?
    @State private var failedFeedback: WorkoutFeedback?
    /// Computed once per history revision off the main actor, not on every body pass. Empty when
    /// the workout is not comparable with the previous one (`postWorkoutComparisonIsShown`).
    @State private var vsLastRows: [SummaryVsLastRow] = []
    /// "Biggest workout" hero chip, computed with the vs-last rows off the main actor.
    @State private var biggestBadge: BiggestWorkoutBadge?

    private let workoutID: UUID
    private let onOpenDetail: (UUID) -> Void
    private let onDone: () -> Void

    init(
        appState: AppState,
        workoutID: UUID,
        onOpenDetail: @escaping (UUID) -> Void,
        onDone: @escaping () -> Void
    ) {
        self.init(
            store: appState.workoutStore,
            workoutID: workoutID,
            onOpenDetail: onOpenDetail,
            onDone: onDone
        )
    }

    init(
        store: WorkoutStore,
        workoutID: UUID,
        onOpenDetail: @escaping (UUID) -> Void,
        onDone: @escaping () -> Void
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.workoutID = workoutID
        self.onOpenDetail = onOpenDetail
        self.onDone = onDone
    }

    var body: some View {
        let rewards = postWorkoutRewards
        let personalRecords = personalRecords
        return GymBackground {
            if let workout = store.workout(id: workoutID) {
                List {
                    Section {
                        heroSection(workout)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    Section {
                        feedbackRows
                    } header: {
                        sectionHeader(gymText("How did it feel?", "Як було?", "Как было?", languageCode: languageCode))
                    }

                    let exerciseRows = exerciseSummaryRows(workout)
                    if !exerciseRows.isEmpty {
                        Section {
                            ForEach(exerciseRows) { row in
                                exerciseRow(row).summaryRowBackground()
                            }
                        } header: {
                            sectionHeader(gymText("By exercise", "За вправами", "По упражнениям", languageCode: languageCode))
                        }
                    }

                    if !trainedMuscles.isEmpty {
                        Section {
                            ForEach(Array(trainedMuscles.prefix(8))) { item in
                                muscleRow(item).summaryRowBackground()
                            }
                        } header: {
                            sectionHeader(gymLocalized("Loaded today", languageCode: languageCode))
                        }
                    }

                    if !personalRecords.isEmpty {
                        Section {
                            ForEach(personalRecords) { record in
                                personalRecordRow(record).summaryRowBackground()
                            }
                        } header: {
                            sectionHeader(gymLocalized("New bests", languageCode: languageCode))
                        }
                    }

                    if !rewards.completedMissions.isEmpty || !rewards.unlockedBadges.isEmpty {
                        Section {
                            ForEach(rewards.completedMissions) { mission in
                                missionRow(mission).summaryRowBackground()
                            }
                            ForEach(rewards.unlockedBadges) { badge in
                                badgeRow(badge).summaryRowBackground()
                            }
                        } header: {
                            sectionHeader(gymText("Achievements", "Досягнення", "Достижения", languageCode: languageCode))
                        }
                    }

                    Section {
                        detailsRow.summaryRowBackground()
                    } footer: {
                        experienceFootnote
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            } else {
                GymContentUnavailableView(
                    "Summary unavailable",
                    systemImage: "chart.bar.xaxis",
                    description: Text("The workout may have been deleted.")
                )
            }
        }
        .navigationTitle(gymText(
            "Workout summary", "Підсумок тренування", "Итог тренировки",
            languageCode: languageCode
        ))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onDone) {
                    Text(gymText("Done", "Готово", "Готово", languageCode: languageCode))
                }
            }
        }
        .task(id: store.derivedDataRevision) { await refreshVsLast() }
    }

    private var postWorkoutExperience: PostWorkoutAttribution? {
        let target = TrainingProfileStore().load(
            accountStorageKey: store.accountStorageKey
        ).workoutsPerWeek
        return postWorkoutAttribution(
            sessions: store.workoutSummaries,
            workoutID: workoutID,
            targetTrainingDays: target,
            calendar: calendar
        )
    }

    private var postWorkoutRewards: PostWorkoutRewardDelta {
        postWorkoutExperience?.rewards ?? .empty
    }

    private var languageCode: String {
        gymCurrentLanguageCode()
    }

    private var sessionSummary: WorkoutSessionSummary? {
        store.workoutSummaries.first { $0.workoutID == workoutID }
    }

    private var sessionHistory: [ExerciseHistoryEntry] {
        store.allExerciseHistory().filter { $0.workoutID == workoutID }
    }

    private var trainedMuscles: [MuscleLoad] {
        MuscleMappingEngine.muscleLoads(
            history: sessionHistory,
            mappings: store.muscleMappings
        )
        .filter { $0.load > 0 }
        .sorted { $0.load > $1.load }
    }

    /// One PR row per exercise (blocks of the same exercise are merged, like Android) under
    /// the same rules as the live record badge (`LivePersonalRecords`); see
    /// `postWorkoutPersonalRecords`.
    private var personalRecords: [PostWorkoutPersonalRecord] {
        guard let workout = store.workout(id: workoutID),
              let current = sessionSummary else { return [] }
        return postWorkoutPersonalRecords(
            blocks: workout.exercises,
            previousHistory: { exerciseID in
                postWorkoutPreviousHistory(
                    store.exerciseHistory(exerciseID: exerciseID),
                    current: current
                )
            },
            title: { exerciseID in
                store.exercise(id: exerciseID).map { gymExerciseName($0) }
            }
        )
    }

    private func exerciseSummaryRows(_ workout: WorkoutSession) -> [PostWorkoutExerciseRow] {
        postWorkoutExerciseRows(
            blocks: workout.exercises,
            title: { exerciseID in store.exercise(id: exerciseID).map { gymExerciseName($0) } }
        )
    }

    /// Compares every exercise with its previous session (shared/exercise-vs-last-v1.json), but only
    /// when this workout is comparable with the previous one (`postWorkoutComparisonIsShown`).
    private func refreshVsLast() async {
        guard let date = store.workout(id: workoutID)?.date else {
            vsLastRows = []
            biggestBadge = nil
            return
        }
        let history = store.allExerciseHistory()
        let summaries = store.workoutSummaries
        let calendar = calendar
        let id = workoutID
        let (rows, badge) = await Task.detached(priority: .userInitiated) {
            let comparable = postWorkoutComparisonIsShown(
                currentSetCount: postWorkoutLoggedSetCount(history: history, workoutID: id),
                previousSetCount: postWorkoutPreviousSetCount(history: history, workoutID: id, currentDate: date)
            )
            let rows = comparable
                ? GymExerciseVsLast.rows(history: history, workoutID: id, currentDate: date)
                : []
            return (rows, biggestWorkoutBadge(summaries: summaries, workoutID: id, calendar: calendar))
        }.value
        guard !Task.isCancelled else { return }
        biggestBadge = badge
        vsLastRows = rows.map { row in
            SummaryVsLastRow(
                id: row.exerciseID,
                title: UUID(uuidString: row.exerciseID)
                    .flatMap { store.exercise(id: $0) }
                    .map { gymExerciseName($0) } ?? "—",
                status: row.status,
                basis: row.basis,
                delta: row.delta,
                best: row.best,
                previousBest: row.previousBest
            )
        }
    }

    // MARK: Hero

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(GymTheme.textSecondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    /// Title, date and the three result numbers on the plain background: the one focal point.
    private func heroSection(_ workout: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(gymText(
                    "Workout complete",
                    "Тренування завершено",
                    "Тренировка завершена",
                    languageCode: languageCode
                ))
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                Text(gymShortDate(workout.date, calendar: calendar, languageCode: languageCode))
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.textSecondary)
            }
            heroStatsRow(workout)
            if let biggestBadge {
                biggestWorkoutPill(biggestBadge)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Volume, sets and duration in one row; at large text they stack so whole words stay readable.
    private func heroStatsRow(_ workout: WorkoutSession) -> some View {
        let layout: AnyLayout = dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            // Label baselines line up even when a long numeral is scaled down to fit its column.
            : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 12))
        let setCount = workout.setCount
        let duration = heroDuration(workout.durationSeconds ?? 0)
        let volume = max(0, workout.totalVolume.isFinite ? workout.totalVolume : 0)
        let kg = gymLocalized("kg", languageCode: languageCode)
        return layout {
            heroStat(
                value: volume.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0))),
                unit: kg,
                label: gymText("Volume", "Обсяг", "Объём", languageCode: languageCode)
            )
            heroStat(
                value: setCount.formatted(.number.locale(gymAppLocale())),
                unit: nil,
                label: gymText("Sets", "Підходи", "Подходы", languageCode: languageCode)
            )
            heroStat(
                value: duration.value,
                unit: duration.unit,
                trailing: duration.trailing,
                label: gymText("Duration", "Тривалість", "Длительность", languageCode: languageCode)
            )
        }
    }

    /// "36" + "мин", "1" + "ч", or "1" + "ч" then "5" + "мин" past the hour, the same reading as
    /// `gymCompactDuration` and Android; "—" when the duration is unknown.
    private func heroDuration(
        _ seconds: Int
    ) -> (value: String, unit: String?, trailing: (value: String, unit: String)?) {
        guard seconds > 0 else { return ("—", nil, nil) }
        let minutes = max(1, seconds / 60)
        let locale = gymAppLocale()
        let minuteUnit = gymText("min", "хв", "мин", languageCode: languageCode)
        if minutes < 60 {
            return (minutes.formatted(.number.locale(locale)), minuteUnit, nil)
        }
        let hours = (minutes / 60).formatted(.number.locale(locale))
        let hourUnit = gymText("h", "год", "ч", languageCode: languageCode)
        let remaining = minutes % 60
        guard remaining > 0 else { return (hours, hourUnit, nil) }
        return (hours, hourUnit, (remaining.formatted(.number.locale(locale)), minuteUnit))
    }

    /// Big tabular numeral with a small unit beside it, the label under it.
    private func heroStat(
        value: String,
        unit: String?,
        trailing: (value: String, unit: String)? = nil,
        label: String
    ) -> some View {
        let numeral = Text(value)
            .gymScaledFont(size: 30, weight: .semibold, design: .rounded, relativeTo: .largeTitle, monospacedDigit: true, maxScale: 1.6)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                numeral
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                        .lineLimit(1)
                        // With a second pair the numerals give way first, so units stay whole.
                        .layoutPriority(trailing == nil ? 0 : 1)
                }
                if let trailing {
                    Text(trailing.value)
                        .gymScaledFont(size: 30, weight: .semibold, design: .rounded, relativeTo: .largeTitle, monospacedDigit: true, maxScale: 1.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.leading, 2)
                    Text(trailing.unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            Text(label)
                .font(.footnote)
                .foregroundStyle(GymTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [label, value, unit, trailing?.value, trailing?.unit].compactMap { $0 }.joined(separator: " ")
        )
    }

    /// Flat tonal capsule with a trophy, matching Android's `biggest_workout_*` InfoPill.
    private func biggestWorkoutPill(_ badge: BiggestWorkoutBadge) -> some View {
        let title = switch badge {
        case .ever:
            gymText(
                "Biggest workout ever", "Найбільший обсяг за весь час", "Самый большой объём за всё время",
                languageCode: languageCode
            )
        case .month:
            gymText(
                "Biggest this month", "Найбільший обсяг цього місяця", "Самый большой объём в этом месяце",
                languageCode: languageCode
            )
        }
        return HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(GymTheme.primary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(GymTheme.primary.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    // MARK: Feedback

    private var feedbackSelection: Binding<WorkoutFeedback?> {
        Binding(
            get: { store.feedback(for: workoutID) },
            set: { if let feedback = $0 { saveFeedback(feedback) } }
        )
    }

    @ViewBuilder
    private var feedbackRows: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Segments no longer fit at accessibility sizes: one checkmark row per answer.
            ForEach(WorkoutFeedback.allCases) { feedback in
                let selected = store.feedback(for: workoutID) == feedback
                Button {
                    saveFeedback(feedback)
                } label: {
                    HStack(spacing: 12) {
                        Text(feedbackTitle(feedback))
                            .foregroundStyle(GymTheme.textPrimary)
                        Spacer(minLength: 8)
                        if selected {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(GymTheme.primary)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .summaryRowBackground()
            }
        } else {
            Picker(
                gymText("How did it feel?", "Як було?", "Как было?", languageCode: languageCode),
                selection: feedbackSelection
            ) {
                ForEach(WorkoutFeedback.allCases) { feedback in
                    Text(feedbackTitle(feedback)).tag(Optional(feedback))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .summaryRowBackground()
        }

        if let feedbackErrorMessage, let failedFeedback {
            VStack(alignment: .leading, spacing: 10) {
                GymStatusBanner(message: feedbackErrorMessage, isError: true)
                Button {
                    saveFeedback(failedFeedback)
                } label: {
                    Label(
                        gymText(
                            "Try again",
                            "Спробувати ще раз",
                            "Попробовать ещё раз",
                            languageCode: languageCode
                        ),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(GymSecondaryButtonStyle())
            }
            .summaryRowBackground()
        }
    }

    private func saveFeedback(_ feedback: WorkoutFeedback) {
        do {
            try store.setWorkoutFeedback(feedback, for: workoutID)
            feedbackErrorMessage = nil
            failedFeedback = nil
        } catch {
            feedbackErrorMessage = gymErrorMessage(error, languageCode: languageCode)
            failedFeedback = feedback
        }
    }

    private func feedbackTitle(_ feedback: WorkoutFeedback) -> String {
        switch feedback {
        case .easy:
            gymText("Easy", "Легко", "Легко", languageCode: languageCode)
        case .normal:
            gymText("Right", "Нормально", "Нормально", languageCode: languageCode)
        case .hard:
            gymText("Hard", "Важко", "Тяжело", languageCode: languageCode)
        }
    }

    // MARK: Rows

    /// "+20 kg" / "−3 reps" (true minus, no-break space before the unit); nil for "new" and "same".
    private func vsLastDeltaText(_ row: SummaryVsLastRow) -> String? {
        guard row.status == .up || row.status == .down, let delta = row.delta else { return nil }
        let sign = delta > 0 ? "+" : "\u{2212}"
        let magnitude = abs(delta)
        if row.basis == .reps {
            let count = Int(magnitude.rounded()).formatted(.number.locale(gymAppLocale()))
            return sign + vsLastRepsText(count)
        }
        return sign + gymVolumeText(magnitude, languageCode: languageCode)
    }

    private func vsLastRepsText(_ count: String) -> String {
        gymText(
            "\(count)\u{00A0}reps",
            "\(count)\u{00A0}повт.",
            "\(count)\u{00A0}повт.",
            languageCode: languageCode
        )
    }

    private func vsLastSetText(_ set: VsLastSet) -> String {
        guard set.weight > 0 else {
            return vsLastRepsText(set.reps.formatted(.number.locale(gymAppLocale())))
        }
        let weight = set.weight.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0 ... 2)))
        return "\(weight) × \(set.reps.formatted(.number.locale(gymAppLocale())))"
    }

    /// Green only for a real improvement; a lower value stays neutral, never red.
    private func vsLastStatusColor(_ status: VsLastStatus) -> Color {
        status == .up ? GymTheme.secondary : GymTheme.textSecondary
    }

    private var vsLastByExercise: [UUID: SummaryVsLastRow] {
        Dictionary(
            vsLastRows.compactMap { row in UUID(uuidString: row.id).map { ($0, row) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func recordDetail(_ record: PostWorkoutPersonalRecord) -> String {
        var parts: [String] = []
        if let weight = record.weight {
            parts.append(
                gymText(
                    "\(formattedRecordValue(weight)) kg",
                    "\(formattedRecordValue(weight)) кг",
                    "\(formattedRecordValue(weight)) кг",
                    languageCode: languageCode
                )
            )
        }
        if let oneRepMax = record.estimatedOneRepMax {
            parts.append(
                gymText(
                    "Est. 1RM \(formattedRecordValue(oneRepMax)) kg",
                    "Розрах. 1ПМ \(formattedRecordValue(oneRepMax)) кг",
                    "1ПМ \(formattedRecordValue(oneRepMax)) кг",
                    languageCode: languageCode
                )
            )
        }
        return parts.joined(separator: " · ")
    }

    private func formattedRecordValue(_ value: Double) -> String {
        value.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0 ... 1)))
    }

    private func personalRecordRow(_ record: PostWorkoutPersonalRecord) -> some View {
        HStack(alignment: .center, spacing: 11) {
            if let exercise = store.exercise(id: record.exerciseID) {
                ExerciseMediaButton(
                    rawExerciseName: exercise.name,
                    catalogKey: exercise.catalogKey,
                    exerciseID: exercise.id,
                    ownerKey: store.accountStorageKey,
                    editable: false,
                    width: 40,
                    height: 40,
                    playOverlayDiameter: 18
                )
            } else {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(GymTheme.record)
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(recordDetail(record))
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Bench press / 3 sets · 60 × 8" with the change against last time on the right: green for an
    /// improvement, neutral for a decrease, nothing when the comparison is hidden or unchanged.
    private func exerciseRow(_ row: PostWorkoutExerciseRow) -> some View {
        let sets = "\(row.setCount) " + gymPlural(
            row.setCount,
            en: ("set", "sets"),
            uk: ("підхід", "підходи", "підходів"),
            ru: ("подход", "подхода", "подходов"),
            languageCode: languageCode
        )
        let detail = row.best.map { "\(sets)\u{00A0}· \(vsLastSetText($0))" } ?? sets
        let comparison = vsLastByExercise[row.exerciseID]
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(GymTheme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let comparison, let delta = vsLastDeltaText(comparison) {
                Text(delta)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(vsLastStatusColor(comparison.status))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }

    private func muscleRow(_ item: MuscleLoad) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(muscleTitle(item))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(item.load.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(GymTheme.textSecondary)
            }
            ProgressView(value: item.load, total: max(1, trainedMuscles.first?.load ?? 1))
                .tint(GymTheme.primary)
        }
        .accessibilityElement(children: .combine)
    }

    private func muscleTitle(_ load: MuscleLoad) -> String {
        guard let definition = MuscleMappingEngine.muscleDefinitions.first(where: { $0.id == load.muscleID }) else {
            return load.muscleID
        }
        return gymText(definition.titleEn, definition.titleUk, definition.titleRu, languageCode: gymCurrentLanguageCode())
    }

    private func missionRow(_ mission: MissionSnapshot) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(GymTheme.secondary)
                .accessibilityHidden(true)
            Text(mission.title.resolved(languageCode: languageCode))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(missionValue(mission.progress)) / \(missionValue(mission.target))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(GymTheme.textSecondary)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }

    private func badgeRow(_ badge: BadgeSnapshot) -> some View {
        HStack(spacing: 11) {
            Image(systemName: AchievementIconCatalog.icon(forID: badge.id))
                .foregroundStyle(gymBadgeAccent(badge.rarity))
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(gymLocalized(badge.name))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(badge.rarity.displayName)
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }

    private func missionValue(_ value: Double) -> String {
        value.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0)))
    }

    private var detailsRow: some View {
        Button {
            onOpenDetail(workoutID)
        } label: {
            HStack {
                Text(gymText(
                    "Workout details",
                    "Деталі тренування",
                    "Детали тренировки",
                    languageCode: languageCode
                ))
                .font(.body)
                .foregroundStyle(GymTheme.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GymTheme.textSecondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "+120 XP · Level 3": the gamification result is one quiet line, not a hero card.
    private var experienceFootnote: some View {
        let xp = sessionSummary.map(GamificationEngine.xpForSession) ?? 0
        let experience = postWorkoutExperience
        let level = (experience?.afterSnapshot ?? store.gamificationSnapshot(calendar: calendar)).progression.level
        let levelUp = experience.flatMap {
            postWorkoutLevelUp(previousLevel: $0.previousLevel, currentLevel: level)
        }
        let levelText = levelUp.map { change in
            gymText(
                "New level \(change.to)",
                "Новий рівень \(change.to)",
                "Новый уровень \(change.to)",
                languageCode: languageCode
            )
        } ?? gymText("Level \(level)", "Рівень \(level)", "Уровень \(level)", languageCode: languageCode)
        return Text("+\(xp) XP · \(levelText)")
            .font(.footnote)
            .foregroundStyle(GymTheme.textSecondary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    /// The inset-grouped row fill of the summary: the app's neutral surface.
    func summaryRowBackground() -> some View {
        listRowBackground(GymTheme.surface)
    }
}

/// One "new best" row of the post-workout summary. The id is the exercise id, so it
/// is stable across renders.
struct PostWorkoutPersonalRecord: Identifiable, Equatable {
    var id: UUID { exerciseID }
    let exerciseID: UUID
    let title: String
    let weight: Double?
    let estimatedOneRepMax: Double?
}

/// Records set by one session, one row per exercise in first-appearance order: the
/// blocks of an exercise are merged, a row carries a weight only when the heaviest set
/// beat the previous best weight and an estimated 1RM only when the best estimate beat
/// the previous best estimate. An exercise without earlier history never has a record,
/// a 0 value is never a record. Mirrors Android's `buildPostWorkoutPersonalRecords`.
func postWorkoutPersonalRecords(
    blocks: [WorkoutExercise],
    previousHistory: (UUID) -> [ExerciseHistoryEntry],
    title: (UUID) -> String?
) -> [PostWorkoutPersonalRecord] {
    var order: [UUID] = []
    var setsByExercise: [UUID: [WorkoutSet]] = [:]
    for block in blocks where !block.sets.isEmpty {
        if setsByExercise[block.exerciseID] == nil { order.append(block.exerciseID) }
        setsByExercise[block.exerciseID, default: []].append(contentsOf: block.sets)
    }
    return order.compactMap { exerciseID -> PostWorkoutPersonalRecord? in
        guard let sets = setsByExercise[exerciseID], let name = title(exerciseID) else { return nil }
        let previous = previousHistory(exerciseID)
        guard let previousMaxWeight = previous.map(\.weight).max(),
              let previousEstimatedMax = previous.map(\.estimatedOneRepMax).max() else {
            return nil
        }

        var weightRecord: Double?
        if let bestWeight = sets.max(by: { $0.weight < $1.weight }),
           bestWeight.weight > previousMaxWeight, bestWeight.weight > 0 {
            weightRecord = bestWeight.weight
        }
        var oneRepMaxRecord: Double?
        if let bestEstimated = sets.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }),
           bestEstimated.estimatedOneRepMax > previousEstimatedMax + 1e-9,
           bestEstimated.estimatedOneRepMax > 0 {
            oneRepMaxRecord = bestEstimated.estimatedOneRepMax
        }

        guard weightRecord != nil || oneRepMaxRecord != nil else { return nil }
        return PostWorkoutPersonalRecord(
            exerciseID: exerciseID,
            title: name,
            weight: weightRecord,
            estimatedOneRepMax: oneRepMaxRecord
        )
    }
}

private extension BadgeRarity {
    var displayName: String {
        gymLocalized(rawValue.capitalized)
    }
}
