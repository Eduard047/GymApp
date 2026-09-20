import Foundation

struct TrainingProgramExercisePlan: Codable, Hashable, Identifiable {
    let position: Int
    var exerciseID: UUID
    var approvedAlternativeExerciseIDs: [UUID]
    var rotationSeed: Int

    var id: Int { position }

    init(
        position: Int,
        exerciseID: UUID,
        approvedAlternativeExerciseIDs: [UUID] = [],
        rotationSeed: Int = 0
    ) {
        self.position = position
        self.exerciseID = exerciseID
        self.approvedAlternativeExerciseIDs = approvedAlternativeExerciseIDs
        self.rotationSeed = rotationSeed
    }

    /// The primary exercise followed by the user-approved alternatives, preserving order.
    var candidateExerciseIDs: [UUID] {
        var result = [exerciseID]
        for alternativeID in approvedAlternativeExerciseIDs
            where alternativeID != exerciseID && !result.contains(alternativeID) {
            result.append(alternativeID)
        }
        return result
    }

    /// Resolves a stable exercise for a rotation occurrence without using randomness.
    func resolvedExerciseID(forRotationIndex rotationIndex: Int) -> UUID {
        let candidates = candidateExerciseIDs
        guard candidates.count > 1 else { return exerciseID }

        let rotation = Self.positiveModulo(rotationIndex, candidates.count)
        let seed = Self.positiveModulo(rotationSeed, candidates.count)
        return candidates[(rotation + seed) % candidates.count]
    }

    private static func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}

struct TrainingProgramWorkoutPlan: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String?
    var exercises: [TrainingProgramExercisePlan]

    init(
        id: UUID = UUID(),
        title: String? = nil,
        exercises: [TrainingProgramExercisePlan] = []
    ) {
        self.id = id
        self.title = title
        self.exercises = exercises
    }

    func exercise(at position: Int) -> TrainingProgramExercisePlan? {
        exercises.first { $0.position == position }
    }

    func resolvedExerciseID(at position: Int, rotationIndex: Int) -> UUID? {
        exercise(at: position)?.resolvedExerciseID(forRotationIndex: rotationIndex)
    }
}

struct TrainingProgramSlot: Codable, Hashable, Identifiable {
    let id: UUID
    var date: Date
    var workoutID: UUID?
    /// The occurrence number used by deterministic exercise rotation for this slot.
    var rotationIndex: Int
    /// A future workout plan assigned specifically to this date.
    var workoutPlan: TrainingProgramWorkoutPlan?

    init(
        id: UUID = UUID(),
        date: Date,
        workoutID: UUID? = nil,
        rotationIndex: Int = 0,
        workoutPlan: TrainingProgramWorkoutPlan? = nil
    ) {
        self.id = id
        self.date = date
        self.workoutID = workoutID
        self.rotationIndex = rotationIndex
        self.workoutPlan = workoutPlan
    }
}

struct TrainingProgram: Codable, Hashable, Identifiable {
    let id: UUID
    let createdAt: Date
    let days: Int
    let goal: String
    var status: String
    /// Calendar weekday values (1 = Sunday ... 7 = Saturday).
    var selectedWeekdays: [Int]
    var slots: [TrainingProgramSlot]

    init(
        id: UUID,
        createdAt: Date,
        days: Int,
        goal: String,
        status: String,
        slots: [TrainingProgramSlot],
        selectedWeekdays: [Int] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.days = days
        self.goal = goal
        self.status = status
        self.selectedWeekdays = selectedWeekdays
        self.slots = slots
    }
}

@MainActor final class TrainingProgramStore: ObservableObject {
    @Published private(set) var program: TrainingProgram?
    @Published private(set) var hasError = false

    private let owner: String
    private let url: URL
    private let writeData: (Data, URL) throws -> Void
    private var committedData: Data?

    private static let persistedSchemaVersion = 2
    private static let oldestSupportedPersistedSchemaVersion = 1
    private static let maximumFileBytes = 32_768
    private static let maximumPlanExerciseCount = 64
    private static let maximumApprovedAlternatives = 32
    private static let maximumTitleLength = 120
    private static let maximumRotationSeed = 1_000_000
    private static let maximumSlotRotationIndex = 10_000
    private static let minimumSupportedTimestamp: TimeInterval = -62_135_769_600
    private static let maximumSupportedTimestamp: TimeInterval = 64_092_211_200

