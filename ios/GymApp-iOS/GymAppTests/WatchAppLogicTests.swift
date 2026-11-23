import Foundation
import XCTest
@testable import GymApp

private let account = String(repeating: "1", count: 64)
private let otherAccount = String(repeating: "2", count: 64)
private let requestId = "aw-0f8fad5b-d9cb-469f-a165-70867728950e"
private let start: Int64 = 1_794_996_000_000

private func boundContext(plan: [WatchPlanExercise], revision: Int64 = 7, binding: String = account) -> WatchBoundContext {
    WatchBoundContext(accountBinding: binding, language: "ru", planRevision: revision, plan: plan,
                      exercises: ["Жим лёжа", "Присед", "Тяга штанги"])
}

private let plan = [
    WatchPlanExercise(name: "Жим лёжа", restSeconds: 120, sets: [.init(weight: 60, reps: 8), .init(weight: 62.5, reps: 6)]),
    WatchPlanExercise(name: "Присед", restSeconds: 90, sets: [.init(weight: 100, reps: 5)])
]

final class WatchWorkoutModelTests: XCTestCase {
    private func planWorkout() throws -> WatchActiveWorkout {
        try XCTUnwrap(WatchWorkoutModel.start(mode: .plan, context: boundContext(plan: plan), requestId: requestId,
                                              nowMillis: start, heartRateEnabled: true))
    }

    func testPlanStartPrefillsFirstTargetAndCountsSetKOfN() throws {
        var workout = try planWorkout()
        XCTAssertEqual(workout.exerciseName, "Жим лёжа")
        XCTAssertEqual(workout.draftWeight, 60)
        XCTAssertEqual(workout.draftReps, 8)
        XCTAssertEqual(workout.planRevision, 7)
        XCTAssertEqual(WatchWorkoutModel.setPosition(workout), WatchSetPosition(index: 1, count: 2))
        XCTAssertTrue(WatchWorkoutModel.logSet(&workout, weight: 60, reps: 8, nowMillis: start + 60_000))
        XCTAssertEqual(WatchWorkoutModel.setPosition(workout), WatchSetPosition(index: 2, count: 2))
        XCTAssertEqual(workout.draftWeight, 62.5)
        XCTAssertEqual(workout.draftReps, 6)
        XCTAssertEqual(WatchWorkoutModel.restRemainingSeconds(workout, nowMillis: start + 60_000), 120)
        XCTAssertTrue(WatchWorkoutModel.logSet(&workout, weight: 62.5, reps: 6, nowMillis: start + 300_000))
        XCTAssertTrue(WatchWorkoutModel.logSet(&workout, weight: 62.5, reps: 5, nowMillis: start + 500_000))
        // Extra sets keep "n of n" and never auto-advance the exercise.
        XCTAssertEqual(WatchWorkoutModel.setPosition(workout), WatchSetPosition(index: 2, count: 2))
        XCTAssertEqual(workout.exerciseName, "Жим лёжа")
        XCTAssertEqual(WatchWorkoutModel.firstUnfinishedPlanExercise(workout), "Присед")
        XCTAssertEqual(WatchWorkoutModel.planProgress(workout).map(\.done), [3, 0])
    }

    func testPlanModeNeedsAPlanAndFreeModeStartsWithoutExercise() throws {
        XCTAssertNil(WatchWorkoutModel.start(mode: .plan, context: boundContext(plan: []), requestId: requestId,
                                             nowMillis: start, heartRateEnabled: false))
        var free = try XCTUnwrap(WatchWorkoutModel.start(mode: .free, context: boundContext(plan: plan),
                                                         requestId: requestId, nowMillis: start, heartRateEnabled: false))
        XCTAssertNil(free.exerciseName)
        XCTAssertNil(free.planRevision)
        XCTAssertTrue(free.plan.isEmpty)
        XCTAssertNil(WatchWorkoutModel.setPosition(free))
        // Never log a set for a nameless exercise.
        XCTAssertFalse(WatchWorkoutModel.logSet(&free, weight: 20, reps: 10, nowMillis: start + 1_000))
        WatchWorkoutModel.selectExercise(&free, name: "Тяга штанги")
        XCTAssertEqual(free.draftWeight, 0)
        XCTAssertEqual(free.draftReps, 10)
        XCTAssertTrue(WatchWorkoutModel.logSet(&free, weight: 40, reps: 12, nowMillis: start + 2_000))
        XCTAssertEqual(WatchWorkoutModel.setPosition(free), WatchSetPosition(index: 2, count: nil))
        XCTAssertEqual(free.draftWeight, 40)
        XCTAssertEqual(WatchWorkoutModel.restRemainingSeconds(free, nowMillis: start + 2_000), WatchSync.defaultRestSeconds)
    }

