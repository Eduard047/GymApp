import SwiftUI

struct MissionsView: View {
    @ObservedObject var store: WorkoutStore
    let onOpenRanks: () -> Void

    @AppStorage("app-language") private var languageCode = AppLanguage.english.rawValue
    @State private var period: MissionPeriod = .daily

    private var snapshot: GamificationSnapshot { store.gamificationSnapshot() }
    private var missions: [MissionCardModel] {
        MissionCardModel.catalog(period: period, store: store, snapshot: snapshot, languageCode: languageCode)
    }

    var body: some View {
        GymBackground {
            ScrollView {
                LazyVStack(spacing: 14) {
                    hero

                    Picker(gymText("Mission period", "Період місій", languageCode: languageCode), selection: $period) {
                        ForEach(MissionPeriod.allCases) { item in
                            Text(item.title(languageCode)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    ForEach(missions) { mission in
                        missionCard(mission)
                    }
                }
                .padding(16)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(gymText("Missions", "Місії", languageCode: languageCode))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onOpenRanks) {
                    Label(gymText("Ranks", "Ранги", languageCode: languageCode), systemImage: "trophy.fill")
                }
            }
        }
    }

    private var hero: some View {
        GymHeroPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gymLocalized(snapshot.progression.title.name, languageCode: languageCode))
                            .font(.title2.bold())
                        Text(gymText("Level \(snapshot.progression.level)", "Рівень \(snapshot.progression.level)", languageCode: languageCode))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                    Spacer()
                    Image(systemName: "scope")
                        .font(.title.bold())
                        .accessibilityHidden(true)
                }

                ProgressView(value: snapshot.progression.levelProgress)
                    .tint(.white)

                HStack(spacing: 10) {
                    GymMetricTile(label: "XP", value: snapshot.progression.totalXP.formatted(), emphasized: true, onHero: true)
                    GymMetricTile(
                        label: gymText("Streak", "Серія", languageCode: languageCode),
                        value: streakValue,
                        onHero: true
                    )
                }
            }
        }
    }

    private var streakValue: String {
        let days = snapshot.streak.currentDays
        return gymText(
            "\(days) \(days == 1 ? "day" : "days")",
            "\(days) дн.",
            languageCode: languageCode
        )
    }

    private func missionCard(_ mission: MissionCardModel) -> some View {
        GymPanel(highlighted: mission.completed) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: mission.completed ? "checkmark.seal.fill" : mission.icon)
                        .font(.title3)
                        .foregroundStyle(mission.completed ? GymTheme.primary : GymTheme.secondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(mission.title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(mission.detail)
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                    Spacer(minLength: 6)
                    GymInfoPill("+\(mission.rewardXP) XP", systemImage: "bolt.fill")
                }

                ProgressView(value: mission.fraction)
                    .tint(mission.completed ? GymTheme.primary : GymTheme.secondary)

                Text("\(mission.progressLabel) / \(mission.targetLabel)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(GymTheme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(mission.completed ? gymText("Completed", "Виконано", languageCode: languageCode) : mission.progressLabel + " / " + mission.targetLabel)
        }
    }
}

private enum MissionPeriod: String, CaseIterable, Identifiable {
    case daily, weekly, monthly
    var id: String { rawValue }

    func title(_ language: String) -> String {
        switch self {
        case .daily: return gymText("Daily", "Щоденні", languageCode: language)
        case .weekly: return gymText("Weekly", "Щотижневі", languageCode: language)
        case .monthly: return gymText("Monthly", "Щомісячні", languageCode: language)
        }
    }
}

