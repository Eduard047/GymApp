import Foundation
import CoreGraphics
import XCTest
@testable import GymApp

@MainActor
final class ProductExperienceV2Tests: XCTestCase {
    func testTutorialCompletionIsVersionedAndAccountBound() throws {
        let suiteName = "AppTutorialStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppTutorialStore(defaults: defaults)

        XCTAssertEqual(AppTutorialStore.currentVersion, 1)
        XCTAssertTrue(store.needsAutomaticPresentation(accountStorageKey: "account-a"))
        XCTAssertTrue(store.needsAutomaticPresentation(accountStorageKey: "account-b"))

        XCTAssertTrue(store.record(.completed, accountStorageKey: "account-a"))
        XCTAssertEqual(
            store.progress(accountStorageKey: "account-a"),
            AppTutorialProgress(version: 1, completion: .completed)
        )
        XCTAssertTrue(store.needsAutomaticPresentation(accountStorageKey: "account-b"))

        XCTAssertTrue(store.record(.skipped, accountStorageKey: "account-b"))
        XCTAssertEqual(
            store.progress(accountStorageKey: "account-b")?.completion,
            .skipped
        )

        // Manual replay is presentation-only: merely loading/replaying the steps
        // leaves the durable automatic-run decision unchanged.
        _ = AppTutorialStep.all(languageCode: "en")
        XCTAssertEqual(
            store.progress(accountStorageKey: "account-a")?.completion,
            .completed
        )

        store.clear(accountStorageKey: "account-a")
        XCTAssertTrue(store.needsAutomaticPresentation(accountStorageKey: "account-a"))
        XCTAssertFalse(store.needsAutomaticPresentation(accountStorageKey: "account-b"))
    }

    func testTutorialUsesFiveCanonicalLocalizedSteps() {
        let english = AppTutorialStep.all(languageCode: "en")
        XCTAssertEqual(english.map(\.id), [
            "todayFocus", "todayPrimaryAction", "exercises", "progress", "profile"
        ])
        XCTAssertEqual(english.map(\.title), [
            "Your next workout",
            "One clear next step",
            "Exercises",
            "Progress and goals",
            "Profile and help"
        ])
        XCTAssertEqual(english.map(\.body), [
            "Start, continue, or adjust today’s plan here.",
            "GymApp keeps the current workout action within easy reach.",
            "Find movements and open their technique guide.",
            "Review your trend, muscle load, records, and missions.",
            "Friends, live workouts, account, devices, and help are here."
        ])

        XCTAssertEqual(
            AppTutorialStep.all(languageCode: "uk").map(\.title),
            [
                "Твоє наступне тренування",
                "Один зрозумілий наступний крок",
                "Вправи",
                "Прогрес і цілі",
                "Профіль і допомога"
            ]
        )
        XCTAssertEqual(
            AppTutorialStep.all(languageCode: "ru").map(\.title),
            [
                "Твоя следующая тренировка",
                "Один понятный следующий шаг",
                "Упражнения",
                "Прогресс и цели",
                "Профиль и помощь"
            ]
        )
    }

    func testTutorialMeasuresPrimaryActionOnlyForItsVisibleStep() {
        XCTAssertFalse(appTutorialShouldMeasurePrimaryAction(target: nil))
        XCTAssertFalse(appTutorialShouldMeasurePrimaryAction(target: .todayFocus))
        XCTAssertFalse(appTutorialShouldMeasurePrimaryAction(target: .exercises))
        XCTAssertTrue(appTutorialShouldMeasurePrimaryAction(target: .todayPrimaryAction))
    }

    func testTutorialCompletionKeepsCurrentRouteUnlessExternalTargetOwnsNavigation() {
        XCTAssertEqual(
            appTutorialFinishRoute(
                currentTarget: .profile,
                externalTargetOwnsNavigation: false
            ),
            .keep(.profile)
        )
        XCTAssertEqual(
            appTutorialFinishRoute(
                currentTarget: .todayPrimaryAction,
                externalTargetOwnsNavigation: false
            ),
            .keep(.todayPrimaryAction)
        )
        XCTAssertEqual(
            appTutorialFinishRoute(
                currentTarget: .profile,
                externalTargetOwnsNavigation: true
            ),
            .yieldToExternalTarget
        )
    }