    func testUndoWindowRestoresPreviousValuesOnlyWithinFiveSeconds() throws {
        var workout = try planWorkout()
        WatchWorkoutModel.logSet(&workout, weight: 57.5, reps: 7, nowMillis: start + 10_000)
        XCTAssertTrue(WatchWorkoutModel.canUndo(workout, nowMillis: start + 14_999))
        XCTAssertFalse(WatchWorkoutModel.canUndo(workout, nowMillis: start + 15_000))
        XCTAssertFalse(WatchWorkoutModel.undo(&workout, nowMillis: start + 15_000))
        WatchWorkoutModel.logSet(&workout, weight: 62.5, reps: 6, nowMillis: start + 200_000)
        XCTAssertTrue(WatchWorkoutModel.undo(&workout, nowMillis: start + 201_000))
        XCTAssertEqual(workout.sets.count, 1)
        XCTAssertEqual(workout.draftWeight, 62.5)
        XCTAssertEqual(workout.draftReps, 6)
        XCTAssertNil(workout.restEndsAtMillis)
        WatchWorkoutModel.logSet(&workout, weight: 62.5, reps: 6, nowMillis: start + 300_000)
        WatchWorkoutModel.addRest(&workout, nowMillis: start + 301_000)
        XCTAssertFalse(WatchWorkoutModel.canUndo(workout, nowMillis: start + 302_000), "+15 s ends the undo window")
        XCTAssertEqual(WatchWorkoutModel.restRemainingSeconds(workout, nowMillis: start + 300_000), 135)
        WatchWorkoutModel.skipRest(&workout)
        XCTAssertNil(WatchWorkoutModel.restRemainingSeconds(workout, nowMillis: start + 300_000))
    }

    func testPauseFreezesElapsedAndRestAndFinishExcludesPauses() throws {
        var workout = try planWorkout()
        WatchWorkoutModel.logSet(&workout, weight: 60, reps: 8, nowMillis: start + 60_000)
        WatchWorkoutModel.pause(&workout, nowMillis: start + 100_000)
        XCTAssertFalse(WatchWorkoutModel.logSet(&workout, weight: 60, reps: 8, nowMillis: start + 110_000))
        XCTAssertEqual(WatchWorkoutModel.activeMillis(workout, nowMillis: start + 400_000), 100_000)
        XCTAssertEqual(WatchWorkoutModel.restRemainingSeconds(workout, nowMillis: start + 400_000), 80)
        WatchWorkoutModel.resume(&workout, nowMillis: start + 400_000)
        XCTAssertEqual(workout.pausedTotalMillis, 300_000)
        XCTAssertEqual(WatchWorkoutModel.restRemainingSeconds(workout, nowMillis: start + 400_000), 80)
        let message = try XCTUnwrap(WatchWorkoutModel.finish(
            workout, endedAtMillis: start + 1_000_000, healthKit: .saved,
            averageHeartRate: 118.4, maximumHeartRate: 161.2, activeKilocalories: 312.44))
        XCTAssertEqual(message.durationSeconds, 700)
        XCTAssertEqual(message.mode, .plan)
        XCTAssertEqual(message.planRevision, 7)
        XCTAssertEqual(message.averageHeartRate, 118)
        XCTAssertEqual(message.maximumHeartRate, 161)
        XCTAssertEqual(message.activeKilocalories, 312.4)
        let bytes = try WatchSyncCodec.encode(message, nowMillis: start + 1_000_000)
        XCTAssertEqual(WatchSyncCodec.decodeWorkout(bytes, nowMillis: start + 1_000_000), .valid(message))
        let summary = WatchWorkoutModel.summary(message)
        XCTAssertEqual(summary.setCount, 1)
        XCTAssertEqual(summary.volumeKilograms, 480)
    }

