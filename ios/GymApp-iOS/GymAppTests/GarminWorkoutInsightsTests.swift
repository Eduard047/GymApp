import Foundation
import XCTest
@testable import GymApp

final class GarminWorkoutInsightsTests: XCTestCase {
    func testBuildsBoundedSessionOverviewFromRecordedSetRows() throws {
        let note = [
            "Garmin",
            "Duration 12:00",
            "Avg HR 120",
            "Max HR 168",
            "S1 30s R60s HR100/150/120 ↓30 C90% I10-40s K1.2/2 Z0/5/10/10/5/0s",
            "S2 40s R90s HR110/168/130 ↓38 C35% I130-170s K1.4/3 Z0/0/10/15/15/0s"
        ].joined(separator: " · ")

        let summary = try XCTUnwrap(GarminWorkoutNoteParser.parse(note))
        let insights = try XCTUnwrap(GarminWorkoutSessionInsights.make(from: summary))

        XCTAssertEqual(insights.timelineDurationSeconds, 720)
        XCTAssertEqual(insights.timelineSlices.map(\.setIndex), [1, 2])
        XCTAssertEqual(insights.timelineSlices.map(\.detectionConfidence), [90, 35])
        XCTAssertEqual(insights.recordedActiveSeconds, 70)
        XCTAssertEqual(insights.recordedRestSeconds, 150)
        XCTAssertEqual(insights.workDensityPercent, 32)
        XCTAssertEqual(insights.averageDetectionConfidence, 63)
        XCTAssertEqual(insights.averageRecoveryHeartRateDrop, 34)
        XCTAssertEqual(insights.aggregateHeartRateZoneSeconds, [0, 5, 20, 25, 20, 0])
        XCTAssertEqual(insights.dominantHeartRateZone, 3)
        XCTAssertEqual(insights.peakHeartRate, 168)
        XCTAssertEqual(insights.peakHeartRateSetIndex, 2)
        XCTAssertEqual(insights.longestRestSeconds, 90)
        XCTAssertEqual(insights.longestRestSetIndex, 2)
        XCTAssertEqual(insights.lowConfidenceSetIndexes, [2])
        XCTAssertFalse(insights.isPartial)
    }

    func testPartialAndSparseRecordsDoNotInventMissingMetrics() throws {
        let summary = try XCTUnwrap(
            GarminWorkoutNoteParser.parse("Garmin · S1 C75% · S+2")
        )
        let insights = try XCTUnwrap(GarminWorkoutSessionInsights.make(from: summary))

        XCTAssertNil(insights.timelineDurationSeconds)
        XCTAssertTrue(insights.timelineSlices.isEmpty)
        XCTAssertNil(insights.recordedActiveSeconds)
        XCTAssertNil(insights.recordedRestSeconds)
        XCTAssertNil(insights.workDensityPercent)
        XCTAssertEqual(insights.averageDetectionConfidence, 75)
        XCTAssertNil(insights.averageRecoveryHeartRateDrop)
        XCTAssertNil(insights.aggregateHeartRateZoneSeconds)
        XCTAssertNil(insights.dominantHeartRateZone)
        XCTAssertNil(insights.peakHeartRate)
        XCTAssertNil(insights.longestRestSeconds)
        XCTAssertTrue(insights.lowConfidenceSetIndexes.isEmpty)
        XCTAssertTrue(insights.isPartial)
    }

    func testDensityRequiresCompleteContiguousSetAndRestRows() throws {
        let missingRest = try XCTUnwrap(
            GarminWorkoutNoteParser.parse(
                "Garmin · Duration 3:00 · S1 30s R0s I0-30s K1/- Z0/0/0/0/0/0s · S2 30s I90-120s K1/- Z0/0/0/0/0/0s"
            )
        )
        let sparseIndexes = try XCTUnwrap(
            GarminWorkoutNoteParser.parse(
                "Garmin · Duration 3:00 · S1 30s I0-30s K1/- Z0/0/0/0/0/0s · S3 30s R60s I90-120s K1/- Z0/0/0/0/0/0s"
            )
        )

        XCTAssertNil(GarminWorkoutSessionInsights.make(from: missingRest)?.workDensityPercent)
        XCTAssertNil(GarminWorkoutSessionInsights.make(from: sparseIndexes)?.workDensityPercent)
    }

