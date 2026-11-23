import Foundation

/// Pure rules of the read-only Apple Health import. They implement
/// `shared/health-import-v1.json` (the same contract Android runs against Health Connect)
/// and know nothing about HealthKit, the store or the UI.
struct HealthImportHeartRateSample: Equatable, Sendable {
    let timeMillis: Int64
    let bpm: Double
}

struct HealthImportSession: Equatable, Sendable {
    /// The HKWorkout uuid string (the contract's `recordId`).
    let recordId: String
    let startMillis: Int64
    let endMillis: Int64
    /// Contract name of the exercise type (for example `traditionalStrengthTraining`),
    /// or nil when the HealthKit activity type is not mapped.
    let exerciseType: String?
    /// Bundle id of the app that wrote the workout.
    let sourceId: String
    let kilocalories: Double?
    let heartRateSamples: [HealthImportHeartRateSample]

    func withHeartRateSamples(
        _ samples: [HealthImportHeartRateSample]
    ) -> HealthImportSession {
        HealthImportSession(
            recordId: recordId,
            startMillis: startMillis,
            endMillis: endMillis,
            exerciseType: exerciseType,
            sourceId: sourceId,
            kilocalories: kilocalories,
            heartRateSamples: samples
        )
    }
}

struct HealthImportExistingWorkout: Equatable, Sendable {
    let startMillis: Int64
    let durationSeconds: Int?
}

struct HealthImportWorkout: Equatable, Sendable {
    let workoutStartedAt: Int64
    let durationSeconds: Int
    let gymCalories: Int
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let note: String
}

enum HealthImportSkipReason: String, CaseIterable, Sendable {
    case invalidRecord = "invalid-record"
    case ownApp = "own-app"
    case notGymType = "not-gym-type"
    case inProgress = "in-progress"
    case duration
    case duplicateReceipt = "duplicate-receipt"
    case overlap
}

enum HealthImportOutcome: Equatable, Sendable {
    case imported(receiptKey: String, workout: HealthImportWorkout)
    case skipped(HealthImportSkipReason)
}

struct HealthImportPlan: Equatable, Sendable {
    var imported: [(receiptKey: String, workout: HealthImportWorkout)] = []
    var skipped: [HealthImportSkipReason: Int] = [:]
    var truncated = 0

    static func == (lhs: HealthImportPlan, rhs: HealthImportPlan) -> Bool {
        lhs.skipped == rhs.skipped && lhs.truncated == rhs.truncated &&
            lhs.imported.count == rhs.imported.count &&
            zip(lhs.imported, rhs.imported).allSatisfy {
                $0.receiptKey == $1.receiptKey && $0.workout == $1.workout
            }
    }
}

enum HealthImportRules {
    static let windowDays = 30
    static let maxSessionsPerRun = 200
    static let maxRecordsScannedPerRun = 1_000
    static let maxHeartRateSamplesPerRun = 50_000
    static let minDurationSeconds = 60
    static let maxDurationSeconds = 86_400
    static let overlapToleranceSeconds = 120
    static let minAutoImportIntervalSeconds = 3_600
    static let minPlausibleBpm = 25.0
    static let maxPlausibleBpm = 240.0
    static let maxKilocalories = 100_000.0
    static let noteSeparator = " · "
    static let receiptKeyPrefix = "apple_health:"
    static let notePrefix = "Apple Health"
    /// Bundle id of this app. A `.`-suffixed variant (development or test builds) is also ours.
    static let ownSourceIds: [String] = ["com.setforge.gymapp.ios", "com.setforge.gymapp.ios.watchkitapp"]
    static let gymExerciseTypes: Set<String> = [
        "traditionalStrengthTraining",
        "functionalStrengthTraining",
        "coreTraining",
        "highIntensityIntervalTraining",
        "crossTraining",
        "gymnastics"
    ]
    /// Same range the activity-only cloud codec accepts for a workout start.
    private static let timestampRange: ClosedRange<Int64> =
        -62_135_769_600_000 ... 64_092_211_200_000

    static let maxReceiptKeyLength = 256