    func testZeroSetWorkoutCannotFinishAndHalfHeartRateIsDropped() throws {
        var workout = try planWorkout()
        XCTAssertNil(WatchWorkoutModel.finish(workout, endedAtMillis: start + 60_000, healthKit: .off,
                                              averageHeartRate: nil, maximumHeartRate: nil, activeKilocalories: nil))
        WatchWorkoutModel.logSet(&workout, weight: 60, reps: 8, nowMillis: start + 1_000)
        let message = try XCTUnwrap(WatchWorkoutModel.finish(workout, endedAtMillis: start + 500, healthKit: .off,
                                                             averageHeartRate: 300, maximumHeartRate: 120, activeKilocalories: .nan))
        XCTAssertNil(message.averageHeartRate)
        XCTAssertNil(message.maximumHeartRate)
        XCTAssertNil(message.activeKilocalories)
        XCTAssertGreaterThan(message.endedAtMillis, message.startedAtMillis)
        XCTAssertGreaterThanOrEqual(message.durationSeconds, 1)
        XCTAssertNoThrow(try WatchSyncCodec.encode(message, nowMillis: start + 2_000))
    }

    func testActiveWorkoutSnapshotRoundTripsThroughJSON() throws {
        var workout = try planWorkout()
        WatchWorkoutModel.logSet(&workout, weight: 60, reps: 8, nowMillis: start + 60_000)
        WatchWorkoutModel.pause(&workout, nowMillis: start + 70_000)
        let data = try JSONEncoder().encode(workout)
        XCTAssertEqual(try JSONDecoder().decode(WatchActiveWorkout.self, from: data), workout)
    }

    func testHeartRateZonesUseMaximum190() {
        XCTAssertEqual(WatchHeartRateZone.zone(bpm: 113), 1)
        XCTAssertEqual(WatchHeartRateZone.zone(bpm: 114), 2)
        XCTAssertEqual(WatchHeartRateZone.zone(bpm: 133), 3)
        XCTAssertEqual(WatchHeartRateZone.zone(bpm: 152), 4)
        XCTAssertEqual(WatchHeartRateZone.zone(bpm: 171), 5)
        XCTAssertNil(WatchHeartRateZone.zone(bpm: 0))
    }
}

final class WatchOutboxPolicyTests: XCTestCase {
    private let now: Int64 = 1_795_000_000_000

    private func item() throws -> WatchOutboxItem {
        var workout = try XCTUnwrap(WatchWorkoutModel.start(mode: .plan, context: boundContext(plan: plan),
                                                            requestId: requestId, nowMillis: start, heartRateEnabled: false))
        WatchWorkoutModel.logSet(&workout, weight: 60, reps: 8, nowMillis: start + 60_000)
        let message = try XCTUnwrap(WatchWorkoutModel.finish(workout, endedAtMillis: start + 600_000, healthKit: .off,
                                                             averageHeartRate: nil, maximumHeartRate: nil, activeKilocalories: nil))
        let envelope = try WatchSyncCodec.encode(message, nowMillis: now)
        return WatchOutboxPolicy.makeItem(message: message, envelope: envelope,
                                          summary: WatchWorkoutModel.summary(message), nowMillis: now)
    }

    private func context(_ binding: String) -> WatchContextMessage {
        WatchContextMessage(sentAtMillis: now, bound: boundContext(plan: plan, binding: binding))
    }