    func testExternalNavigationDismissesTutorialInMemoryWithoutRecordingCompletion() throws {
        let suiteName = "AppTutorialInterruptionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppTutorialStore(defaults: defaults)

        let automatic = appTutorialExternalInterruption(
            currentStepIndex: 2,
            isManualReplay: false
        )
        XCTAssertNil(automatic.stepIndex)
        XCTAssertFalse(automatic.isManualReplay)
        XCTAssertTrue(automatic.suppressAutomaticPresentationForSession)
        XCTAssertTrue(store.needsAutomaticPresentation(accountStorageKey: "account-a"))

        let manual = appTutorialExternalInterruption(
            currentStepIndex: 4,
            isManualReplay: true
        )
        XCTAssertNil(manual.stepIndex)
        XCTAssertFalse(manual.isManualReplay)
        XCTAssertTrue(manual.suppressAutomaticPresentationForSession)
        let beforeAutomaticPresentation = appTutorialExternalInterruption(
            currentStepIndex: nil,
            isManualReplay: false
        )
        XCTAssertNil(beforeAutomaticPresentation.stepIndex)
        XCTAssertTrue(beforeAutomaticPresentation.suppressAutomaticPresentationForSession)
    }

    func testManualTutorialCompletionRecordsOnlyIfFirstRunIsStillPending() {
        XCTAssertTrue(appTutorialShouldRecordCompletion(
            isManualReplay: false,
            needsAutomaticPresentation: true
        ))
        XCTAssertTrue(appTutorialShouldRecordCompletion(
            isManualReplay: true,
            needsAutomaticPresentation: true
        ))
        XCTAssertFalse(appTutorialShouldRecordCompletion(
            isManualReplay: true,
            needsAutomaticPresentation: false
        ))
    }

    func testTutorialCardNeverCoversPrimaryActionSpotlight() {
        let size = CGSize(width: 393, height: 759)
        let primaryAction = CGRect(x: 54, y: 292, width: 285, height: 54)
        let center = appTutorialCardCenterY(in: size, targetRect: primaryAction)
        let card = CGRect(x: 0, y: center - 150, width: size.width, height: 300)
        XCTAssertFalse(card.intersects(primaryAction.insetBy(dx: -8, dy: -8)))

        let bottomTab = CGRect(x: 220, y: 704, width: 104, height: 62)
        let topCenter = appTutorialCardCenterY(in: size, targetRect: bottomTab)
        let topCard = CGRect(x: 0, y: topCenter - 150, width: size.width, height: 300)
        XCTAssertFalse(topCard.intersects(bottomTab.insetBy(dx: -8, dy: -8)))
    }

    func testTutorialTabMeasurementMapsOnlyValidSelectedBottomTabs() throws {
        let windowBounds = CGRect(x: 0, y: 0, width: 414, height: 896)
        let exercisesFrame = CGRect(x: 112, y: 814, width: 100, height: 62)
        let exercises = try XCTUnwrap(appTutorialTabMeasurement(
            itemCount: 4,
            selectedIndex: 1,
            windowFrame: exercisesFrame,
            windowBounds: windowBounds
        ))
        XCTAssertEqual(exercises.target, .exercises)
        XCTAssertEqual(exercises.windowFrame, exercisesFrame)

        XCTAssertEqual(
            appTutorialTabMeasurement(
                itemCount: 4,
                selectedIndex: 2,
                windowFrame: CGRect(x: 212, y: 814, width: 100, height: 62),
                windowBounds: windowBounds
            )?.target,
            .progress
        )
        XCTAssertEqual(
            appTutorialTabMeasurement(
                itemCount: 4,
                selectedIndex: 3,
                windowFrame: CGRect(x: 312, y: 814, width: 100, height: 62),
                windowBounds: windowBounds
            )?.target,
            .profile
        )

        XCTAssertNil(appTutorialTabMeasurement(
            itemCount: 3,
            selectedIndex: 1,
            windowFrame: exercisesFrame,
            windowBounds: windowBounds
        ))
        XCTAssertNil(appTutorialTabMeasurement(
            itemCount: 4,
            selectedIndex: 0,
            windowFrame: exercisesFrame,
            windowBounds: windowBounds
        ))
        XCTAssertNil(appTutorialTabMeasurement(
            itemCount: 4,
            selectedIndex: 1,
            windowFrame: .zero,
            windowBounds: windowBounds
        ))
        XCTAssertNil(appTutorialTabMeasurement(
            itemCount: 4,
            selectedIndex: 1,
            windowFrame: CGRect(x: CGFloat.nan, y: 814, width: 100, height: 62),
            windowBounds: windowBounds
        ))
        XCTAssertNil(appTutorialTabMeasurement(
            itemCount: 4,
            selectedIndex: 1,
            windowFrame: CGRect(x: 0, y: 800, width: 500, height: 62),
            windowBounds: windowBounds
        ))
    }

