import SwiftUI
import UIKit

enum SocialActivityPresentationState: Equatable {
    case privateData
    case temporarilyUnavailable
    case empty
    case available
}

func socialActivityPresentationState(
    isShared: Bool,
    activityUpdatedAt: String?,
    itemCount: Int
) -> SocialActivityPresentationState {
    guard isShared else { return .privateData }
    guard activityUpdatedAt != nil else { return .temporarilyUnavailable }
    return itemCount == 0 ? .empty : .available
}

struct SocialRecentWorkoutRow: Identifiable, Equatable {
    let id: Int
    let workout: SocialRecentWorkout
}

func socialRecentWorkoutRows(_ workouts: [SocialRecentWorkout]) -> [SocialRecentWorkoutRow] {
    workouts.enumerated().map { SocialRecentWorkoutRow(id: $0.offset, workout: $0.element) }
}

enum SocialWorkoutInvitePreparationDecision: Equatable {
    case blockedByActiveWorkout
    case confirmEditableCopy
    case confirmPendingReplacement(UUID)
}

func socialWorkoutInvitePreparationDecision(
    canAcceptWorkoutInvites: Bool,
    pendingSharedWorkoutID: UUID?
) -> SocialWorkoutInvitePreparationDecision {
    guard canAcceptWorkoutInvites else { return .blockedByActiveWorkout }
    if let pendingSharedWorkoutID {
        return .confirmPendingReplacement(pendingSharedWorkoutID)
    }
    return .confirmEditableCopy
}

struct SocialRecordMetricLabels: Equatable {
    let maximumWeight: String
    let maximumRepetitions: String
}

func socialRecordMetricLabels(
    _ record: SocialExerciseRecord,
    languageCode: String
) -> SocialRecordMetricLabels {
    let weight = record.bestWeightKg.formatted(.number.precision(.fractionLength(0 ... 2)))
    return SocialRecordMetricLabels(
        maximumWeight: "\(gymText("Max weight", "Макс. вага", "Макс. вес", languageCode: languageCode)): \(weight) kg",
        maximumRepetitions: "\(gymText("Max reps", "Макс. повтори", "Макс. повторы", languageCode: languageCode)): \(record.bestReps)"
    )
}

@MainActor
struct FriendsView: View {
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    @ObservedObject private var appState: AppState
    @ObservedObject private var auth: AuthService
    @ObservedObject private var liveWorkoutCoordinator: LiveWorkoutCoordinator
    @AccessibilityFocusState private var focusedNativePushTarget: NativePushProfileFocus?

    private let canAcceptWorkoutInvites: Bool
    private let nativePushAccessibilityTarget: NativePushProfileFocus?
    private let onOpenAccountSettings: () -> Void
    private let onOpenLiveWorkout: () -> Void

    @State private var friendCode = ""
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isLoading = false
    @State private var activeActionID: String?
    @State private var privacyDraft: SocialPrivacy?
    @State private var privacyIsDirty = false
    @State private var workoutDetailPrivacyDraft: Bool?
    @State private var workoutDetailPrivacyIsDirty = false
    @State private var confirmation: FriendsConfirmation?

    init(
        appState: AppState,
        auth: AuthService,
        canAcceptWorkoutInvites: Bool,
        liveWorkoutCoordinator: LiveWorkoutCoordinator,
        nativePushAccessibilityTarget: NativePushProfileFocus? = nil,
        onOpenAccountSettings: @escaping () -> Void,
        onOpenLiveWorkout: @escaping () -> Void
    ) {
        self.appState = appState
        self.auth = auth
        self.canAcceptWorkoutInvites = canAcceptWorkoutInvites
        self.liveWorkoutCoordinator = liveWorkoutCoordinator
        self.nativePushAccessibilityTarget = nativePushAccessibilityTarget
        self.onOpenAccountSettings = onOpenAccountSettings
        self.onOpenLiveWorkout = onOpenLiveWorkout
    }

    var body: some View {
        LazyVStack(spacing: GymTheme.contentSpacing) {
            if !isCloudAccount {
                localAccountState
            } else {
                hero

                if let errorMessage {
                    GymStatusBanner(message: errorMessage, isError: true)
                }
                if let statusMessage {
                    GymStatusBanner(message: statusMessage, isError: false)
                }

                if let dashboard = appState.socialDashboard {
                    liveWorkoutCard
                    workoutInvitesCard
                    requestsCard(dashboard)
                    friendsRankingCard(dashboard)
                    addFriendCard
                    friendCodeCard(dashboard)
                    privacyCard(dashboard)
                    blockedCard(dashboard)
                } else if isLoading {
                    GymPanel {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(t("Loading Friends…", "Завантажуємо друзів…", "Загружаем друзей…"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    unavailableCard
                }
            }
        }
        .task(id: auth.session?.storageKey) {
            privacyDraft = nil
            privacyIsDirty = false
            workoutDetailPrivacyDraft = nil
            workoutDetailPrivacyIsDirty = false
            await refreshAll()
        }
        .task(id: nativePushAccessibilityTarget) {
            await Task.yield()
            focusedNativePushTarget = nativePushAccessibilityTarget
        }
        .onChange(of: appState.socialDashboard?.currentUser.settingsRevision) { _ in
            guard !privacyIsDirty else { return }
            privacyDraft = appState.socialDashboard?.currentUser.privacy
        }
        .onReceive(NotificationCenter.default.publisher(for: .gymAppSocialChanged)) { note in
            guard note.object as? String == auth.session?.cloud?.userID else { return }
            Task { await refreshAll(force: true) }
        }
        .alert(item: $confirmation, content: confirmationAlert)
    }

    private var isCloudAccount: Bool {
        auth.session?.cloud != nil
    }

    private var localAccountState: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    t("Friends need a cloud account", "Для друзів потрібен хмарний акаунт", "Для друзей нужен облачный аккаунт"),
                    systemImage: "person.2.slash"
                )
                .font(.headline)
                Text(
                    t(
                        "Open account settings to switch to a cloud account. Offline workouts stay on this iPhone.",
                        "Відкрий налаштування акаунта, щоб перейти до хмарного акаунта. Офлайн-тренування залишаться на цьому iPhone.",
                        "Открой настройки аккаунта, чтобы перейти в облачный аккаунт. Офлайн-тренировки останутся на этом iPhone."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(GymTheme.textSecondary)
                Button(action: onOpenAccountSettings) {
                    Label(
                        t(
                            "Open account settings",
                            "Відкрити налаштування акаунта",
                            "Открыть настройки аккаунта"
                        ),
                        systemImage: "person.crop.circle.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymPrimaryButtonStyle())
            }
        }
    }

    private var hero: some View {
        GymHeroPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Label(t("Friends", "Друзі", "Друзья"), systemImage: "person.2.fill")
                        .font(.title2.bold())
                    Spacer(minLength: 8)
                    if let dashboard = appState.socialDashboard,
                       dashboard.currentUser.statsAvailable,
                       let xp = dashboard.currentUser.xp,
                       let level = dashboard.currentUser.level {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(xp) XP").font(.title3.bold().monospacedDigit())
                            Text("\(t("Level", "Рівень", "Уровень")) \(level)")
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.76))
                        }
                    }
                }
                Button {
                    Task { await refreshAll(force: true) }
                } label: {
                    Label(
                        isLoading
                            ? t("Refreshing…", "Оновлюємо…", "Обновляем…")
                            : t("Refresh Friends", "Оновити друзів", "Обновить друзей"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .disabled(isLoading)
            }
        }
    }