    func testOnlyMatchingAckDeletesAndResendIsByteIdentical() throws {
        let queued = try item()
        let sent = WatchOutboxPolicy.markSent(queued, nowMillis: now)
        XCTAssertEqual(sent.envelope, queued.envelope)
        XCTAssertEqual(sent.status, .sent)
        XCTAssertTrue(sent.everSent)
        XCTAssertFalse(WatchOutboxPolicy.canRewrite(sent))
        XCTAssertEqual(sent.nextAttemptAtMillis, now + 60_000)
        let wrongAccount = WatchReply.ack(.init(requestId: requestId, accountBinding: otherAccount, status: .committed))
        XCTAssertEqual(WatchOutboxPolicy.apply(wrongAccount, to: sent, nowMillis: now), .ignore)
        let wrongId = WatchReply.ack(.init(requestId: "aw-7c9e6679-7425-40de-944b-e07fc1f90ae7", accountBinding: account, status: .committed))
        XCTAssertEqual(WatchOutboxPolicy.apply(wrongId, to: sent, nowMillis: now), .ignore)
        let match = WatchReply.ack(.init(requestId: requestId, accountBinding: account, status: .duplicate))
        XCTAssertEqual(WatchOutboxPolicy.apply(match, to: sent, nowMillis: now), .delete)
    }

    func testTransientNackBacksOffAndNewContextMakesItDue() throws {
        var current = WatchOutboxPolicy.markSent(try item(), nowMillis: now)
        let expected: [Int64] = [60, 300, 900, 3_600, 3_600]
        for (attempt, seconds) in expected.enumerated() {
            guard case .update(let next) = WatchOutboxPolicy.apply(.nack(.init(requestId: requestId, reason: .rateLimited)),
                                                                   to: current, nowMillis: now) else {
                return XCTFail("transient nack must keep the item")
            }
            XCTAssertEqual(next.status, .queued)
            XCTAssertEqual(next.nextAttemptAtMillis, now + seconds * 1_000, "attempt \(attempt + 1)")
            XCTAssertFalse(WatchOutboxPolicy.isSendable(next, context: context(account), nowMillis: now, outstanding: []))
            current = WatchOutboxPolicy.markSent(next, nowMillis: now)
            current.status = .queued
        }
        let due = WatchOutboxPolicy.applyContext(context(account), to: current, nowMillis: now)
        XCTAssertTrue(WatchOutboxPolicy.isSendable(due, context: context(account), nowMillis: now, outstanding: []))
        XCTAssertFalse(WatchOutboxPolicy.isSendable(due, context: context(account), nowMillis: now, outstanding: [requestId]))
        XCTAssertFalse(WatchOutboxPolicy.isSendable(due, context: context(otherAccount), nowMillis: now, outstanding: []))
        XCTAssertFalse(WatchOutboxPolicy.isSendable(due, context: WatchContextMessage(sentAtMillis: now, bound: nil),
                                                    nowMillis: now, outstanding: []))
    }

    func testHoldNackWaitsForMatchingAccountContext() throws {
        let sent = WatchOutboxPolicy.markSent(try item(), nowMillis: now)
        guard case .update(let held) = WatchOutboxPolicy.apply(.nack(.init(requestId: requestId, reason: .foreignAccount)),
                                                               to: sent, nowMillis: now) else { return XCTFail("hold keeps") }
        XCTAssertEqual(held.status, .held)
        XCTAssertFalse(WatchOutboxPolicy.isSendable(held, context: context(account), nowMillis: now + 10_000_000, outstanding: []))
        XCTAssertEqual(WatchOutboxPolicy.applyContext(context(otherAccount), to: held, nowMillis: now), held)
        let released = WatchOutboxPolicy.applyContext(context(account), to: held, nowMillis: now + 5)
        XCTAssertEqual(released.status, .queued)
        XCTAssertEqual(released.envelope, sent.envelope)
        XCTAssertTrue(WatchOutboxPolicy.isSendable(released, context: context(account), nowMillis: now + 5, outstanding: []))

        guard case .update(let version) = WatchOutboxPolicy.apply(.nack(.init(requestId: requestId, reason: .unsupportedVersion)),
                                                                  to: sent, nowMillis: now) else { return XCTFail("hold keeps") }
        XCTAssertEqual(WatchOutboxPolicy.applyContext(context(account), to: version, nowMillis: now).status, .held)
        XCTAssertEqual(WatchOutboxPolicy.applyContext(context(account), to: version, nowMillis: now,
                                                      protocolVersion: WatchSync.protocolVersion + 1).status, .queued)
    }

