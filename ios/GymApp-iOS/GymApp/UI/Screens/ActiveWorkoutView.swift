import Foundation
import SwiftUI

enum ActiveWorkoutRestReconciliationOutcome: Equatable {
    case synchronized
    case restStoppedBecauseTimerUnavailable
    case timerCleanupPending
}

struct ActiveWorkoutActionStatus: Equatable {
    let message: String
    let isError: Bool
}

func activeWorkoutActionStatus(
    liveQueueFailure: String?,
    restProjectionWarning: String?,
    success: String
) -> ActiveWorkoutActionStatus {
    if let liveQueueFailure {
        return ActiveWorkoutActionStatus(message: liveQueueFailure, isError: true)
    }
    if let restProjectionWarning {
        return ActiveWorkoutActionStatus(message: restProjectionWarning, isError: true)
    }
    return ActiveWorkoutActionStatus(message: success, isError: false)
}

func activeWorkoutValueEditorsAreDisabled(
    isCompleted: Bool,
    hasCommitIntent: Bool,
    isLivePlanFrozen _: Bool
) -> Bool {
    // A live room freezes the shared plan structure, but each participant must
    // still be able to enter the weight and reps they actually performed.
    isCompleted || hasCommitIntent
}

func activeWorkoutStructuralActionsAreDisabled(
    hasStoredExercise: Bool,
    hasCommitIntent: Bool,
    isLivePlanFrozen: Bool
) -> Bool {
    !hasStoredExercise || hasCommitIntent || isLivePlanFrozen
}

/// The active-workout file owns the rest deadline. RestTimerManager is a
/// recoverable countdown projection, so a crash between their writes is healed
/// in this direction only and can never extend the committed rest interval.
@MainActor
enum ActiveWorkoutRestReconciler {
    static func timerID(for draftID: UUID) -> String {
        "active-workout-\(draftID.uuidString)-rest"
    }

    static func reconcile(
        draft: ActiveWorkoutDraft,
        store: ActiveWorkoutStore,
        manager: RestTimerManager,
        title: String,
        now: Date = Date()
    ) throws -> ActiveWorkoutRestReconciliationOutcome {
        let timerID = timerID(for: draft.id)
        guard let deadline = draft.timing?.restingUntil, deadline > now else {
            return manager.synchronize(id: timerID, deadline: nil, title: title)
                ? .synchronized
                : .timerCleanupPending
        }

        if manager.synchronize(id: timerID, deadline: deadline, title: title) {
            return .synchronized
        }

        // The countdown projection could not be made durable. Resume the
        // authoritative workout clock without rolling back any recorded set.
        _ = try store.endRest(
            draftID: draft.id,
            expectedRevision: draft.revision,
            now: now
        )
        return manager.synchronize(id: timerID, deadline: nil, title: title)
            ? .restStoppedBecauseTimerUnavailable
            : .timerCleanupPending
    }
}

private enum LiveParticipantSelection: String {
    case current
    case peer
}

@MainActor
struct ActiveWorkoutView: View {
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var workoutStore: WorkoutStore
    @ObservedObject private var activeWorkoutStore: ActiveWorkoutStore
    @ObservedObject private var liveWorkoutCoordinator: LiveWorkoutCoordinator
    @ObservedObject private var restTimers: RestTimerManager

    private let draftID: UUID
    private let onFinished: (UUID) -> Void
    private let onClose: () -> Void
    private let onDiscarded: () -> Void
    private let reportStatus: (String, Bool) -> Void

    @State private var adaptationRequest: WorkoutAdaptationRequest?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showingDiscardConfirmation = false
    @State private var collapsedExerciseIDs = Set<UUID>()
    @State private var expandedSetIDs = Set<UUID>()
    @FocusState private var focusedWeightSetID: UUID?
    @State private var liveParticipantSelection: LiveParticipantSelection = .current

    init(
        workoutStore: WorkoutStore,
        activeWorkoutStore: ActiveWorkoutStore,
        liveWorkoutCoordinator: LiveWorkoutCoordinator,
        restTimers: RestTimerManager,
        draftID: UUID,
        onFinished: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void,
        onDiscarded: @escaping () -> Void,
        onStatus: @escaping (String, Bool) -> Void = { _, _ in }
    ) {
        _workoutStore = ObservedObject(wrappedValue: workoutStore)
        _activeWorkoutStore = ObservedObject(wrappedValue: activeWorkoutStore)
        _liveWorkoutCoordinator = ObservedObject(wrappedValue: liveWorkoutCoordinator)
        _restTimers = ObservedObject(wrappedValue: restTimers)
        self.draftID = draftID
        self.onFinished = onFinished
        self.onClose = onClose
        self.onDiscarded = onDiscarded
        self.reportStatus = onStatus
    }