    func testTutorialTabMeasurementConvertsWindowCoordinatesAndRejectsStaleTarget() throws {
        let portraitMeasurement = AppTutorialTabMeasurement(
            target: .exercises,
            windowFrame: CGRect(x: 112, y: 814, width: 100, height: 62)
        )
        XCTAssertEqual(
            appTutorialLocalTabTargetRect(
                measurement: portraitMeasurement,
                expectedTarget: .exercises,
                overlayGlobalFrame: CGRect(x: 0, y: 59, width: 414, height: 802)
            ),
            CGRect(x: 112, y: 755, width: 100, height: 62)
        )
        XCTAssertNil(appTutorialLocalTabTargetRect(
            measurement: portraitMeasurement,
            expectedTarget: .progress,
            overlayGlobalFrame: CGRect(x: 0, y: 59, width: 414, height: 802)
        ))

        let landscape = try XCTUnwrap(appTutorialTabMeasurement(
            itemCount: 4,
            selectedIndex: 3,
            windowFrame: CGRect(x: 720, y: 350, width: 110, height: 40),
            windowBounds: CGRect(x: 0, y: 0, width: 896, height: 414)
        ))
        XCTAssertEqual(
            appTutorialLocalTabTargetRect(
                measurement: landscape,
                expectedTarget: .profile,
                overlayGlobalFrame: CGRect(x: 44, y: 0, width: 808, height: 393)
            ),
            CGRect(x: 676, y: 350, width: 110, height: 40)
        )
    }

    func testTutorialTabFramesRequireExactCountAndFollowLayoutDirection() throws {
        let frames = [
            CGRect(x: 312, y: 814, width: 80, height: 54),
            CGRect(x: 22, y: 814, width: 80, height: 54),
            CGRect(x: 216, y: 814, width: 80, height: 54),
            CGRect(x: 119, y: 814, width: 80, height: 54)
        ]
        let leftToRight = try XCTUnwrap(appTutorialOrderedTabFrames(
            frames,
            itemCount: 4,
            isRightToLeft: false
        ))
        XCTAssertEqual(leftToRight.map(\.minX), [22, 119, 216, 312])

        let rightToLeft = try XCTUnwrap(appTutorialOrderedTabFrames(
            frames,
            itemCount: 4,
            isRightToLeft: true
        ))
        XCTAssertEqual(rightToLeft.map(\.minX), [312, 216, 119, 22])

        XCTAssertNil(appTutorialOrderedTabFrames(
            Array(frames.dropLast()),
            itemCount: 4,
            isRightToLeft: false
        ))
        XCTAssertNil(appTutorialOrderedTabFrames(
            frames + [CGRect(x: 0, y: 0, width: 80, height: 54)],
            itemCount: 4,
            isRightToLeft: false
        ))
        XCTAssertNil(appTutorialOrderedTabFrames(
            Array(frames.dropLast()) + [.zero],
            itemCount: 4,
            isRightToLeft: false
        ))
    }

    func testTutorialCardHeightStaysInsideShortAccessibilityViewport() {
        XCTAssertEqual(
            appTutorialMaximumCardHeight(in: CGSize(width: 852, height: 320)),
            288
        )
        XCTAssertEqual(
            appTutorialMaximumCardHeight(in: CGSize(width: 320, height: 180)),
            180
        )
        XCTAssertFalse(appTutorialUsesBoundedScroll(
            dynamicTypeSizeIsAccessibility: false,
            maximumCardHeight: 727
        ))
        XCTAssertTrue(appTutorialUsesBoundedScroll(
            dynamicTypeSizeIsAccessibility: true,
            maximumCardHeight: 727
        ))
        XCTAssertTrue(appTutorialUsesBoundedScroll(
            dynamicTypeSizeIsAccessibility: false,
            maximumCardHeight: 288
        ))
        XCTAssertEqual(
            appTutorialPinnedActions(canGoBack: false),
            [.skip, .advance]
        )
        XCTAssertEqual(
            appTutorialPinnedActions(canGoBack: true),
            [.skip, .back, .advance]
        )
    }

    func testTutorialInitialPlacementUsesCompactCoachCardEstimate() {
        XCTAssertEqual(
            appTutorialInitialCardHalfHeight(maximumCardHeight: 727),
            108
        )
        XCTAssertEqual(
            appTutorialInitialCardHalfHeight(maximumCardHeight: 180),
            90
        )

        let size = CGSize(width: 393, height: 759)
        let todayFocus = CGRect(x: 16, y: 92, width: 361, height: 410)
        let halfHeight = appTutorialInitialCardHalfHeight(maximumCardHeight: 727)
        let center = appTutorialCardCenterY(
            in: size,
            targetRect: todayFocus,
            estimatedHalfHeight: halfHeight
        )
        let card = CGRect(
            x: 16,
            y: center - halfHeight,
            width: 361,
            height: halfHeight * 2
        )
        XCTAssertFalse(card.intersects(todayFocus.insetBy(dx: -8, dy: -8)))
        XCTAssertLessThanOrEqual(card.maxY, size.height - 16)
    }