    func testDeterministicNackStaysFailedUntilDiscard() throws {
        let sent = WatchOutboxPolicy.markSent(try item(), nowMillis: now)
        for reason in [WatchNackReason.malformed, .conflict, .invalid] {
            guard case .update(let failed) = WatchOutboxPolicy.apply(.nack(.init(requestId: requestId, reason: reason)),
                                                                     to: sent, nowMillis: now) else { return XCTFail("kept") }
            XCTAssertEqual(failed.status, .failed)
            XCTAssertEqual(failed.reason, reason.rawValue)
            XCTAssertEqual(WatchOutboxPolicy.applyContext(context(account), to: failed, nowMillis: now), failed)
            XCTAssertFalse(WatchOutboxPolicy.isSendable(failed, context: context(account), nowMillis: now + 99_999_999, outstanding: []))
        }
        XCTAssertTrue(WatchOutboxPolicy.canStartWorkout(itemCount: WatchSync.maximumOutboxItems - 1))
        XCTAssertFalse(WatchOutboxPolicy.canStartWorkout(itemCount: WatchSync.maximumOutboxItems))
    }

    func testEnvelopeIsRewrittenOnlyBeforeTheFirstSend() throws {
        let queued = try item()
        let other = Data("{}".utf8)
        let rewritten = try XCTUnwrap(WatchOutboxPolicy.rewriting(queued, envelope: other))
        XCTAssertEqual(rewritten.envelope, other)
        XCTAssertEqual(rewritten.requestId, queued.requestId)
        XCTAssertEqual(rewritten.status, .queued)
        let sent = WatchOutboxPolicy.markSent(queued, nowMillis: now)
        XCTAssertNil(WatchOutboxPolicy.rewriting(sent, envelope: other))
        // An item still being finished counts as in flight: it is not sent before its bytes settle.
        XCTAssertFalse(WatchOutboxPolicy.isSendable(queued, context: context(account), nowMillis: now, outstanding: [queued.requestId]))
        XCTAssertTrue(WatchOutboxPolicy.isSendable(queued, context: context(account), nowMillis: now, outstanding: []))
    }

    func testSnapshotOfAnAlreadyFinishedWorkoutIsNotRestored() throws {
        let finished = try item()
        XCTAssertTrue(WatchOutboxPolicy.isAlreadyFinished(requestId: requestId, outbox: [finished]))
        XCTAssertFalse(WatchOutboxPolicy.isAlreadyFinished(requestId: "aw-7c9e6679-7425-40de-944b-e07fc1f90ae7", outbox: [finished]))
        XCTAssertFalse(WatchOutboxPolicy.isAlreadyFinished(requestId: requestId, outbox: []))
    }

    func testItemRoundTripsThroughJSON() throws {
        let original = WatchOutboxPolicy.markSent(try item(), nowMillis: now)
        let decoded = try JSONDecoder().decode(WatchOutboxItem.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.envelope, original.envelope)
    }
}

final class WatchCrownStepsTests: XCTestCase {
    func testWeightStepCyclesAndWheelOptionsIncludeOffGridPlanValue() {
        XCTAssertEqual(WatchCrownSteps.nextWeightStep(after: 1), 2.5)
        XCTAssertEqual(WatchCrownSteps.nextWeightStep(after: 2.5), 5)
        XCTAssertEqual(WatchCrownSteps.nextWeightStep(after: 5), 1)
        XCTAssertEqual(WatchCrownSteps.validWeightStep(0), 2.5)
        let options = WatchCrownSteps.weightOptions(step: 5, including: [62.5])
        XCTAssertEqual(options.first, 0)
        XCTAssertEqual(options.last, 500)
        XCTAssertTrue(options.contains(62.5))
        XCTAssertEqual(options.count, 102)
        XCTAssertEqual(WatchCrownSteps.weightOptions(step: 2.5).count, 201)
        XCTAssertEqual(WatchCrownSteps.repsOptions(including: [150]).last, 150)
        XCTAssertEqual(WatchCrownSteps.normalizedWeight(-3), 0)
        XCTAssertEqual(WatchCrownSteps.normalizedWeight(12.346), 12.35)
        XCTAssertEqual(WatchCrownSteps.normalizedReps(0), 1)
    }

