import SwiftUI

struct TrainingProgramView: View {
    @ObservedObject var workouts: WorkoutStore
    @StateObject private var store: TrainingProgramStore
    @State private var showsFinish = false
    @State private var showsNewCycle = false
    @State private var confirmationID: UUID?
    let onPrepare: () -> Void

    init(workouts: WorkoutStore, onPrepare: @escaping () -> Void) {
        self.workouts = workouts
        self.onPrepare = onPrepare
        _store = StateObject(wrappedValue: TrainingProgramStore(owner: workouts.accountStorageKey, workoutStorageURL: workouts.storageURL))
    }

    private func t(_ en: String, _ uk: String, _ ru: String) -> String {
        gymText(en, uk, ru, languageCode: gymCurrentLanguageCode())
    }

    private func goalLabel(_ goal: String) -> String {
        switch TrainingGoal(rawValue: goal) {
        case .aestheticFatLoss: gymLocalized("Aesthetic fat loss")
        case .muscleGain: gymLocalized("Muscle gain")
        case .strength: gymLocalized("Strength")
        default: gymLocalized("Balanced")
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: GymTheme.Spacing.large) {
                if store.hasError {
                    GymPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(t("Could not confirm the saved program. Reload and try again.",
                                   "Не вдалося підтвердити збереження програми. Онови й повтори.",
                                   "Не удалось подтвердить сохранение программы. Обновите и повторите."))
                                .foregroundStyle(GymTheme.error)
                            Button(t("Reload program", "Оновити програму", "Обновить программу")) { store.reload() }
                                .buttonStyle(GymSecondaryButtonStyle())
                        }
                    }
                }
                if let p = store.program {
                    program(p)
                } else if !store.hasError {
                    GymPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(t("Four-week program", "Програма на чотири тижні", "Программа на четыре недели"))
                                .font(GymTheme.TypeScale.sectionTitle)
                            Text(t("Plan your training days. Each workout uses your latest results.",
                                   "Заплануй дні тренувань. Кожне тренування враховує твої останні результати.",
                                   "Запланируйте дни тренировок. Каждая тренировка учитывает последние результаты."))
                                .foregroundStyle(GymTheme.textSecondary)
                            Button(t("Create program", "Створити програму", "Создать программу")) { create() }
                                .buttonStyle(GymPrimaryButtonStyle())
                        }
                    }
                }
            }
            .id("program-start")
            .padding(.horizontal, GymTheme.screenHorizontalInset)
            .padding(.vertical, GymTheme.Spacing.large)
        }
        .onChange(of: store.program?.id) { _ in proxy.scrollTo("program-start", anchor: .top) }
        .onChange(of: store.program?.status) { _ in proxy.scrollTo("program-start", anchor: .top) }
        .onChange(of: store.hasError) { hasError in if hasError { proxy.scrollTo("program-start", anchor: .top) } }
        }
        .alert(t("Finish this program?", "Завершити програму?", "Завершить программу?"), isPresented: $showsFinish) {
            Button(t("Finish program", "Завершити програму", "Завершить программу")) {
                if confirmationID == store.program?.id { store.status("completed") }
            }
            Button(t("Cancel", "Скасувати", "Отмена"), role: .cancel) {}
        } message: {
            Text(t("Saved workouts stay in your history. You can reopen an unfinished schedule later.",
                   "Збережені тренування залишаться в історії. Незавершений розклад можна відновити пізніше.",
                   "Сохранённые тренировки останутся в истории. Незавершённое расписание можно возобновить позже."))
        }
        .alert(t("Start a new program?", "Почати нову програму?", "Начать новую программу?"), isPresented: $showsNewCycle) {
            Button(t("Create program", "Створити програму", "Создать программу")) { create(replacing: confirmationID) }
            Button(t("Cancel", "Скасувати", "Отмена"), role: .cancel) {}
        } message: {
            Text(t("This replaces the previous schedule. All saved workouts stay in your history.",
                   "Новий розклад замінить попередній. Усі збережені тренування залишаться в історії.",
                   "Новое расписание заменит предыдущее. Все сохранённые тренировки останутся в истории."))
        }
        .onChange(of: workouts.accountStorageKey) { _ in showsFinish = false; showsNewCycle = false; confirmationID = nil }
    }

    private func create(replacing id: UUID? = nil) {
        store.create(profile: TrainingProfileStore().load(accountStorageKey: workouts.accountStorageKey), replacing: id)
    }

    @ViewBuilder private func program(_ p: TrainingProgram) -> some View {
        let next = store.next()
        let completed = p.slots.filter { $0.workoutID != nil }.count
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(t("Four-week program", "Програма на чотири тижні", "Программа на четыре недели"))
                    .font(GymTheme.TypeScale.sectionTitle)
                Text(goalLabel(p.goal)).foregroundStyle(GymTheme.textSecondary)
                Text(t("Workouts completed: \(completed) of \(p.slots.count)",
                       "Виконано тренувань: \(completed) із \(p.slots.count)",
                       "Выполнено тренировок: \(completed) из \(p.slots.count)"))
                    .font(.subheadline).monospacedDigit()
                SwiftUI.ProgressView(value: Double(completed), total: Double(p.slots.count))
                if p.status == "completed" {
                    Text(t("Program finished", "Програму завершено", "Программа завершена")).font(.headline)
                    Button(t("New program", "Нова програма", "Новая программа")) {
                        confirmationID = p.id; showsNewCycle = true
                    }.buttonStyle(GymPrimaryButtonStyle())
                    if next != nil {
                        Button(t("Reopen program", "Відновити програму", "Возобновить программу")) { store.reopen() }
                            .buttonStyle(GymSecondaryButtonStyle())
                    }
                } else if p.status == "paused" {
                    Text(t("Program paused", "Програму призупинено", "Программа приостановлена")).font(.headline)
                    Button(t("Resume program", "Продовжити програму", "Продолжить программу")) { store.status("active") }
                        .buttonStyle(GymPrimaryButtonStyle())
                } else if let next {
                    Text(t("Next workout", "Наступне тренування", "Следующая тренировка")).font(.headline)
                    Text(gymFormattedDate(next.date, date: .abbreviated, time: .omitted))
                    Button(t("Prepare workout", "Підготувати тренування", "Подготовить тренировку"), action: onPrepare)
                        .buttonStyle(GymPrimaryButtonStyle())
                    if let match = store.matchingWorkout(next, workouts: workouts.workoutSummaries) {
                        Button(t("Count saved workout", "Зарахувати тренування", "Засчитать тренировку") + ": " + gymFormattedDate(match.date, date: .abbreviated, time: .omitted)) {
                            store.link(match)
                        }.buttonStyle(GymSecondaryButtonStyle())
                    }
                }
                if p.status != "completed" {
                    DisclosureGroup(t("Program options", "Дії з програмою", "Действия с программой")) {
                        VStack(spacing: 8) {
                            if p.status == "active" {
                                Button(t("Move next workout", "Перенести наступне тренування", "Перенести следующую тренировку")) { store.reschedule() }
                                    .buttonStyle(GymSecondaryButtonStyle())
                                Button(t("Pause program", "Призупинити програму", "Приостановить программу")) { store.status("paused") }
                                    .buttonStyle(GymSecondaryButtonStyle())
                            }
                            Button(t("Finish program", "Завершити програму", "Завершить программу")) {
                                confirmationID = p.id; showsFinish = true
                            }.buttonStyle(GymSecondaryButtonStyle())
                        }.padding(.top, 8)
                    }
                }
            }.disabled(store.hasError)
        }
        ForEach(0..<4, id: \.self) { week in
            GymPanel {
                DisclosureGroup(t("Week \(week + 1)", "Тиждень \(week + 1)", "Неделя \(week + 1)")) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(p.slots.dropFirst(week * p.days).prefix(p.days))) { slot in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(gymFormattedDate(slot.date, date: .abbreviated, time: .omitted))
                                Label(slot.workoutID == nil ? t("Planned", "Заплановано", "Запланировано") : t("Completed", "Виконано", "Выполнено"),
                                      systemImage: slot.workoutID == nil ? "calendar" : "checkmark.circle")
                                    .font(.subheadline).foregroundStyle(GymTheme.textSecondary)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }.padding(.top, 12)
                }
            }
        }
    }
}
