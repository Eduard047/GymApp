import SwiftUI

@MainActor
struct LeaderboardView: View {
    @AppStorage("app-language") private var languageCode = AppLanguage.english.rawValue
    @AppStorage private var hiddenProfileIDsJSON: String
    @ObservedObject private var store: WorkoutStore
    @ObservedObject private var appState: AppState
    @ObservedObject private var cloudSync: CloudSyncService
    @ObservedObject private var auth: AuthService
    private let embedded: Bool

    @State private var remoteRows: [LeaderboardEntry] = []
    @State private var errorMessage: String?
    @State private var isShowingLocalFallback = true
    @State private var lastRefreshedAt: Date?
    @State private var pendingReport: LeaderboardEntry?
    @State private var safetyMessage: String?
    @State private var safetyMessageIsError = false

    init(
        store: WorkoutStore,
        appState: AppState,
        auth: AuthService,
        embedded: Bool = false
    ) {
        self.store = store
        self.appState = appState
        self.cloudSync = appState.cloudSync
        self.auth = auth
        self.embedded = embedded
        _hiddenProfileIDsJSON = AppStorage(
            wrappedValue: "[]",
            leaderboardHiddenProfilesDefaultsKey(for: store.accountStorageKey)
        )
    }

    var body: some View {
        configuredContent
            .environment(\.locale, appLocale)
            .task(id: auth.session?.storageKey) {
                await refreshLeaderboard()
            }
            .alert(item: $pendingReport) { row in
                Alert(
                    title: Text(t("Report this display name?", "Поскаржитися на це ім’я?")),
                    message: Text(
                        t(
                            "GymApp will send the profile identifier and a fixed offensive-name reason to the moderation queue. No free-form text is sent.",
                            "GymApp надішле ідентифікатор профілю та фіксовану причину щодо неприйнятного імені до черги модерації. Довільний текст не надсилається."
                        )
                    ),
                    primaryButton: .destructive(Text(t("Report", "Поскаржитися"))) {
                        Task { await reportDisplayName(row) }
                    },
                    secondaryButton: .cancel(Text(t("Cancel", "Скасувати")))
                )
            }
    }

    @ViewBuilder
    private var configuredContent: some View {
        if embedded {
            leaderboardContent
        } else {
            GymBackground {
                ScrollView {
                    leaderboardContent
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await refreshLeaderboard()
                }
            }
            .navigationTitle(t("Rating status", "Статус рейтингу"))
        }
    }

    private var leaderboardContent: some View {
        LazyVStack(spacing: 12) {
            ratingHero
            refreshCard

            if isShowingLocalFallback {
                fallbackCard
            }

            if let errorMessage {
                GymStatusBanner(message: errorMessage, isError: true)
            }

            if let safetyMessage {
                GymStatusBanner(message: safetyMessage, isError: safetyMessageIsError)
            }

            if displayedRows.isEmpty, !cloudSync.isSyncing {
                emptyState
            } else {
                ForEach(Array(displayedRows.enumerated()), id: \.element.id) { index, row in
                    leaderboardRow(row, place: index + 1)
                }
            }
        }
    }

