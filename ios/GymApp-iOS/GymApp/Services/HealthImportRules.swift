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
        segments.append(durationLabel(language: language) + " " + noteDuration(durationSeconds))
        if gymCalories > 0 {
            // Number before the unit, like everywhere else in the app ("356 kcal").
            segments.append(language == "en" ? "\(gymCalories) kcal" : "\(gymCalories) ккал")
        }
        if let averageHeartRate, averageHeartRate > 0 {
            let label: String
            switch language {
            case "uk": label = "Середній пульс"
            case "ru": label = "Средний пульс"
            default: label = "Avg HR"
            }
            segments.append("\(label) \(averageHeartRate)")
        }
        if let maximumHeartRate, maximumHeartRate > 0 {
            let label: String
            switch language {
            case "uk": label = "Макс. пульс"
            case "ru": label = "Макс. пульс"
            default: label = "Max HR"
            }
            segments.append("\(label) \(maximumHeartRate)")
        }
        return segments.joined(separator: noteSeparator)
    }

    /// Note duration: m:ss below one hour, h:mm:ss from one hour on (two-digit minutes and seconds).
    static func noteDuration(_ durationSeconds: Int) -> String {
        let hours = durationSeconds / 3_600
        let minutes = (durationSeconds % 3_600) / 60
        let seconds = String(format: "%02d", durationSeconds % 60)
        if hours > 0 {
            return "\(hours):" + String(format: "%02d", minutes) + ":\(seconds)"
        }
        return "\(minutes):\(seconds)"
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
                "Core training", "Тренування м’язів кора", "Тренировка мышц кора"
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

// MARK: - Activity-only workout presentation

/// Where an activity-only workout (time and metrics, no exercises or sets) came from.
enum ActivityWorkoutSource: Equatable {
    case garmin
    case healthConnect
    case appleHealth
    case wearOS
    case appleWatch
    case unknown
}

/// What the workout row and the detail screen show for an activity-only workout. The source is
/// read from the note prefix; a workout may have been imported on the other platform and arrived
/// through cloud sync, so every prefix is recognised here. Metrics are read from the note in the
/// current wording ("356 kcal", "Duration 1:02:05", «Середній пульс») and in the wording stored
/// before it changed ("kcal 356", "Duration 62:05", «Сер пульс»), in all three languages.
/// Stored notes are never rewritten. Mirrors Android `parseActivityWorkoutPresentation`.
struct ActivityWorkoutPresentation: Equatable {
    let source: ActivityWorkoutSource
    let savedTypeLabel: String?
    let durationSeconds: Int?
    let kilocalories: Int?
    let averageHeartRate: Int?
    let maximumHeartRate: Int?

    static func parse(_ note: String?) -> ActivityWorkoutPresentation {
        var text = ""
        if let note, note.utf8.count <= maxNoteBytes { text = note }
        let segments = text.components(separatedBy: HealthImportRules.noteSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let source: ActivityWorkoutSource
        if captures(garminMarker, in: text) != nil {
            source = .garmin
        } else if segments.first == healthConnectPrefix {
            source = .healthConnect
        } else if segments.first == HealthImportRules.notePrefix {
            source = .appleHealth
        } else if segments.contains(wearOSMarker) {
            // A watch note may start with the athlete's own text, so the marker can be any segment.
            source = .wearOS
        } else if segments.contains(appleWatchMarker) {
            source = .appleWatch
        } else {
            source = .unknown
        }

        var savedTypeLabel: String?
        if source == .healthConnect || source == .appleHealth, segments.count > 1,
           !isMetricSegment(segments[1]) {
            savedTypeLabel = segments[1]
        }

        // Group 1 is the older "kcal 356" order, group 2 the current "356 kcal" order.
        let calorieText = group(1, of: calorieValue, in: text) ?? group(2, of: calorieValue, in: text)
        var kilocalories = bounded(calorieText, 1 ... maxKilocalories)
        if kilocalories == nil {
            kilocalories = bounded(group(1, of: gymCalorieValue, in: text), 1 ... maxKilocalories)
        }
        var averageHeartRate = bounded(
            group(1, of: averageHeartRateValue, in: text), 1 ... maxHeartRate
        )
        var maximumHeartRate = bounded(
            group(1, of: maximumHeartRateValue, in: text), 1 ... maxHeartRate
        )
        if let average = averageHeartRate, let maximum = maximumHeartRate, average > maximum {
            averageHeartRate = nil
            maximumHeartRate = nil
        }
        return ActivityWorkoutPresentation(
            source: source,
            savedTypeLabel: savedTypeLabel,
            durationSeconds: group(1, of: durationValue, in: text).flatMap(parseDuration),
            kilocalories: kilocalories,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate
        )
    }

    /// Activity type in the given language when it is a known type, else as it was saved.
    func typeLabel(languageCode: String) -> String? {
        guard let savedTypeLabel else { return nil }
        let wanted = savedTypeLabel.replacingOccurrences(of: "'", with: "’")
        guard let known = Self.knownTypeLabels.first(where: {
            $0.en == wanted || $0.uk == wanted || $0.ru == wanted
        }) else { return savedTypeLabel }
        let lowered = languageCode.lowercased()
        if lowered.hasPrefix("uk") { return known.uk }
        if lowered.hasPrefix("ru") { return known.ru }
        return known.en
    }

    /// The real source of the workout; "Garmin" only for a Garmin workout.
    func sourceTitle(languageCode: String) -> String {
        switch source {
        case .garmin:
            gymText(
                "Garmin free workout", "Вільне тренування Garmin", "Свободная тренировка Garmin",
                languageCode: languageCode
            )
        case .healthConnect:
            gymText(
                "Workout from Health Connect", "Тренування з Health Connect",
                "Тренировка из Health Connect",
                languageCode: languageCode
            )
        case .appleHealth:
            gymText(
                "Workout from Apple Health", "Тренування з Apple Health",
                "Тренировка из Apple Health",
                languageCode: languageCode
            )
        case .wearOS:
            gymText(
                "Wear OS workout", "Тренування з Wear OS", "Тренировка с Wear OS",
                languageCode: languageCode
            )
        case .appleWatch:
            gymText(
                "Apple Watch workout", "Тренування з Apple Watch", "Тренировка с Apple Watch",
                languageCode: languageCode
            )
        case .unknown:
            gymText(
                "Free workout", "Вільне тренування", "Свободная тренировка",
                languageCode: languageCode
            )
        }
    }

    /// Row and detail subtitle: the source, then the activity type when the import knows it.
    func subtitle(languageCode: String) -> String {
        let title = sourceTitle(languageCode: languageCode)
        guard let type = typeLabel(languageCode: languageCode), !type.isEmpty else { return title }
        return "\(title) · \(type)"
    }

    private static let maxNoteBytes = 16_384
    private static let maxKilocalories = 100_000
    private static let maxHeartRate = 240
    private static let healthConnectPrefix = "Health Connect"
    private static let wearOSMarker = "Wear OS"
    private static let appleWatchMarker = "Apple Watch"
    private static let garminMarker = #"^Garmin(?: Fenix 8)?(?: ·|$)"#
    private static let durationValue =
        #"(?:Duration|Тривалість|Длительность)\s+([0-9]{1,5}:[0-9]{2}(?::[0-9]{2})?)(?![0-9:])"#
    /// "356 kcal" / «356 ккал» (current) and "kcal 356" / «ккал 356» (older) as a whole segment.
    private static let calorieValue =
        #"(?:^| · )(?:(?:kcal|ккал)\s+([0-9]{1,6})|([0-9]{1,6})\s+(?:kcal|ккал))(?= ·|$)"#
    private static let gymCalorieValue = #"Gym\s+(?:kcal|ккал)\s+([0-9]{1,6})(?![0-9])"#
    private static let averageHeartRateValue =
        #"(?:Avg HR|Сер пульс|Сер\. пульс|Середній пульс|Средний пульс)\s+([0-9]{1,3})(?![0-9])"#
    private static let maximumHeartRateValue =
        #"(?:Max HR|Макс пульс|Макс\. пульс)\s+([0-9]{1,3})(?![0-9])"#

    /// Type labels of both health stores, so a workout imported on the other platform reads in
    /// the current language too.
    private static let knownTypeLabels: [(en: String, uk: String, ru: String)] = [
        ("Strength training", "Силове тренування", "Силовая тренировка"),
        (
            "Functional strength training", "Функціональне силове тренування",
            "Функциональная силовая тренировка"
        ),
        ("Core training", "Тренування м’язів кора", "Тренировка мышц кора"),
        ("HIIT", "HIIT", "HIIT"),
        ("Cross training", "Крос-тренінг", "Кросс-тренинг"),
        ("Gymnastics", "Гімнастика", "Гимнастика"),
        ("Weightlifting", "Важка атлетика", "Тяжёлая атлетика"),
        ("Calisthenics", "Калістеніка", "Калистеника"),
        ("Boot camp", "Буткемп", "Буткемп")
    ]

    private static func isMetricSegment(_ segment: String) -> Bool {
        [durationValue, calorieValue, averageHeartRateValue, maximumHeartRateValue]
            .contains { captures($0, in: segment) != nil }
    }

    private static func captures(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0 ..< match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    /// One capture group of the first match, nil when the pattern or that group did not match.
    private static func group(_ index: Int, of pattern: String, in text: String) -> String? {
        guard let groups = captures(pattern, in: text), groups.indices.contains(index) else {
            return nil
        }
        return groups[index]
    }

    private static func bounded(_ value: String?, _ range: ClosedRange<Int>) -> Int? {
        guard let text = value, let number = Int(text), range.contains(number) else {
            return nil
        }
        return number
    }

    private static func parseDuration(_ value: String) -> Int? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 2 || parts.count == 3, !parts.contains(nil) else { return nil }
        let numbers = parts.compactMap { $0 }
        let seconds: Int
        if numbers.count == 2 {
            guard (0 ... 59).contains(numbers[1]) else { return nil }
            seconds = numbers[0] * 60 + numbers[1]
        } else {
            guard (0 ... 59).contains(numbers[1]), (0 ... 59).contains(numbers[2]) else { return nil }
            seconds = numbers[0] * 3_600 + numbers[1] * 60 + numbers[2]
        }
        return seconds > 0 ? seconds : nil
    }
}
