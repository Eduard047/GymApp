import Foundation

/// Human-readable workout report, the iPhone twin of Android's `backupReportLines`
/// (ExerciseListScreen.kt). Same sections, order, labels, caps and newest-60 selection.
/// It takes only exercises and workouts, so account ids, emails and tokens cannot reach it.
enum WorkoutReport {
    static let maxPages = 24
    static let maxLines = 480
    static let maxExercises = 120
    static let maxSessions = 60
    static let maxExercisesPerSession = 24
    static let maxSetsPerExercise = 20
    static let maxTextChars = 320
    static let schemaVersion = 1

    /// Indices of the `limit` newest sessions by date, newest first. Ties keep the later
    /// position first, matching Android `selectPdfSessionIndices`.
    static func selectSessionIndices(dates: [Date], limit: Int) -> [Int] {
        let millis = dates.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
        return millis.indices
            .sorted { lhs, rhs in
                millis[lhs] != millis[rhs] ? millis[lhs] > millis[rhs] : lhs > rhs
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// Android `boundedPdfText`: control characters become spaces, capped, trimmed.
    static func boundedText(_ value: String) -> String {
        var result = ""
        var count = 0
        for character in value {
            if count >= maxTextChars { break }
            let isControl = character.unicodeScalars.contains { $0.properties.generalCategory == .control }
            result.append(isControl ? " " : character)
            count += 1
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Android `pdfWeightText`: the shared weight display format (up to 2 decimals, no grouping).
    static func weightText(_ weight: Double, languageCode: String) -> String {
        gymMachineWeightEditText(weight.isFinite ? weight : 0, languageCode: languageCode)
    }

    static func lines(
        exercises: [Exercise],
        sessions: [WorkoutSession],
        exportedAt: Date = Date(),
        languageCode: String = gymCurrentLanguageCode(),
        uses24Hour: Bool = gymSystemUses24Hour(),
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [String] {
        func t(_ en: String, _ uk: String, _ ru: String) -> String {
            gymText(en, uk, ru, languageCode: languageCode)
        }
        let exerciseNameByID = Dictionary(
            exercises.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        var lines: [String] = []

        lines.append(t(
            "GymApp PRIVATE workout backup report",
            "ПРИВАТНИЙ звіт резервної копії тренувань GymApp",
            "ПРИВАТНЫЙ отчёт резервной копии тренировок GymApp"
        ))
        let exported = gymFormattedTimestamp(
            exportedAt,
            date: .abbreviated,
            time: .shortened,
            languageCode: languageCode,
            uses24Hour: uses24Hour
        )
        lines.append(t("Exported: \(exported)", "Експортовано: \(exported)", "Экспортировано: \(exported)"))
        lines.append(t("Schema: \(schemaVersion)", "Схема: \(schemaVersion)", "Схема: \(schemaVersion)"))
        lines.append(t(
            "PRIVATE: includes exercise names, workout dates and notes, weights, and repetitions.",
            "ПРИВАТНО: містить назви вправ, дати й нотатки тренувань, вагу та повторення.",
            "ПРИВАТНО: содержит названия упражнений, даты и заметки тренировок, вес и повторения."
        ))
        lines.append("")
        lines.append("## " + t("Summary", "Підсумок", "Сводка"))
        lines.append(t(
            "Exercises: \(exercises.count)",
            "Вправ: \(exercises.count)",
            "Упражнений: \(exercises.count)"
        ))
        lines.append(t(
            "Workouts: \(sessions.count)",
            "Тренувань: \(sessions.count)",
            "Тренировок: \(sessions.count)"
        ))

        lines.append("")
        lines.append("## " + t("Exercises", "Вправи", "Упражнения"))
        if exercises.isEmpty {
            lines.append(t("No exercises exported.", "Вправи не експортовано.", "Упражнения не экспортированы."))
        } else {
            let exerciseLimit = min(exercises.count, maxExercises)
            for exercise in exercises.prefix(exerciseLimit) {
                let name = boundedText(exercise.name)
                if !name.isEmpty { lines.append("- \(name)") }
            }
            if exercises.count > exerciseLimit {
                let more = exercises.count - exerciseLimit
                lines.append(t("More exercises: \(more)", "Ще вправ: \(more)", "Ещё упражнений: \(more)"))
            }
        }

        lines.append("")
        lines.append("## " + t("Workouts", "Тренування", "Тренировки"))
        if sessions.isEmpty {
            lines.append(t("No workouts exported.", "Тренування не експортовано.", "Тренировки не экспортированы."))
        } else {
            let order = selectSessionIndices(dates: sessions.map(\.date), limit: maxSessions)
            for sessionIndex in order {
                if lines.count >= maxLines { break }
                let session = sessions[sessionIndex]
                let day = gymShortDate(session.date, calendar: calendar, now: now, languageCode: languageCode)
                let time = gymFormattedTimeOfDay(session.date, languageCode: languageCode, uses24Hour: uses24Hour)
                let note = boundedText(session.note ?? "")
                lines.append("\(day) · \(time)" + (note.isEmpty ? "" : " - \(note)"))
                let exerciseLimit = min(session.exercises.count, maxExercisesPerSession)
                for workoutExercise in session.exercises.prefix(exerciseLimit) {
                    if lines.count >= maxLines { break }
                    let sets = workoutExercise.sets
                    let setLimit = min(sets.count, maxSetsPerExercise)
                    let setParts = sets.prefix(setLimit).map { set in
                        let weight = weightText(set.weight, languageCode: languageCode)
                        return t("\(weight) kg × \(set.reps)", "\(weight) кг × \(set.reps)", "\(weight) кг × \(set.reps)")
                    }
                    var moreSets = ""
                    if sets.count > setLimit {
                        let more = sets.count - setLimit
                        moreSets = ", … " + t("more sets: \(more)", "ще підходів: \(more)", "ещё подходов: \(more)")
                    }
                    let name = boundedText(exerciseNameByID[workoutExercise.exerciseID] ?? "")
                    lines.append("  - \(name): " + setParts.joined(separator: ", ") + moreSets)
                }
                if session.exercises.count > exerciseLimit {
                    let more = session.exercises.count - exerciseLimit
                    lines.append("  … " + t("More exercises: \(more)", "Ще вправ: \(more)", "Ещё упражнений: \(more)"))
                }
                lines.append("")
            }
            if sessions.count > order.count {
                let more = sessions.count - order.count
                lines.append(t("More workouts: \(more)", "Ще тренувань: \(more)", "Ещё тренировок: \(more)"))
            }
        }

        if lines.count >= maxLines {
            lines[maxLines - 1] = t(
                "Report truncated at the private PDF safety limit.",
                "Звіт скорочено на безпечній межі приватного PDF.",
                "Отчёт сокращён из-за ограничения размера приватного PDF."
            )
        }
        return Array(lines.prefix(maxLines))
    }

    /// Android `wrapPdfText`: every returned line measures at most `maxWidth`; over-wide words
    /// are split by characters so wrapping always terminates.
    static func wrap(_ text: String, maxWidth: CGFloat, measure: (String) -> CGFloat) -> [String] {
        precondition(maxWidth > 0)
        let bounded = String(text.prefix(maxTextChars))
        if measure(bounded) <= maxWidth { return [bounded] }
        var lines: [String] = []
        var current = ""
        for word in bounded.split(separator: " ", omittingEmptySubsequences: false) {
            var chunks: [String] = []
            var rest = Array(word)
            while !rest.isEmpty, measure(String(rest)) > maxWidth {
                var end = max(1, rest.count - 1)
                while end > 1, measure(String(rest[0 ..< end])) > maxWidth { end -= 1 }
                chunks.append(String(rest[0 ..< end]))
                rest = Array(rest[end...])
            }
            if !rest.isEmpty || chunks.isEmpty { chunks.append(String(rest)) }
            for chunk in chunks {
                if current.trimmingCharacters(in: .whitespaces).isEmpty {
                    current = chunk
                } else if measure("\(current) \(chunk)") <= maxWidth {
                    current += " \(chunk)"
                } else {
                    lines.append(current)
                    current = chunk
                }
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(current) }
        return lines
    }
}