    private struct Envelope: Codable {
        let version: Int
        let owner: String
        let program: TrainingProgram
    }

    private struct VersionHeader: Decodable {
        let version: Int
        let owner: String
    }

    private struct LegacyEnvelope: Decodable {
        let version: Int
        let owner: String
        let program: LegacyTrainingProgram
    }

    private struct LegacyTrainingProgram: Decodable {
        let id: UUID
        let createdAt: Date
        let days: Int
        let goal: String
        let status: String
        let slots: [LegacyTrainingProgramSlot]
    }

    private struct LegacyTrainingProgramSlot: Decodable {
        let id: UUID
        let date: Date
        let workoutID: UUID?
    }

    private struct DecodedProgram {
        let program: TrainingProgram
        let wasMigrated: Bool
    }

    init(
        owner: String,
        workoutStorageURL: URL,
        writeData: @escaping (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        }
    ) {
        precondition((1 ... 128).contains(owner.count) && owner.utf8.count <= 512)
        self.owner = owner
        self.url = Self.storageURL(forWorkoutStorageURL: workoutStorageURL)
        self.writeData = writeData
        reload()
    }

    static func storageURL(forWorkoutStorageURL workoutStorageURL: URL) -> URL {
        // Keep the v1 path so existing files are discovered and migrated in place.
        workoutStorageURL
            .deletingPathExtension()
            .appendingPathExtension("training-program-v1.json")
    }

    func reload() {
        do {
            let raw = try readData()
            guard let raw else {
                committedData = nil
                program = nil
                hasError = false
                return
            }

            let decoded = try Self.decodePersistedProgram(
                raw,
                owner: owner,
                calendar: .current
            )
            committedData = raw
            program = decoded.program
            hasError = false

            // The atomic write keeps the v1 file intact if migration cannot be confirmed.
            if decoded.wasMigrated {
                _ = save(decoded.program)
            }
        } catch {
            hasError = true
        }
    }

    @discardableResult
    func create(
        profile: TrainingProfile,
        selectedWeekdays: [Int]? = nil,
        replacing expectedID: UUID? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard !hasError,
              program == nil
                ? expectedID == nil
                : program?.status == "completed" && program?.id == expectedID
        else {
            return false
        }

        let days = profile.workoutsPerWeek
        let dates: [Date]
        let weekdays: [Int]

        if let selectedWeekdays {
            guard let normalizedWeekdays = Self.normalizedWeekdays(
                selectedWeekdays,
                expectedCount: days
            ),
            let generatedDates = Self.dates(
                for: normalizedWeekdays,
                startingAt: now,
                calendar: calendar
            ) else {
                return false
            }
            weekdays = normalizedWeekdays
            dates = generatedDates
        } else {
            // Preserve the existing API's date behavior for callers that have not
            // adopted weekday selection yet.
            guard let generatedDates = Self.legacyDates(
                for: days,
                startingAt: now,
                calendar: calendar
            ) else {
                return false
            }
            dates = generatedDates
            weekdays = Array(
                dates.prefix(days).map {
                    calendar.component(.weekday, from: $0)
                }
            )
        }

        guard dates.count == days * 4,
              weekdays.count == days,
              let value = Self.makeProgram(
                  profile: profile,
                  selectedWeekdays: weekdays,
                  dates: dates,
                  createdAt: now
              ) else {
            return false
        }
        return save(value)
    }

    /// Changes the recurring weekdays before any workout has been linked.
    /// Existing slot IDs and assigned future plans are preserved.
    @discardableResult
    func setSelectedWeekdays(
        _ weekdays: [Int],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard !hasError,
              var current = program,
              current.status != "completed",
              current.slots.allSatisfy({ $0.workoutID == nil }),
              let normalizedWeekdays = Self.normalizedWeekdays(
                  weekdays,
                  expectedCount: current.days
              ),
              let dates = Self.dates(
                  for: normalizedWeekdays,
                  startingAt: now,
                  calendar: calendar
              ) else {
            return false
        }

        guard dates.count == current.slots.count else { return false }
        current.selectedWeekdays = normalizedWeekdays
        for index in current.slots.indices {
            current.slots[index].date = dates[index]
            current.slots[index].rotationIndex = index / current.days
        }
        return save(current)
    }