private struct MissionCardModel: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let progress: Double
    let target: Double
    let rewardXP: Int
    let formatAsVolume: Bool

    var fraction: Double { target <= 0 ? 0 : min(1, max(0, progress / target)) }
    var completed: Bool { progress >= target }
    var progressLabel: String { format(progress) }
    var targetLabel: String { format(target) }

    private func format(_ value: Double) -> String {
        if formatAsVolume {
            return Measurement(value: value, unit: UnitMass.kilograms)
                .formatted(
                    .measurement(
                        width: .abbreviated,
                        usage: .asProvided,
                        numberFormatStyle: .number.precision(.fractionLength(0))
                    )
                    .locale(AppLanguage(rawValue: gymCurrentLanguageCode())?.locale ?? AppLanguage.english.locale)
                )
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    @MainActor
    static func catalog(
        period: MissionPeriod,
        store: WorkoutStore,
        snapshot: GamificationSnapshot,
        languageCode: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MissionCardModel] {
        let interval: DateInterval
        switch period {
        case .daily:
            interval = DateInterval(start: calendar.startOfDay(for: now), end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now)
        case .weekly:
            let start = calendar.gymMondayStart(of: now)
            interval = DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start) ?? now)
        case .monthly:
            interval = calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 1)
        }

        let workouts = store.workouts.filter { interval.contains($0.date) }
        let workoutCount = Double(workouts.count)
        let workoutDays = Double(Set(workouts.map { calendar.gymEpochDay(for: $0.date) }).count)
        let exerciseCount = Double(workouts.reduce(0) { $0 + $1.exercises.count })
        let setCount = Double(workouts.reduce(0) { $0 + $1.setCount })
        let reps = Double(workouts.reduce(0) { total, workout in
            total + workout.exercises.reduce(0) { $0 + $1.sets.reduce(0) { $0 + $1.reps } }
        })
        let volume = workouts.reduce(0) { $0 + $1.totalVolume }
        let xp = Double(workouts.map(WorkoutStoreSummaryAdapter.summary).reduce(0) { $0 + GamificationEngine.xpForSession($1) })
        let uniqueExercises = Double(Set(workouts.flatMap { $0.exercises.map(\.exerciseID) }).count)

        func mission(_ id: String, _ en: String, _ uk: String, _ detailEn: String, _ detailUk: String,
                     icon: String, progress: Double, target: Double, xp: Int, volume: Bool = false) -> MissionCardModel {
            MissionCardModel(
                id: "\(period.rawValue)-\(id)",
                title: gymText(en, uk, languageCode: languageCode),
                detail: gymText(detailEn, detailUk, languageCode: languageCode),
                icon: icon,
                progress: progress,
                target: target,
                rewardXP: xp,
                formatAsVolume: volume
            )
        }

        switch period {
        case .daily:
            return [
                mission("show-up", "Show up", "Прийди в зал", "Log one workout today.", "Запиши одне тренування сьогодні.", icon: "figure.strengthtraining.traditional", progress: workoutCount, target: 1, xp: 35),
                mission("sets", "Quality sets", "Якісні підходи", "Complete 10 working sets.", "Виконай 10 робочих підходів.", icon: "list.number", progress: setCount, target: 10, xp: 45),
                mission("exercises", "Variety", "Різноманіття", "Train with 3 exercises.", "Виконай 3 вправи.", icon: "square.grid.2x2", progress: exerciseCount, target: 3, xp: 35),
                mission("reps", "Rep builder", "Повтор за повтором", "Complete 80 repetitions.", "Виконай 80 повторів.", icon: "repeat", progress: reps, target: 80, xp: 40),
                mission("xp", "Momentum", "Імпульс", "Earn 150 workout XP.", "Зароби 150 XP за тренування.", icon: "bolt.fill", progress: xp, target: 150, xp: 50)
            ]
        case .weekly:
            return [
                mission("workouts", "Weekly rhythm", "Ритм тижня", "Complete 3 workouts.", "Виконай 3 тренування.", icon: "calendar", progress: workoutCount, target: 3, xp: 120),
                mission("days", "Active days", "Активні дні", "Train on 3 different days.", "Тренуйся у 3 різні дні.", icon: "calendar.badge.checkmark", progress: workoutDays, target: 3, xp: 100),
                mission("sets", "Set volume", "Обсяг підходів", "Complete 35 sets.", "Виконай 35 підходів.", icon: "list.number", progress: setCount, target: 35, xp: 110),
                mission("reps", "Rep bank", "Банк повторів", "Complete 300 reps.", "Виконай 300 повторів.", icon: "repeat", progress: reps, target: 300, xp: 100),
                mission("volume", "Move weight", "Рухай вагу", "Lift 20,000 kg total volume.", "Набери 20 000 кг обсягу.", icon: "scalemass.fill", progress: volume, target: 20_000, xp: 140, volume: true),
                mission("variety", "Exercise library", "Бібліотека вправ", "Use 8 unique exercises.", "Виконай 8 різних вправ.", icon: "square.grid.3x3", progress: uniqueExercises, target: 8, xp: 90),
                mission("five", "Extra session", "Додаткова сесія", "Complete 4 workouts.", "Виконай 4 тренування.", icon: "plus.circle", progress: workoutCount, target: 4, xp: 160),
                mission("fifty", "Fifty sets", "П’ятдесят підходів", "Complete 50 sets.", "Виконай 50 підходів.", icon: "50.circle", progress: setCount, target: 50, xp: 150),
                mission("xp", "XP week", "XP-тиждень", "Earn 700 workout XP.", "Зароби 700 XP.", icon: "bolt.fill", progress: xp, target: 700, xp: 130),
                mission("streak", "Keep the flame", "Тримай вогонь", "Reach a 3-day streak.", "Досягни серії у 3 дні.", icon: "flame.fill", progress: Double(snapshot.streak.currentDays), target: 3, xp: 150)
            ]
        case .monthly:
            return [
                mission("workouts", "Monthly base", "Основа місяця", "Complete 12 workouts.", "Виконай 12 тренувань.", icon: "calendar", progress: workoutCount, target: 12, xp: 400),
                mission("days", "Consistent month", "Стабільний місяць", "Train on 12 different days.", "Тренуйся у 12 різні дні.", icon: "calendar.badge.checkmark", progress: workoutDays, target: 12, xp: 420),
                mission("sets", "Set century", "Сотня підходів", "Complete 140 sets.", "Виконай 140 підходів.", icon: "list.number", progress: setCount, target: 140, xp: 380),
                mission("reps", "Rep marathon", "Марафон повторів", "Complete 1,200 reps.", "Виконай 1 200 повторів.", icon: "repeat", progress: reps, target: 1_200, xp: 360),
                mission("volume", "Tonnage", "Тоннаж", "Lift 80,000 kg total volume.", "Набери 80 000 кг обсягу.", icon: "scalemass.fill", progress: volume, target: 80_000, xp: 500, volume: true),
                mission("variety", "Movement range", "Різні рухи", "Use 16 unique exercises.", "Виконай 16 різних вправ.", icon: "square.grid.3x3", progress: uniqueExercises, target: 16, xp: 300),
                mission("sixteen", "High frequency", "Висока частота", "Complete 16 workouts.", "Виконай 16 тренувань.", icon: "figure.run", progress: workoutCount, target: 16, xp: 600),
                mission("twohundred", "Set fortress", "Фортеця підходів", "Complete 200 sets.", "Виконай 200 підходів.", icon: "building.columns.fill", progress: setCount, target: 200, xp: 550),
                mission("xp", "XP campaign", "XP-кампанія", "Earn 3,000 workout XP.", "Зароби 3 000 XP.", icon: "bolt.fill", progress: xp, target: 3_000, xp: 500),
                mission("streak", "Long flame", "Довгий вогонь", "Reach an 8-day streak.", "Досягни серії у 8 днів.", icon: "flame.fill", progress: Double(snapshot.streak.currentDays), target: 8, xp: 650)
            ]
        }
    }
}

private enum WorkoutStoreSummaryAdapter {
    static func summary(_ workout: WorkoutSession) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            workoutID: workout.id,
            date: workout.date,
            note: workout.note,
            exerciseCount: workout.exercises.count,
            setCount: workout.setCount,
            totalVolume: workout.totalVolume
        )
    }
}