    private var ratingHero: some View {
        GymHeroPanel {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    heroCopy
                    Spacer(minLength: 8)
                    yourStats
                        .frame(minWidth: 138)
                }
                VStack(alignment: .leading, spacing: 14) {
                    heroCopy
                    yourStats
                }
            }
        }
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                t("Rating not available yet", "Рейтинг поки недоступний"),
                systemImage: "lock.shield.fill"
            )
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text(
                t(
                    "Workouts are currently scored on your device, so public ranking is disabled, not queued for review. It will appear only after a future app and server update adds verified scoring; no release date is set. Your private progress remains available.",
                    "Зараз тренування оцінюються на пристрої, тому публічний рейтинг вимкнено, а не поставлено в чергу на перевірку. Він з’явиться лише після майбутнього оновлення застосунку й сервера з перевіреним підрахунком; дати випуску поки немає. Твій приватний прогрес залишається доступним."
                )
            )
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)

            Text(t("Private progress only", "Лише приватний прогрес"))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.13), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var yourStats: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("YOUR PROGRESS", "ТВІЙ ПРОГРЕС"))
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(Color.white.opacity(0.72))
            Text("\(localStats.xp.formatted()) XP")
                .font(.title2.bold())
                .contentTransition(.numericText())
            Text(
                "\(t("Level", "Рівень")) \(localStats.level) • " + workoutCount(localStats.workouts)
            )
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.8))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var refreshCard: some View {
        GymPanel(highlighted: true) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    refreshCopy
                    Spacer(minLength: 8)
                    refreshButton
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 12) {
                    refreshCopy
                    refreshButton
                }
            }
        }
    }

    private var refreshCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: isShowingLocalFallback ? "iphone" : "cloud.fill")
                    .foregroundStyle(isShowingLocalFallback ? GymTheme.secondary : GymTheme.primary)
                    .accessibilityHidden(true)
                Text(t("Your synced progress", "Твій синхронізований прогрес"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            if cloudSync.isSyncing {
                Text(t("Loading protected cloud progress…", "Завантажуємо захищений хмарний прогрес…"))
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.textSecondary)
            } else if let lastRefreshedAt, !isShowingLocalFallback {
                Text(
                    t(
                        "Updated \(lastRefreshedAt.formatted(.relative(presentation: .named).locale(appLocale)))",
                        "Оновлено \(lastRefreshedAt.formatted(.relative(presentation: .named).locale(appLocale)))"
                    )
                )
                .font(.subheadline)
                .foregroundStyle(GymTheme.textSecondary)
            } else {
                Text(
                    isShowingLocalFallback
                        ? t("Showing on-device stats.", "Показано дані з цього пристрою.")
                        : t("Your own cloud progress is up to date.", "Твій власний хмарний прогрес актуальний.")
                )
                .font(.subheadline)
                .foregroundStyle(GymTheme.textSecondary)
            }

            if !cloudSync.isSyncing {
                Text(
                    t(
                        "Refresh updates only your own cloud XP. It does not start a rating check.",
                        "Оновлення завантажує лише твої власні XP із хмари. Воно не запускає перевірку рейтингу."
                    )
                )
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
            }

            if !hiddenProfileIDs.isEmpty {
                Button(t("Show blocked athletes again", "Знову показувати заблокованих атлетів")) {
                    hiddenProfileIDsJSON = "[]"
                    safetyMessageIsError = false
                    safetyMessage = t("Blocked athletes are visible again.", "Заблокованих атлетів знову видно.")
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await refreshLeaderboard() }
        } label: {
            HStack(spacing: 8) {
                if cloudSync.isSyncing {
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityHidden(true)
                }
                Text(
                    cloudSync.isSyncing
                        ? t("Loading", "Завантаження")
                        : t("Refresh progress", "Оновити прогрес")
                )
            }
        }
        .buttonStyle(GymPrimaryButtonStyle())
        .disabled(cloudSync.isSyncing || auth.session?.cloud == nil)
        .accessibilityHint(
            auth.session?.cloud == nil
                ? t("Sign in with a cloud account to refresh", "Увійди у хмарний акаунт, щоб оновити")
                : t(
                    "Refreshes only your cloud progress; it does not start a rating check",
                    "Оновлює лише твій хмарний прогрес і не запускає перевірку рейтингу"
                )
        )
    }

    private var fallbackCard: some View {
        GymPanel {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: auth.session?.cloud == nil ? "person.crop.circle.badge.exclamationmark" : "wifi.slash")
                    .font(.title3)
                    .foregroundStyle(GymTheme.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Local progress", "Локальний прогрес"))
                        .font(.subheadline.weight(.semibold))
                    Text(fallbackExplanation)
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var emptyState: some View {
        GymPanel {
            ContentUnavailableView {
                Label(t("No synced progress yet", "Синхронізованого прогресу ще немає"), systemImage: "person.crop.circle")
            } description: {
                Text(t("Sign in and sync to restore your protected progress here.", "Увійди та синхронізуй дані, щоб відновити тут свій захищений прогрес."))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func leaderboardRow(_ row: LeaderboardEntry, place: Int) -> some View {
        GymPanel(highlighted: row.isCurrentUser) {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        placeBadge(place, isCurrentUser: row.isCurrentUser)
                        rowIdentity(row)
                        Spacer(minLength: 8)
                        xpLabel(row)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            placeBadge(place, isCurrentUser: row.isCurrentUser)
                            rowIdentity(row)
                        }
                        xpLabel(row)
                    }
                }

                if !row.isCurrentUser, auth.session?.cloud != nil {
                    HStack {
                        Spacer()
                        Menu {
                            Button(role: .destructive) {
                                pendingReport = row
                            } label: {
                                Label(t("Report display name", "Поскаржитися на ім’я"), systemImage: "exclamationmark.bubble")
                            }

                            Button {
                                blockFromLeaderboard(row)
                            } label: {
                                Label(t("Block from leaderboard", "Заблокувати в рейтингу"), systemImage: "person.crop.circle.badge.xmark")
                            }
                        } label: {
                            Label(t("Safety options", "Параметри безпеки"), systemImage: "ellipsis.circle")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                t(
                    "Protected progress for \(gymLocalized(row.displayName, languageCode: languageCode))",
                    "Захищений прогрес: \(gymLocalized(row.displayName, languageCode: languageCode))"
                )
            )
            .accessibilityValue(
                t(
                    "\(row.xp) XP, level \(row.level), \(workoutCount(row.workouts))" +
                        (row.isCurrentUser ? ", current user" : ""),
                    "\(row.xp) XP, рівень \(row.level), \(workoutCount(row.workouts))" +
                        (row.isCurrentUser ? ", поточний користувач" : "")
                )
            )
        }
    }

    private func placeBadge(_ place: Int, isCurrentUser: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13)
                .fill(placeColor(place).opacity(0.15))
            if isCurrentUser {
                Image(systemName: "person.fill")
                    .font(.headline)
            } else if place <= 3 {
                VStack(spacing: 1) {
                    Image(systemName: "medal.fill")
                        .font(.caption)
                    Text("\(place)")
                        .font(.headline.bold())
                }
            } else {
                Text("\(place)")
                    .font(.headline.bold())
            }
        }
        .foregroundStyle(placeColor(place))
        .frame(width: 50, height: 50)
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(placeColor(place).opacity(0.28), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func rowIdentity(_ row: LeaderboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(gymLocalized(row.displayName, languageCode: languageCode))
                    .font(.headline)
                    .lineLimit(2)
                if row.isCurrentUser {
                    GymInfoPill(t("You", "Ти"), systemImage: "location.fill")
                }
            }
            Text(
                "\(t("Level", "Рівень")) \(row.level) • " + workoutCount(row.workouts)
            )
            .font(.subheadline)
            .foregroundStyle(GymTheme.textSecondary)
        }
    }

    private func xpLabel(_ row: LeaderboardEntry) -> some View {
        Text("\(row.xp.formatted()) XP")
            .font(.title3.bold())
            .foregroundStyle(row.isCurrentUser ? GymTheme.primary : GymTheme.textPrimary)
            .contentTransition(.numericText())
    }

    private var appLocale: Locale {
        AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
    }

    private var localStats: SyncProfileStats {
        store.syncProfileStats()
    }

    private var localEntry: LeaderboardEntry {
        LeaderboardEntry(
            userID: auth.session?.cloud?.userID ?? auth.session?.storageKey ?? "local",
            displayName: auth.session?.displayName ?? t("Local Athlete", "Локальний атлет"),
            xp: localStats.xp,
            level: localStats.level,
            workouts: localStats.workouts,
            isCurrentUser: true
        )
    }

    private var displayedRows: [LeaderboardEntry] {
        isShowingLocalFallback
            ? [localEntry]
            : remoteRows.filter { $0.isCurrentUser || !hiddenProfileIDs.contains($0.id) }
    }

    private var hiddenProfileIDs: Set<String> {
        guard let data = hiddenProfileIDsJSON.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(values)
    }

    private var fallbackExplanation: String {
        if auth.session?.cloud == nil {
            return t(
                "This is an offline account. Sign in with a cloud account to protect and synchronize your progress; your workouts remain available on this device.",
                "Це офлайн-акаунт. Увійди у хмарний акаунт, щоб захистити й синхронізувати прогрес; твої тренування залишаються на цьому пристрої."
            )
        }
        return t(
            "Protected cloud progress is unavailable, so the latest on-device XP, level and workouts are shown. Pull down or tap Refresh to try again.",
            "Захищений хмарний прогрес недоступний, тому показано актуальні XP, рівень і тренування з цього пристрою. Потягни вниз або натисни «Оновити», щоб спробувати ще раз."
        )
    }

    private func refreshLeaderboard() async {
        guard let cloudAccount = auth.session?.cloud else {
            remoteRows = []
            errorMessage = nil
            isShowingLocalFallback = true
            lastRefreshedAt = nil
            return
        }

        errorMessage = nil
        do {
            let loaded = try await appState.refreshCloudLeaderboard()

            var merged = loaded
            if !merged.contains(where: { $0.userID == cloudAccount.userID }) {
                merged.append(localEntry)
            }
            remoteRows = merged.sorted(by: leaderboardOrder)
            isShowingLocalFallback = false
            lastRefreshedAt = Date()
        } catch {
            remoteRows = []
            isShowingLocalFallback = true
            errorMessage = gymErrorMessage(error, languageCode: languageCode)
        }
    }

    private func reportDisplayName(_ row: LeaderboardEntry) async {
        guard !row.isCurrentUser else { return }
        do {
            try await cloudSync.reportLeaderboardDisplayName(profileID: row.id)
            safetyMessageIsError = false
            safetyMessage = t(
                "Report sent. The display name was added to the moderation queue.",
                "Скаргу надіслано. Ім’я додано до черги модерації."
            )
        } catch {
            safetyMessageIsError = true
            safetyMessage = gymErrorMessage(error, languageCode: languageCode)
        }
    }

    private func blockFromLeaderboard(_ row: LeaderboardEntry) {
        guard !row.isCurrentUser else { return }
        var values = hiddenProfileIDs
        values.insert(row.id)
        if let data = try? JSONEncoder().encode(values.sorted()),
           let encoded = String(data: data, encoding: .utf8) {
            hiddenProfileIDsJSON = encoded
        }
        safetyMessageIsError = false
        safetyMessage = t(
            "Athlete blocked from your leaderboard.",
            "Атлета заблоковано у твоєму рейтингу."
        )
    }

    private func leaderboardOrder(_ lhs: LeaderboardEntry, _ rhs: LeaderboardEntry) -> Bool {
        if lhs.xp != rhs.xp { return lhs.xp > rhs.xp }
        if lhs.workouts != rhs.workouts { return lhs.workouts > rhs.workouts }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func placeColor(_ place: Int) -> Color {
        switch place {
        case 1: GymTheme.tertiary
        case 2: GymTheme.secondary
        case 3: GymTheme.primary
        default: GymTheme.textSecondary
        }
    }

    private func t(_ english: String, _ ukrainian: String) -> String {
        gymText(english, ukrainian, languageCode: languageCode)
    }

    private func workoutCount(_ count: Int) -> String {
        gymCount(
            count,
            englishOne: "workout",
            englishMany: "workouts",
            ukrainianOne: "тренування",
            ukrainianFew: "тренування",
            ukrainianMany: "тренувань",
            languageCode: languageCode
        )
    }
}