    func next(now: Date = Date(), calendar: Calendar = .current) -> TrainingProgramSlot? {
        program?.slots.first { $0.workoutID == nil }
    }

    func slot(id: UUID) -> TrainingProgramSlot? {
        program?.slots.first { $0.id == id }
    }

    func matchingWorkout(
        _ slot: TrainingProgramSlot,
        workouts: [WorkoutSessionSummary]
    ) -> WorkoutSessionSummary? {
        guard let program,
              let index = program.slots.firstIndex(where: { $0.id == slot.id }) else {
            return nil
        }
        let until = program.slots.indices.contains(index + 1)
            ? program.slots[index + 1].date
            : slot.date.addingTimeInterval(7 * 86_400)
        let used = Set(program.slots.compactMap(\.workoutID))
        return workouts
            .filter {
                $0.date >= slot.date &&
                $0.date < until &&
                !used.contains($0.workoutID)
            }
            .max { $0.date < $1.date }
    }

    func link(_ workout: WorkoutSessionSummary) {
        guard let slot = next() else { return }
        _ = link(workout, to: slot.id)
    }

    /// Links a saved workout to a specific planned slot.
    @discardableResult
    func link(_ workout: WorkoutSessionSummary, to slotID: UUID) -> Bool {
        guard var current = program,
              current.status == "active",
              let index = current.slots.firstIndex(where: { $0.id == slotID }),
              current.slots[index].workoutID == nil,
              matchingWorkout(current.slots[index], workouts: [workout])?.workoutID
                  == workout.workoutID else {
            return false
        }

        current.slots[index].workoutID = workout.workoutID
        if current.slots.allSatisfy({ $0.workoutID != nil }) {
            current.status = "completed"
        }
        return save(current)
    }

    func workoutPlan(for slotID: UUID) -> TrainingProgramWorkoutPlan? {
        slot(id: slotID)?.workoutPlan
    }

    /// Assigns a plan to one future slot without starting a workout.
    @discardableResult
    func assignWorkoutPlan(
        _ plan: TrainingProgramWorkoutPlan,
        to slotID: UUID
    ) -> Bool {
        guard !hasError,
              var current = program,
              current.status != "completed",
              let index = current.slots.firstIndex(where: { $0.id == slotID }),
              current.slots[index].workoutID == nil else {
            return false
        }

        guard (try? Self.validate(plan)) != nil else { return false }
        current.slots[index].workoutPlan = plan
        return save(current)
    }

    @discardableResult
    func removeWorkoutPlan(from slotID: UUID) -> Bool {
        guard !hasError,
              var current = program,
              current.status != "completed",
              let index = current.slots.firstIndex(where: { $0.id == slotID }),
              current.slots[index].workoutID == nil,
              current.slots[index].workoutPlan != nil else {
            return false
        }

        current.slots[index].workoutPlan = nil
        return save(current)
    }

    func resolvedExerciseID(for slotID: UUID, position: Int) -> UUID? {
        guard let slot = slot(id: slotID),
              let plan = slot.workoutPlan else {
            return nil
        }
        return plan.resolvedExerciseID(
            at: position,
            rotationIndex: slot.rotationIndex
        )
    }

    func status(_ value: String) {
        guard ["active", "paused", "completed"].contains(value),
              var p = program,
              p.status != "completed" else {
            return
        }
        p.status = value
        _ = save(p)
    }

    func reopen() {
        guard var p = program,
              p.status == "completed",
              p.slots.contains(where: { $0.workoutID == nil }) else {
            return
        }
        p.status = "active"
        _ = save(p)
    }

