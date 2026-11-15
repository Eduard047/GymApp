import XCTest
@testable import GymApp

final class ActiveWorkoutFinishFlowTests: XCTestCase {
    // MARK: Decision

    func testFinishesImmediatelyWhenEverySetIsLoggedOrNothingIsPlanned() {
        XCTAssertEqual(ActiveWorkoutFinishDecision.decide(planned: 6, completed: 6, hasCommitIntent: false), .finishNow)
        XCTAssertEqual(ActiveWorkoutFinishDecision.decide(planned: 0, completed: 0, hasCommitIntent: false), .finishNow)
        XCTAssertEqual(ActiveWorkoutFinishDecision.decide(planned: 3, completed: 5, hasCommitIntent: false), .finishNow)
    }

    func testAsksWithTheUnloggedCount() {
        XCTAssertEqual(
            ActiveWorkoutFinishDecision.decide(planned: 6, completed: 5, hasCommitIntent: false),
            .confirmUnlogged(count: 1)
        )
        XCTAssertEqual(
            ActiveWorkoutFinishDecision.decide(planned: 10, completed: 3, hasCommitIntent: false),
            .confirmUnlogged(count: 7)
        )
    }

    func testPendingCommitRetryNeverAsks() {
        XCTAssertEqual(ActiveWorkoutFinishDecision.decide(planned: 6, completed: 2, hasCommitIntent: true), .finishNow)
    }

    // MARK: Plural copy

    func testWorkoutMessageRussianPlurals() {
        let ru = AppLanguage.russian.rawValue
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutMessage(unlogged: 1, languageCode: ru), "Не записан 1 подход — он не попадёт в историю.")
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutMessage(unlogged: 2, languageCode: ru), "Не записано 2 подхода — они не попадут в историю.")
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutMessage(unlogged: 5, languageCode: ru), "Не записано 5 подходов — они не попадут в историю.")
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutMessage(unlogged: 11, languageCode: ru), "Не записано 11 подходов — они не попадут в историю.")
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutMessage(unlogged: 21, languageCode: ru), "Не записан 21 подход — он не попадёт в историю.")
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutMessage(unlogged: 22, languageCode: ru), "Не записано 22 подхода — они не попадут в историю.")
    }

    func testWorkoutMessageUkrainianAndEnglish() {
        let uk = AppLanguage.ukrainian.rawValue
        let en = AppLanguage.english.rawValue
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutMessage(unlogged: 1, languageCode: uk), "Не записано 1 підхід — він не потрапить в історію.")
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutMessage(unlogged: 3, languageCode: uk), "Не записано 3 підходи — вони не потраплять в історію.")
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutMessage(unlogged: 12, languageCode: uk), "Не записано 12 підходів — вони не потраплять в історію.")
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutMessage(unlogged: 1, languageCode: en), "1 set isn't logged — it won't be saved.")
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutMessage(unlogged: 4, languageCode: en), "4 sets aren't logged — they won't be saved.")
    }

    func testExerciseDialogCopy() {
        let ru = AppLanguage.russian.rawValue
        let uk = AppLanguage.ukrainian.rawValue
        let en = AppLanguage.english.rawValue
        XCTAssertEqual(ActiveWorkoutFinishCopy.exerciseTitle(languageCode: ru), "Завершить упражнение?")
        XCTAssertEqual(ActiveWorkoutFinishCopy.exerciseMessage(unlogged: 1, languageCode: ru), "Не записан 1 подход")
        XCTAssertEqual(ActiveWorkoutFinishCopy.exerciseMessage(unlogged: 3, languageCode: ru), "Не записано 3 подхода")
        XCTAssertEqual(ActiveWorkoutFinishCopy.exerciseMessage(unlogged: 5, languageCode: ru), "Не записано 5 подходов")
        XCTAssertEqual(ActiveWorkoutFinishCopy.exerciseMessage(unlogged: 2, languageCode: uk), "Не записано 2 підходи")
        XCTAssertEqual(ActiveWorkoutFinishCopy.exerciseMessage(unlogged: 1, languageCode: en), "1 set isn't logged")
        XCTAssertEqual(ActiveWorkoutFinishCopy.exerciseMessage(unlogged: 2, languageCode: en), "2 sets aren't logged")
        XCTAssertEqual(ActiveWorkoutFinishCopy.exerciseFinishWithoutButton(unlogged: 1, languageCode: ru), "Завершить без него")
        XCTAssertEqual(ActiveWorkoutFinishCopy.exerciseFinishWithoutButton(unlogged: 2, languageCode: ru), "Завершить без них")
        XCTAssertEqual(ActiveWorkoutFinishCopy.exerciseFinishWithoutButton(unlogged: 1, languageCode: uk), "Завершити без нього")
        XCTAssertEqual(ActiveWorkoutFinishCopy.exerciseFinishWithoutButton(unlogged: 1, languageCode: en), "Finish without it")
    }

    func testButtonCopy() {
        let ru = AppLanguage.russian.rawValue
        let uk = AppLanguage.ukrainian.rawValue
        let en = AppLanguage.english.rawValue
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutTitle(languageCode: ru), "Завершить тренировку?")
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutTitle(languageCode: uk), "Завершити тренування?")
        XCTAssertEqual(ActiveWorkoutFinishCopy.workoutTitle(languageCode: en), "Finish workout?")
        XCTAssertEqual(ActiveWorkoutFinishCopy.finishButton(languageCode: ru), "Завершить")
        XCTAssertEqual(ActiveWorkoutFinishCopy.finishButton(languageCode: uk), "Завершити")
        XCTAssertEqual(ActiveWorkoutFinishCopy.finishButton(languageCode: en), "Finish")
        XCTAssertEqual(ActiveWorkoutFinishCopy.markAllDoneButton(languageCode: ru), "Отметить все как выполненные")
        XCTAssertEqual(ActiveWorkoutFinishCopy.markAllDoneButton(languageCode: uk), "Позначити всі як виконані")
        XCTAssertEqual(ActiveWorkoutFinishCopy.markAllDoneButton(languageCode: en), "Mark all as done")
    }

    // MARK: Input normalization

    func testNormalizerStripsLeadingZeros() {
        XCTAssertEqual(GymNumericInputNormalizer.normalize("006"), "6")
        XCTAssertEqual(GymNumericInputNormalizer.normalize("0060"), "60")
        XCTAssertEqual(GymNumericInputNormalizer.normalize("060"), "60")
        XCTAssertEqual(GymNumericInputNormalizer.normalize("00"), "0")
        XCTAssertEqual(GymNumericInputNormalizer.normalize("000,5"), "0,5")
        XCTAssertEqual(GymNumericInputNormalizer.normalize("007.25"), "7.25")
    }

    func testNormalizerKeepsValidValues() {
        for value in ["", "0", "5", "60", "100", "0.5", "0,5", "0,", "0.", ".5", ",5", "102,5", "-5", "abc", "1e5"] {
            XCTAssertEqual(GymNumericInputNormalizer.normalize(value), value, value)
        }
    }

    func testNormalizedTextParsesToTypedNumber() {
        XCTAssertEqual(GymWeightFieldFormat.parse(GymNumericInputNormalizer.normalize("006")), 6)
        XCTAssertEqual(GymWeightFieldFormat.parse(GymNumericInputNormalizer.normalize("060")), 60)
        XCTAssertEqual(GymWeightFieldFormat.parse(GymNumericInputNormalizer.normalize("0,5")), 0.5)
    }
}