    func testFormatsFollowLanguage() {
        XCTAssertEqual(WatchCrownSteps.formatWeight(57.5, language: "uk"), "57,5")
        XCTAssertEqual(WatchCrownSteps.formatWeight(57.5, language: "en"), "57.5")
        XCTAssertEqual(WatchCrownSteps.formatWeight(60, language: "ru"), "60")
        XCTAssertEqual(WatchCrownSteps.formatWeight(1.25, language: "ru"), "1,25")
        XCTAssertEqual(WatchCrownSteps.formatDuration(seconds: 2_892), "48:12")
        XCTAssertEqual(WatchCrownSteps.formatDuration(seconds: 3_725), "1:02:05")
        XCTAssertEqual(WatchCrownSteps.formatVolume(5_240, language: "uk"), "5\u{00A0}240")
        XCTAssertEqual(WatchCrownSteps.formatVolume(5_240, language: "en"), "5,240")
    }
}

final class WatchTextAndContextTests: XCTestCase {
    func testEveryKeyIsTranslatedAndLanguageFollowsSystemLocale() {
        for key in WatchTextKey.allCases {
            for language in ["en", "uk", "ru"] {
                XCTAssertFalse(WatchText.string(key, language).isEmpty, "\(key) \(language)")
            }
            XCTAssertNil(WatchText.string(key, "ru").range(of: "[іїєґ]", options: .regularExpression), "\(key) ru has Ukrainian letters")
        }
        XCTAssertEqual(WatchText.language(preferredLanguages: ["uk-UA"]), "uk")
        XCTAssertEqual(WatchText.language(preferredLanguages: ["ru_RU", "en"]), "ru")
        XCTAssertEqual(WatchText.language(preferredLanguages: ["de-DE", "en-GB"]), "en")
        XCTAssertEqual(WatchText.setLine(WatchSetPosition(index: 2, count: 4), "uk"), "Підхід 2 з 4")
        XCTAssertEqual(WatchText.setLine(WatchSetPosition(index: 3, count: nil), "ru"), "Подход 3")
        XCTAssertEqual(WatchText.weightReps(weight: 57.5, reps: 7, "uk"), "57,5 кг × 7")
        XCTAssertEqual(WatchText.format(.next, "en", WatchText.weightReps(weight: 60, reps: 8, "en")), "Next: 60 kg × 8")
    }

    func testContextMergeKeepsNewerPlanAndDropsEverythingWhenUnbound() {
        let cached = WatchContextMessage(sentAtMillis: 1, bound: boundContext(plan: plan, revision: 9))
        let older = WatchContextMessage(sentAtMillis: 2, bound: WatchBoundContext(
            accountBinding: account, language: "en", planRevision: 8, plan: [], exercises: ["Присед"]))
        let merged = WatchContextMerge.merge(cached: cached, incoming: older)
        XCTAssertEqual(merged.bound?.planRevision, 9)
        XCTAssertEqual(merged.bound?.plan, plan)
        XCTAssertEqual(merged.bound?.exercises, ["Присед"])
        XCTAssertEqual(merged.bound?.language, "en")
        let otherAccountContext = WatchContextMessage(sentAtMillis: 3, bound: boundContext(plan: [], revision: 1, binding: otherAccount))
        XCTAssertEqual(WatchContextMerge.merge(cached: cached, incoming: otherAccountContext), otherAccountContext)
        let unbound = WatchContextMessage(sentAtMillis: 4, bound: nil)
        XCTAssertEqual(WatchContextMerge.merge(cached: cached, incoming: unbound), unbound)
    }
}
