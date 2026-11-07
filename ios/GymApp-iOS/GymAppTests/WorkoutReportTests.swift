import Foundation
import XCTest
@testable import GymApp

@MainActor
final class WorkoutReportTests: XCTestCase {
    private let truncated = "Report truncated at the private PDF safety limit."

    private func lines(
        exercises: [Exercise],
        sessions: [WorkoutSession],
        language: String = "en"
    ) -> [String] {
        WorkoutReport.lines(
            exercises: exercises,
            sessions: sessions,
            exportedAt: Date(timeIntervalSince1970: 1_750_000_000),
            languageCode: language,
            uses24Hour: true,
            now: Date(timeIntervalSince1970: 1_750_000_000)
        )
    }

    private func session(
        _ index: Int,
        exercise: Exercise,
        note: String? = nil,
        sets: [WorkoutSet] = [WorkoutSet(weight: 82.5, reps: 5)]
    ) -> WorkoutSession {
        WorkoutSession(
            date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400),
            note: note ?? "n\(index)",
            exercises: [WorkoutExercise(exerciseID: exercise.id, sets: sets)]
        )
    }

    func testSelectionKeepsNewestSixtyNewestFirstWithTieOrder() {
        let dates = (0 ..< 200).map { Date(timeIntervalSince1970: 1_000 + Double($0)) }
        let picked = WorkoutReport.selectSessionIndices(dates: dates, limit: 60)
        XCTAssertEqual(picked.count, 60)
        XCTAssertEqual(picked.first, 199)
        XCTAssertEqual(picked.last, 140)

        let shuffled = [30, 10, 50, 20, 50].map { Date(timeIntervalSince1970: Double($0)) }
        XCTAssertEqual(WorkoutReport.selectSessionIndices(dates: shuffled, limit: 3), [4, 2, 0])
    }

    func testTwoHundredWorkoutsListNewestSixtyAndMoreCount() {
        let bench = Exercise(name: "Bench Press")
        let sessions = (0 ..< 200).map { session($0, exercise: bench) }
        let report = lines(exercises: [bench], sessions: sessions)

        XCTAssertEqual(report.first, "GymApp PRIVATE workout backup report")
        XCTAssertEqual(report[2], "Schema: 1")
        XCTAssertTrue(report.contains("## Summary"))
        XCTAssertTrue(report.contains("Exercises: 1"))
        XCTAssertTrue(report.contains("Workouts: 200"))
        XCTAssertEqual(report.firstIndex(of: "## Exercises").map { report[$0 + 1] }, "- Bench Press")
        XCTAssertEqual(report.last, "More workouts: 140")
        let dateLines = report.filter { $0.contains(" · ") }
        XCTAssertEqual(dateLines.count, 60)
        XCTAssertTrue(dateLines.first?.hasSuffix("- n199") == true)
        XCTAssertTrue(dateLines.last?.hasSuffix("- n140") == true)
        XCTAssertTrue(report.contains("  - Bench Press: 82.5 kg × 5"))
        XCTAssertFalse(report.contains(truncated))
    }

    func testUkrainianAndRussianLabelsAndCommaWeights() {
        let squat = Exercise(name: "Squat")
        let sessions = [session(1, exercise: squat, sets: [WorkoutSet(weight: 82.5, reps: 5)])]
        let uk = lines(exercises: [squat], sessions: sessions, language: "uk")
        XCTAssertEqual(uk.first, "ПРИВАТНИЙ звіт резервної копії тренувань GymApp")
        XCTAssertTrue(uk.contains("## Підсумок"))
        XCTAssertTrue(uk.contains("Вправ: 1"))
        XCTAssertTrue(uk.contains("Тренувань: 1"))
        XCTAssertTrue(uk.contains("  - Squat: 82,5 кг × 5"))
        let ru = lines(exercises: [squat], sessions: sessions, language: "ru")
        XCTAssertTrue(ru.contains("## Сводка"))
        XCTAssertTrue(ru.contains("Упражнений: 1"))
        XCTAssertTrue(ru.contains("  - Squat: 82,5 кг × 5"))
        XCTAssertEqual(WorkoutReport.weightText(1250.25, languageCode: "uk"), "1250,25")
        XCTAssertEqual(WorkoutReport.weightText(.infinity, languageCode: "en"), "0")
    }

    func testEmptyAndPerItemCaps() {
        XCTAssertTrue(lines(exercises: [], sessions: []).contains("No exercises exported."))
        XCTAssertTrue(lines(exercises: [], sessions: []).contains("No workouts exported."))

        let many = (0 ..< 130).map { Exercise(name: "Ex \($0)") }
        let sets = (0 ..< 25).map { WorkoutSet(weight: Double($0), reps: 1) }
        let workoutExercises = (0 ..< 30).map { WorkoutExercise(exerciseID: many[$0].id, sets: sets) }
        let big = WorkoutSession(date: Date(timeIntervalSince1970: 1_700_000_000), exercises: workoutExercises)
        let report = lines(exercises: many, sessions: [big])
        XCTAssertTrue(report.contains("More exercises: 10"))
        XCTAssertEqual(report.filter { $0.hasPrefix("  - Ex ") }.count, 24)
        XCTAssertTrue(report.contains("  … More exercises: 6"))
        XCTAssertTrue(report.first { $0.hasPrefix("  - Ex 0:") }?.hasSuffix(", … more sets: 5") == true)
    }

    func testReportIsCappedAt480LinesWithTruncationNotice() {
        let many = (0 ..< 24).map { Exercise(name: "Ex \($0)") }
        let sessions = (0 ..< 60).map { index in
            WorkoutSession(
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400),
                exercises: many.map { WorkoutExercise(exerciseID: $0.id, sets: [WorkoutSet(weight: 50, reps: 5)]) }
            )
        }
        let report = lines(exercises: many, sessions: sessions)
        XCTAssertEqual(report.count, 480)
        XCTAssertEqual(report.last, truncated)
    }

    func testBoundedTextStripsControlsAndCaps() {
        XCTAssertEqual(WorkoutReport.boundedText("a\nb\rc\u{7}d "), "a b c d")
        XCTAssertEqual(WorkoutReport.boundedText(String(repeating: "x", count: 500)).count, 320)
    }

    func testWrappedLinesNeverExceedWidth() {
        let measure: (String) -> CGFloat = { text in
            CGFloat(text.reduce(0) { sum, ch in sum + (ch == " " ? 3 : (ch.isUppercase ? 8 : 5)) })
        }
        let text = "Тренування " + String(repeating: "ПРИСІДАННЯ СО ШТАНГОЮ ", count: 8) + String(repeating: "А", count: 120)
        let wrapped = WorkoutReport.wrap(text, maxWidth: 120, measure: measure)
        XCTAssertGreaterThan(wrapped.count, 1)
        for line in wrapped { XCTAssertLessThanOrEqual(measure(line), 120, line) }
        XCTAssertEqual(WorkoutReport.wrap("abc", maxWidth: 100, measure: measure), ["abc"])
        XCTAssertEqual(WorkoutReport.wrap("", maxWidth: 100, measure: measure), [""])
        let words = "one two three four five six seven eight nine ten"
        XCTAssertEqual(WorkoutReport.wrap(words, maxWidth: 60, measure: measure).joined(separator: " "), words)
    }

    func testPDFIsWrittenAndReportExcludesAccountIdentifiers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gymapp-workout-report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try WorkoutStore(accountStorageKey: "report-account-canary", directoryURL: directory)
        let exercise = try store.addExercise(name: "PRIVATE EXERCISE CANARY")
        _ = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            note: "PRIVATE NOTE CANARY",
            exercises: [WorkoutExerciseDraft(exerciseID: exercise.id, sets: [.init(weight: 123.45, reps: 7)])]
        )
        let report = lines(exercises: store.exercises, sessions: store.workouts)
        let text = report.joined(separator: "\n")
        XCTAssertTrue(text.contains("PRIVATE EXERCISE CANARY"))
        XCTAssertTrue(text.contains("123.45 kg × 7"))
        for forbidden in ["report-account-canary", "@example.com", "access-token", "refresh-token"] {
            XCTAssertFalse(text.contains(forbidden))
        }

        let url = try ExportService.writeWorkoutPDF(lines: report)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("GymApp-workouts-"))
        XCTAssertEqual(String(data: data.prefix(5), encoding: .ascii), "%PDF-")
        XCTAssertGreaterThan(data.count, 500)
    }
}