    /// A record id must be non-empty, free of control characters (Unicode category Cc) and
    /// short enough that the whole receipt key stays within `maxReceiptKeyLength` UTF-16 units.
    static func isValidRecordId(_ recordId: String) -> Bool {
        !recordId.isEmpty &&
            receiptKeyPrefix.utf16.count + recordId.utf16.count <= maxReceiptKeyLength &&
            !recordId.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    static func receiptKey(recordId: String) -> String {
        receiptKeyPrefix + recordId
    }

    static func isOwnSource(_ sourceId: String) -> Bool {
        ownSourceIds.contains { sourceId == $0 || sourceId.hasPrefix($0 + ".") }
    }

    static func durationSeconds(_ session: HealthImportSession) -> Int? {
        guard timestampRange.contains(session.startMillis),
              timestampRange.contains(session.endMillis),
              session.endMillis > session.startMillis else {
            return nil
        }
        let seconds = (session.endMillis - session.startMillis) / 1_000
        guard seconds >= Int64(minDurationSeconds),
              seconds <= Int64(maxDurationSeconds) else {
            return nil
        }
        return Int(seconds)
    }

    static func overlaps(
        _ session: HealthImportSession,
        existing: [HealthImportExistingWorkout]
    ) -> Bool {
        let tolerance = Int64(overlapToleranceSeconds) * 1_000
        return existing.contains { workout in
            let start = workout.startMillis
            let length = Int64(max(workout.durationSeconds ?? 0, 0)) * 1_000
            let (end, overflow) = start.addingReportingOverflow(length)
            let existingEnd = overflow ? Int64.max : end
            return saturatingSubtract(start, tolerance) <= session.endMillis &&
                saturatingAdd(existingEnd, tolerance) >= session.startMillis
        }
    }

    /// Steps 1-5 of the decision order. None of them depends on heart rate or calories, so the
    /// caller can run this before reading any samples.
    static func skipReason(
        for session: HealthImportSession,
        existingWorkouts: [HealthImportExistingWorkout],
        receipts: Set<String>,
        nowMillis: Int64 = .max
    ) -> HealthImportSkipReason? {
        if !isValidRecordId(session.recordId) { return .invalidRecord }
        if isOwnSource(session.sourceId) { return .ownApp }
        guard let type = session.exerciseType, gymExerciseTypes.contains(type) else {
            return .notGymType
        }
        guard durationSeconds(session) != nil else { return .duration }
        if session.endMillis > nowMillis { return .inProgress }
        if receipts.contains(receiptKey(recordId: session.recordId)) { return .duplicateReceipt }
        if overlaps(session, existing: existingWorkouts) { return .overlap }
        return nil
    }

    static func evaluate(
        _ session: HealthImportSession,
        existingWorkouts: [HealthImportExistingWorkout],
        receipts: Set<String>,
        languageCode: String,
        nowMillis: Int64 = .max
    ) -> HealthImportOutcome {
        if let reason = skipReason(
            for: session,
            existingWorkouts: existingWorkouts,
            receipts: receipts,
            nowMillis: nowMillis
        ) {
            return .skipped(reason)
        }
        guard let duration = durationSeconds(session),
              let type = session.exerciseType else {
            return .skipped(.duration)
        }
        let heartRate = heartRateSummary(session)
        let calories = gymCalories(session.kilocalories)
        let note = buildNote(
            type: type,
            durationSeconds: duration,
            gymCalories: calories,
            averageHeartRate: heartRate?.average,
            maximumHeartRate: heartRate?.maximum,
            languageCode: languageCode
        )
        return .imported(
            receiptKey: receiptKey(recordId: session.recordId),
            workout: HealthImportWorkout(
                workoutStartedAt: session.startMillis,
                durationSeconds: duration,
                gymCalories: calories,
                averageHeartRate: heartRate?.average,
                maximumHeartRate: heartRate?.maximum,
                note: note
            )
        )
    }

    /// Reads at most `maxRecordsScannedPerRun` records, drops own-app and non-gym records
    /// (counted as skipped) and keeps at most `maxSessionsPerRun` of the rest, newest start
    /// first. What does not fit is reported as truncated, not skipped.
    static func select(_ sessions: [HealthImportSession]) -> (
        candidates: [HealthImportSession],
        skipped: [HealthImportSkipReason: Int],
        truncated: Int
    ) {
        var skipped: [HealthImportSkipReason: Int] = [:]
        var candidates: [HealthImportSession] = []
        for session in sessions.prefix(maxRecordsScannedPerRun)
            .sorted(by: { $0.startMillis > $1.startMillis }) {
            if !isValidRecordId(session.recordId) {
                skipped[.invalidRecord, default: 0] += 1
            } else if isOwnSource(session.sourceId) {
                skipped[.ownApp, default: 0] += 1
            } else if session.exerciseType.map(gymExerciseTypes.contains) != true {
                skipped[.notGymType, default: 0] += 1
            } else {
                candidates.append(session)
            }
        }
        var truncated = 0
        if candidates.count > maxSessionsPerRun {
            truncated = candidates.count - maxSessionsPerRun
            candidates.removeLast(truncated)
        }
        return (candidates, skipped, truncated)
    }

    /// Whole-run planning used by tests and by the service once samples are available.
    /// `samples` supplies the heart-rate samples of a session (the service reads them lazily).
    static func plan(
        sessions: [HealthImportSession],
        existingWorkouts: [HealthImportExistingWorkout],
        receipts: Set<String>,
        languageCode: String,
        nowMillis: Int64 = .max,
        samples: (HealthImportSession) -> [HealthImportHeartRateSample] = { $0.heartRateSamples }
    ) -> HealthImportPlan {
        let selection = select(sessions)
        var plan = HealthImportPlan()
        plan.skipped = selection.skipped
        plan.truncated = selection.truncated
        var existing = existingWorkouts
        var knownReceipts = receipts
        let candidates = selection.candidates
        for candidate in candidates {
            if let reason = skipReason(
                for: candidate,
                existingWorkouts: existing,
                receipts: knownReceipts,
                nowMillis: nowMillis
            ) {
                plan.skipped[reason, default: 0] += 1
                continue
            }
            let full = candidate.withHeartRateSamples(samples(candidate))
            switch evaluate(
                full,
                existingWorkouts: existing,
                receipts: knownReceipts,
                languageCode: languageCode,
                nowMillis: nowMillis
            ) {
            case let .imported(key, workout):
                plan.imported.append((key, workout))
                knownReceipts.insert(key)
                existing.append(HealthImportExistingWorkout(
                    startMillis: workout.workoutStartedAt,
                    durationSeconds: workout.durationSeconds
                ))
            case let .skipped(reason):
                plan.skipped[reason, default: 0] += 1
            }
        }
        return plan
    }

    static func heartRateSummary(
        _ session: HealthImportSession
    ) -> (average: Int, maximum: Int)? {
        let values = session.heartRateSamples.lazy
            .filter {
                $0.timeMillis >= session.startMillis && $0.timeMillis <= session.endMillis &&
                    $0.bpm.isFinite && $0.bpm >= minPlausibleBpm && $0.bpm <= maxPlausibleBpm
            }
            .map(\.bpm)
        var count = 0
        var sum = 0.0
        var maximum = 0.0
        for value in values {
            count += 1
            sum += value
            maximum = max(maximum, value)
        }
        guard count > 0 else { return nil }
        return (
            average: Int((sum / Double(count) + 0.5).rounded(.down)),
            maximum: Int(maximum.rounded())
        )
    }

    static func gymCalories(_ kilocalories: Double?) -> Int {
        guard let kilocalories, kilocalories.isFinite,
              kilocalories >= 0, kilocalories <= maxKilocalories else { return 0 }
        return Int((kilocalories + 0.5).rounded(.down))
    }

    static func buildNote(
        type: String,
        durationSeconds: Int,
        gymCalories: Int,
        averageHeartRate: Int?,
        maximumHeartRate: Int?,
        languageCode: String
    ) -> String {
        let language = normalizedLanguage(languageCode)
        var segments = [notePrefix, typeLabel(type, language: language)]
        segments.append(
            durationLabel(language: language) + " " +
                "\(durationSeconds / 60):" + String(format: "%02d", durationSeconds % 60)
        )
        if gymCalories > 0 {
            segments.append(language == "en" ? "kcal \(gymCalories)" : "ккал \(gymCalories)")
        }
        if let averageHeartRate, averageHeartRate > 0 {
            let label: String
            switch language {
            case "uk": label = "Сер пульс"
            case "ru": label = "Средний пульс"
            default: label = "Avg HR"
            }
            segments.append("\(label) \(averageHeartRate)")
        }
        if let maximumHeartRate, maximumHeartRate > 0 {
            let label: String
            switch language {
            case "uk": label = "Макс пульс"
            case "ru": label = "Макс. пульс"
            default: label = "Max HR"
            }
            segments.append("\(label) \(maximumHeartRate)")
        }
        return segments.joined(separator: noteSeparator)
    }

    private static func durationLabel(language: String) -> String {
        switch language {
        case "uk": "Тривалість"
        case "ru": "Длительность"
        default: "Duration"
        }
    }

    static func typeLabel(_ type: String, language: String) -> String {
        let labels: [String: (en: String, uk: String, ru: String)] = [
            "traditionalStrengthTraining": (
                "Strength training", "Силове тренування", "Силовая тренировка"
            ),
            "functionalStrengthTraining": (
                "Functional strength training",
                "Функціональне силове тренування",
                "Функциональная силовая тренировка"
            ),
            "coreTraining": (
                "Core training", "Тренування м'язів кора", "Тренировка мышц кора"
            ),
            "highIntensityIntervalTraining": ("HIIT", "HIIT", "HIIT"),
            "crossTraining": ("Cross training", "Крос-тренінг", "Кросс-тренинг"),
            "gymnastics": ("Gymnastics", "Гімнастика", "Гимнастика")
        ]
        guard let label = labels[type] else { return type }
        switch normalizedLanguage(language) {
        case "uk": return label.uk
        case "ru": return label.ru
        default: return label.en
        }
    }

    private static func normalizedLanguage(_ code: String) -> String {
        let lowered = code.lowercased()
        if lowered.hasPrefix("uk") { return "uk" }
        if lowered.hasPrefix("ru") { return "ru" }
        return "en"
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? (rhs > 0 ? Int64.max : Int64.min) : value
    }

    private static func saturatingSubtract(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.subtractingReportingOverflow(rhs)
        return overflow ? (rhs > 0 ? Int64.min : Int64.max) : value
    }
}