    func reschedule(now: Date = Date(), calendar: Calendar = .current) {
        guard var p = program,
              p.status == "active",
              let slot = next(),
              let index = p.slots.firstIndex(where: { $0.id == slot.id }) else {
            return
        }
        let used = Set(
            p.slots
                .filter { $0.id != slot.id }
                .map { calendar.startOfDay(for: $0.date) }
        )
        var day = calendar.startOfDay(for: now)
        for _ in 0 ... p.slots.count {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                hasError = true
                return
            }
            day = nextDay
            if !used.contains(day) {
                p.slots[index].date = day
                p.slots.sort { $0.date < $1.date }
                _ = save(p)
                return
            }
        }
        hasError = true
    }

    private func readData() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Self.maximumFileBytes + 1
        guard size <= Self.maximumFileBytes else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumFileBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        return data
    }

    @discardableResult
    private func save(_ value: TrainingProgram) -> Bool {
        do {
            guard !hasError, try readData() == committedData else {
                throw CocoaError(.fileWriteUnknown)
            }
            try Self.validate(value)
            let data = try JSONEncoder().encode(
                Envelope(
                    version: Self.persistedSchemaVersion,
                    owner: owner,
                    program: value
                )
            )
            guard data.count <= Self.maximumFileBytes else {
                throw CocoaError(.fileWriteUnknown)
            }
            try writeData(data, url)
            guard try readData() == data else {
                throw CocoaError(.fileWriteUnknown)
            }

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

    private static func decodePersistedProgram(
        _ data: Data,
        owner: String,
        calendar: Calendar
    ) throws -> DecodedProgram {
        let decoder = JSONDecoder()
        let header = try decoder.decode(VersionHeader.self, from: data)
        guard header.owner == owner,
              (oldestSupportedPersistedSchemaVersion ... persistedSchemaVersion)
                  .contains(header.version) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        switch header.version {
        case 1:
            let legacy = try decoder.decode(LegacyEnvelope.self, from: data)
            try validate(legacy.program)
            let migrated = try migrate(legacy.program, calendar: calendar)
            return DecodedProgram(program: migrated, wasMigrated: true)
        case persistedSchemaVersion:
            let current = try decoder.decode(Envelope.self, from: data)
            guard current.owner == owner, current.version == persistedSchemaVersion else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try validate(current.program)
            return DecodedProgram(program: current.program, wasMigrated: false)
        default:
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private static func migrate(
        _ legacy: LegacyTrainingProgram,
        calendar: Calendar
    ) throws -> TrainingProgram {
        let weekdays = inferredWeekdays(
            from: legacy.slots,
            expectedCount: legacy.days,
            calendar: calendar
        )
        let slots = legacy.slots.enumerated().map { index, slot in
            TrainingProgramSlot(
                id: slot.id,
                date: slot.date,
                workoutID: slot.workoutID,
                rotationIndex: min(index / legacy.days, maximumSlotRotationIndex)
            )
        }
        let migrated = TrainingProgram(
            id: legacy.id,
            createdAt: legacy.createdAt,
            days: legacy.days,
            goal: legacy.goal,
            status: legacy.status,
            slots: slots,
            selectedWeekdays: weekdays
        )
        try validate(migrated)
        return migrated
    }

    private static func makeProgram(
        profile: TrainingProfile,
        selectedWeekdays: [Int],
        dates: [Date],
        createdAt: Date
    ) -> TrainingProgram? {
        guard dates.count == profile.workoutsPerWeek * 4 else { return nil }
        let slots = dates.enumerated().map { index, date in
            TrainingProgramSlot(
                date: date,
                rotationIndex: index / profile.workoutsPerWeek
            )
        }
        return TrainingProgram(
            id: UUID(),
            createdAt: createdAt,
            days: profile.workoutsPerWeek,
            goal: profile.goal.rawValue,
            status: "active",
            slots: slots,
            selectedWeekdays: selectedWeekdays
        )
    }

    private static func legacyDates(
        for days: Int,
        startingAt now: Date,
        calendar: Calendar
    ) -> [Date]? {
        guard let offsets = legacyOffsets(for: days) else { return nil }
        let start = calendar.startOfDay(for: now)
        return (0 ..< 4).flatMap { week in
            offsets.compactMap {
                calendar.date(
                    byAdding: .day,
                    value: week * 7 + $0,
                    to: start
                )
            }
        }
    }

    private static func legacyOffsets(for days: Int) -> [Int]? {
        [
            2: [0, 3],
            3: [0, 2, 4],
            4: [0, 1, 3, 5],
            5: [0, 1, 2, 3, 4],
            6: [0, 1, 2, 3, 4, 5]
        ][days]
    }

    private static func dates(
        for weekdays: [Int],
        startingAt now: Date,
        calendar: Calendar
    ) -> [Date]? {
        let start = calendar.startOfDay(for: now)
        let offsets = (0 ..< 7).compactMap { offset -> Int? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return weekdays.contains(calendar.component(.weekday, from: date)) ? offset : nil
        }
        guard offsets.count == weekdays.count else { return nil }
        return (0 ..< 4).flatMap { week in
            offsets.compactMap {
                calendar.date(
                    byAdding: .day,
                    value: week * 7 + $0,
                    to: start
                )
            }
        }
    }

    private static func normalizedWeekdays(
        _ weekdays: [Int],
        expectedCount: Int
    ) -> [Int]? {
        let normalized = weekdays.sorted()
        guard normalized.count == expectedCount,
              normalized.allSatisfy({ (1 ... 7).contains($0) }),
              Set(normalized).count == normalized.count else {
            return nil
        }
        return normalized
    }

    private static func inferredWeekdays(
        from slots: [LegacyTrainingProgramSlot],
        expectedCount: Int,
        calendar: Calendar
    ) -> [Int] {
        let inferred = Array(
            Set(slots.map { calendar.component(.weekday, from: $0.date) })
        ).sorted()
        guard inferred.count == expectedCount else {
            return Array(1 ... 7).prefix(expectedCount).map { $0 }
        }
        return inferred
    }

    private static func validate(_ program: TrainingProgram) throws {
        try validateCommon(
            createdAt: program.createdAt,
            days: program.days,
            goal: program.goal,
            status: program.status,
            slotCount: program.slots.count
        )
        guard normalizedWeekdays(
            program.selectedWeekdays,
            expectedCount: program.days
        ) == program.selectedWeekdays,
        Set(program.slots.map(\.id)).count == program.slots.count,
        Set(program.slots.compactMap(\.workoutID)).count
            == program.slots.compactMap(\.workoutID).count,
        zip(program.slots, program.slots.dropFirst()).allSatisfy({ $0.date < $1.date }),
        program.slots.allSatisfy({ slot in
            return isSupportedDate(slot.date) &&
                (0 ... maximumSlotRotationIndex).contains(slot.rotationIndex) &&
                (try? validate(slot.workoutPlan)) != nil
        }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private static func validate(_ legacy: LegacyTrainingProgram) throws {
        try validateCommon(
            createdAt: legacy.createdAt,
            days: legacy.days,
            goal: legacy.goal,
            status: legacy.status,
            slotCount: legacy.slots.count
        )
        guard Set(legacy.slots.map(\.id)).count == legacy.slots.count,
              Set(legacy.slots.compactMap(\.workoutID)).count
                  == legacy.slots.compactMap(\.workoutID).count,
              zip(legacy.slots, legacy.slots.dropFirst())
                  .allSatisfy({ $0.date < $1.date }),
              legacy.slots.allSatisfy({ isSupportedDate($0.date) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private static func validateCommon(
        createdAt: Date,
        days: Int,
        goal: String,
        status: String,
        slotCount: Int
    ) throws {
        let now = Date()
        guard createdAt.timeIntervalSince1970.isFinite,
              createdAt <= now,
              (2 ... 6).contains(days),
              goal.count <= 64,
              ["active", "paused", "completed"].contains(status),
              slotCount == days * 4 else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private static func validate(
        _ plan: TrainingProgramWorkoutPlan
    ) throws {
        if let title = plan.title {
            guard title.count <= maximumTitleLength,
                  !title.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0)
                  }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }

        guard plan.exercises.count <= maximumPlanExerciseCount,
              plan.exercises.map(\.position) == Array(0 ..< plan.exercises.count) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        for exercise in plan.exercises {
            guard (0 ... maximumRotationSeed).contains(exercise.rotationSeed),
                  exercise.approvedAlternativeExerciseIDs.count <= maximumApprovedAlternatives,
                  Set(exercise.approvedAlternativeExerciseIDs).count
                      == exercise.approvedAlternativeExerciseIDs.count,
                  !exercise.approvedAlternativeExerciseIDs.contains(exercise.exerciseID) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }

    private static func validate(_ plan: TrainingProgramWorkoutPlan?) throws {
        if let plan {
            try validate(plan)
        }
    }

    private static func isSupportedDate(_ date: Date) -> Bool {
        let time = date.timeIntervalSince1970
        return time.isFinite &&
            time >= minimumSupportedTimestamp &&
            time <= min(
                maximumSupportedTimestamp,
                Date().timeIntervalSince1970 + 40 * 86_400
            )
    }
}
