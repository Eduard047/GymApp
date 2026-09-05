import Foundation

struct TrainingProgramSlot: Codable, Hashable, Identifiable {
    let id: UUID
    var date: Date
    var workoutID: UUID?
}
struct TrainingProgram: Codable, Hashable, Identifiable {
    let id: UUID
    let createdAt: Date
    let days: Int
    let goal: String
    var status: String
    var slots: [TrainingProgramSlot]
}

@MainActor final class TrainingProgramStore: ObservableObject {
    @Published private(set) var program: TrainingProgram?
    private let owner: String
    private let url: URL
    private struct Envelope: Codable { let version: Int; let owner: String; let program: TrainingProgram }
    init(owner: String, workoutStorageURL: URL) {
        precondition((1 ... 128).contains(owner.count) && owner.utf8.count <= 512)
        self.owner = owner
        url = Self.storageURL(forWorkoutStorageURL: workoutStorageURL)
        program = Self.load(url: url, owner: owner)
    }
    static func storageURL(forWorkoutStorageURL workoutStorageURL: URL) -> URL {
        workoutStorageURL.deletingPathExtension().appendingPathExtension("training-program-v1.json")
    }
    func create(profile: TrainingProfile, now: Date = Date(), calendar: Calendar = .current) {
        let offsets = [2:[0,3],3:[0,2,4],4:[0,1,3,5],5:[0,1,2,3,4],6:[0,1,2,3,4,5]][profile.workoutsPerWeek]!
        let start = calendar.startOfDay(for: now)
        let slots = (0..<4).flatMap { week in offsets.map { TrainingProgramSlot(id: UUID(), date: calendar.date(byAdding: .day, value: week*7+$0, to: start)!, workoutID: nil) } }
        try? save(TrainingProgram(id: UUID(), createdAt: now, days: profile.workoutsPerWeek, goal: profile.goal.rawValue, status: "active", slots: slots))
    }
    func next(now: Date = Date(), calendar: Calendar = .current) -> TrainingProgramSlot? {
        guard let program else { return nil }
        return program.slots.first { $0.workoutID == nil }
    }
    func matchingWorkout(_ slot: TrainingProgramSlot, workouts: [WorkoutSessionSummary]) -> WorkoutSessionSummary? {
        guard let program, let i = program.slots.firstIndex(where: { $0.id == slot.id }) else { return nil }
        let until = program.slots.indices.contains(i+1) ? program.slots[i+1].date : slot.date.addingTimeInterval(7*86400)
        let used = Set(program.slots.compactMap(\.workoutID))
        return workouts.filter { $0.date >= slot.date && $0.date < until && !used.contains($0.workoutID) }.max { $0.date < $1.date }
    }
    func link(_ workout: WorkoutSessionSummary) { guard var p=program, p.status=="active", let slot=next(), matchingWorkout(slot, workouts:[workout])?.workoutID==workout.workoutID, let i=p.slots.firstIndex(where:{$0.id==slot.id}) else{return};p.slots[i].workoutID=workout.workoutID;if p.slots.allSatisfy({$0.workoutID != nil}){p.status="completed"};try? save(p) }
    func status(_ value:String){guard ["active","paused","completed"].contains(value),var p=program,p.status != "completed" else{return};p.status=value;try? save(p)}
    func reschedule(now:Date=Date(),calendar:Calendar = .current){guard var p=program,p.status=="active",let slot=next(now:now,calendar:calendar),let i=p.slots.firstIndex(where:{$0.id==slot.id})else{return};let used=Set(p.slots.filter{$0.id != slot.id}.map{calendar.startOfDay(for:$0.date)});var date=calendar.startOfDay(for:calendar.date(byAdding:.day,value:1,to:now)!);while used.contains(date){date=calendar.date(byAdding:.day,value:1,to:date)!};p.slots[i].date=date;p.slots.sort{$0.date<$1.date};try? save(p)}
    private func save(_ value:TrainingProgram)throws{try Self.validate(value);let data=try JSONEncoder().encode(Envelope(version:1,owner:owner,program:value));guard data.count<=32768 else{throw CocoaError(.fileWriteUnknown)};try data.write(to:url,options:.atomic);var values=URLResourceValues();values.isExcludedFromBackup=true;var mutable=url;try? mutable.setResourceValues(values);program=value}
    private static func load(url:URL,owner:String)->TrainingProgram?{guard let size=(try? url.resourceValues(forKeys:[.fileSizeKey]))?.fileSize,size<=32768,let data=try? Data(contentsOf:url),data.count<=32768,let e=try? JSONDecoder().decode(Envelope.self,from:data),e.version==1,e.owner==owner,(try? validate(e.program)) != nil else{return nil};return e.program}
    private static func validate(_ p:TrainingProgram)throws{guard p.createdAt.timeIntervalSince1970.isFinite,p.createdAt<=Date(),p.slots.allSatisfy({let time=$0.date.timeIntervalSince1970;return time.isFinite && time >= -62135769600 && time <= min(64092211200,Date().timeIntervalSince1970+40*86400)}),p.days>=2,p.days<=6,p.goal.count<=64,["active","paused","completed"].contains(p.status),p.slots.count==p.days*4,Set(p.slots.map(\.id)).count==p.slots.count,Set(p.slots.compactMap(\.workoutID)).count==p.slots.compactMap(\.workoutID).count,zip(p.slots,p.slots.dropFirst()).allSatisfy({$0.date<$1.date}) else{throw CocoaError(.fileReadCorruptFile)}}
}