    func testTutorialScreenshotStepArgumentIsStrictAndOneBased() {
        XCTAssertEqual(
            appTutorialScreenshotStepIndex(arguments: ["app", "--screenshot-tutorial-step=2"]),
            1
        )
        XCTAssertNil(appTutorialScreenshotStepIndex(arguments: ["--screenshot-tutorial-step=0"]))
        XCTAssertNil(appTutorialScreenshotStepIndex(arguments: ["--screenshot-tutorial-step=6"]))
        XCTAssertNil(appTutorialScreenshotStepIndex(arguments: ["--screenshot-tutorial-step=2x"]))
    }

    func testNativePushScrollHonorsReduceMotion() {
        XCTAssertEqual(nativePushScrollBehavior(reduceMotion: false), .animated)
        XCTAssertEqual(nativePushScrollBehavior(reduceMotion: true), .immediate)
    }

    func testTodayEstimatedDurationUsesCanonicalBoundedFormula() {
        XCTAssertEqual(
            TodayFocusPlanMetrics.estimatedMinutes(exerciseCount: 0, setCount: 0),
            10
        )
        XCTAssertEqual(
            TodayFocusPlanMetrics.estimatedMinutes(exerciseCount: 1, setCount: 1),
            10
        )
        XCTAssertEqual(
            TodayFocusPlanMetrics.estimatedMinutes(exerciseCount: 3, setCount: 9),
            27
        )
        XCTAssertEqual(
            TodayFocusPlanMetrics.estimatedMinutes(exerciseCount: 20, setCount: 100),
            90
        )
    }

    func testTodayProjectionCacheReusesStableInputsAndRejectsOtherAccountData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("today-projection-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try WorkoutStore(
            accountStorageKey: "today-cache-a",
            directoryURL: directory
        )
        let exercise = try store.addExercise(name: "Today cache press")
        let referenceDate = Date(timeIntervalSince1970: 1_780_041_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let profile = TrainingProfile()
        let cache = TodayScreenProjectionCache()

        let first = cache.projection(
            store: store,
            referenceDate: referenceDate,
            calendar: calendar,
            trainingProfile: profile,
            monthOffset: 0
        )
        let repeated = cache.projection(
            store: store,
            referenceDate: referenceDate,
            calendar: calendar,
            trainingProfile: profile,
            monthOffset: 0
        )
        XCTAssertEqual(cache.buildCount, 1)
        XCTAssertEqual(first.accountStorageKey, "today-cache-a")
        XCTAssertEqual(repeated.accountStorageKey, first.accountStorageKey)

        _ = try store.createWorkout(
            date: referenceDate.addingTimeInterval(-24 * 60 * 60),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: exercise.id,
                    sets: [.init(weight: 60, reps: 8)]
                )
            ]
        )
        let afterMutation = cache.projection(
            store: store,
            referenceDate: referenceDate,
            calendar: calendar,
            trainingProfile: profile,
            monthOffset: 0
        )
        XCTAssertEqual(cache.buildCount, 2)
        XCTAssertEqual(afterMutation.heroMetrics.totalWorkouts, 1)
        XCTAssertEqual(afterMutation.monthWorkouts.count, 1)

        try store.switchAccount(to: "today-cache-b")
        let otherAccount = cache.projection(
            store: store,
            referenceDate: referenceDate,
            calendar: calendar,
            trainingProfile: profile,
            monthOffset: 0
        )
        XCTAssertEqual(cache.buildCount, 3)
        XCTAssertEqual(otherAccount.accountStorageKey, "today-cache-b")
        XCTAssertEqual(otherAccount.heroMetrics.totalWorkouts, 0)
        XCTAssertTrue(otherAccount.monthWorkouts.isEmpty)

        try store.switchAccount(to: "today-cache-a")
        let restoredAccount = cache.projection(
            store: store,
            referenceDate: referenceDate,
            calendar: calendar,
            trainingProfile: profile,
            monthOffset: 0
        )
        XCTAssertEqual(cache.buildCount, 4)
        XCTAssertEqual(restoredAccount.accountStorageKey, "today-cache-a")
        XCTAssertEqual(restoredAccount.heroMetrics.totalWorkouts, 1)
    }
}