    var body: some View {
        GymBackground {
            if let draft = currentDraft {
                ScrollView {
                    LazyVStack(spacing: GymTheme.contentSpacing) {
                        if liveWorkoutCoordinator.isAttachedToCurrentDraft {
                            liveParticipantTabs
                        }

                        if !liveWorkoutCoordinator.isAttachedToCurrentDraft ||
                            liveParticipantSelection == .current {
                            progressPanel(draft)

                            if let statusMessage {
                                GymStatusBanner(message: statusMessage, isError: statusIsError)
                            }

                            ForEach(draft.exercises) { exercise in
                                exercisePanel(exercise, draft: draft)
                            }

                            finishPanel(draft)
                        } else {
                            livePeerProgressPanel(draft)
                            if let snapshot = liveWorkoutCoordinator.snapshot,
                               snapshot.room.status == .active {
                                ForEach(snapshot.plan.exercises, id: \.exerciseID) { exercise in
                                    livePeerExercisePanel(exercise, snapshot: snapshot)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, GymTheme.screenHorizontalInset)
                    .padding(.top, GymTheme.screenVerticalInset)
                    .padding(.bottom, GymTheme.screenBottomInset)
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                GymContentUnavailableView {
                    Label(
                        gymText(
                            "Workout unavailable",
                            "Тренування недоступне",
                            "Тренировка недоступна",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(
                        gymText(
                            "The active workout changed or was already completed.",
                            "Активне тренування змінилося або вже завершене.",
                            "Активная тренировка изменилась или уже завершена.",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                }
            }
        }
        .sheet(item: $adaptationRequest) { request in
            WorkoutAdaptationSheet(request: request, workoutStore: workoutStore, activeStore: activeWorkoutStore,
                coordinator: liveWorkoutCoordinator)
        }
        .navigationTitle(
            gymText(
                "Workout",
                "Тренування",
                "Тренировка",
                languageCode: gymCurrentLanguageCode()
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(
                    gymText(
                        "Minimize",
                        "Згорнути",
                        "Свернуть",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    action: onClose
                )
                .accessibilityHint(
                    gymText(
                        "Minimizes the screen; the workout keeps running and all changes are already saved",
                        "Згортає екран; тренування продовжує йти, усі зміни вже збережено",
                        "Сворачивает экран; тренировка продолжает идти, все изменения уже сохранены",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
            if !liveWorkoutCoordinator.isAttachedToCurrentDraft {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if let draft = currentDraft,
                           !liveWorkoutCoordinator.planIsFrozenForCurrentDraft,
                           draft.commitIntent == nil,
                           draft.exercises.contains(where: { $0.sets.contains(where: { !$0.isCompleted }) }) {
                            Menu {
                                ForEach(["equipmentUnavailable", "timeCut", "tooHard"], id: \.self) { reason in
                                    Button(WorkoutAdaptationRequest.title(reason)) {
                                        adaptationRequest = WorkoutAdaptationRequest(source: draft, reason: reason, store: workoutStore)
                                    }
                                }
                            } label: {
                                Label(
                                    gymText(
                                        "Adapt workout",
                                        "Адаптувати тренування",
                                        "Адаптировать тренировку",
                                        languageCode: gymCurrentLanguageCode()
                                    ),
                                    systemImage: "slider.horizontal.3"
                                )
                            }
                        }
                        Button(role: .destructive) {
                            showingDiscardConfirmation = true
                        } label: {
                            Label(
                                gymText(
                                    "Discard",
                                    "Відкинути",
                                    "Удалить",
                                    languageCode: gymCurrentLanguageCode()
                                ),
                                systemImage: "trash"
                            )
                        }
                        .disabled(currentDraft?.commitIntent != nil)
                    } label: {
                        Label(
                            gymText(
                                "More workout options",
                                "Інші дії",
                                "Другие действия",
                                languageCode: gymCurrentLanguageCode()
                            ),
                            systemImage: "ellipsis.circle"
                        )
                    }
                    .accessibilityLabel(
                        gymText(
                            "More workout options",
                            "Інші дії",
                            "Другие действия",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                }
            }
        }
        .interactiveDismissDisabled(false)
        .alert(
            gymText(
                "Discard active workout?",
                "Відкинути активне тренування?",
                "Удалить активную тренировку?",
                languageCode: gymCurrentLanguageCode()
            ),
            isPresented: $showingDiscardConfirmation
        ) {
            Button(
                gymText(
                    "Discard",
                    "Відкинути",
                    "Удалить",
                    languageCode: gymCurrentLanguageCode()
                ),
                role: .destructive,
                action: discard
            )
            Button(
                gymText(
                    "Cancel",
                    "Скасувати",
                    "Отмена",
                    languageCode: gymCurrentLanguageCode()
                ),
                role: .cancel
            ) {}
        } message: {
            Text(
                gymText(
                    "Recorded and planned sets in this active draft will be removed. Saved workout history is not affected.",
                    "Записані й заплановані підходи цього чернеткового тренування буде видалено. Збережена історія не зміниться.",
                    "Записанные и запланированные подходы этого черновика будут удалены. Сохранённая история не изменится.",
                    languageCode: gymCurrentLanguageCode()
                )
            )
        }
        .onAppear {
            liveParticipantSelection = .current
            collapseCompletedExercises()
            reconcileRestProjection()
        }
        .onChange(of: liveWorkoutCoordinator.attachedRoomID) { _, roomID in
            if roomID == nil { liveParticipantSelection = .current }
        }
    }

    private var currentDraft: ActiveWorkoutDraft? {
        guard let draft = activeWorkoutStore.draft, draft.id == draftID else { return nil }
        return draft
    }

    private func progressPanel(_ draft: ActiveWorkoutDraft) -> some View {
        let exerciseName = currentExerciseDisplayName(draft)
        return GymHeroPanel(
            contentPadding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
            gradient: LinearGradient(
                colors: [GymTheme.brandFill, GymTheme.brandFillBright],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            solidFill: GymTheme.brandFill
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if draft.commitIntent != nil {
                    Text(
                        gymText(
                            "Completion is safely locked. Retry Finish to confirm history and clear this screen.",
                            "Завершення безпечно зафіксовано. Повтори завершення, щоб підтвердити історію й закрити цей екран.",
                            "Завершение безопасно зафиксировано. Повтори завершение, чтобы подтвердить историю и закрыть этот экран.",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.9))
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = draft.totalElapsedSeconds(at: context.date)
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 7, height: 7)
                                Text(
                                    gymText(
                                        "In progress",
                                        "Триває",
                                        "Идёт",
                                        languageCode: gymCurrentLanguageCode()
                                    )
                                )
                                .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Color.white.opacity(0.85))

                            Text(Self.clock(elapsed))
                                .font(.system(size: 36, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white)

                            if let exerciseName {
                                Text(
                                    gymText(
                                        "Now: \(exerciseName)",
                                        "Зараз: \(exerciseName)",
                                        "Сейчас: \(exerciseName)",
                                        languageCode: gymCurrentLanguageCode()
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.85))
                                .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)

                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.28), lineWidth: 7)
                            Circle()
                                .trim(
                                    from: 0,
                                    to: min(1, Double(draft.completedSetCount) / Double(max(1, draft.plannedSetCount)))
                                )
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 1) {
                                Text("\(draft.completedSetCount)/\(draft.plannedSetCount)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.white)
                                Text(
                                    gymText(
                                        "sets",
                                        "підх.",
                                        "подх.",
                                        languageCode: gymCurrentLanguageCode()
                                    )
                                )
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.85))
                            }
                        }
                        .frame(width: 68, height: 68)
                        .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        heroAccessibilitySummary(
                            elapsed: elapsed,
                            draft: draft,
                            exerciseName: exerciseName
                        )
                    )
                }
            }
        }
    }

    /// First exercise with at least one uncompleted set, i.e. the exercise
    /// shown in the hero card's "Now: …" caption.
    private func currentExerciseDisplayName(_ draft: ActiveWorkoutDraft) -> String? {
        guard let exercise = draft.exercises.first(where: { $0.sets.contains(where: { !$0.isCompleted }) }) else {
            return nil
        }
        guard let stored = workoutStore.exercise(id: exercise.exerciseID) else { return nil }
        return gymExerciseName(stored)
    }

    /// "Прошло 14:40, выполнено 3 из 15 подходов, сейчас жим…" — the hero
    /// card's single combined accessibility element.
    private func heroAccessibilitySummary(
        elapsed: TimeInterval,
        draft: ActiveWorkoutDraft,
        exerciseName: String?
    ) -> String {
        let clock = Self.clock(elapsed)
        let base = gymText(
            "Elapsed \(clock), \(setsProgressSummary(draft)) done",
            "Минуло \(clock), \(setsProgressSummary(draft)) виконано",
            "Прошло \(clock), выполнено \(setsProgressSummary(draft))",
            languageCode: gymCurrentLanguageCode()
        )
        guard let exerciseName else { return base }
        return base + gymText(
            ", now: \(exerciseName)",
            ", зараз: \(exerciseName)",
            ", сейчас: \(exerciseName)",
            languageCode: gymCurrentLanguageCode()
        )
    }

    /// "0 of 15 sets" / "0 з 15 підходів" / "0 из 15 подходов", pluralized
    /// against the planned total via `gymCount`.
    private func setsProgressSummary(_ draft: ActiveWorkoutDraft) -> String {
        let totalWord = gymCount(
            draft.plannedSetCount,
            englishOne: "set",
            englishMany: "sets",
            ukrainianOne: "підхід",
            ukrainianFew: "підходи",
            ukrainianMany: "підходів",
            languageCode: gymCurrentLanguageCode()
        )
        return gymText(
            "\(draft.completedSetCount) of \(totalWord)",
            "\(draft.completedSetCount) з \(totalWord)",
            "\(draft.completedSetCount) из \(totalWord)",
            languageCode: gymCurrentLanguageCode()
        )
    }

    private func livePeerPanel(_ draft: ActiveWorkoutDraft) -> some View {
        let peer = liveWorkoutCoordinator.peerProgress
        let completed = peer?.completedSets.count ?? 0
        let peerName = liveWorkoutCoordinator.peerDisplayName ?? gymText(
            "Friend",
            "Друг",
            "Друг",
            languageCode: gymCurrentLanguageCode()
        )
        let lanes = liveWorkoutCoordinator.exerciseLaneSummaries
        let lensShape = UnevenRoundedRectangle(
            topLeadingRadius: 26,
            bottomLeadingRadius: 26,
            bottomTrailingRadius: 42,
            topTrailingRadius: 54,
            style: .continuous
        )
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: GymTheme.Spacing.medium) {
                HStack(alignment: .top, spacing: GymTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: GymTheme.Spacing.xSmall) {
                        Text(
                            gymText(
                                "SPOTTER LENS",
                                "СПОТТЕР-ЛІНЗА",
                                "СПОТТЕР-ЛИНЗА",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                        .font(GymTheme.TypeScale.utility)
                        .tracking(0.55)
                        .foregroundStyle(GymTheme.primary)

                        Text(
                            gymText(
                                "Live with \(peerName)",
                                "Наживо з \(peerName)",
                                "Вживую с \(peerName)",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                        .font(GymTheme.TypeScale.heroTitle)
                        .foregroundStyle(GymTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    }

                    Spacer(minLength: GymTheme.Spacing.xSmall)

                    Image(systemName: peer?.finishedAt == nil
                        ? "wave.3.right.circle.fill"
                        : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(peer?.finishedAt == nil ? GymTheme.primary : GymTheme.secondary)
                        .accessibilityHidden(true)
                }

                spotterProgressLine(
                    label: gymText(
                        "You",
                        "Ти",
                        "Ты",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    completed: draft.completedSetCount,
                    total: draft.plannedSetCount,
                    accent: GymTheme.primary
                )
                spotterProgressLine(
                    label: peerName,
                    completed: completed,
                    total: draft.plannedSetCount,
                    accent: GymTheme.secondary
                )

                Text(
                    peer?.finishedAt == nil
                        ? gymText(
                            "Each recorded set appears in its own lane. The shared plan stays frozen for both athletes.",
                            "Кожен записаний підхід з’являється у своїй доріжці. Спільний план зафіксований для обох спортсменів.",
                            "Каждый записанный подход появляется в своей дорожке. Общий план зафиксирован для обоих спортсменов.",
                            languageCode: gymCurrentLanguageCode()
                        )
                        : gymText(
                            "Your friend finished. Your local progress remains safe until you finish too.",
                            "Друг завершив. Твій локальний прогрес залишається в безпеці, доки ти теж не завершиш.",
                            "Друг завершил. Твой локальный прогресс остаётся в безопасности, пока ты тоже не завершишь.",
                            languageCode: gymCurrentLanguageCode()
                        )
                )
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(GymTheme.Spacing.large)

            if !lanes.isEmpty {
                Divider()
                    .overlay(GymTheme.outlineSoft)

                ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                    liveExerciseLane(lane, peerName: peerName)
                    if index < lanes.count - 1 {
                        Divider()
                            .padding(.leading, GymTheme.Spacing.large)
                            .overlay(GymTheme.outlineSoft)
                    }
                }
            }
        }
        .background {
            lensShape.fill(GymTheme.surface)
            lensShape.fill(GymTheme.primary.opacity(0.025))
        }
        .overlay {
            lensShape.strokeBorder(
                GymTheme.primary.opacity(0.24),
                lineWidth: GymTheme.hairlineWidth
            )
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [GymTheme.primary, GymTheme.secondary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.leading, 5)
                .padding(.vertical, GymTheme.Spacing.large)
                .accessibilityHidden(true)
        }
        .clipShape(lensShape)
        .shadow(color: GymTheme.primary.opacity(0.1), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .contain)
    }

    private var liveParticipantTabs: some View {
        let selfName = liveWorkoutCoordinator.selfDisplayName ?? gymText(
            "You",
            "Ти",
            "Ты",
            languageCode: gymCurrentLanguageCode()
        )
        let peerName = liveWorkoutCoordinator.peerDisplayName ?? gymText(
            "Friend",
            "Друг",
            "Друг",
            languageCode: gymCurrentLanguageCode()
        )
        return Picker(
            gymText(
                "Participant",
                "Учасник",
                "Участник",
                languageCode: gymCurrentLanguageCode()
            ),
            selection: $liveParticipantSelection
        ) {
            Text(selfName).tag(LiveParticipantSelection.current)
            Text(peerName).tag(LiveParticipantSelection.peer)
        }
        .pickerStyle(.segmented)
        .accessibilityValue(
            liveParticipantSelection == .current ? selfName : peerName
        )
    }

    private func livePeerProgressPanel(_ draft: ActiveWorkoutDraft) -> some View {
        let peer = liveWorkoutCoordinator.peerProgress
        let peerName = liveWorkoutCoordinator.peerDisplayName ?? gymText(
            "Friend",
            "Друг",
            "Друг",
            languageCode: gymCurrentLanguageCode()
        )
        let completed = peer?.completedSets.count ?? 0
        return GymHeroPanel {
            VStack(alignment: .leading, spacing: GymTheme.Spacing.medium) {
                Text(peerName)
                    .font(GymTheme.TypeScale.heroTitle)
                    .foregroundStyle(.white)
                HStack(spacing: GymTheme.Spacing.small) {
                    Image(systemName: peer?.finishedAt == nil
                        ? "wave.3.right.circle.fill"
                        : "checkmark.circle.fill")
                    Text(peer?.finishedAt == nil
                        ? "\(completed) / \(draft.plannedSetCount)"
                        : gymText(
                            "Finished",
                            "Завершено",
                            "Завершено",
                            languageCode: gymCurrentLanguageCode()
                        ))
                }
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                Text(gymText(
                    "Live progress · Read only",
                    "Live-прогрес · Лише перегляд",
                    "Live-прогресс · Только просмотр",
                    languageCode: gymCurrentLanguageCode()
                ))
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.82))
            }
        }
    }

    private func livePeerExercisePanel(
        _ exercise: LiveWorkoutPlanExercise,
        snapshot: LiveWorkoutSnapshot
    ) -> some View {
        let completedByID = Dictionary(
            uniqueKeysWithValues: snapshot.peerParticipant?.progress?.completedSets.map {
                ($0.setID, $0)
            } ?? []
        )
        return GymPanel {
            VStack(alignment: .leading, spacing: GymTheme.Spacing.medium) {
                Text(BuiltInExerciseCatalog.displayName(
                    catalogKey: exercise.catalogKey,
                    rawName: exercise.name,
                    languageCode: gymCurrentLanguageCode()
                ))
                .font(.headline)
                ForEach(Array(exercise.sets.enumerated()), id: \.element.setID) { index, planned in
                    let completed = completedByID[planned.setID]
                    HStack(spacing: GymTheme.Spacing.medium) {
                        Text(gymText(
                            "Set \(index + 1)",
                            "Підхід \(index + 1)",
                            "Подход \(index + 1)",
                            languageCode: gymCurrentLanguageCode()
                        ))
                        .foregroundStyle(GymTheme.textSecondary)
                        Spacer()
                        Text(completed.map {
                            "\($0.weight.formatted(.number.precision(.fractionLength(0 ... 2)))) kg × \($0.reps)"
                        } ?? gymText(
                            "Not logged · \(planned.weight.formatted(.number.precision(.fractionLength(0 ... 2)))) kg × \(planned.reps)",
                            "Не записано · \(planned.weight.formatted(.number.precision(.fractionLength(0 ... 2)))) kg × \(planned.reps)",
                            "Не записано · \(planned.weight.formatted(.number.precision(.fractionLength(0 ... 2)))) kg × \(planned.reps)",
                            languageCode: gymCurrentLanguageCode()
                        ))
                        .monospacedDigit()
                        .foregroundStyle(completed == nil ? GymTheme.textSecondary : GymTheme.textPrimary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func spotterProgressLine(
        label: String,
        completed: Int,
        total: Int,
        accent: Color
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: GymTheme.Spacing.xSmall) {
                    HStack(alignment: .firstTextBaseline, spacing: GymTheme.Spacing.small) {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GymTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: GymTheme.Spacing.small)
                        Text("\(completed)/\(total)")
                            .font(GymTheme.TypeScale.utility)
                            .foregroundStyle(GymTheme.textPrimary)
                    }
                    ProgressView(value: Double(completed), total: Double(max(1, total)))
                        .tint(accent)
                }
            } else {
                HStack(spacing: GymTheme.Spacing.small) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 72, alignment: .leading)

                    ProgressView(value: Double(completed), total: Double(max(1, total)))
                        .tint(accent)

                    Text("\(completed)/\(total)")
                        .font(GymTheme.TypeScale.utility)
                        .foregroundStyle(GymTheme.textPrimary)
                        .frame(minWidth: 42, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(completed) / \(total)")
    }

    private func liveExerciseLane(
        _ lane: LiveWorkoutExerciseLaneSummary,
        peerName: String
    ) -> some View {
        let displayName = BuiltInExerciseCatalog.displayName(
            catalogKey: lane.catalogKey,
            rawName: lane.name,
            languageCode: gymCurrentLanguageCode()
        )
        let selfCompleted = lane.selfCompleted.lazy.filter { $0 }.count
        return VStack(alignment: .leading, spacing: GymTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: GymTheme.Spacing.small) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GymTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: GymTheme.Spacing.xSmall)
                Text("\(selfCompleted)/\(lane.selfCompleted.count)")
                    .font(GymTheme.TypeScale.utility)
                    .foregroundStyle(GymTheme.textSecondary)
            }
            liveSetLane(
                label: gymText(
                    "You",
                    "Ти",
                    "Ты",
                    languageCode: gymCurrentLanguageCode()
                ),
                completed: lane.selfCompleted,
                accent: GymTheme.primary
            )
            liveSetLane(
                label: peerName,
                completed: lane.peerCompleted,
                accent: GymTheme.secondary
            )
        }
        .padding(.horizontal, GymTheme.Spacing.large)
        .padding(.vertical, GymTheme.Spacing.medium)
        .accessibilityElement(children: .contain)
    }

    private func liveSetLane(label: String, completed: [Bool], accent: Color) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: GymTheme.Spacing.xSmall) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    liveSetIndicators(completed: completed, accent: accent)
                }
            } else {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 72, alignment: .leading)
                    liveSetIndicators(completed: completed, accent: accent)
                }
            }
        }
    }

    private func liveSetIndicators(completed: [Bool], accent: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(completed.indices, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(completed[index] ? accent.opacity(0.14) : GymTheme.surfaceVariant.opacity(0.62))
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                completed[index] ? accent.opacity(0.72) : GymTheme.outlineSoft,
                                lineWidth: completed[index] ? 1.25 : GymTheme.hairlineWidth
                            )
                        if completed[index] {
                            Image(systemName: "checkmark")
                                .font(.caption2.bold())
                                .foregroundStyle(accent)
                        } else {
                            Text("\(index + 1)")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(GymTheme.textSecondary)
                        }
                    }
                    .frame(width: 28, height: 25)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        gymText(
                            "Set \(index + 1)",
                            "Підхід \(index + 1)",
                            "Подход \(index + 1)",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                    .accessibilityValue(
                        completed[index]
                            ? gymText(
                                "Recorded",
                                "Записано",
                                "Записано",
                                languageCode: gymCurrentLanguageCode()
                            )
                            : gymText(
                                "Planned",
                                "Заплановано",
                                "Запланировано",
                                languageCode: gymCurrentLanguageCode()
                            )
                    )
                }
            }
        }
    }

    private func exercisePanel(
        _ exercise: ActiveWorkoutExercise,
        draft: ActiveWorkoutDraft
    ) -> some View {
        let storedExercise = workoutStore.exercise(id: exercise.exerciseID)
        let exerciseName = storedExercise.map { gymExerciseName($0) } ?? gymText(
            "Unavailable exercise",
            "Недоступна вправа",
            "Недоступное упражнение",
            languageCode: gymCurrentLanguageCode()
        )
        let completedCount = exercise.sets.lazy.filter(\.isCompleted).count
        let fullyCompleted = completedCount == exercise.sets.count
        let currentExerciseID = draft.exercises.first(where: { candidate in
            candidate.sets.contains(where: { !$0.isCompleted })
        })?.id
        let isCurrent = currentExerciseID == exercise.id
        let isCollapsed = collapsedExerciseIDs.contains(exercise.id)
        let setCountPhrase = gymCount(
            exercise.sets.count,
            englishOne: "set",
            englishMany: "sets",
            ukrainianOne: "підхід",
            ukrainianFew: "підходи",
            ukrainianMany: "підходів",
            languageCode: gymCurrentLanguageCode()
        )
        return GymPanel(highlighted: isCurrent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    if let storedExercise {
                        ExerciseMediaButton(
                            rawExerciseName: storedExercise.name,
                            catalogKey: storedExercise.catalogKey,
                            exerciseID: storedExercise.id,
                            ownerKey: workoutStore.accountStorageKey,
                            editable: ExerciseMediaPresentation.isEditable(on: .activeWorkout)
                        )
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isCollapsed { collapsedExerciseIDs.remove(exercise.id) }
                            else { collapsedExerciseIDs.insert(exercise.id) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exerciseName)
                                    .font(.headline)
                                    .foregroundStyle(GymTheme.textPrimary)
                                if isCollapsed {
                                    Label(
                                        "\(completedCount) / \(exercise.sets.count)",
                                        systemImage: fullyCompleted
                                            ? "checkmark.seal.fill"
                                            : "circle.dotted"
                                    )
                                    .font(.subheadline.monospacedDigit().weight(.bold))
                                    .foregroundStyle(
                                        fullyCompleted ? GymTheme.secondary : GymTheme.textSecondary
                                    )
                                    if !isCurrent {
                                        Text(
                                            fullyCompleted
                                                ? gymText(
                                                    "Completed", "Завершено", "Завершено",
                                                    languageCode: gymCurrentLanguageCode()
                                                )
                                                : gymText(
                                                    "Up next · \(setCountPhrase)",
                                                    "Далі · \(setCountPhrase)",
                                                    "Далее · \(setCountPhrase)",
                                                    languageCode: gymCurrentLanguageCode()
                                                )
                                        )
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(GymTheme.textSecondary)
                                    }
                                } else {
                                    Text(exerciseSetSubtitle(exercise: exercise, draft: draft))
                                        .font(.caption)
                                        .foregroundStyle(GymTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                                .foregroundStyle(GymTheme.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(exerciseName)
                    .accessibilityValue("\(completedCount) / \(exercise.sets.count)")
                }

                if !isCollapsed {
                    let currentID = currentSetID(in: draft)
                    // Tight inner stack: the outer card's spacing: 14 is meant
                    // for header/rows-block/footer, not between every single
                    // row and divider — nesting the rows here keeps each row's
                    // own vertical padding as the only gap between them.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                            setRow(
                                set,
                                position: index,
                                exercise: exercise,
                                exerciseName: exerciseName,
                                draft: draft
                            )
                            // A thin divider between two plain (upcoming/completed)
                            // rows only — the current set's own tinted card already
                            // separates itself visually, so no divider hugs it.
                            if index < exercise.sets.count - 1,
                               set.id != currentID,
                               exercise.sets[index + 1].id != currentID {
                                Divider().overlay(GymTheme.outlineSoft)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            appendSet(to: exercise)
                        } label: {
                            Text(
                                gymText(
                                    "+ Set",
                                    "+ Підхід",
                                    "+ Подход",
                                    languageCode: gymCurrentLanguageCode()
                                )
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GymTheme.primary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(GymTheme.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                        .accessibilityLabel(
                            gymText(
                                "Add set",
                                "Додати підхід",
                                "Добавить подход",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                        .disabled(
                            activeWorkoutStructuralActionsAreDisabled(
                                hasStoredExercise: storedExercise != nil,
                                hasCommitIntent: draft.commitIntent != nil,
                                isLivePlanFrozen: liveWorkoutCoordinator.planIsFrozenForCurrentDraft
                            )
                        )

                        Button {
                            saveExercise(exercise, draft: draft)
                        } label: {
                            Text(
                                gymText(
                                    "Finish",
                                    "Завершити",
                                    "Завершить",
                                    languageCode: gymCurrentLanguageCode()
                                )
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GymTheme.primary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(GymTheme.primary.opacity(0.7), lineWidth: 1)
                        )
                        .accessibilityLabel(
                            gymText(
                                "Save exercise",
                                "Зберегти вправу",
                                "Сохранить упражнение",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                        .disabled(
                            activeWorkoutStructuralActionsAreDisabled(
                                hasStoredExercise: storedExercise != nil,
                                hasCommitIntent: draft.commitIntent != nil,
                                isLivePlanFrozen: liveWorkoutCoordinator.planIsFrozenForCurrentDraft
                            )
                        )
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func setRow(
        _ set: ActiveWorkoutSet,
        position: Int,
        exercise: ActiveWorkoutExercise,
        exerciseName: String,
        draft: ActiveWorkoutDraft
    ) -> some View {
        let isCurrent = currentSetID(in: draft) == set.id
        if set.isCompleted {
            completedSetRow(set, position: position, draft: draft)
        } else if isCurrent {
            currentSetRow(set, position: position, exercise: exercise, exerciseName: exerciseName, draft: draft)
        } else {
            upcomingSetRow(set, position: position, draft: draft)
        }
    }

    /// The one editable set at a time: compact badge + weight + × + reps,
    /// weight-step chips, then the primary "Log" button. Marked as current
    /// via a themed border and an accessibility trait/value instead of a
    /// separate "Current" pill.
    private func currentSetRow(
        _ set: ActiveWorkoutSet,
        position: Int,
        exercise: ActiveWorkoutExercise,
        exerciseName: String,
        draft: ActiveWorkoutDraft
    ) -> some View {
        let restSeconds = restDurationSeconds(for: exercise)
        let fieldsDisabled = activeWorkoutValueEditorsAreDisabled(
            isCompleted: false,
            hasCommitIntent: draft.commitIntent != nil,
            isLivePlanFrozen: liveWorkoutCoordinator.planIsFrozenForCurrentDraft
        )
        let last = previousPerformance(exercise: exercise, position: position, draft: draft)
        let preceding = exercise.sets.prefix(position).last(where: { $0.isCompleted })
        let repeatWeight = preceding?.weight ?? last?.weight
        let repeatReps = preceding?.reps ?? last?.reps

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(
                    gymText(
                        "Set \(position + 1)",
                        "Підхід \(position + 1)",
                        "Подход \(position + 1)",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(GymTheme.primary)

                Spacer(minLength: 8)

                if let last, let repeatWeight, let repeatReps {
                    Button {
                        updateSet(draft: draft, setID: set.id, weight: repeatWeight, reps: repeatReps)
                    } label: {
                        Text(
                            gymText(
                                "previous \(last.weight.formatted()) × \(last.reps)",
                                "минулого разу \(last.weight.formatted()) × \(last.reps)",
                                "прошлый раз \(last.weight.formatted()) × \(last.reps)",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GymTheme.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.commitIntent != nil)
                    .accessibilityLabel(
                        gymText(
                            "Repeat previous, \(last.weight.formatted()) kilograms by \(last.reps)",
                            "Повторити попередні, \(last.weight.formatted()) кілограмів на \(last.reps)",
                            "Повторить предыдущие, \(last.weight.formatted()) килограммов на \(last.reps)",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                    .accessibilityHint(
                        gymText(
                            "Double tap to reuse this weight and reps",
                            "Двічі торкніться, щоб повторити цю вагу й повторення",
                            "Дважды нажмите, чтобы повторить этот вес и повторения",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Spacer(minLength: 0)
                TextField(
                    "0",
                    value: weightBinding(setID: set.id),
                    format: .number.precision(.fractionLength(0 ... 2))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 30, weight: .semibold).monospacedDigit())
                .foregroundStyle(GymTheme.textPrimary)
                .fixedSize()
                .disabled(fieldsDisabled)
                .focused($focusedWeightSetID, equals: set.id)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(focusedWeightSetID == set.id ? GymTheme.primary : Color.clear)
                        .frame(height: 1.5)
                }
                .accessibilityLabel(weightAccessibilityLabel(position: position))

                Text(gymLocalized("kg"))
                    .font(.system(size: 15))
                    .foregroundStyle(GymTheme.textSecondary)

                Text(verbatim: "×")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(GymTheme.textSecondary)
                    .accessibilityHidden(true)

                Text(set.reps.formatted())
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .foregroundStyle(GymTheme.textPrimary)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    weightStepCapsule(set: set, position: position, exercise: exercise, draft: draft, disabled: fieldsDisabled)
                    repsStepCapsule(set: set, position: position, disabled: fieldsDisabled)
                }
            } else {
                HStack(spacing: 8) {
                    weightStepCapsule(set: set, position: position, exercise: exercise, draft: draft, disabled: fieldsDisabled)
                    repsStepCapsule(set: set, position: position, disabled: fieldsDisabled)
                }
            }

            Button {
                recordSet(set, exercise: exercise, exerciseName: exerciseName, draft: draft)
            } label: {
                // No extra vertical padding/minHeight here: GymPrimaryButtonStyle
                // already adds its own vertical padding + minHeight 48, and
                // stacking another minHeight on top of that padding was what
                // pushed this button to ~68pt tall.
                logButtonText(restSeconds: restSeconds)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GymPrimaryButtonStyle())
            .disabled(draft.commitIntent != nil)
            .accessibilityLabel(logButtonLabel(restSeconds: restSeconds))
            .accessibilityHint(
                gymText(
                    "Saves this set before starting its movement-based rest timer",
                    "Зберігає цей підхід перед запуском таймера відпочинку для цієї вправи",
                    "Сохраняет этот подход перед запуском таймера отдыха для этого упражнения",
                    languageCode: gymCurrentLanguageCode()
                )
            )
        }
        .padding(10)
        .background(GymTheme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isSelected)
        .accessibilityValue(
            gymText("Current set", "Поточний підхід", "Текущий подход", languageCode: gymCurrentLanguageCode())
        )
    }

    /// "Записать подход · отдых 3:00" as one line, with the rest suffix in a
    /// lighter weight/secondary-on-blue tint. Drops the suffix entirely when
    /// no rest timer applies.
    private func logButtonText(restSeconds: Int) -> Text {
        let main = Text(
            gymText("Log set", "Записати підхід", "Записать подход", languageCode: gymCurrentLanguageCode())
        )
        .font(.headline)
        guard restSeconds > 0 else { return main }
        let mmss = String(format: "%d:%02d", restSeconds / 60, restSeconds % 60)
        let suffix = Text(
            " · " + gymText(
                "rest \(mmss)",
                "відпочинок \(mmss)",
                "отдых \(mmss)",
                languageCode: gymCurrentLanguageCode()
            )
        )
        .font(.subheadline)
        .foregroundStyle(Color.white.opacity(0.75))
        return main + suffix
    }

    /// One slim, equal-height pill shared by the weight and reps rows: a
    /// step button at each end (44pt tap target via a larger button frame),
    /// a tiny center label, and a 32–36pt-tall visual capsule centered
    /// within that larger tap frame via `.background(alignment:)`.
    private func stepCapsule(
        minusLabel: String,
        minusAccessibilityLabel: String,
        minusDisabled: Bool,
        minusAction: @escaping () -> Void,
        centerLabel: String,
        plusLabel: String,
        plusAccessibilityLabel: String,
        plusDisabled: Bool,
        plusAction: @escaping () -> Void,
        accessibilityLabel: String,
        accessibilityValue: String,
        useSymbolGlyphs: Bool = false,
        adjustableAction: @escaping (AccessibilityAdjustmentDirection) -> Void
    ) -> some View {
        HStack(spacing: 0) {
            Button(action: minusAction) {
                Group {
                    if useSymbolGlyphs {
                        Image(systemName: minusLabel)
                    } else {
                        Text(minusLabel)
                    }
                }
                .font(useSymbolGlyphs ? .body.weight(.semibold) : .caption2.weight(.bold))
                .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(minusDisabled)

            Text(centerLabel)
                .font(.caption2)
                .foregroundStyle(GymTheme.textSecondary)
                .frame(maxWidth: .infinity)

            Button(action: plusAction) {
                Group {
                    if useSymbolGlyphs {
                        Image(systemName: plusLabel)
                    } else {
                        Text(plusLabel)
                    }
                }
                .font(useSymbolGlyphs ? .body.weight(.semibold) : .caption2.weight(.bold))
                .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(plusDisabled)
        }
        .buttonStyle(.plain)
        .foregroundStyle(GymTheme.primary)
        .background(alignment: .center) {
            Capsule().fill(GymTheme.surface).frame(height: 34)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard !(minusDisabled && plusDisabled) else { return }
            adjustableAction(direction)
        }
    }

    /// "−2,5   вес   +2,5" capsule: same nominal-step/disabled logic the
    /// old weight-step chips used (honors a machine's `allowedWeightsKg`).
    private func weightStepCapsule(
        set: ActiveWorkoutSet,
        position: Int,
        exercise: ActiveWorkoutExercise,
        draft: ActiveWorkoutDraft,
        disabled: Bool
    ) -> some View {
        let allowed = workoutStore.exercise(id: exercise.exerciseID)?.machineLoadProfile?.allowedWeightsKg ?? []
        // Nominal step shown even when that direction is blocked (e.g. at
        // 0 kg or at the machine's lowest stop): the default 2.5 kg
        // increment, or the smallest gap between the machine's allowed
        // weights when it has one.
        let nominalStep: Double = {
            guard allowed.count >= 2 else { return 2.5 }
            let gaps = zip(allowed, allowed.dropFirst()).map { $1 - $0 }
            return gaps.min() ?? 2.5
        }()
        let minusWeight = TrainingTools.stepWeight(set.weight, direction: -1, allowed: allowed)
        let minusCanMove = minusWeight != set.weight
        let minusDelta = minusCanMove ? abs(minusWeight - set.weight) : nominalStep
        let plusWeight = TrainingTools.stepWeight(set.weight, direction: 1, allowed: allowed)
        let plusCanMove = plusWeight != set.weight
        let plusDelta = plusCanMove ? abs(plusWeight - set.weight) : nominalStep

        return stepCapsule(
            minusLabel: "−" + minusDelta.formatted(),
            minusAccessibilityLabel: gymText("Decrease weight by \(minusDelta.formatted())", "Зменшити вагу на \(minusDelta.formatted())", "Уменьшить вес на \(minusDelta.formatted())", languageCode: gymCurrentLanguageCode()),
            minusDisabled: disabled || !minusCanMove,
            minusAction: { updateSet(draft: draft, setID: set.id, weight: minusWeight, reps: set.reps) },
            centerLabel: gymText("weight", "вага", "вес", languageCode: gymCurrentLanguageCode()),
            plusLabel: "+" + plusDelta.formatted(),
            plusAccessibilityLabel: gymText("Increase weight by \(plusDelta.formatted())", "Збільшити вагу на \(plusDelta.formatted())", "Увеличить вес на \(plusDelta.formatted())", languageCode: gymCurrentLanguageCode()),
            plusDisabled: disabled || !plusCanMove,
            plusAction: { updateSet(draft: draft, setID: set.id, weight: plusWeight, reps: set.reps) },
            accessibilityLabel: gymText("Weight", "Вага", "Вес", languageCode: gymCurrentLanguageCode()),
            accessibilityValue: "\(set.weight.formatted()) \(gymLocalized("kg"))",
            adjustableAction: { direction in
                switch direction {
                case .increment: if plusCanMove { updateSet(draft: draft, setID: set.id, weight: plusWeight, reps: set.reps) }
                case .decrement: if minusCanMove { updateSet(draft: draft, setID: set.id, weight: minusWeight, reps: set.reps) }
                @unknown default: break
                }
            }
        )
    }

    /// "−   повт.   +" capsule for reps.
    private func repsStepCapsule(set: ActiveWorkoutSet, position: Int, disabled: Bool) -> some View {
        let reps = repsBinding(setID: set.id)
        return stepCapsule(
            minusLabel: "minus",
            minusAccessibilityLabel: gymText("Decrease reps", "Зменшити повторення", "Уменьшить повторения", languageCode: gymCurrentLanguageCode()),
            minusDisabled: disabled || reps.wrappedValue <= 1,
            minusAction: { reps.wrappedValue = max(1, reps.wrappedValue - 1) },
            centerLabel: gymText("reps", "повт.", "повт.", languageCode: gymCurrentLanguageCode()),
            plusLabel: "plus",
            plusAccessibilityLabel: gymText("Increase reps", "Збільшити повторення", "Увеличить повторения", languageCode: gymCurrentLanguageCode()),
            plusDisabled: disabled,
            plusAction: { reps.wrappedValue += 1 },
            accessibilityLabel: gymText("Reps", "Повторення", "Повторы", languageCode: gymCurrentLanguageCode()),
            accessibilityValue: reps.wrappedValue.formatted(),
            useSymbolGlyphs: true,
            adjustableAction: { direction in
                switch direction {
                case .increment: reps.wrappedValue += 1
                case .decrement: reps.wrappedValue = max(1, reps.wrappedValue - 1)
                @unknown default: break
                }
            }
        )
    }

    /// A not-yet-reached set: one compact read-only line, tappable to
    /// expand into the same compact editor the current set uses (preserves
    /// the prior ability to edit a non-current set inline).
    private func upcomingSetRow(
        _ set: ActiveWorkoutSet,
        position: Int,
        draft: ActiveWorkoutDraft
    ) -> some View {
        let isExpanded = expandedSetIDs.contains(set.id)
        let fieldsDisabled = activeWorkoutValueEditorsAreDisabled(
            isCompleted: false,
            hasCommitIntent: draft.commitIntent != nil,
            isLivePlanFrozen: liveWorkoutCoordinator.planIsFrozenForCurrentDraft
        )
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded { expandedSetIDs.remove(set.id) } else { expandedSetIDs.insert(set.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("\(position + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(GymTheme.textSecondary)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().strokeBorder(GymTheme.outlineSoft, lineWidth: 1.5)
                        )
                    Text(weightRepsSummary(weight: set.weight, reps: set.reps))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                gymText(
                    "Set \(position + 1), \(weightRepsSummary(weight: set.weight, reps: set.reps))",
                    "Підхід \(position + 1), \(weightRepsSummary(weight: set.weight, reps: set.reps))",
                    "Подход \(position + 1), \(weightRepsSummary(weight: set.weight, reps: set.reps))",
                    languageCode: gymCurrentLanguageCode()
                )
            )
            .accessibilityHint(
                gymText(
                    "Double tap to edit this set",
                    "Двічі торкніться, щоб редагувати цей підхід",
                    "Дважды нажмите, чтобы редактировать этот подход",
                    languageCode: gymCurrentLanguageCode()
                )
            )

            if isExpanded {
                HStack(spacing: 8) {
                    GymSetWeightField(
                        weight: weightBinding(setID: set.id),
                        disabled: fieldsDisabled,
                        accessibilityLabel: Text(weightAccessibilityLabel(position: position))
                    )
                    Text(verbatim: "×")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                        .accessibilityHidden(true)
                    GymSetRepsCapsule(
                        reps: repsBinding(setID: set.id),
                        disabled: fieldsDisabled,
                        accessibilityLabel: Text(repsAccessibilityLabel(position: position))
                    )
                    Spacer(minLength: 4)
                }
            }
        }
        .padding(.vertical, 10)
    }

    /// A recorded set: one line with a checkmark. The latest recorded set
    /// keeps its rest timer and "Undo latest set" action underneath.
    private func completedSetRow(
        _ set: ActiveWorkoutSet,
        position: Int,
        draft: ActiveWorkoutDraft
    ) -> some View {
        let isLatestCompleted = draft.undoableSetID == set.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.secondary)
                    .frame(width: 22, height: 22)
                    .background(GymTheme.secondary.opacity(0.18), in: Circle())
                Text(weightRepsSummary(weight: set.weight, reps: set.reps))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GymTheme.textSecondary)
                Spacer(minLength: 8)
                if isLatestCompleted, let deadline = draft.timing?.restingUntil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
                        if remaining > 0 {
                            Text(
                                gymText(
                                    "rest \(Self.clock(TimeInterval(remaining)))",
                                    "відпочинок \(Self.clock(TimeInterval(remaining)))",
                                    "отдых \(Self.clock(TimeInterval(remaining)))",
                                    languageCode: gymCurrentLanguageCode()
                                )
                            )
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(GymTheme.primary)
                            .accessibilityHidden(true)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                gymText(
                    "Set \(position + 1) recorded, \(weightRepsSummary(weight: set.weight, reps: set.reps))",
                    "Підхід \(position + 1) записано, \(weightRepsSummary(weight: set.weight, reps: set.reps))",
                    "Подход \(position + 1) записан, \(weightRepsSummary(weight: set.weight, reps: set.reps))",
                    languageCode: gymCurrentLanguageCode()
                )
            )

            if isLatestCompleted {
                activeRestPanel(draft: draft)

                Button {
                    undoLatestSet(set, draft: draft)
                } label: {
                    Label(
                        gymText(
                            "Undo latest set",
                            "Скасувати останній підхід",
                            "Отменить последний подход",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "arrow.uturn.backward.circle"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .disabled(draft.commitIntent != nil)
                .accessibilityHint(
                    gymText(
                        "Restores the latest recorded set for editing and stops its rest timer",
                        "Повертає останній записаний підхід до редагування й зупиняє таймер відпочинку",
                        "Возвращает последний записанный подход к редактированию и останавливает таймер отдыха",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
        }
        .padding(.vertical, 10)
    }

    /// Previous session's weight/reps at this set position (or its closest
    /// preceding one), used both by the exercise header's " · прошлый раз …"
    /// caption and by the "Repeat previous" chip below.
    private func previousPerformance(
        exercise: ActiveWorkoutExercise,
        position: Int,
        draft: ActiveWorkoutDraft
    ) -> (weight: Double, reps: Int)? {
        let history = workoutStore.exerciseHistory(exerciseID: exercise.exerciseID).filter { $0.sessionDate < draft.startedAt }
        let latestID = history.sorted { $0.sessionDate == $1.sessionDate ? $0.workoutID.uuidString > $1.workoutID.uuidString : $0.sessionDate > $1.sessionDate }.first?.workoutID
        let previous = history.filter { $0.workoutID == latestID }.sorted { $0.setOrderIndex < $1.setOrderIndex }
        guard let last = previous.first(where: { $0.setOrderIndex == position }) ?? previous.last else { return nil }
        return (last.weight, last.reps)
    }

    /// "Подход 2 из 3" for the exercise card header. The previous-session
    /// performance moved into the current set block's own header row (see
    /// `currentSetRow`), so this stays a plain position/total line.
    private func exerciseSetSubtitle(exercise: ActiveWorkoutExercise, draft: ActiveWorkoutDraft) -> String {
        let total = exercise.sets.count
        let index = exercise.sets.firstIndex(where: { !$0.isCompleted }) ?? max(0, total - 1)
        return gymText(
            "Set \(index + 1) of \(total)",
            "Підхід \(index + 1) з \(total)",
            "Подход \(index + 1) из \(total)",
            languageCode: gymCurrentLanguageCode()
        )
    }

    private func weightAccessibilityLabel(position: Int) -> String {
        gymText(
            "Weight for set \(position + 1)",
            "Вага для підходу \(position + 1)",
            "Вес для подхода \(position + 1)",
            languageCode: gymCurrentLanguageCode()
        )
    }

    private func repsAccessibilityLabel(position: Int) -> String {
        gymText(
            "Repetitions for set \(position + 1)",
            "Повторення для підходу \(position + 1)",
            "Повторения для подхода \(position + 1)",
            languageCode: gymCurrentLanguageCode()
        )
    }

    private func weightRepsSummary(weight: Double, reps: Int) -> String {
        "\(weight.formatted()) \(gymLocalized("kg")) × \(reps)"
    }


    private func logButtonLabel(restSeconds: Int) -> String {
        guard restSeconds > 0 else {
            return gymText("Log", "Записати", "Записать", languageCode: gymCurrentLanguageCode())
        }
        let mmss = String(format: "%d:%02d", restSeconds / 60, restSeconds % 60)
        return gymText(
            "Log · rest \(mmss)",
            "Записати · відпочинок \(mmss)",
            "Записать · отдых \(mmss)",
            languageCode: gymCurrentLanguageCode()
        )
    }

    @ViewBuilder
    private func activeRestPanel(draft: ActiveWorkoutDraft) -> some View {
        if let deadline = draft.timing?.restingUntil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
                if remaining > 0 {
                    GymPanel(highlighted: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                gymText(
                                    "Set saved. Rest timer",
                                    "Підхід збережено. Таймер відпочинку",
                                    "Подход сохранён. Таймер отдыха",
                                    languageCode: gymCurrentLanguageCode()
                                )
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GymTheme.primary)

                            Text(Self.clock(TimeInterval(remaining)))
                                .font(.title2.monospacedDigit().bold())
                                .foregroundStyle(GymTheme.textPrimary)

                            activeRestControls
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(
                        gymText(
                            "Rest timer",
                            "Таймер відпочинку",
                            "Таймер отдыха",
                            languageCode: gymCurrentLanguageCode()
                        )
                    )
                    .accessibilityValue(Self.clock(TimeInterval(remaining)))
                }
            }
        }
    }

    private var activeRestControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                restAdjustmentButton(-15)
                restAdjustmentButton(15)
                stopRestButton
            }
            VStack(spacing: 8) {
                restAdjustmentButton(-15)
                restAdjustmentButton(15)
                stopRestButton
            }
        }
    }

    private func restAdjustmentButton(_ deltaSeconds: Int) -> some View {
        Button {
            adjustManualRest(deltaSeconds)
        } label: {
            Text(deltaSeconds < 0 ? "−15" : "+15")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(
            deltaSeconds < 0
                ? gymText(
                    "Subtract 15 seconds",
                    "Зменшити на 15 секунд",
                    "Убавить 15 секунд",
                    languageCode: gymCurrentLanguageCode()
                )
                : gymText(
                    "Add 15 seconds",
                    "Додати 15 секунд",
                    "Добавить 15 секунд",
                    languageCode: gymCurrentLanguageCode()
                )
        )
    }

    private var stopRestButton: some View {
        Button {
            stopManualRest()
        } label: {
            Text(
                gymText(
                    "Stop rest",
                    "Зупинити відпочинок",
                    "Остановить отдых",
                    languageCode: gymCurrentLanguageCode()
                )
            )
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private func finishPanel(_ draft: ActiveWorkoutDraft) -> some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: gymText(
                        "Complete this workout",
                        "Завершити тренування",
                        "Завершить тренировку",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                Button {
                    recordAllSets(draft)
                } label: {
                    Label(
                        gymText(
                            "Save all",
                            "Зберегти все",
                            "Сохранить всё",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "checkmark.circle"
                    )
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .disabled(
                    draft.completedSetCount == draft.plannedSetCount ||
                        draft.commitIntent != nil
                )
                Button {
                    finish(draft)
                } label: {
                    Label(
                        draft.commitIntent == nil
                            ? gymText(
                                "Finish and view summary",
                                "Завершити й переглянути підсумок",
                                "Завершить и посмотреть итог",
                                languageCode: gymCurrentLanguageCode()
                            )
                            : gymText(
                                "Retry finish",
                                "Повторити завершення",
                                "Повторить завершение",
                                languageCode: gymCurrentLanguageCode()
                            ),
                        systemImage: "checkmark.seal.fill"
                    )
                }
                .buttonStyle(GymPrimaryButtonStyle())
                .disabled(draft.completedSetCount == 0)
            }
        }
    }

    private func weightBinding(setID: UUID) -> Binding<Double> {
        Binding(
            get: { activeSet(id: setID)?.weight ?? 0 },
            set: { newWeight in
                guard let draft = currentDraft,
                      let set = activeSet(id: setID),
                      !set.isCompleted else { return }
                updateSet(
                    draft: draft,
                    setID: setID,
                    weight: newWeight,
                    reps: set.reps
                )
            }
        )
    }

    private func repsBinding(setID: UUID) -> Binding<Int> {
        Binding(
            get: { activeSet(id: setID)?.reps ?? 1 },
            set: { newReps in
                guard let draft = currentDraft,
                      let set = activeSet(id: setID),
                      !set.isCompleted else { return }
                updateSet(
                    draft: draft,
                    setID: setID,
                    weight: set.weight,
                    reps: newReps
                )
            }
        )
    }

    private func activeSet(id: UUID) -> ActiveWorkoutSet? {
        currentDraft?.exercises.lazy.flatMap(\.sets).first { $0.id == id }
    }

    private func currentSetID(in draft: ActiveWorkoutDraft) -> UUID? {
        draft.exercises.lazy
            .flatMap(\.sets)
            .first(where: { !$0.isCompleted })?
            .id
    }

    private func updateSet(
        draft: ActiveWorkoutDraft,
        setID: UUID,
        weight: Double,
        reps: Int
    ) {
        do {
            try activeWorkoutStore.updateSet(
                draftID: draft.id,
                setID: setID,
                weight: weight,
                reps: reps,
                expectedRevision: draft.revision
            )
            statusMessage = nil
        } catch {
            show(error)
        }
    }

    private func recordSet(
        _ set: ActiveWorkoutSet,
        exercise: ActiveWorkoutExercise,
        exerciseName: String,
        draft: ActiveWorkoutDraft
    ) {
        let restSeconds = restDurationSeconds(for: exercise)
        var liveQueueFailureMessage: String?
        do {
            let updated = try activeWorkoutStore.recordSet(
                draftID: draft.id,
                setID: set.id,
                expectedRevision: draft.revision,
                restSeconds: restSeconds
            )
            do {
                try liveWorkoutCoordinator.localSetWasCompleted(
                    localSetID: set.id,
                    weight: set.weight,
                    reps: set.reps
                )
            } catch {
                let message = gymLocalized(
                    gymSafeEnglishErrorMessage(error),
                    languageCode: gymCurrentLanguageCode()
                )
                liveQueueFailureMessage = message
                reportStatus(message, true)
            }
            // The active draft owns the exact deadline. The countdown projection
            // can be reconstructed from it after a crash between the two writes.
            let restOutcome = try ActiveWorkoutRestReconciler.reconcile(
                draft: updated,
                store: activeWorkoutStore,
                manager: restTimers,
                title: exerciseName
            )
            if let updatedExercise = updated.exercises.first(where: { $0.id == exercise.id }),
               updatedExercise.sets.allSatisfy(\.isCompleted) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    // Keep the latest completed row expanded so its rest and undo
                    // controls remain immediately reachable.
                    collapsedExerciseIDs.remove(exercise.id)
                    if let nextExercise = updated.exercises.first(where: { candidate in
                        candidate.sets.contains(where: { !$0.isCompleted })
                    }) {
                        collapsedExerciseIDs.remove(nextExercise.id)
                    }
                }
            }
            applyActiveWorkoutActionStatus(
                liveQueueFailure: liveQueueFailureMessage,
                restProjectionWarning: restOutcome == .synchronized
                    ? nil
                    : gymText(
                        "Set recorded, but the rest timer could not be saved durably. Rest was stopped.",
                        "Підхід записано, але таймер відпочинку не вдалося надійно зберегти. Відпочинок зупинено.",
                        "Подход записан, но таймер отдыха не удалось надёжно сохранить. Отдых остановлен.",
                        languageCode: gymCurrentLanguageCode()
                    ),
                success: gymText(
                    "Set recorded. Rest timer started.",
                    "Підхід записано. Таймер відпочинку запущено.",
                    "Подход записан. Таймер отдыха запущен.",
                    languageCode: gymCurrentLanguageCode()
                )
            )
        } catch {
            showActionFailure(error, liveQueueFailure: liveQueueFailureMessage)
        }
    }

    private func recordAllSets(_ draft: ActiveWorkoutDraft) {
        let orderedInputs = draft.exercises.flatMap { exercise in
            exercise.sets.compactMap { set in
                set.isCompleted
                    ? nil
                    : (
                        set.id,
                        ActiveWorkoutSetInput(weight: set.weight, reps: set.reps)
                    )
            }
        }
        let inputs = Dictionary(uniqueKeysWithValues: orderedInputs)
        let liveInputs = orderedInputs.map {
            (id: $0.0, weight: $0.1.weight, reps: $0.1.reps)
        }
        var liveQueueFailureMessage: String?
        do {
            try liveWorkoutCoordinator.preflightLocalSetsCompletion(liveInputs)
            let updated = try activeWorkoutStore.recordAllSets(
                draftID: draft.id,
                expectedRevision: draft.revision,
                inputs: inputs
            )
            do {
                try liveWorkoutCoordinator.localSetsWereCompleted(liveInputs)
            } catch {
                let message = gymLocalized(
                    gymSafeEnglishErrorMessage(error),
                    languageCode: gymCurrentLanguageCode()
                )
                liveQueueFailureMessage = message
                reportStatus(message, true)
            }
            // Batch persistence never starts rest. Any older rest is retired only
            // after the one atomic draft revision has succeeded.
            let restOutcome = try ActiveWorkoutRestReconciler.reconcile(
                draft: updated,
                store: activeWorkoutStore,
                manager: restTimers,
                title: currentRestExerciseName(updated)
            )
            let restCleanupSucceeded = restOutcome == .synchronized
            withAnimation(.easeInOut(duration: 0.2)) {
                collapsedExerciseIDs.formUnion(
                    updated.exercises.compactMap { exercise in
                        exercise.sets.allSatisfy(\.isCompleted) ? exercise.id : nil
                    }
                )
            }
            applyActiveWorkoutActionStatus(
                liveQueueFailure: liveQueueFailureMessage,
                restProjectionWarning: restCleanupSucceeded
                    ? nil
                    : gymText(
                        "Sets were saved, but old local controls could not be fully cleared.",
                        "Підходи збережено, але старі локальні елементи не вдалося повністю очистити.",
                        "Подходы сохранены, но старые локальные элементы не удалось полностью очистить.",
                        languageCode: gymCurrentLanguageCode()
                    ),
                success: gymText(
                    "All sets saved.",
                    "Усі підходи збережено.",
                    "Все подходы сохранены.",
                    languageCode: gymCurrentLanguageCode()
                )
            )
        } catch {
            showActionFailure(error, liveQueueFailure: liveQueueFailureMessage)
        }
    }

    private func undoLatestSet(
        _ set: ActiveWorkoutSet,
        draft: ActiveWorkoutDraft
    ) {
        var liveQueueFailureMessage: String?
        do {
            let updated = try activeWorkoutStore.undoLatestRecordedSet(
                draftID: draft.id,
                setID: set.id,
                expectedRevision: draft.revision
            )
            do {
                try liveWorkoutCoordinator.localSetWasUndone(localSetID: set.id)
            } catch {
                let message = gymLocalized(
                    gymSafeEnglishErrorMessage(error),
                    languageCode: gymCurrentLanguageCode()
                )
                liveQueueFailureMessage = message
                reportStatus(message, true)
            }
            let restOutcome = try ActiveWorkoutRestReconciler.reconcile(
                draft: updated,
                store: activeWorkoutStore,
                manager: restTimers,
                title: currentRestExerciseName(updated)
            )
            applyActiveWorkoutActionStatus(
                liveQueueFailure: liveQueueFailureMessage,
                restProjectionWarning: restOutcome == .synchronized
                    ? nil
                    : gymText(
                        "Latest set restored, but old rest cleanup must be retried.",
                        "Останній підхід відновлено, але очищення старого відпочинку треба повторити.",
                        "Последний подход восстановлен, но очистку старого отдыха нужно повторить.",
                        languageCode: gymCurrentLanguageCode()
                    ),
                success: gymText(
                    "Latest set restored for editing. Rest stopped.",
                    "Останній підхід повернуто до редагування. Відпочинок зупинено.",
                    "Последний подход возвращён к редактированию. Отдых остановлен.",
                    languageCode: gymCurrentLanguageCode()
                )
            )
        } catch {
            showActionFailure(error, liveQueueFailure: liveQueueFailureMessage)
        }
    }

    private func startManualRest(_ seconds: Int) {
        guard let draft = currentDraft else { return }
        let title = currentRestExerciseName(draft)
        do {
            let updated = try activeWorkoutStore.beginRest(
                draftID: draft.id,
                expectedRevision: draft.revision,
                seconds: seconds
            )
            let restOutcome = try ActiveWorkoutRestReconciler.reconcile(
                draft: updated,
                store: activeWorkoutStore,
                manager: restTimers,
                title: title
            )
            if restOutcome == .synchronized {
                statusMessage = nil
                statusIsError = false
            } else {
                showRestProjectionWarning(
                    gymText(
                        "The rest timer could not be saved durably, so rest was stopped.",
                        "Таймер відпочинку не вдалося надійно зберегти, тому відпочинок зупинено.",
                        "Таймер отдыха не удалось надёжно сохранить, поэтому отдых остановлен.",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
        } catch {
            show(error)
        }
    }

    private func adjustManualRest(_ deltaSeconds: Int) {
        guard let draft = currentDraft else { return }
        let now = Date()
        let currentRemaining = draft.timing?.restingUntil.map {
            max(0, Int(ceil($0.timeIntervalSince(now))))
        } ?? 0
        let adjusted = currentRemaining + deltaSeconds
        if adjusted <= 0 {
            stopManualRest()
            return
        }
        do {
            let updated = try activeWorkoutStore.adjustRest(
                draftID: draft.id,
                expectedRevision: draft.revision,
                remainingSeconds: adjusted,
                now: now
            )
            let restOutcome = try ActiveWorkoutRestReconciler.reconcile(
                draft: updated,
                store: activeWorkoutStore,
                manager: restTimers,
                title: currentRestExerciseName(updated),
                now: now
            )
            if restOutcome == .synchronized {
                statusMessage = nil
                statusIsError = false
            } else {
                showRestProjectionWarning(
                    gymText(
                        "The adjusted rest timer could not be saved durably, so rest was stopped.",
                        "Скоригований таймер відпочинку не вдалося надійно зберегти, тому відпочинок зупинено.",
                        "Изменённый таймер отдыха не удалось надёжно сохранить, поэтому отдых остановлен.",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
        } catch {
            show(error)
        }
    }

    private func stopManualRest() {
        guard let draft = currentDraft else { return }
        do {
            let updated = try activeWorkoutStore.endRest(
                draftID: draft.id,
                expectedRevision: draft.revision
            )
            let restOutcome = try ActiveWorkoutRestReconciler.reconcile(
                draft: updated,
                store: activeWorkoutStore,
                manager: restTimers,
                title: currentRestExerciseName(updated)
            )
            if restOutcome == .synchronized {
                statusMessage = nil
                statusIsError = false
            } else {
                showRestProjectionWarning(
                    gymText(
                        "Rest was stopped, but old timer cleanup must be retried.",
                        "Відпочинок зупинено, але очищення старого таймера треба повторити.",
                        "Отдых остановлен, но очистку старого таймера нужно повторить.",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
        } catch {
            show(error)
        }
    }

    private func restDurationSeconds(for exercise: ActiveWorkoutExercise) -> Int {
        let stored = workoutStore.exercise(id: exercise.exerciseID)
        return RecommendationEngine.restDurationSeconds(
            exerciseCatalogKey: stored?.catalogKey ?? exercise.exerciseCatalogKey,
            exerciseName: stored?.name ?? exercise.exerciseName ?? ""
        )
    }

    private func currentRestExerciseName(_ draft: ActiveWorkoutDraft) -> String {
        guard let latestID = draft.undoableSetID,
              let exercise = draft.exercises.first(where: {
                  $0.sets.contains { $0.id == latestID }
              }) else {
            return gymText(
                "Workout",
                "Тренування",
                "Тренировка",
                languageCode: gymCurrentLanguageCode()
            )
        }
        return workoutStore.exercise(id: exercise.exerciseID).map { gymExerciseName($0) } ??
            exercise.exerciseName ?? "Workout"
    }

    private func nextSetDescription(_ draft: ActiveWorkoutDraft) -> String? {
        for exercise in draft.exercises {
            guard let index = exercise.sets.firstIndex(where: { !$0.isCompleted }) else { continue }
            let name = workoutStore.exercise(id: exercise.exerciseID).map { gymExerciseName($0) } ??
                exercise.exerciseName ?? gymText(
                    "Exercise",
                    "Вправа",
                    "Упражнение",
                    languageCode: gymCurrentLanguageCode()
                )
            return gymText(
                "Current target: \(name), set \(index + 1)",
                "Поточна ціль: \(name), підхід \(index + 1)",
                "Текущая цель: \(name), подход \(index + 1)",
                languageCode: gymCurrentLanguageCode()
            )
        }
        return nil
    }

    private func saveExercise(_ exercise: ActiveWorkoutExercise, draft: ActiveWorkoutDraft) {
        guard !liveWorkoutCoordinator.planIsFrozenForCurrentDraft else {
            show(LiveWorkoutSidecarError.invalidState)
            return
        }
        do {
            let updated = try activeWorkoutStore.saveExercise(
                draftID: draft.id,
                exerciseBlockID: exercise.id,
                expectedRevision: draft.revision
            )
            let restOutcome = try ActiveWorkoutRestReconciler.reconcile(
                draft: updated,
                store: activeWorkoutStore,
                manager: restTimers,
                title: currentRestExerciseName(updated)
            )
            _ = withAnimation(.easeInOut(duration: 0.2)) {
                collapsedExerciseIDs.insert(exercise.id)
            }
            applyActiveWorkoutActionStatus(
                liveQueueFailure: nil,
                restProjectionWarning: restOutcome == .synchronized
                    ? nil
                    : gymText(
                        "Exercise was saved, but old local rest controls could not be fully cleared.",
                        "Вправу збережено, але старі локальні елементи відпочинку не вдалося повністю очистити.",
                        "Упражнение сохранено, но старые локальные элементы отдыха не удалось полностью очистить.",
                        languageCode: gymCurrentLanguageCode()
                    ),
                success: gymText(
                    "Exercise saved.", "Вправу збережено.", "Упражнение сохранено.",
                    languageCode: gymCurrentLanguageCode()
                )
            )
        } catch {
            show(error)
        }
    }

    private func appendSet(to exercise: ActiveWorkoutExercise) {
        guard let draft = currentDraft else { return }
        guard !liveWorkoutCoordinator.planIsFrozenForCurrentDraft else {
            show(LiveWorkoutSidecarError.invalidState)
            return
        }
        let source = exercise.sets.last
        do {
            let updated = try activeWorkoutStore.appendSet(
                draftID: draft.id,
                exerciseBlockID: exercise.id,
                weight: source?.weight ?? workoutStore.lastWeight(exerciseID: exercise.exerciseID) ?? 0,
                reps: source?.reps ?? 10,
                expectedRevision: draft.revision
            )
            let restOutcome = try ActiveWorkoutRestReconciler.reconcile(
                draft: updated,
                store: activeWorkoutStore,
                manager: restTimers,
                title: currentRestExerciseName(updated)
            )
            if restOutcome == .synchronized {
                statusMessage = nil
                statusIsError = false
            } else {
                showRestProjectionWarning(
                    gymText(
                        "Set added, but old local rest controls could not be fully cleared.",
                        "Підхід додано, але старі локальні елементи відпочинку не вдалося повністю очистити.",
                        "Подход добавлен, но старые локальные элементы отдыха не удалось полностью очистить.",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
        } catch {
            show(error)
        }
    }

    private func finish(_ draft: ActiveWorkoutDraft) {
        do {
            let workout = try activeWorkoutStore.finish(
                draftID: draft.id,
                expectedRevision: draft.revision,
                into: workoutStore
            )
            do {
                try liveWorkoutCoordinator.localWorkoutWasFinished(localDraftID: draft.id)
            } catch {
                reportStatus(gymSafeEnglishErrorMessage(error), true)
            }
            restTimers.cancel(id: timerKey(draftID: draft.id))
            onFinished(workout.id)
        } catch {
            show(error)
        }
    }

    private func discard() {
        guard !liveWorkoutCoordinator.isAttachedToCurrentDraft else {
            show(LiveWorkoutSidecarError.invalidState)
            return
        }
        guard let draft = currentDraft else {
            onDiscarded()
            return
        }
        do {
            try activeWorkoutStore.discard(
                draftID: draft.id,
                expectedRevision: draft.revision
            )
            restTimers.cancel(id: timerKey(draftID: draft.id))
            reportStatus(
                gymText(
                    "Active workout discarded.",
                    "Активне тренування відкинуто.",
                    "Активная тренировка удалена.",
                    languageCode: gymCurrentLanguageCode()
                ),
                false
            )
            onDiscarded()
        } catch {
            show(error)
        }
    }

    private func timerKey(draftID: UUID) -> String {
        ActiveWorkoutRestReconciler.timerID(for: draftID)
    }

    private func reconcileRestProjection() {
        guard let draft = currentDraft else { return }
        do {
            let outcome = try ActiveWorkoutRestReconciler.reconcile(
                draft: draft,
                store: activeWorkoutStore,
                manager: restTimers,
                title: currentRestExerciseName(draft)
            )
            guard outcome != .synchronized else { return }
            showRestProjectionWarning(
                gymText(
                    "Workout progress was restored, but rest-timer recovery was incomplete. Rest was stopped safely.",
                    "Прогрес тренування відновлено, але відновлення таймера відпочинку не завершено. Відпочинок безпечно зупинено.",
                    "Прогресс тренировки восстановлен, но восстановление таймера отдыха не завершено. Отдых безопасно остановлен.",
                    languageCode: gymCurrentLanguageCode()
                )
            )
        } catch {
            show(error)
        }
    }

    private func showRestProjectionWarning(_ message: String) {
        statusMessage = message
        statusIsError = true
    }

    private func applyActiveWorkoutActionStatus(
        liveQueueFailure: String?,
        restProjectionWarning: String?,
        success: String
    ) {
        let resolved = activeWorkoutActionStatus(
            liveQueueFailure: liveQueueFailure,
            restProjectionWarning: restProjectionWarning,
            success: success
        )
        statusMessage = resolved.message
        statusIsError = resolved.isError
    }

    private func showActionFailure(
        _ error: Error,
        liveQueueFailure: String?
    ) {
        guard let liveQueueFailure else {
            show(error)
            return
        }
        applyActiveWorkoutActionStatus(
            liveQueueFailure: liveQueueFailure,
            restProjectionWarning: gymErrorMessage(error),
            success: ""
        )
    }

    private func collapseCompletedExercises() {
        guard let draft = currentDraft else { return }
        let currentExerciseID = draft.exercises.first(where: { exercise in
            exercise.sets.contains(where: { !$0.isCompleted })
        })?.id
        let undoableExerciseID = draft.undoableSetID.flatMap { undoableSetID in
            draft.exercises.first(where: { exercise in
                exercise.sets.contains(where: { $0.id == undoableSetID })
            })?.id
        }
        collapsedExerciseIDs = Set(
            draft.exercises.compactMap { exercise in
                exercise.id == currentExerciseID || exercise.id == undoableExerciseID
                    ? nil
                    : exercise.id
            }
        )
    }

    private static func clock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        let hours = seconds / 3_600
        let minutes = seconds % 3_600 / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }

    private func show(_ error: Error) {
        statusMessage = gymErrorMessage(error)
        statusIsError = true
    }
}
