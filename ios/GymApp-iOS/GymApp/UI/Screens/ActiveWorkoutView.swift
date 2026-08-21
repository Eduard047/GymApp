import Foundation
import SwiftUI

enum ActiveWorkoutRestReconciliationOutcome: Equatable {
    case synchronized
    case restStoppedBecauseTimerUnavailable
    case timerCleanupPending
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
    @ObservedObject private var workoutStore: WorkoutStore
    @ObservedObject private var activeWorkoutStore: ActiveWorkoutStore
    @ObservedObject private var liveWorkoutCoordinator: LiveWorkoutCoordinator
    @ObservedObject private var restTimers: RestTimerManager

    private let draftID: UUID
    private let onFinished: (UUID) -> Void
    private let onClose: () -> Void
    private let onDiscarded: () -> Void
    private let reportStatus: (String, Bool) -> Void

    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showingDiscardConfirmation = false
    @State private var collapsedExerciseIDs = Set<UUID>()
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
        .navigationTitle(
            gymText(
                "Active workout",
                "Активне тренування",
                "Активная тренировка",
                languageCode: gymCurrentLanguageCode()
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(
                    gymText(
                        "Back",
                        "Назад",
                        "Назад",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    action: onClose
                )
                .accessibilityHint(
                    gymText(
                        "Closes the screen; all changes are already saved",
                        "Закриває екран; усі зміни вже збережено",
                        "Закрывает экран; все изменения уже сохранены",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
            if !liveWorkoutCoordinator.isAttachedToCurrentDraft {
                ToolbarItem(placement: .destructiveAction) {
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
        .onChange(of: liveWorkoutCoordinator.attachedRoomID) { roomID in
            if roomID == nil { liveParticipantSelection = .current }
        }
    }

    private var currentDraft: ActiveWorkoutDraft? {
        guard let draft = activeWorkoutStore.draft, draft.id == draftID else { return nil }
        return draft
    }

    private func progressPanel(_ draft: ActiveWorkoutDraft) -> some View {
        GymHeroPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label(
                    gymText(
                        "Workout in progress",
                        "Тренування триває",
                        "Тренировка идёт",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    systemImage: "figure.strengthtraining.traditional"
                )
                .font(.title2.bold())

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
                    .foregroundStyle(Color.white.opacity(0.84))
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    GymInfoPill(
                        "\(draft.completedSetCount) / \(draft.plannedSetCount)",
                        systemImage: "checkmark.circle.fill",
                        accent: .white
                    )
                    GymInfoPill(
                        gymFormattedDate(draft.startedAt, date: .omitted, time: .shortened),
                        systemImage: "clock.fill",
                        accent: .white
                    )
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        GymInfoPill(
                            Self.clock(draft.totalElapsedSeconds(at: context.date)),
                            systemImage: "stopwatch.fill",
                            accent: .white
                        )
                        .accessibilityLabel(
                            gymText(
                                "Workout time",
                                "Загальний час тренування",
                                "Общее время тренировки",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                    }
                }

                ProgressView(
                    value: Double(draft.completedSetCount),
                    total: Double(max(1, draft.plannedSetCount))
                )
                .tint(.white)
                .accessibilityLabel(
                    gymText(
                        "Workout progress",
                        "Прогрес тренування",
                        "Прогресс тренировки",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                .accessibilityValue("\(draft.completedSetCount) / \(draft.plannedSetCount)")

            }
        }
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
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(GymTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 72, alignment: .leading)
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
        let isCollapsed = collapsedExerciseIDs.contains(exercise.id)
        return GymPanel(highlighted: !fullyCompleted) {
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
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        setRow(
                            set,
                            position: index,
                            exercise: exercise,
                            exerciseName: exerciseName,
                            draft: draft
                        )
                    }

                    Button {
                        appendSet(to: exercise)
                    } label: {
                        Label(
                            gymText(
                                "Add set",
                                "Додати підхід",
                                "Добавить подход",
                                languageCode: gymCurrentLanguageCode()
                            ),
                            systemImage: "plus.circle"
                        )
                    }
                    .buttonStyle(GymSecondaryButtonStyle())
                    .disabled(
                        storedExercise == nil || draft.commitIntent != nil ||
                            liveWorkoutCoordinator.planIsFrozenForCurrentDraft
                    )

                    Button {
                        saveExercise(exercise, draft: draft)
                    } label: {
                        Label(
                            gymText(
                                "Save exercise",
                                "Зберегти вправу",
                                "Сохранить упражнение",
                                languageCode: gymCurrentLanguageCode()
                            ),
                            systemImage: "checkmark.circle.fill"
                        )
                    }
                    .buttonStyle(GymPrimaryButtonStyle())
                    .disabled(
                        storedExercise == nil || draft.commitIntent != nil ||
                            liveWorkoutCoordinator.planIsFrozenForCurrentDraft
                    )
                }
            }
        }
    }

    private func setRow(
        _ set: ActiveWorkoutSet,
        position: Int,
        exercise: ActiveWorkoutExercise,
        exerciseName: String,
        draft: ActiveWorkoutDraft
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(
                    gymText(
                        "Set \(position + 1)",
                        "Підхід \(position + 1)",
                        "Подход \(position + 1)",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                .font(.subheadline.bold())
                Spacer(minLength: 8)
                if set.isCompleted {
                    Label(
                        gymText(
                            "Recorded",
                            "Записано",
                            "Записано",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(GymTheme.secondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    setEditors(set: set, draft: draft)
                }
                VStack(spacing: 10) {
                    setEditors(set: set, draft: draft)
                }
            }

        }
        .padding(12)
        .background(
            set.isCompleted ? GymTheme.secondary.opacity(0.18) : GymTheme.surfaceVariant.opacity(0.48),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    set.isCompleted ? GymTheme.secondary.opacity(0.65) : Color.clear,
                    lineWidth: set.isCompleted ? 1.5 : 0
                )
        }
    }

    @ViewBuilder
    private func setEditors(
        set: ActiveWorkoutSet,
        draft: ActiveWorkoutDraft
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(
                gymText(
                    "Weight",
                    "Вага",
                    "Вес",
                    languageCode: gymCurrentLanguageCode()
                )
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(GymTheme.textSecondary)
            TextField(
                "0",
                value: weightBinding(setID: set.id),
                format: .number.precision(.fractionLength(0 ... 2))
            )
            .keyboardType(.decimalPad)
            .gymTextFieldChrome()
            .disabled(
                draft.commitIntent != nil || liveWorkoutCoordinator.planIsFrozenForCurrentDraft
            )
        }
        .frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: 5) {
            Text(
                gymText(
                    "Repetitions",
                    "Повторення",
                    "Повторения",
                    languageCode: gymCurrentLanguageCode()
                )
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(GymTheme.textSecondary)
            Stepper(value: repsBinding(setID: set.id), in: 1 ... 10_000) {
                Text(set.reps.formatted())
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(GymTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            .disabled(
                draft.commitIntent != nil || liveWorkoutCoordinator.planIsFrozenForCurrentDraft
            )
        }
        .frame(maxWidth: .infinity)
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
                reportStatus(gymSafeEnglishErrorMessage(error), true)
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
                    _ = collapsedExerciseIDs.insert(exercise.id)
                }
            }
            if restOutcome == .synchronized {
                statusMessage = gymText(
                    "Set recorded. Rest timer started.",
                    "Підхід записано. Таймер відпочинку запущено.",
                    "Подход записан. Таймер отдыха запущен.",
                    languageCode: gymCurrentLanguageCode()
                )
                statusIsError = false
            } else {
                showRestProjectionWarning(
                    gymText(
                        "Set recorded, but the rest timer could not be saved durably. Rest was stopped.",
                        "Підхід записано, але таймер відпочинку не вдалося надійно зберегти. Відпочинок зупинено.",
                        "Подход записан, но таймер отдыха не удалось надёжно сохранить. Отдых остановлен.",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
        } catch {
            show(error)
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
                reportStatus(gymSafeEnglishErrorMessage(error), true)
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
            statusMessage = restCleanupSucceeded
                ? gymText(
                    "All sets saved.",
                    "Усі підходи збережено.",
                    "Все подходы сохранены.",
                    languageCode: gymCurrentLanguageCode()
                )
                : gymText(
                    "Sets were saved, but old local controls could not be fully cleared.",
                    "Підходи збережено, але старі локальні елементи не вдалося повністю очистити.",
                    "Подходы сохранены, но старые локальные элементы не удалось полностью очистить.",
                    languageCode: gymCurrentLanguageCode()
                )
            statusIsError = !restCleanupSucceeded
        } catch {
            show(error)
        }
    }

    private func undoLatestSet(
        _ set: ActiveWorkoutSet,
        draft: ActiveWorkoutDraft
    ) {
        do {
            let updated = try activeWorkoutStore.undoLatestRecordedSet(
                draftID: draft.id,
                setID: set.id,
                expectedRevision: draft.revision
            )
            do {
                try liveWorkoutCoordinator.localSetWasUndone(localSetID: set.id)
            } catch {
                reportStatus(gymSafeEnglishErrorMessage(error), true)
            }
            let restOutcome = try ActiveWorkoutRestReconciler.reconcile(
                draft: updated,
                store: activeWorkoutStore,
                manager: restTimers,
                title: currentRestExerciseName(updated)
            )
            statusMessage = gymText(
                restOutcome == .synchronized
                    ? "Latest set restored for editing. Rest stopped."
                    : "Latest set restored, but old rest cleanup must be retried.",
                restOutcome == .synchronized
                    ? "Останній підхід повернуто до редагування. Відпочинок зупинено."
                    : "Останній підхід відновлено, але очищення старого відпочинку треба повторити.",
                restOutcome == .synchronized
                    ? "Последний подход возвращён к редактированию. Отдых остановлен."
                    : "Последний подход восстановлен, но очистку старого отдыха нужно повторить.",
                languageCode: gymCurrentLanguageCode()
            )
            statusIsError = restOutcome != .synchronized
        } catch {
            show(error)
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
            _ = try activeWorkoutStore.saveExercise(
                draftID: draft.id,
                exerciseBlockID: exercise.id,
                expectedRevision: draft.revision
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                collapsedExerciseIDs.insert(exercise.id)
            }
            statusMessage = gymText(
                "Exercise saved.", "Вправу збережено.", "Упражнение сохранено.",
                languageCode: gymCurrentLanguageCode()
            )
            statusIsError = false
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
            try activeWorkoutStore.appendSet(
                draftID: draft.id,
                exerciseBlockID: exercise.id,
                weight: source?.weight ?? workoutStore.lastWeight(exerciseID: exercise.exerciseID) ?? 0,
                reps: source?.reps ?? 10,
                expectedRevision: draft.revision
            )
            statusMessage = nil
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

    private func collapseCompletedExercises() {
        guard let draft = currentDraft else { return }
        collapsedExerciseIDs.formUnion(
            draft.exercises.compactMap { exercise in
                exercise.sets.allSatisfy(\.isCompleted) ? exercise.id : nil
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