    private func friendCodeCard(_ dashboard: SocialDashboard) -> some View {
        let canonicalCode = appState.socialFriendCode ?? dashboard.currentUser.friendCode
        let displayCode = SocialFriendCode.display(canonicalCode)
        return GymPanel {
            VStack(alignment: .leading, spacing: 10) {
                GymSectionTitle(
                    title: t("Your friend code", "Твій код друга", "Твой код друга")
                )
                Text(displayCode)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GymTheme.surfaceVariant, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = displayCode
                        statusMessage = t("Friend code copied.", "Код друга скопійовано.", "Код друга скопирован.")
                    } label: {
                        Label(t("Copy", "Копіювати", "Копировать"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    ShareLink(
                        item: displayCode,
                        subject: Text(t("GymApp friend code", "Код друга GymApp", "Код друга GymApp")),
                        message: Text(
                            t(
                                "Add me in GymApp with this friend code.",
                                "Додай мене в GymApp за цим кодом друга.",
                                "Добавь меня в GymApp по этому коду друга."
                            )
                        )
                    ) {
                        Label(t("Share", "Поділитися", "Поделиться"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var addFriendCard: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 10) {
                GymSectionTitle(
                    title: t("Add a friend", "Додати друга", "Добавить друга")
                )
                TextField(t("Friend code", "Код друга", "Код друга"), text: $friendCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await sendFriendRequest() }
                } label: {
                    Label(t("Send request", "Надіслати запит", "Отправить запрос"), systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymPrimaryButtonStyle())
                .disabled(activeActionID != nil || !validEnteredFriendCode)
            }
        }
    }

    private func requestsCard(_ dashboard: SocialDashboard) -> some View {
        return GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: t("Friend requests", "Запити в друзі", "Запросы в друзья"),
                    supporting: t(
                        "Accepting shares only the categories enabled in Privacy below.",
                        "Після прийняття друг побачить лише категорії, увімкнені в налаштуваннях приватності нижче.",
                        "После принятия друг увидит только категории, включённые в настройках приватности ниже."
                    )
                )
                if dashboard.incoming.isEmpty, dashboard.outgoing.isEmpty {
                    empty(t("No pending friend requests.", "Немає запитів у друзі.", "Нет запросов в друзья."))
                }
                ForEach(dashboard.incoming) { request in
                    requestRow(request, incoming: true)
                }
                ForEach(dashboard.outgoing) { request in
                    requestRow(request, incoming: false)
                }
            }
        }
    }

    private func requestRow(_ request: SocialFriendRequest, incoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.displayName).font(.headline)
                    Text(incoming
                         ? t("Wants to be your friend", "Хоче додатися в друзі", "Хочет добавиться в друзья")
                         : t("Waiting for a response", "Очікує відповіді", "Ожидает ответа"))
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                }
                Spacer()
                if activeActionID == request.friendshipID { ProgressView() }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    requestActionButtons(request, incoming: incoming)
                }
                VStack(spacing: 8) {
                    requestActionButtons(request, incoming: incoming)
                }
            }
            .disabled(activeActionID != nil)
        }
        .padding(.vertical, 4)
        .id(NativePushProfileFocus.friendRequest(request.friendshipID))
        .accessibilityFocused(
            $focusedNativePushTarget,
            equals: .friendRequest(request.friendshipID)
        )
    }

    @ViewBuilder
    private func requestActionButtons(
        _ request: SocialFriendRequest,
        incoming: Bool
    ) -> some View {
        if incoming {
            Button {
                Task { await respond(request, accept: true) }
            } label: {
                Text(t("Accept", "Прийняти", "Принять"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                Task { await respond(request, accept: false) }
            } label: {
                Text(t("Decline", "Відхилити", "Отклонить"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                confirmation = .blockRequest(request)
            } label: {
                Text(t("Block", "Заблокувати", "Заблокировать"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            Button(role: .destructive) {
                Task { await cancel(request) }
            } label: {
                Text(t("Cancel request", "Скасувати запит", "Отменить запрос"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var workoutInvitesCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: t("Workout invitations", "Запрошення на тренування", "Приглашения на тренировку"),
                    supporting: t(
                        "Accepting creates an independent local copy. Later edits are never synchronized between friends.",
                        "Після прийняття створюється незалежна локальна копія. Подальші зміни між друзями не синхронізуються.",
                        "После принятия создаётся независимая локальная копия. Дальнейшие изменения между друзьями не синхронизируются."
                    )
                )
                if let inbox = appState.socialWorkoutInbox {
                    let incoming = inbox.incoming
                    let outgoing = inbox.outgoing.filter { $0.status == .pending }
                    if incoming.isEmpty, outgoing.isEmpty {
                        empty(t("No workout invitations.", "Немає запрошень на тренування.", "Нет приглашений на тренировку."))
                    }
                    ForEach(incoming) { invite in
                        workoutInviteRow(invite, incoming: true)
                    }
                    ForEach(outgoing) { invite in
                        workoutInviteRow(invite, incoming: false)
                    }
                    if inbox.nextCursor != nil {
                        Button {
                            Task { await loadMoreWorkoutInvites() }
                        } label: {
                            Text(t(
                                "Load more invitations",
                                "Завантажити більше запрошень",
                                "Загрузить больше приглашений"
                            ))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(activeActionID != nil)
                    }
                } else if isLoading {
                    ProgressView()
                } else {
                    empty(t("Workout inbox is unavailable.", "Вхідні тренування недоступні.", "Входящие тренировки недоступны."))
                }
            }
        }
    }

    private var liveWorkoutCard: some View {
        GymPanel(highlighted: liveWorkoutCoordinator.pendingInvitationCount > 0) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: t("Live workouts", "Живі тренування", "Живые тренировки"),
                    supporting: t(
                        "The plan is frozen for two people. Accepting starts it for both immediately; each person edits only their own sets.",
                        "План зафіксований для двох. Прийняття одразу запускає його для обох; кожен редагує лише свої підходи.",
                        "План зафиксирован для двоих. Принятие сразу запускает его для обоих; каждый редактирует только свои подходы."
                    )
                )

                if let message = liveWorkoutCoordinator.lastError {
                    GymStatusBanner(message: message, isError: true)
                } else if let message = liveWorkoutCoordinator.lastStatus {
                    GymStatusBanner(message: message, isError: false)
                }

                let invitations = liveWorkoutCoordinator.inbox?.invitations ?? []
                let rooms = liveWorkoutCoordinator.inbox?.rooms ?? []
                if invitations.isEmpty, rooms.isEmpty {
                    empty(t("No live workout invitations.", "Немає живих запрошень.", "Нет живых приглашений."))
                }

                ForEach(invitations) { invitation in
                    VStack(alignment: .leading, spacing: 8) {
                        liveWorkoutSummary(
                            name: invitation.owner.displayName,
                            summary: invitation.summary,
                            state: t("Invites you to train live", "Запрошує тренуватися наживо", "Приглашает тренироваться вживую")
                        )
                        HStack(spacing: 8) {
                            Button(t("Start together", "Почати разом", "Начать вместе")) {
                                Task { await respondToLiveInvitation(invitation, accept: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                !canAcceptWorkoutInvites
                                    || appState.pendingSharedWorkout != nil
                                    || liveWorkoutCoordinator.isRestoring(roomID: invitation.roomID)
                            )

                            Button(t("Decline", "Відхилити", "Отклонить"), role: .destructive) {
                                Task { await respondToLiveInvitation(invitation, accept: false) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .disabled(activeActionID != nil)
                        if !canAcceptWorkoutInvites || appState.pendingSharedWorkout != nil {
                            Text(
                                t(
                                    "Finish or close the current workout draft before joining.",
                                    "Заверши або закрий поточну чернетку тренування перед приєднанням.",
                                    "Заверши или закрой текущий черновик тренировки перед присоединением."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .id(NativePushProfileFocus.liveRoom(invitation.roomID))
                    .accessibilityFocused(
                        $focusedNativePushTarget,
                        equals: .liveRoom(invitation.roomID)
                    )
                }

                ForEach(rooms) { room in
                    VStack(alignment: .leading, spacing: 8) {
                        liveWorkoutSummary(
                            name: room.peer.displayName,
                            summary: room.summary,
                            state: liveRoomState(room)
                        )
                        HStack(spacing: 8) {
                            if room.status == .ready || room.status == .active {
                                Button(
                                    room.status == .active
                                        ? t("Open workout", "Відкрити тренування", "Открыть тренировку")
                                        : t("Restore workout", "Відновити тренування", "Восстановить тренировку")
                                ) {
                                    Task { await openLiveRoom(room) }
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            if room.role == .owner {
                                Button(t("Cancel room", "Скасувати кімнату", "Отменить комнату"), role: .destructive) {
                                    Task { await closeLiveRoom(room, leave: false) }
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button(t("Leave room", "Вийти з кімнати", "Выйти из комнаты"), role: .destructive) {
                                    Task { await closeLiveRoom(room, leave: true) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .disabled(activeActionID != nil)
                    }
                    .padding(.vertical, 4)
                    .id(NativePushProfileFocus.liveRoom(room.roomID))
                    .accessibilityFocused(
                        $focusedNativePushTarget,
                        equals: .liveRoom(room.roomID)
                    )
                }

                HStack(spacing: 8) {
                    Label(
                        liveWorkoutCoordinator.realtimeConnected
                            ? t("Live updates connected", "Живі оновлення підключено", "Живые обновления подключены")
                            : t("Live updates with polling fallback", "Живі оновлення з резервним опитуванням", "Живые обновления с резервным опросом"),
                        systemImage: liveWorkoutCoordinator.realtimeConnected ? "bolt.horizontal.circle.fill" : "arrow.clockwise.circle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GymTheme.textSecondary)
                    Spacer()
                    Button {
                        Task { await liveWorkoutCoordinator.refreshAll(showErrors: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(liveWorkoutCoordinator.isRefreshing)
                    .accessibilityLabel(t("Refresh live workouts", "Оновити живі тренування", "Обновить живые тренировки"))
                }
            }
        }
        .id(NativePushProfileFocus.liveWorkouts)
        .accessibilityFocused($focusedNativePushTarget, equals: .liveWorkouts)
    }

    private func liveWorkoutSummary(
        name: String,
        summary: LiveWorkoutSummary,
        state: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wave.3.right.circle.fill")
                .foregroundStyle(GymTheme.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(state).font(.caption.bold()).foregroundStyle(GymTheme.primary)
                Text(
                    "\(summary.exerciseCount) \(t("exercises", "вправ", "упражнений")) · \(summary.setCount) \(t("sets", "підходів", "подходов"))"
                )
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
                Text(summary.exerciseNames.prefix(3).map(localizedExerciseName).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            if activeActionID?.contains(name) == true { ProgressView() }
        }
    }

    private func liveRoomState(_ room: LiveWorkoutOpenRoom) -> String {
        switch room.status {
        case .waiting:
            return t("Waiting for acceptance", "Очікуємо прийняття", "Ожидаем принятия")
        case .ready:
            return t(
                "Confirmed · restoring start",
                "Підтверджено · відновлюємо старт",
                "Подтверждено · восстанавливаем старт"
            )
        case .active:
            return t("Workout is live", "Тренування наживо", "Тренировка вживую")
        default:
            return t("Room closed", "Кімнату закрито", "Комната закрыта")
        }
    }

    private func workoutInviteRow(_ invite: SocialWorkoutInvite, incoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(invite.displayName).font(.headline)
                    Text(
                        "\(invite.summary.exerciseCount) \(t("exercises", "вправ", "упражнений")) · \(invite.summary.setCount) \(t("sets", "підходів", "подходов"))"
                    )
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                }
                Spacer()
                if activeActionID == invite.inviteID { ProgressView() }
            }
            Text(invite.summary.exerciseNames.prefix(3).map(localizedExerciseName).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
                .lineLimit(2)
            if incoming, invite.status == .accepted {
                Text(
                    t(
                        "Accepted · recovery copy available",
                        "Прийнято · доступна копія для відновлення",
                        "Принято · доступна копия для восстановления"
                    )
                )
                .font(.caption.bold())
                .foregroundStyle(GymTheme.primary)
            }
            HStack(spacing: 8) {
                if incoming, invite.status == .pending {
                    Button(t("Accept workout", "Прийняти тренування", "Принять тренировку")) {
                        prepareWorkoutInvite(invite, action: .accept)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(t("Decline", "Відхилити", "Отклонить"), role: .destructive) {
                        Task { await respondWorkoutInvite(invite, accept: false) }
                    }
                    .buttonStyle(.bordered)
                } else if incoming, invite.status == .accepted {
                    Button(t("Open local copy", "Відкрити локальну копію", "Открыть локальную копию")) {
                        prepareWorkoutInvite(invite, action: .recover)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(t("Cancel invite", "Скасувати запрошення", "Отменить приглашение"), role: .destructive) {
                        Task { await cancelWorkoutInvite(invite) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .disabled(activeActionID != nil)
        }
        .padding(.vertical, 4)
        .id(NativePushProfileFocus.workoutInvite(invite.inviteID))
        .accessibilityFocused(
            $focusedNativePushTarget,
            equals: .workoutInvite(invite.inviteID)
        )
    }

    private func friendsRankingCard(_ dashboard: SocialDashboard) -> some View {
        let ranked = rankedProfiles(dashboard)
        let unranked = dashboard.friends.filter { !$0.statsAvailable }
        return GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: t("Friends ranking", "Рейтинг друзів", "Рейтинг друзей")
                )
                if dashboard.friends.isEmpty {
                    empty(t("Add a friend to start comparing progress.", "Додай друга, щоб порівнювати прогрес.", "Добавь друга, чтобы сравнивать прогресс."))
                }
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, item in
                    rankedRow(item, place: index + 1)
                }
                ForEach(unranked) { friend in
                    NavigationLink {
                        FriendDetailView(
                            friend: friend,
                            appState: appState,
                            liveWorkoutCoordinator: liveWorkoutCoordinator
                        )
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.displayName).font(.headline)
                                Text(friend.progressShared
                                     ? t("Synced progress unavailable", "Синхронізований прогрес недоступний", "Синхронизированный прогресс недоступен")
                                     : t("Progress is private", "Прогрес приватний", "Прогресс скрыт"))
                                    .font(.caption)
                                    .foregroundStyle(GymTheme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(NativePushProfileFocus.friendRequest(friend.friendshipID))
                    .accessibilityFocused(
                        $focusedNativePushTarget,
                        equals: .friendRequest(friend.friendshipID)
                    )
                }
            }
        }
    }

    private func rankedRow(_ item: RankedSocialProfile, place: Int) -> some View {
        Group {
            if let friend = item.friend {
                NavigationLink {
                    FriendDetailView(
                        friend: friend,
                        appState: appState,
                        liveWorkoutCoordinator: liveWorkoutCoordinator
                    )
                } label: {
                    rankingRowContent(item, place: place)
                }
                .buttonStyle(.plain)
                .id(NativePushProfileFocus.friendRequest(friend.friendshipID))
                .accessibilityFocused(
                    $focusedNativePushTarget,
                    equals: .friendRequest(friend.friendshipID)
                )
            } else {
                rankingRowContent(item, place: place)
            }
        }
    }

    private func rankingRowContent(_ item: RankedSocialProfile, place: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(place)")
                .font(.headline.monospacedDigit())
                .frame(width: 26, height: 26)
                .background(place <= 3 ? GymTheme.primary.opacity(0.16) : GymTheme.surfaceVariant)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName).font(.headline)
                    if item.isCurrentUser {
                        Text(t("You", "Ти", "Ты"))
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(GymTheme.primary.opacity(0.14), in: Capsule())
                    }
                }
                Text("\(t("Level", "Рівень", "Уровень")) \(item.level) · \(item.workouts) \(t("workouts", "тренувань", "тренировок"))")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
            }
            Spacer()
            Text("\(item.xp) XP").font(.subheadline.bold().monospacedDigit())
            if item.friend != nil { Image(systemName: "chevron.right").font(.caption) }
        }
        .contentShape(Rectangle())
    }

    private func privacyCard(_ dashboard: SocialDashboard) -> some View {
        let draft = privacyDraft ?? dashboard.currentUser.privacy
        return GymPanel {
            VStack(alignment: .leading, spacing: 10) {
                GymSectionTitle(
                    title: t("What friends can see", "Що бачать друзі", "Что видят друзья"),
                    supporting: t(
                        "Changes apply server-side to every accepted friend.",
                        "Зміни застосовуються на сервері для всіх прийнятих друзів.",
                        "Изменения применяются на сервере для всех принятых друзей."
                    )
                )
                privacyToggle(
                    t("Allow new friend requests", "Дозволити нові запити в друзі", "Разрешить новые запросы в друзья"),
                    value: draft.allowRequests,
                    keyPath: \.allowRequests
                )
                privacyToggle(
                    t("Share XP, level and workout count", "Показувати XP, рівень і кількість тренувань", "Показывать XP, уровень и число тренировок"),
                    value: draft.shareProgress,
                    keyPath: \.shareProgress
                )
                privacyToggle(
                    t("Share five recent workout summaries", "Показувати п’ять останніх тренувань", "Показывать пять последних тренировок"),
                    value: draft.shareRecentWorkouts,
                    keyPath: \.shareRecentWorkouts
                )
                privacyToggle(
                    t("Share exercise records", "Показувати рекорди у вправах", "Показывать рекорды в упражнениях"),
                    value: draft.shareRecords,
                    keyPath: \.shareRecords
                )
                Toggle(
                    t(
                        "Share exercises, weights, and reps",
                        "Показувати вправи, вагу й повтори",
                        "Показывать упражнения, вес и повторения"
                    ),
                    isOn: Binding(
                        get: {
                            workoutDetailPrivacyDraft ??
                                appState.socialWorkoutDetailPrivacy?.shareWorkoutDetails ?? false
                        },
                        set: { value in
                            workoutDetailPrivacyDraft = value
                            workoutDetailPrivacyIsDirty = true
                        }
                    )
                )
                .disabled(appState.socialWorkoutDetailPrivacy == nil)
                Text(t(
                    "Off by default. Friends can open exact sets only when this is enabled.",
                    "Вимкнено за замовчуванням. Друзі зможуть відкрити точні підходи лише після ввімкнення.",
                    "По умолчанию выключено. Друзья смогут открыть точные подходы только после включения."
                ))
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
                Button {
                    Task { await savePrivacy() }
                } label: {
                    Label(t("Save privacy", "Зберегти приватність", "Сохранить приватность"), systemImage: "lock.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .disabled((!privacyIsDirty && !workoutDetailPrivacyIsDirty) || activeActionID != nil)
            }
        }
    }

    private func privacyToggle(
        _ title: String,
        value: Bool,
        keyPath: WritableKeyPath<SocialPrivacy, Bool>
    ) -> some View {
        Toggle(title, isOn: Binding(
            get: { (privacyDraft ?? appState.socialDashboard?.currentUser.privacy)?[keyPath: keyPath] ?? value },
            set: { newValue in
                guard var next = privacyDraft ?? appState.socialDashboard?.currentUser.privacy else { return }
                next[keyPath: keyPath] = newValue
                privacyDraft = next
                privacyIsDirty = true
            }
        ))
    }

    private func blockedCard(_ dashboard: SocialDashboard) -> some View {
        Group {
            if !dashboard.blocked.isEmpty {
                GymPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        GymSectionTitle(
                            title: t("Blocked people", "Заблоковані користувачі", "Заблокированные пользователи"),
                            supporting: t(
                                "Blocked people cannot send friend or workout requests.",
                                "Заблоковані користувачі не можуть надсилати запити в друзі чи тренування.",
                                "Заблокированные пользователи не могут отправлять запросы в друзья или тренировки."
                            )
                        )
                        ForEach(dashboard.blocked) { profile in
                            HStack {
                                Text(profile.displayName).font(.headline)
                                Spacer()
                                Button(t("Unblock", "Розблокувати", "Разблокировать")) {
                                    Task { await unblock(profile) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(activeActionID != nil)
                            }
                        }
                    }
                }
            }
        }
    }

    private var unavailableCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Friends are unavailable", "Друзі недоступні", "Друзья недоступны"))
                    .font(.headline)
                Text(t("Try refreshing. Your workout history was not changed.", "Спробуй оновити. Історію тренувань не змінено.", "Попробуй обновить. История тренировок не изменена."))
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.textSecondary)
                Button(t("Try again", "Спробувати ще", "Повторить")) {
                    Task { await refreshAll(force: true) }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var validEnteredFriendCode: Bool {
        SocialFriendCode.normalize(friendCode) != nil
    }

    private func rankedProfiles(_ dashboard: SocialDashboard) -> [RankedSocialProfile] {
        var profiles: [RankedSocialProfile] = []
        let current = dashboard.currentUser
        if current.statsAvailable,
           let xp = current.xp,
           let level = current.level,
           let workouts = current.workouts {
            profiles.append(RankedSocialProfile(
                id: current.profileID,
                displayName: current.displayName,
                xp: xp,
                level: level,
                workouts: workouts,
                isCurrentUser: true,
                friend: nil
            ))
        }
        profiles.append(contentsOf: dashboard.friends.compactMap { friend in
            guard friend.statsAvailable,
                  let xp = friend.xp,
                  let level = friend.level,
                  let workouts = friend.workouts else { return nil }
            return RankedSocialProfile(
                id: friend.profileID,
                displayName: friend.displayName,
                xp: xp,
                level: level,
                workouts: workouts,
                isCurrentUser: false,
                friend: friend
            )
        })
        return profiles.sorted {
            if $0.xp != $1.xp { return $0.xp > $1.xp }
            if $0.workouts != $1.workouts { return $0.workouts > $1.workouts }
            let nameOrder = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return $0.id < $1.id
        }
    }

    private func refreshAll(force: Bool = false) async {
        guard isCloudAccount, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let dashboard = try await appState.refreshSocialDashboard()
            if !privacyIsDirty { privacyDraft = dashboard.currentUser.privacy }
        } catch {
            errorMessage = socialError(
                t("Could not refresh Friends. Try again.", "Не вдалося оновити друзів. Спробуй ще раз.", "Не удалось обновить друзей. Попробуй ещё раз.")
            )
        }
        do {
            _ = try await appState.refreshSocialWorkoutInbox()
        } catch {
            if appState.socialWorkoutInbox == nil {
                errorMessage = socialError(
                    t("Could not load workout invitations.", "Не вдалося завантажити запрошення на тренування.", "Не удалось загрузить приглашения на тренировку.")
                )
            }
        }
        do {
            let detailPrivacy = try await appState.refreshSocialWorkoutDetailPrivacy()
            if !workoutDetailPrivacyIsDirty {
                workoutDetailPrivacyDraft = detailPrivacy.shareWorkoutDetails
            }
        } catch {
            workoutDetailPrivacyDraft = nil
        }
        await liveWorkoutCoordinator.refreshAll(showErrors: false)
    }

    private func respondToLiveInvitation(
        _ invitation: LiveWorkoutInvitation,
        accept: Bool
    ) async {
        guard activeActionID == nil else { return }
        if accept, (!canAcceptWorkoutInvites || appState.pendingSharedWorkout != nil) {
            errorMessage = t(
                "Finish or close the current workout draft before joining this live room.",
                "Заверши або закрий поточну чернетку тренування перед приєднанням до живої кімнати.",
                "Заверши или закрой текущий черновик тренировки перед присоединением к живой комнате."
            )
            return
        }
        activeActionID = "live-\(invitation.roomID)"
        errorMessage = nil
        defer { activeActionID = nil }
        do {
            let outcome = try await liveWorkoutCoordinator.respond(
                to: invitation,
                accept: accept
            )
            switch outcome {
            case .active:
                statusMessage = t(
                    "Live workout started.",
                    "Спільне тренування почалося.",
                    "Совместная тренировка началась."
                )
                onOpenLiveWorkout()
            case .confirmedRestoring:
                statusMessage = t(
                    "Acceptance confirmed. Restoring the started workout…",
                    "Прийняття підтверджено. Відновлюємо розпочате тренування…",
                    "Принятие подтверждено. Восстанавливаем начатую тренировку…"
                )
            case .declined:
                statusMessage = t(
                    "Live invitation declined.",
                    "Живе запрошення відхилено.",
                    "Живое приглашение отклонено."
                )
            }
        } catch {
            errorMessage = gymSafeEnglishErrorMessage(error)
        }
    }

    private func openLiveRoom(_ room: LiveWorkoutOpenRoom) async {
        guard activeActionID == nil else { return }
        activeActionID = "live-\(room.roomID)"
        errorMessage = nil
        defer { activeActionID = nil }
        do {
            try await liveWorkoutCoordinator.openRoom(room.roomID)
            guard liveWorkoutCoordinator.isAttachedToCurrentDraft else {
                throw LiveWorkoutSidecarError.invalidState
            }
            onOpenLiveWorkout()
        } catch {
            errorMessage = gymSafeEnglishErrorMessage(error)
        }
    }

    private func closeLiveRoom(_ room: LiveWorkoutOpenRoom, leave: Bool) async {
        guard activeActionID == nil else { return }
        activeActionID = "live-\(room.roomID)"
        errorMessage = nil
        defer { activeActionID = nil }
        do {
            try await liveWorkoutCoordinator.openRoom(room.roomID)
            if leave {
                try await liveWorkoutCoordinator.leaveRoom()
            } else {
                try await liveWorkoutCoordinator.cancelRoom()
            }
        } catch {
            errorMessage = gymSafeEnglishErrorMessage(error)
        }
    }

    private func sendFriendRequest() async {
        guard let code = SocialFriendCode.normalize(friendCode) else { return }
        await perform(id: "send-friend") {
            try await appState.sendFriendRequest(friendCode: code)
            friendCode = ""
            statusMessage = confirmedSocialStatus(t(
                "Request submitted if this code can receive requests.",
                "Запит надіслано, якщо цей код може приймати запити.",
                "Запрос отправлен, если этот код может принимать запросы."
            ))
        }
    }

    private func respond(_ request: SocialFriendRequest, accept: Bool) async {
        await perform(id: request.friendshipID) {
            try await appState.respondFriendRequest(request, accept: accept)
            statusMessage = confirmedSocialStatus(accept
                ? t("Friend added.", "Друга додано.", "Друг добавлен.")
                : t("Request declined.", "Запит відхилено.", "Запрос отклонён."))
        }
    }

    private func cancel(_ request: SocialFriendRequest) async {
        await perform(id: request.friendshipID) {
            try await appState.cancelFriendRequest(request)
            statusMessage = confirmedSocialStatus(
                t("Request cancelled.", "Запит скасовано.", "Запрос отменён.")
            )
        }
    }

    private func prepareWorkoutInvite(
        _ invite: SocialWorkoutInvite,
        action: WorkoutInvitePreparation.Action
    ) {
        let decision = socialWorkoutInvitePreparationDecision(
            canAcceptWorkoutInvites: canAcceptWorkoutInvites,
            pendingSharedWorkoutID: appState.pendingSharedWorkout?.id
        )
        guard decision != .blockedByActiveWorkout else {
            errorMessage = t(
                "Finish the active workout before opening this invitation. It remains safely available in Friends.",
                "Заверши активне тренування, перш ніж відкривати це запрошення. Воно безпечно залишиться в Друзях.",
                "Заверши активную тренировку, прежде чем открывать это приглашение. Оно безопасно останется в Друзьях."
            )
            return
        }
        guard (action == .accept && invite.status == .pending) ||
                (action == .recover && invite.status == .accepted) else {
            errorMessage = t(
                "This invitation changed. Refresh Friends before trying again.",
                "Це запрошення змінилося. Онови Друзів і спробуй ще раз.",
                "Это приглашение изменилось. Обнови Друзей и попробуй ещё раз."
            )
            return
        }
        let pendingID: UUID?
        if case .confirmPendingReplacement(let id) = decision {
            pendingID = id
        } else {
            pendingID = nil
        }
        confirmation = .workout(WorkoutInvitePreparation(
            invite: invite,
            action: action,
            pendingID: pendingID
        ))
    }

    private func commitWorkoutInvite(_ preparation: WorkoutInvitePreparation) async {
        switch preparation.action {
        case .accept:
            await respondWorkoutInvite(
                preparation.invite,
                accept: true,
                replacingPendingID: preparation.pendingID
            )
        case .recover:
            await perform(id: preparation.invite.inviteID) {
                _ = try await appState.recoverAcceptedWorkoutInvite(
                    preparation.invite,
                    replacingPendingSharedWorkoutID: preparation.pendingID
                )
                statusMessage = t(
                    "Accepted workout reopened as a local preview.",
                    "Прийняте тренування знову відкрито в локальному перегляді.",
                    "Принятая тренировка снова открыта в локальном просмотре."
                )
            }
        }
    }

    private func respondWorkoutInvite(
        _ invite: SocialWorkoutInvite,
        accept: Bool,
        replacingPendingID: UUID? = nil
    ) async {
        await perform(id: invite.inviteID) {
            _ = try await appState.respondWorkoutInvite(
                invite,
                accept: accept,
                replacingPendingSharedWorkoutID: replacingPendingID
            )
            statusMessage = confirmedSocialStatus(accept
                ? t("Workout copied to a local preview.", "Тренування скопійовано в локальний перегляд.", "Тренировка скопирована в локальный просмотр.")
                : t("Workout invitation declined.", "Запрошення на тренування відхилено.", "Приглашение на тренировку отклонено."))
        }
    }

    private func cancelWorkoutInvite(_ invite: SocialWorkoutInvite) async {
        await perform(id: invite.inviteID) {
            try await appState.cancelWorkoutInvite(invite)
            statusMessage = confirmedSocialStatus(
                t("Workout invitation cancelled.", "Запрошення на тренування скасовано.", "Приглашение на тренировку отменено.")
            )
        }
    }

    private func loadMoreWorkoutInvites() async {
        await perform(id: "workout-inbox-more") {
            _ = try await appState.loadMoreSocialWorkoutInbox()
        }
    }

    private func block(_ request: SocialFriendRequest) async {
        await perform(id: request.profileID) {
            try await appState.blockSocialProfile(profileID: request.profileID)
            statusMessage = confirmedSocialStatus(t(
                "Request sender blocked.",
                "Відправника запиту заблоковано.",
                "Отправитель запроса заблокирован."
            ))
        }
    }

    private func confirmationAlert(_ confirmation: FriendsConfirmation) -> Alert {
        switch confirmation {
        case .blockRequest(let request):
            return Alert(
                title: Text(t("Block this person?", "Заблокувати користувача?", "Заблокировать пользователя?")),
                message: Text(
                    t(
                        "The friend request is removed, and this person cannot send new friend or workout requests until you unblock them.",
                        "Запит у друзі буде видалено, і користувач не зможе надсилати нові запити в друзі чи тренування, доки ти його не розблокуєш.",
                        "Запрос в друзья будет удалён, и пользователь не сможет отправлять новые запросы в друзья или тренировки, пока ты его не разблокируешь."
                    )
                ),
                primaryButton: .destructive(Text(t("Block", "Заблокувати", "Заблокировать"))) {
                    Task { await block(request) }
                },
                secondaryButton: .cancel(Text(t("Cancel", "Скасувати", "Отмена")))
            )
        case .workout(let preparation):
            let replacesPending = preparation.pendingID != nil
            let title = replacesPending
                ? t("Replace shared workout?", "Замінити спільне тренування?", "Заменить общую тренировку?")
                : preparation.action == .accept
                    ? t("Accept workout invitation?", "Прийняти запрошення на тренування?", "Принять приглашение на тренировку?")
                    : t("Open accepted workout?", "Відкрити прийняте тренування?", "Открыть принятую тренировку?")
            let message = replacesPending
                ? t(
                    "The plan currently waiting in preview will be replaced. Your workout history is not changed.",
                    "План, який зараз очікує в перегляді, буде замінено. Історія тренувань не зміниться.",
                    "План, который сейчас ждёт в просмотре, будет заменён. История тренировок не изменится."
                )
                : t(
                    "GymApp will open an independent editable local copy. Later changes are not synchronized with your friend.",
                    "GymApp відкриє незалежну редаговану локальну копію. Подальші зміни не синхронізуються з другом.",
                    "GymApp откроет независимую редактируемую локальную копию. Дальнейшие изменения не синхронизируются с другом."
                )
            let actionTitle = replacesPending
                ? t("Replace", "Замінити", "Заменить")
                : t("Open copy", "Відкрити копію", "Открыть копию")
            let primary: Alert.Button = replacesPending
                ? .destructive(Text(actionTitle)) { Task { await commitWorkoutInvite(preparation) } }
                : .default(Text(actionTitle)) { Task { await commitWorkoutInvite(preparation) } }
            return Alert(
                title: Text(title),
                message: Text(message),
                primaryButton: primary,
                secondaryButton: .cancel(
                    Text(replacesPending
                         ? t("Keep current", "Залишити поточне", "Оставить текущее")
                         : t("Cancel", "Скасувати", "Отмена"))
                )
            )
        }
    }

    private func savePrivacy() async {
        guard let privacyDraft else { return }
        await perform(id: "privacy") {
            let desiredWorkoutDetails = workoutDetailPrivacyDraft
            var generalPrivacyWasConfirmed = false
            if privacyIsDirty {
                try await appState.updateSocialPrivacy(privacyDraft)
                generalPrivacyWasConfirmed = true
                privacyIsDirty = false
                self.privacyDraft = privacyDraft
            }
            do {
                if workoutDetailPrivacyIsDirty,
                   let desiredWorkoutDetails {
                    try await appState.updateSocialWorkoutDetailPrivacy(desiredWorkoutDetails)
                    workoutDetailPrivacyIsDirty = false
                    workoutDetailPrivacyDraft = desiredWorkoutDetails
                }
            } catch {
                if generalPrivacyWasConfirmed {
                    statusMessage = confirmedSocialStatus(
                        t(
                            "Main privacy settings saved. The exact-workout-details setting was not changed; refresh and retry it.",
                            "Основні налаштування приватності збережено. Налаштування точних деталей тренувань не змінено — онови дані й повтори його.",
                            "Основные настройки приватности сохранены. Настройка точных деталей тренировок не изменена — обнови данные и повтори её."
                        )
                    )
                    errorMessage = t(
                        "One privacy setting still needs attention.",
                        "Одне налаштування приватності ще потребує уваги.",
                        "Одна настройка приватности ещё требует внимания."
                    )
                    return
                }
                throw error
            }
            statusMessage = confirmedSocialStatus(
                t("Privacy updated.", "Приватність оновлено.", "Приватность обновлена.")
            )
        }
    }

    private func unblock(_ profile: SocialBlockedProfile) async {
        await perform(id: profile.profileID) {
            try await appState.unblockSocialProfile(profileID: profile.profileID)
            statusMessage = confirmedSocialStatus(
                t("Person unblocked.", "Користувача розблоковано.", "Пользователь разблокирован.")
            )
        }
    }

    private func confirmedSocialStatus(_ confirmedMessage: String) -> String {
        guard appState.isRestoringConfirmedSocialMutation else { return confirmedMessage }
        return t(
            "Change confirmed. Refreshing Friends without repeating the action…",
            "Зміну підтверджено. Оновлюємо Друзів без повторення дії…",
            "Изменение подтверждено. Обновляем Друзей без повторения действия…"
        )
    }

    private func perform(id: String, action: () async throws -> Void) async {
        guard activeActionID == nil else { return }
        activeActionID = id
        errorMessage = nil
        statusMessage = nil
        defer { activeActionID = nil }
        do {
            try await action()
        } catch {
            errorMessage = socialError(
                t("This action could not be completed safely. Refresh and try again.", "Не вдалося безпечно виконати дію. Онови дані й спробуй ще раз.", "Не удалось безопасно выполнить действие. Обнови данные и попробуй ещё раз.")
            )
        }
    }

    private func socialError(_ fallback: String) -> String {
        if auth.session?.cloud == nil {
            return t("Your cloud session ended. Sign in again.", "Хмарна сесія завершилася. Увійди знову.", "Облачная сессия завершилась. Войди снова.")
        }
        return fallback
    }

    private func localizedExerciseName(_ rawName: String) -> String {
        gymExerciseName(rawName, languageCode: languageCode)
    }

    private func empty(_ text: String) -> some View {
        GymInlineState(text, systemImage: "circle.dashed")
    }

    private func t(_ english: String, _ ukrainian: String, _ russian: String) -> String {
        gymText(english, ukrainian, russian, languageCode: languageCode)
    }
}

private struct WorkoutInvitePreparation {
    enum Action: String {
        case accept
        case recover
    }

    let invite: SocialWorkoutInvite
    let action: Action
    let pendingID: UUID?
}

private enum FriendsConfirmation: Identifiable {
    case blockRequest(SocialFriendRequest)
    case workout(WorkoutInvitePreparation)

    var id: String {
        switch self {
        case .blockRequest(let request):
            return "block-\(request.profileID)"
        case .workout(let preparation):
            return "workout-\(preparation.action.rawValue)-\(preparation.invite.inviteID)"
        }
    }
}

private struct RankedSocialProfile: Identifiable {
    let id: String
    let displayName: String
    let xp: Int
    let level: Int
    let workouts: Int
    let isCurrentUser: Bool
    let friend: SocialFriendSummary?
}

@MainActor
private struct FriendDetailView: View {
    fileprivate enum WorkoutShareMode: String, Identifiable {
        case copy
        case live

        var id: String { rawValue }
    }

    private enum Confirmation: String, Identifiable {
        case remove
        case block

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    @ObservedObject private var appState: AppState
    @ObservedObject private var liveWorkoutCoordinator: LiveWorkoutCoordinator

    let friend: SocialFriendSummary

    @State private var details: SocialFriendDetails?
    @State private var friendWorkouts: [SocialFriendWorkout] = []
    @State private var friendWorkoutActivityRevision: String?
    @State private var friendWorkoutDetailsAvailable = false
    @State private var selectedFriendWorkout: SocialFriendWorkout?
    @State private var isLoading = false
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var confirmation: Confirmation?
    @State private var loadRequestRevision: UInt64 = 0
    @State private var workoutShareMode: WorkoutShareMode?
    @State private var sharingWorkoutID: UUID?
    @State private var actionMessage: String?

    init(
        friend: SocialFriendSummary,
        appState: AppState,
        liveWorkoutCoordinator: LiveWorkoutCoordinator
    ) {
        self.friend = friend
        self.appState = appState
        self.liveWorkoutCoordinator = liveWorkoutCoordinator
    }

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(spacing: GymTheme.contentSpacing) {
                    header
                    trainingTogetherCard
                    if let actionMessage {
                        GymStatusBanner(message: actionMessage, isError: false)
                    }
                    if let errorMessage {
                        GymStatusBanner(message: errorMessage, isError: true)
                    }
                    if let details {
                        progressCard(details)
                        recentWorkoutsCard(details)
                        recordsCard(details)
                        safetyCard
                    } else if isLoading {
                        ProgressView(t("Loading friend…", "Завантажуємо друга…", "Загружаем друга…"))
                            .frame(maxWidth: .infinity)
                            .padding(30)
                    } else {
                        GymPanel {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(t("Friend profile unavailable", "Профіль друга недоступний", "Профиль друга недоступен"))
                                    .font(.headline)
                                Text(t("The friendship may have changed. Return to Friends and refresh.", "Дружба могла змінитися. Повернися до друзів і онови дані.", "Дружба могла измениться. Вернись к друзьям и обнови данные."))
                                    .font(.subheadline)
                                    .foregroundStyle(GymTheme.textSecondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, GymTheme.screenHorizontalInset)
                .padding(.top, GymTheme.screenVerticalInset)
                .padding(.bottom, GymTheme.screenBottomInset)
            }
            .refreshable { await load() }
        }
        .navigationTitle(friend.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.socialDashboardRefreshRevision) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .gymAppSocialChanged)) { note in
            guard note.object as? String == appState.auth.session?.cloud?.userID else { return }
            loadRequestRevision &+= 1
            details = nil
            friendWorkouts = []
            friendWorkoutActivityRevision = nil
            friendWorkoutDetailsAvailable = false
            selectedFriendWorkout = nil
            Task { await load() }
        }
        .sheet(item: $workoutShareMode) { mode in
            FriendWorkoutPickerSheet(
                friendName: friend.displayName,
                workouts: appState.workoutStore.workouts,
                mode: mode,
                sharingWorkoutID: sharingWorkoutID,
                onSelect: { workout in
                    Task { await share(workout, mode: mode) }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(
            isPresented: Binding(
                get: { authorizedSelectedFriendWorkout != nil },
                set: { presented in
                    if !presented { selectedFriendWorkout = nil }
                }
            )
        ) {
            if let workout = authorizedSelectedFriendWorkout {
                NavigationStack {
                    FriendWorkoutReadOnlyDetailView(
                        friendName: friend.displayName,
                        workout: workout,
                        languageCode: languageCode
                    )
                }
                .presentationDetents([.large])
            }
        }
        .alert(item: $confirmation) { confirmation in
            switch confirmation {
            case .remove:
                return Alert(
                    title: Text(t("Remove friend?", "Видалити друга?", "Удалить друга?")),
                    message: Text(t("Both people immediately lose access to shared friend details.", "Обидва користувачі одразу втратять доступ до даних друга.", "Оба пользователя сразу потеряют доступ к данным друга.")),
                    primaryButton: .destructive(Text(t("Remove", "Видалити", "Удалить"))) {
                        Task { await removeFriend() }
                    },
                    secondaryButton: .cancel(Text(t("Cancel", "Скасувати", "Отмена")))
                )
            case .block:
                return Alert(
                    title: Text(t("Block this person?", "Заблокувати користувача?", "Заблокировать пользователя?")),
                    message: Text(t("Blocking also removes the friendship and prevents new friend or workout requests.", "Блокування також видалить дружбу й заборонить нові запити в друзі та тренування.", "Блокировка также удалит дружбу и запретит новые запросы в друзья и тренировки.")),
                    primaryButton: .destructive(Text(t("Block", "Заблокувати", "Заблокировать"))) {
                        Task { await blockFriend() }
                    },
                    secondaryButton: .cancel(Text(t("Cancel", "Скасувати", "Отмена")))
                )
            }
        }
    }

    private var header: some View {
        GymHeroPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label(friend.displayName, systemImage: "person.crop.circle.fill")
                    .font(.title2.bold())
                Text(t("Accepted friend", "Прийнятий друг", "Принятый друг"))
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.82))
            }
        }
    }

    private var trainingTogetherCard: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 10) {
                GymSectionTitle(
                    title: t("Train with this friend", "Тренуйся з цим другом", "Тренируйся с этим другом"),
                    supporting: t(
                        "Choose one saved workout, then send an editable copy or open a synchronized live room.",
                        "Вибери одне збережене тренування, а потім надішли редаговану копію або відкрий синхронізовану live-кімнату.",
                        "Выбери одну сохранённую тренировку, затем отправь редактируемую копию или открой синхронизированную live-комнату."
                    )
                )
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { friendTrainingButtons }
                    VStack(spacing: 8) { friendTrainingButtons }
                }
                if appState.workoutStore.workouts.isEmpty {
                    Text(
                        t(
                            "Save a workout first; it will then appear here.",
                            "Спочатку збережи тренування — після цього воно з’явиться тут.",
                            "Сначала сохрани тренировку — после этого она появится здесь."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var friendTrainingButtons: some View {
        Button {
            workoutShareMode = .copy
        } label: {
            Label(t("Send workout", "Надіслати тренування", "Отправить тренировку"), systemImage: "paperplane.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .disabled(isMutating || appState.workoutStore.workouts.isEmpty)

        Button {
            workoutShareMode = .live
        } label: {
            Label(t("Train live", "Тренуватися live", "Тренироваться live"), systemImage: "figure.strengthtraining.traditional")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymPrimaryButtonStyle())
        .disabled(isMutating || appState.workoutStore.workouts.isEmpty)
    }

    private func progressCard(_ details: SocialFriendDetails) -> some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Progress", "Прогрес", "Прогресс")).font(.headline)
                if details.friend.statsAvailable,
                   let xp = details.friend.xp,
                   let level = details.friend.level,
                   let workouts = details.friend.workouts {
                    HStack(spacing: 10) {
                        metric("XP", "\(xp)")
                        metric(t("Level", "Рівень", "Уровень"), "\(level)")
                        metric(t("Workouts", "Тренування", "Тренировки"), "\(workouts)")
                    }
                } else {
                    Text(details.sharing.progress
                         ? t("Synced progress is temporarily unavailable.", "Синхронізований прогрес тимчасово недоступний.", "Синхронизированный прогресс временно недоступен.")
                         : t("This friend keeps progress private.", "Цей друг приховує прогрес.", "Этот друг скрывает прогресс."))
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                }
            }
        }
    }

    private func recentWorkoutsCard(_ details: SocialFriendDetails) -> some View {
        let state = socialActivityPresentationState(
            isShared: details.sharing.recentWorkouts,
            activityUpdatedAt: details.activityUpdatedAt,
            itemCount: details.recentWorkouts.count
        )
        return GymPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Recent workouts", "Останні тренування", "Недавние тренировки")).font(.headline)
                if state == .privateData {
                    Text(t("This friend keeps recent workouts private.", "Цей друг приховує останні тренування.", "Этот друг скрывает недавние тренировки."))
                        .font(.subheadline).foregroundStyle(GymTheme.textSecondary)
                } else if state == .temporarilyUnavailable {
                    Text(t("Synced workouts are temporarily unavailable.", "Синхронізовані тренування тимчасово недоступні.", "Синхронизированные тренировки временно недоступны."))
                        .font(.subheadline).foregroundStyle(GymTheme.textSecondary)
                } else if state == .empty {
                    Text(t("No synced workouts yet.", "Ще немає синхронізованих тренувань.", "Синхронизированных тренировок пока нет."))
                        .font(.subheadline).foregroundStyle(GymTheme.textSecondary)
                } else if friendWorkoutDetailsAvailable && !friendWorkouts.isEmpty {
                    ForEach(friendWorkouts) { workout in
                        Button {
                            selectedFriendWorkout = workout
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(formatDay(workout.workoutDay)).font(.headline)
                                    Spacer()
                                    Text("\(workout.exerciseCount) · \(workout.setCount)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(GymTheme.textSecondary)
                                }
                                Text(workout.exercises.map {
                                    gymExerciseName($0.name, catalogKey: $0.catalogKey, languageCode: languageCode)
                                }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                                .lineLimit(3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                } else {
                    ForEach(Array(details.recentWorkouts.enumerated()), id: \.offset) { _, workout in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(formatDay(workout.workoutDay)).font(.headline)
                                Spacer()
                                Text("\(workout.exerciseCount) · \(workout.setCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(GymTheme.textSecondary)
                            }
                            Text(workout.exercises.map {
                                gymExerciseName($0.name, catalogKey: $0.catalogKey, languageCode: languageCode)
                            }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                            .lineLimit(3)
                        }
                        .padding(.vertical, 4)
                    }
                    Text(t("Sets are private.", "Підходи приховано.", "Подходы скрыты."))
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                }
            }
        }
    }

    private func recordsCard(_ details: SocialFriendDetails) -> some View {
        let state = socialActivityPresentationState(
            isShared: details.sharing.records,
            activityUpdatedAt: details.activityUpdatedAt,
            itemCount: details.exerciseRecords.count
        )
        return GymPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Exercise records", "Рекорди у вправах", "Рекорды в упражнениях")).font(.headline)
                if state == .privateData {
                    Text(t("This friend keeps exercise records private.", "Цей друг приховує рекорди у вправах.", "Этот друг скрывает рекорды в упражнениях."))
                        .font(.subheadline).foregroundStyle(GymTheme.textSecondary)
                } else if state == .temporarilyUnavailable {
                    Text(t("Synced records are temporarily unavailable.", "Синхронізовані рекорди тимчасово недоступні.", "Синхронизированные рекорды временно недоступны."))
                        .font(.subheadline).foregroundStyle(GymTheme.textSecondary)
                } else if state == .empty {
                    Text(t("No synced records yet.", "Ще немає синхронізованих рекордів.", "Синхронизированных рекордов пока нет."))
                        .font(.subheadline).foregroundStyle(GymTheme.textSecondary)
                } else {
                    ForEach(details.exerciseRecords) { record in
                        let metrics = socialRecordMetricLabels(record, languageCode: languageCode)
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gymExerciseName(record.name, catalogKey: record.catalogKey, languageCode: languageCode))
                                    .font(.headline)
                                Text("\(record.workoutCount) \(t("workouts", "тренувань", "тренировок")) · \(formatDay(record.lastWorkoutDay))")
                                    .font(.caption)
                                    .foregroundStyle(GymTheme.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(metrics.maximumWeight)
                                Text(metrics.maximumRepetitions)
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(GymTheme.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(GymTheme.surfaceVariant, in: Capsule())
                            .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private var safetyCard: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Friend controls", "Керування другом", "Управление другом")).font(.headline)
                Button(t("Remove friend", "Видалити друга", "Удалить друга"), role: .destructive) {
                    confirmation = .remove
                }
                .buttonStyle(.bordered)
                .disabled(isMutating)
                Button(t("Block person", "Заблокувати користувача", "Заблокировать пользователя"), role: .destructive) {
                    confirmation = .block
                }
                .buttonStyle(.bordered)
                .disabled(isMutating)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(GymTheme.textSecondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authorizedSelectedFriendWorkout: SocialFriendWorkout? {
        guard details?.sharing.recentWorkouts == true,
              details?.activityUpdatedAt == friendWorkoutActivityRevision,
              friendWorkoutDetailsAvailable,
              appState.socialDashboard?.friends.contains(where: {
                  $0.profileID == friend.profileID
              }) == true,
              let selectedFriendWorkout else { return nil }
        return friendWorkouts.first(where: {
            $0.workoutID == selectedFriendWorkout.workoutID
        })
    }

    private func load() async {
        loadRequestRevision &+= 1
        let requestRevision = loadRequestRevision
        details = nil
        friendWorkouts = []
        friendWorkoutActivityRevision = nil
        friendWorkoutDetailsAvailable = false
        selectedFriendWorkout = nil
        isLoading = true
        errorMessage = nil
        guard appState.socialDashboard?.friends.contains(where: {
            $0.profileID == friend.profileID
        }) == true else {
            isLoading = false
            errorMessage = t("This friend profile is unavailable. Refresh Friends before trying again.", "Профіль друга недоступний. Онови список друзів і спробуй ще раз.", "Профиль друга недоступен. Обнови список друзей и попробуй ещё раз.")
            return
        }
        do {
            let loaded = try await appState.socialFriendDetails(profileID: friend.profileID)
            guard requestRevision == loadRequestRevision,
                  appState.socialDashboard?.friends.contains(where: {
                      $0.profileID == friend.profileID
                  }) == true else {
                if requestRevision == loadRequestRevision {
                    details = nil
                    isLoading = false
                }
                return
            }
            details = loaded
            isLoading = false
            guard loaded.sharing.recentWorkouts,
                  loaded.activityUpdatedAt != nil else { return }

            do {
                let capability = try await appState.socialFriendWorkoutDetailCapability(
                    profileID: friend.profileID
                )
                let workoutPage: SocialFriendWorkoutPage? = if capability.available {
                    try await appState.socialFriendWorkoutPage(
                        profileID: friend.profileID,
                        expectedActivityRevision: loaded.activityUpdatedAt
                    )
                } else {
                    nil
                }
                guard requestRevision == loadRequestRevision,
                      appState.socialDashboard?.friends.contains(where: {
                          $0.profileID == friend.profileID
                      }) == true else { return }
                friendWorkouts = workoutPage?.items ?? []
                friendWorkoutActivityRevision = workoutPage?.activityRevision
                friendWorkoutDetailsAvailable = workoutPage != nil
            } catch {
                guard requestRevision == loadRequestRevision,
                      appState.socialDashboard?.friends.contains(where: {
                          $0.profileID == friend.profileID
                      }) == true else { return }
                // Exact-set availability is optional. Keep the already-authorized
                // five summaries visible and fail closed to non-tappable rows.
                friendWorkouts = []
                friendWorkoutActivityRevision = nil
                friendWorkoutDetailsAvailable = false
                selectedFriendWorkout = nil
            }
        } catch {
            guard requestRevision == loadRequestRevision else { return }
            // Friend data is never retained after a failed authorization/relation check.
            details = nil
            friendWorkouts = []
            friendWorkoutActivityRevision = nil
            friendWorkoutDetailsAvailable = false
            errorMessage = t("This friend profile is unavailable. Refresh Friends before trying again.", "Профіль друга недоступний. Онови список друзів і спробуй ще раз.", "Профиль друга недоступен. Обнови список друзей и попробуй ещё раз.")
        }
        if requestRevision == loadRequestRevision { isLoading = false }
    }

    private func removeFriend() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await appState.removeFriend(friend)
            details = nil
            friendWorkouts = []
            friendWorkoutActivityRevision = nil
            friendWorkoutDetailsAvailable = false
            selectedFriendWorkout = nil
            dismiss()
        } catch {
            details = nil
            friendWorkouts = []
            friendWorkoutActivityRevision = nil
            friendWorkoutDetailsAvailable = false
            selectedFriendWorkout = nil
            errorMessage = t("The friend could not be removed safely. Refresh and try again.", "Не вдалося безпечно видалити друга. Онови дані й спробуй ще раз.", "Не удалось безопасно удалить друга. Обнови данные и попробуй ещё раз.")
        }
    }

    private func blockFriend() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await appState.blockSocialProfile(profileID: friend.profileID)
            details = nil
            friendWorkouts = []
            friendWorkoutActivityRevision = nil
            friendWorkoutDetailsAvailable = false
            selectedFriendWorkout = nil
            dismiss()
        } catch {
            details = nil
            friendWorkouts = []
            friendWorkoutActivityRevision = nil
            friendWorkoutDetailsAvailable = false
            selectedFriendWorkout = nil
            errorMessage = t("The person could not be blocked safely. Refresh and try again.", "Не вдалося безпечно заблокувати користувача. Онови дані й спробуй ще раз.", "Не удалось безопасно заблокировать пользователя. Обнови данные и попробуй ещё раз.")
        }
    }

    private func share(_ workout: WorkoutSession, mode: WorkoutShareMode) async {
        guard sharingWorkoutID == nil else { return }
        guard let expectedAccountKey = appState.activeAccountStorageKey,
              appState.auth.session?.cloud != nil,
              appState.socialDashboard?.friends.contains(where: {
                  $0.profileID == friend.profileID
              }) == true else {
            workoutShareMode = nil
            errorMessage = t(
                "This friend is no longer available. Refresh Friends and try again.",
                "Цей друг більше недоступний. Онови список друзів і спробуй ще раз.",
                "Этот друг больше недоступен. Обнови список друзей и попробуй ещё раз."
            )
            return
        }
        sharingWorkoutID = workout.id
        errorMessage = nil
        defer { sharingWorkoutID = nil }
        do {
            var exercisesByID: [UUID: Exercise] = [:]
            for exercise in appState.workoutStore.exercises {
                exercisesByID[exercise.id] = exercise
            }
            let plan = try SharedWorkoutLinkEncoder.makePlan(
                workout: workout,
                exercises: exercisesByID
            )
            guard appState.activeAccountStorageKey == expectedAccountKey,
                  appState.socialDashboard?.friends.contains(where: {
                      $0.profileID == friend.profileID
                  }) == true else {
                return
            }
            switch mode {
            case .copy:
                try await appState.sendWorkoutInvite(to: friend.profileID, plan: plan)
            case .live:
                try await liveWorkoutCoordinator.sendInvite(to: friend.profileID, plan: plan)
            }
            guard appState.activeAccountStorageKey == expectedAccountKey else { return }
            workoutShareMode = nil
            actionMessage = mode == .live
                ? t(
                    "Live invitation sent. The workout starts for both of you when your friend joins.",
                    "Live-запрошення надіслано. Тренування почнеться для вас обох, коли друг приєднається.",
                    "Live-приглашение отправлено. Тренировка начнётся для вас обоих, когда друг присоединится."
                )
                : t(
                    "Workout copy sent to this friend.",
                    "Копію тренування надіслано цьому другу.",
                    "Копия тренировки отправлена этому другу."
                )
        } catch {
            guard appState.activeAccountStorageKey == expectedAccountKey else { return }
            errorMessage = t(
                "The workout could not be shared safely. Refresh and try again.",
                "Не вдалося безпечно поділитися тренуванням. Онови дані й спробуй ще раз.",
                "Не удалось безопасно поделиться тренировкой. Обнови данные и попробуй ещё раз."
            )
        }
    }

    private func formatDay(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
            .weekday(.abbreviated)
            .locale(AppLanguage(rawValue: languageCode)?.locale ?? Locale(identifier: "en"))
        style.timeZone = TimeZone(secondsFromGMT: 0)!
        return date.formatted(style)
    }

    private func t(_ english: String, _ ukrainian: String, _ russian: String) -> String {
        gymText(english, ukrainian, russian, languageCode: languageCode)
    }
}

private struct FriendWorkoutReadOnlyDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let friendName: String
    let workout: SocialFriendWorkout
    let languageCode: String

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(spacing: GymTheme.contentSpacing) {
                    GymPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(formatDay(workout.workoutDay))
                                .font(.title2.bold())
                                .foregroundStyle(GymTheme.textPrimary)
                            Text(friendName)
                                .font(.headline)
                                .foregroundStyle(GymTheme.textSecondary)
                            Text(t("Shared workout · Read only", "Спільне тренування · Лише перегляд", "Общая тренировка · Только просмотр"))
                                .font(.subheadline)
                                .foregroundStyle(GymTheme.textSecondary)
                            HStack(spacing: 16) {
                                compactMetric(
                                    t("Exercises", "Вправи", "Упражнения"),
                                    workout.exerciseCount
                                )
                                compactMetric(
                                    t("Sets", "Підходи", "Подходы"),
                                    workout.setCount
                                )
                            }
                        }
                    }
                    if workout.truncated {
                        GymStatusBanner(
                            message: t(
                                "Only the first 100 shared sets are shown.",
                                "Показано перші 100 спільних підходів.",
                                "Показаны первые 100 общих подходов."
                            ),
                            isError: false
                        )
                    }
                    ForEach(workout.exercises) { exercise in
                        GymPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .center, spacing: 10) {
                                    ExerciseMediaButton(
                                        rawExerciseName: exercise.name,
                                        catalogKey: exercise.catalogKey,
                                        exerciseID: UUID(
                                            uuidString: "00000000-0000-0000-0000-000000000000"
                                        )!,
                                        ownerKey: "social-friend-read-only",
                                        editable: false
                                    )
                                    Text(gymExerciseName(
                                        exercise.name,
                                        catalogKey: exercise.catalogKey,
                                        languageCode: languageCode
                                    ))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
                                    HStack(spacing: 12) {
                                        Text(t("Set", "Підхід", "Подход") + " \(index + 1)")
                                            .foregroundStyle(GymTheme.textSecondary)
                                        Spacer()
                                        Text("\(set.weightKg.formatted(.number.precision(.fractionLength(0 ... 2)))) kg × \(set.reps)")
                                            .monospacedDigit()
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, GymTheme.screenHorizontalInset)
                .padding(.top, GymTheme.screenVerticalInset)
                .padding(.bottom, GymTheme.screenBottomInset)
            }
        }
        .navigationTitle(t("Workout", "Тренування", "Тренировка"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(t("Done", "Готово", "Готово")) { dismiss() }
            }
        }
    }

    private func compactMetric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(GymTheme.textSecondary)
            Text(value.formatted()).font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDay(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
            .weekday(.abbreviated)
            .locale(AppLanguage(rawValue: languageCode)?.locale ?? Locale(identifier: "en"))
        style.timeZone = TimeZone(secondsFromGMT: 0)!
        return date.formatted(style)
    }

    private func t(_ english: String, _ ukrainian: String, _ russian: String) -> String {
        gymText(english, ukrainian, russian, languageCode: languageCode)
    }
}

private struct FriendWorkoutPickerSheet: View {
    let friendName: String
    let workouts: [WorkoutSession]
    let mode: FriendDetailView.WorkoutShareMode
    let sharingWorkoutID: UUID?
    let onSelect: (WorkoutSession) -> Void

    var body: some View {
        NavigationStack {
            GymBackground {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        GymSectionTitle(
                            eyebrow: mode == .live ? "LIVE" : t("Private copy", "Приватна копія", "Приватная копия"),
                            title: friendName,
                            supporting: mode == .live
                                ? t(
                                    "Choose the frozen plan you will complete independently in two synchronized lanes.",
                                    "Вибери зафіксований план, який ви виконуватимете незалежно у двох синхронізованих доріжках.",
                                    "Выбери зафиксированный план, который вы будете выполнять независимо в двух синхронизированных дорожках."
                                )
                                : t(
                                    "Choose a saved workout to send as an editable copy.",
                                    "Вибери збережене тренування для надсилання як редагованої копії.",
                                    "Выбери сохранённую тренировку для отправки как редактируемой копии."
                                )
                        )
                        if workouts.isEmpty {
                            GymContentUnavailableView {
                                Label(
                                    t("No saved workouts", "Немає збережених тренувань", "Нет сохранённых тренировок"),
                                    systemImage: "tray"
                                )
                            } description: {
                                Text(
                                    t(
                                        "Save a workout first, then return to this friend.",
                                        "Спочатку збережи тренування, а потім повернися до цього друга.",
                                        "Сначала сохрани тренировку, затем вернись к этому другу."
                                    )
                                )
                            }
                        } else {
                            ForEach(workouts.sorted { $0.date > $1.date }) { workout in
                                Button {
                                    onSelect(workout)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: mode == .live ? "wave.3.right.circle.fill" : "doc.on.doc.fill")
                                            .foregroundStyle(GymTheme.primary)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(gymFormattedDate(workout.date, date: .abbreviated, time: .shortened))
                                                .font(.headline)
                                                .foregroundStyle(GymTheme.textPrimary)
                                            Text("\(workout.exercises.count) \(t("exercises", "вправ", "упражнений"))")
                                                .font(.caption)
                                                .foregroundStyle(GymTheme.textSecondary)
                                        }
                                        Spacer()
                                        if sharingWorkoutID == workout.id {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(GymTheme.textSecondary)
                                        }
                                    }
                                    .padding(12)
                                    .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                                .disabled(sharingWorkoutID != nil)
                            }
                        }
                    }
                    .padding(14)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(t("Choose workout", "Вибрати тренування", "Выбрать тренировку"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func t(_ english: String, _ ukrainian: String, _ russian: String) -> String {
        gymText(english, ukrainian, russian, languageCode: gymCurrentLanguageCode())
    }
}