    func testInsightBuilderRejectsMalformedNonFiniteAndOversizedInput() {
        let nonFinite = GarminWorkoutNoteSummary(
            durationSeconds: 60,
            gymCalories: nil,
            garminCalories: nil,
            averageHeartRate: nil,
            maximumHeartRate: nil,
            endingHeartRateZone: nil,
            completedSetCount: nil,
            plannedSetCount: nil,
            setMetrics: [],
            intervals: [
                GarminWorkoutNoteInterval(
                    setIndex: 1,
                    startSeconds: 0,
                    endSeconds: 20,
                    gymCalories: .nan,
                    garminCalories: nil,
                    heartRateZoneSeconds: [0, 5, 5, 5, 5, 0]
                )
            ],
            omittedMetricRows: nil
        )
        XCTAssertNil(GarminWorkoutSessionInsights.make(from: nonFinite))

        let malformedZones = GarminWorkoutNoteSummary(
            durationSeconds: 60,
            gymCalories: nil,
            garminCalories: nil,
            averageHeartRate: nil,
            maximumHeartRate: nil,
            endingHeartRateZone: nil,
            completedSetCount: nil,
            plannedSetCount: nil,
            setMetrics: [],
            intervals: [
                GarminWorkoutNoteInterval(
                    setIndex: 1,
                    startSeconds: 0,
                    endSeconds: 20,
                    gymCalories: 1,
                    garminCalories: nil,
                    heartRateZoneSeconds: [0, 5, 5, 5, 5]
                )
            ],
            omittedMetricRows: nil
        )
        XCTAssertNil(GarminWorkoutSessionInsights.make(from: malformedZones))

        let oversizedMetrics = (1 ... 61).map { index in
            GarminWorkoutNoteSetMetrics(
                setIndex: index,
                activeSeconds: 20,
                restBeforeSeconds: nil,
                startHeartRate: nil,
                peakHeartRate: nil,
                endHeartRate: nil,
                recoveryHeartRateDrop: nil,
                detectionConfidence: 80
            )
        }
        let oversized = GarminWorkoutNoteSummary(
            durationSeconds: nil,
            gymCalories: nil,
            garminCalories: nil,
            averageHeartRate: nil,
            maximumHeartRate: nil,
            endingHeartRateZone: nil,
            completedSetCount: nil,
            plannedSetCount: nil,
            setMetrics: oversizedMetrics,
            intervals: [],
            omittedMetricRows: nil
        )
        XCTAssertNil(GarminWorkoutSessionInsights.make(from: oversized))
    }

    func testParserKeepsLegacyGarminPrefixAndRejectsUnboundedOrNonFiniteNotes() {
        XCTAssertNotNil(
            GarminWorkoutNoteParser.parse("Garmin Fenix 8 · Duration 1:00")
        )
        XCTAssertNil(
            GarminWorkoutNoteParser.parse("Garmin · S1 I0-10s Knan/- Z0/0/0/0/0/0s")
        )
        XCTAssertNil(
            GarminWorkoutNoteParser.parse("Garmin · " + String(repeating: "a", count: 4_001))
        )
    }

    func testTimelinePositionClampsMalformedCoordinates() {
        XCTAssertEqual(
            GarminWorkoutChartModel.timelinePosition(-10, duration: 100),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            GarminWorkoutChartModel.timelinePosition(25, duration: 100),
            0.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            GarminWorkoutChartModel.timelinePosition(200, duration: 100),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            GarminWorkoutChartModel.timelinePosition(20, duration: 0),
            0,
            accuracy: 0.0001
        )
    }

    func testInsightCopyInterpolatesValuesInAllSupportedLanguages() {
        XCTAssertEqual(
            GarminWorkoutDetailCopy.timelineValue(
                setCount: 4,
                duration: 125,
                languageCode: "en"
            ),
            "4 recorded sets across 2:05"
        )
        XCTAssertEqual(
            GarminWorkoutDetailCopy.peakSet(
                setIndex: 3,
                heartRate: 166,
                languageCode: "uk"
            ),
            "Найвищий записаний пік підходу: S3, 166 уд/хв."
        )
        XCTAssertEqual(
            GarminWorkoutDetailCopy.longestRest(
                setIndex: 2,
                seconds: 95,
                languageCode: "ru"
            ),
            "Самый длинный записанный отдых был перед S2: 1:35."
        )
        XCTAssertEqual(
            GarminWorkoutDetailCopy.lowConfidenceSets([2, 5], languageCode: "ru"),
            "Проверь определение подходов S2, S5: сигнал датчиков был ниже 40%."
        )
    }
}
