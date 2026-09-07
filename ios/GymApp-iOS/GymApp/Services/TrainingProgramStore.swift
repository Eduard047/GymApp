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
    @Published private(set) var hasError = false
    private let owner: String
    private let url: URL
    private let writeData: (Data, URL) throws -> Void
    private var committedData: Data?
    private struct Envelope: Codable { let version: Int; let owner: String; let program: TrainingProgram }

    init(owner: String, workoutStorageURL: URL,
         writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        precondition((1 ... 128).contains(owner.count) && owner.utf8.count <= 512)
        self.owner = owner
        self.url = Self.storageURL(forWorkoutStorageURL: workoutStorageURL)
        self.writeData = writeData
        reload()
    }

    static func storageURL(forWorkoutStorageURL workoutStorageURL: URL) -> URL {
        workoutStorageURL.deletingPathExtension().appendingPathExtension("training-program-v1.json")
    }

    func reload() {
        do {
            let raw = try readData()
            let value = try raw.map { data -> TrainingProgram in
                let envelope = try JSONDecoder().decode(Envelope.self, from: data)
                guard envelope.version == 1, envelope.owner == owner else { throw CocoaError(.fileReadCorruptFile) }
                try Self.validate(envelope.program)
                return envelope.program
            }
            committedData = raw
            program = value
            hasError = false
        } catch {
            hasError = true
        }
    }

    @discardableResult
    func create(profile: TrainingProfile, replacing expectedID: UUID? = nil,
                now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !hasError, program == nil ? expectedID == nil :
                program?.status == "completed" && program?.id == expectedID,
              let offsets = [2: [0, 3], 3: [0, 2, 4], 4: [0, 1, 3, 5],
                             5: [0, 1, 2, 3, 4], 6: [0, 1, 2, 3, 4, 5]][profile.workoutsPerWeek]
        else { hasError = true; return false }
        let start = calendar.startOfDay(for: now)
        let dates = (0..<4).flatMap { week in offsets.compactMap {
            calendar.date(byAdding: .day, value: week * 7 + $0, to: start)
        } }
        guard dates.count == profile.workoutsPerWeek * 4 else { hasError = true; return false }
        return save(TrainingProgram(id: UUID(), createdAt: now, days: profile.workoutsPerWeek,
            goal: profile.goal.rawValue, status: "active",
            slots: dates.map { TrainingProgramSlot(id: UUID(), date: $0, workoutID: nil) }))
    }

    func next(now: Date = Date(), calendar: Calendar = .current) -> TrainingProgramSlot? {
        program?.slots.first { $0.workoutID == nil }
    }

    func matchingWorkout(_ slot: TrainingProgramSlot, workouts: [WorkoutSessionSummary]) -> WorkoutSessionSummary? {
        guard let program, let i = program.slots.firstIndex(where: { $0.id == slot.id }) else { return nil }
        let until = program.slots.indices.contains(i + 1) ? program.slots[i + 1].date : slot.date.addingTimeInterval(7 * 86400)
        let used = Set(program.slots.compactMap(\.workoutID))
        return workouts.filter { $0.date >= slot.date && $0.date < until && !used.contains($0.workoutID) }
            .max { $0.date < $1.date }
    }

    func link(_ workout: WorkoutSessionSummary) {
        guard var p = program, p.status == "active", let slot = next(),
              matchingWorkout(slot, workouts: [workout])?.workoutID == workout.workoutID,
              let i = p.slots.firstIndex(where: { $0.id == slot.id }) else { return }
        p.slots[i].workoutID = workout.workoutID
        if p.slots.allSatisfy({ $0.workoutID != nil }) { p.status = "completed" }
        save(p)
    }

    func status(_ value: String) {
        guard ["active", "paused", "completed"].contains(value), var p = program,
              p.status != "completed" else { return }
        p.status = value
        save(p)
    }

    func reopen() {
        guard var p = program, p.status == "completed", p.slots.contains(where: { $0.workoutID == nil }) else { return }
        p.status = "active"
        save(p)
    }

    func reschedule(now: Date = Date(), calendar: Calendar = .current) {
        guard var p = program, p.status == "active", let slot = next(),
              let i = p.slots.firstIndex(where: { $0.id == slot.id }) else { return }
        let used = Set(p.slots.filter { $0.id != slot.id }.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: now)
        for _ in 0...p.slots.count {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { hasError = true; return }
            day = nextDay
            if !used.contains(day) {
                p.slots[i].date = day
                p.slots.sort { $0.date < $1.date }
                save(p)
                return
            }
        }
        hasError = true
    }

    private func readData() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 32769
        guard size <= 32768 else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf: url)
        guard data.count <= 32768 else { throw CocoaError(.fileReadTooLarge) }
        return data
    }

    @discardableResult private func save(_ value: TrainingProgram) -> Bool {
        do {
            guard !hasError, try readData() == committedData else { throw CocoaError(.fileWriteUnknown) }
            try Self.validate(value)
            let data = try JSONEncoder().encode(Envelope(version: 1, owner: owner, program: value))
            guard data.count <= 32768 else { throw CocoaError(.fileWriteUnknown) }
            try writeData(data, url)
            guard try readData() == data else { throw CocoaError(.fileWriteUnknown) }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = url
            try? mutable.setResourceValues(values)
            committedData = data
            program = value
            return true
        } catch {
            hasError = true
            return false
        }
    }

    private static func validate(_ p: TrainingProgram) throws {
        let now = Date()
        guard p.createdAt.timeIntervalSince1970.isFinite, p.createdAt <= now,
              p.days >= 2, p.days <= 6, p.goal.count <= 64,
              ["active", "paused", "completed"].contains(p.status), p.slots.count == p.days * 4,
              Set(p.slots.map(\.id)).count == p.slots.count,
              Set(p.slots.compactMap(\.workoutID)).count == p.slots.compactMap(\.workoutID).count,
              zip(p.slots, p.slots.dropFirst()).allSatisfy({ $0.date < $1.date }),
              p.slots.allSatisfy({
                  let time = $0.date.timeIntervalSince1970
                  return time.isFinite && time >= -62135769600 && time <= min(64092211200, now.timeIntervalSince1970 + 40 * 86400)
              }) else { throw CocoaError(.fileReadCorruptFile) }
    }
}
