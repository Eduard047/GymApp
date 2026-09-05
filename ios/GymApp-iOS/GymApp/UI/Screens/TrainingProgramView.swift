import SwiftUI

struct TrainingProgramView: View {
    @ObservedObject var workouts: WorkoutStore
    @StateObject private var store: TrainingProgramStore
    let onPrepare: () -> Void
    init(workouts: WorkoutStore, onPrepare: @escaping () -> Void) {
        self.workouts=workouts;self.onPrepare=onPrepare
        _store=StateObject(wrappedValue:TrainingProgramStore(owner:workouts.accountStorageKey,workoutStorageURL:workouts.storageURL))
    }
    private func t(_ en:String,_ uk:String,_ ru:String)->String{gymText(en,uk,ru,languageCode:gymCurrentLanguageCode())}
    private func goalLabel(_ goal: String) -> String {
        switch TrainingGoal(rawValue: goal) {
        case .aestheticFatLoss: gymLocalized("Aesthetic fat loss")
        case .muscleGain: gymLocalized("Muscle gain")
        case .strength: gymLocalized("Strength")
        default: gymLocalized("Balanced")
        }
    }
    var body:some View{ScrollView{VStack(spacing:16){if let p=store.program{program(p)}else{GymPanel { VStack(alignment: .leading, spacing: 12) { Label(t("Four-week program","Програма на чотири тижні","Программа на четыре недели"), systemImage:"calendar.badge.plus").font(.title2.bold()); Text(t("Schedule four weeks from your current goal and frequency.","Заплануй чотири тижні за поточною ціллю та частотою.","Запланируйте четыре недели по текущей цели и частоте.")) } };Button(t("Create program","Створити програму","Создать программу")){store.create(profile:TrainingProfileStore().load(accountStorageKey:workouts.accountStorageKey))}.buttonStyle(GymPrimaryButtonStyle())}}.padding()}}
    @ViewBuilder private func program(_ p:TrainingProgram)->some View{let next=store.next();let linked=p.slots.filter{$0.workoutID != nil}.count;let match=next.flatMap{store.matchingWorkout($0,workouts:workouts.workoutSummaries)}
        GymPanel{VStack(alignment:.leading,spacing:12){Text(t("Four-week program","Програма на чотири тижні","Программа на четыре недели")).font(.title2.bold());Text("\(goalLabel(p.goal)) · \(linked)/\(p.slots.count)");ProgressView(value:Double(linked),total:Double(p.slots.count));Text(p.status=="paused" ? t("Paused","Призупинено","Приостановлено") : p.status=="completed" ? t("Finished","Завершено","Завершено") : next.map{t("Next","Наступне","Следующее")+": "+gymFormattedDate($0.date, date: .abbreviated, time: .omitted)} ?? t("All sessions linked","Усі тренування прив’язано","Все тренировки привязаны"));if p.status=="active",next != nil{Button(t("Prepare next workout","Підготувати наступне тренування","Подготовить следующую тренировку"),action:onPrepare).buttonStyle(GymPrimaryButtonStyle());Text(t("Smart Coach recalculates targets from current history in the editor.","Розумний тренер перерахує цілі з поточної історії в редакторі.","Умный тренер пересчитает цели по текущей истории в редакторе.")).font(.caption);Button(t("Move to next free day","Перенести на вільний день","Перенести на свободный день")){store.reschedule()}.buttonStyle(GymSecondaryButtonStyle());if let match{Button(t("Link saved workout","Прив’язати збережене тренування","Привязать сохранённую тренировку")+": "+gymFormattedDate(match.date, date: .abbreviated, time: .omitted)){store.link(match)}.buttonStyle(GymSecondaryButtonStyle())}};HStack{if p.status=="active"{Button(t("Pause","Призупинити","Приостановить")){store.status("paused")}}else if p.status=="paused"{Button(t("Resume","Продовжити","Продолжить")){store.status("active")}};if p.status != "completed"{Button(t("Finish","Завершити","Завершить")){store.status("completed")}}}}}
        ForEach(Array(p.slots.enumerated()),id:\.element.id){i,slot in HStack{Text("\(i+1). "+gymFormattedDate(slot.date, date: .abbreviated, time: .omitted));Spacer();Text(slot.workoutID==nil ? "—":"✓")}.frame(minHeight:44).padding(.horizontal)}
    }
}
