import Foundation
import XCTest
@testable import GymApp

final class PlanEditorSnapshotTests: XCTestCase {
    func testSnapshotIgnoresEphemeralDraftAndSetIdentifiers() {
        let exerciseID = UUID()
        let date = Date(timeIntervalSince1970: 1_787_000_000)
        let firstDraft = WorkoutEditorExerciseDraft(
            id: UUID(),
            exerciseID: exerciseID,
            sets: [WorkoutEditorSetDraft(id: UUID(), weight: 42.5, reps: 8)]
        )
        let recreatedDraft = WorkoutEditorExerciseDraft(
            id: UUID(),
            exerciseID: exerciseID,
            sets: [WorkoutEditorSetDraft(id: UUID(), weight: 42.5, reps: 8)]
        )

        XCTAssertEqual(
            PlanEditorSnapshot(date: date, note: "", effort: .auto, drafts: [firstDraft]),
            PlanEditorSnapshot(date: date, note: "", effort: .auto, drafts: [recreatedDraft])
        )
    }

    func testSnapshotStillDetectsMeaningfulPlanChanges() {
        let exerciseID = UUID()
        let date = Date(timeIntervalSince1970: 1_787_000_000)
        let baseline = WorkoutEditorExerciseDraft(
            exerciseID: exerciseID,
            sets: [WorkoutEditorSetDraft(weight: 0, reps: 10)]
        )
        let edited = WorkoutEditorExerciseDraft(
            exerciseID: exerciseID,
            sets: [WorkoutEditorSetDraft(weight: 0, reps: 12)]
        )

        XCTAssertNotEqual(
            PlanEditorSnapshot(date: date, note: "", effort: .auto, drafts: [baseline]),
            PlanEditorSnapshot(date: date, note: "", effort: .auto, drafts: [edited])
        )
    }

    func testNavigationDraftPreservesMeaningfulEditorStateForSameAccountOnly() {
        let account = "account-a"
        let date = Date(timeIntervalSince1970: 1_787_000_000)
        let exerciseID = UUID()
        let editorDraft = WorkoutEditorExerciseDraft(
            exerciseID: exerciseID,
            sets: [WorkoutEditorSetDraft(weight: 82.5, reps: 7)]
        )
        let baseline = PlanEditorSnapshot(
            date: date,
            note: "",
            effort: .auto,
            drafts: []
        )
        let friend = SocialFriendSummary(
            friendshipID: "friendship-a",
            profileID: "profile-b",
            displayName: "Training Partner",
            xp: nil,
            level: nil,
            workouts: nil,
            progressShared: false,
            statsAvailable: false,
            progressUpdatedAt: nil,
            friendshipRevision: 7
        )
        let state = WorkoutPlanEditorDraftState(
            accountStorageKey: account,
            date: date,
            note: "Paused while checking history",
            profile: TrainingProfile(workoutsPerWeek: 4),
            selectedEffort: .hard,
            latestSmartPlan: nil,
            smartGeneratedDraftIDs: [editorDraft.id],
            smartPlanIsStale: true,
            drafts: [editorDraft],
            baselinePlanSnapshot: baseline,
            liveInviteRecipient: friend
        )

        XCTAssertTrue(state.belongs(to: account))
        XCTAssertFalse(state.belongs(to: "account-b"))
        XCTAssertFalse(state.belongs(to: ""))
        XCTAssertEqual(state.date, date)
        XCTAssertEqual(state.note, "Paused while checking history")
        XCTAssertEqual(state.profile.workoutsPerWeek, 4)
        XCTAssertEqual(state.selectedEffort, .hard)
        XCTAssertEqual(state.smartGeneratedDraftIDs, [editorDraft.id])
        XCTAssertTrue(state.smartPlanIsStale)
        XCTAssertEqual(state.drafts, [editorDraft])
        XCTAssertEqual(state.baselinePlanSnapshot, baseline)
        XCTAssertEqual(state.liveInviteRecipient, friend)
    }

    func testConfirmedLiveDraftResolutionUsesFullFingerprintAndExactSessionBinding() throws {
        let account = "cloud_11111111-1111-4111-8111-111111111111"
        let userID = "11111111-1111-4111-8111-111111111111"
        let sessionID = "22222222-2222-4222-8222-222222222222"
        let date = Date(timeIntervalSince1970: 1_787_000_000.125)
        let exerciseID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let draftID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        let setID = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
        let recipient = SocialFriendSummary(
            friendshipID: "f_33333333333333333333333333333333",
            profileID: "p_22222222222222222222222222222222",
            displayName: "Training Partner",
            xp: 10,
            level: 2,
            workouts: 3,
            progressShared: true,
            statsAvailable: true,
            progressUpdatedAt: "2026-08-15T10:00:00Z",
            friendshipRevision: 7
        )

        func makeState(note: String, weight: Double) -> WorkoutPlanEditorDraftState {
            let editorDraft = WorkoutEditorExerciseDraft(
                id: draftID,
                exerciseID: exerciseID,
                sets: [WorkoutEditorSetDraft(id: setID, weight: weight, reps: 8)]
            )
            return WorkoutPlanEditorDraftState(
                accountStorageKey: account,
                date: date,
                note: note,
                profile: TrainingProfile(workoutsPerWeek: 4),
                selectedEffort: .hard,
                latestSmartPlan: nil,
                smartGeneratedDraftIDs: [draftID],
                smartPlanIsStale: true,
                drafts: [editorDraft],
                baselinePlanSnapshot: PlanEditorSnapshot(
                    date: date,
                    note: "baseline",
                    effort: .auto,
                    drafts: [editorDraft]
                ),
                liveInviteRecipient: recipient
            )
        }

        let sent = makeState(note: "Sent note", weight: 82.5)
        let fingerprint = try sent.liveSendFingerprint()
        XCTAssertEqual(fingerprint.count, 64)
        XCTAssertEqual(try sent.liveSendFingerprint(), fingerprint)
        XCTAssertNotEqual(
            try makeState(note: "Newer note", weight: 82.5).liveSendFingerprint(),
            fingerprint
        )
        XCTAssertNotEqual(
            try makeState(note: "Sent note", weight: 85).liveSendFingerprint(),
            fingerprint
        )

        let consumption = LiveWorkoutDraftConsumption(
            version: 1,
            userID: userID,
            sessionID: sessionID,
            operationID: UUID(),
            roomID: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            phase: .confirmed,
            recipientProfileID: recipient.profileID,
            friendshipID: recipient.friendshipID,
            friendshipRevision: recipient.friendshipRevision,
            draftFingerprint: fingerprint,
            createdAt: date,
            expiresAt: date.addingTimeInterval(24 * 60 * 60)
        )
        let exactResolution = resolveConfirmedLiveWorkoutDraft(
                consumption,
                draft: sent,
                accountStorageKey: account,
                userID: userID,
                sessionID: sessionID
            )
        XCTAssertEqual(exactResolution, .consume)
        XCTAssertTrue(exactResolution.shouldAcknowledge)

        let newer = makeState(note: "Newer note", weight: 82.5)
        guard case .preserveUnbound(let preserved) = resolveConfirmedLiveWorkoutDraft(
            consumption,
            draft: newer,
            accountStorageKey: account,
            userID: userID,
            sessionID: sessionID
        ) else {
            return XCTFail("A newer exact-recipient draft must be preserved and unbound")
        }
        XCTAssertNil(preserved.liveInviteRecipient)
        XCTAssertEqual(preserved.note, newer.note)
        XCTAssertEqual(preserved.drafts, newer.drafts)
        XCTAssertTrue(
            ConfirmedLiveWorkoutDraftResolution.preserveUnbound(preserved).shouldAcknowledge
        )
        let unrelatedResolution = resolveConfirmedLiveWorkoutDraft(
                consumption,
                draft: sent,
                accountStorageKey: account,
                userID: userID,
                sessionID: "44444444-4444-4444-8444-444444444444"
            )
        XCTAssertEqual(unrelatedResolution, .unrelated)
        XCTAssertFalse(unrelatedResolution.shouldAcknowledge)
    }

    func testLiveInviteRecipientRequiresFreshMatchingFriendshipAndRevision() {
        let recipient = SocialFriendSummary(
            friendshipID: "friendship-a",
            profileID: "profile-b",
            displayName: "Training Partner",
            xp: nil,
            level: nil,
            workouts: nil,
            progressShared: false,
            statsAvailable: false,
            progressUpdatedAt: nil,
            friendshipRevision: 7
        )
        let currentUser = SocialSelfProfile(
            profileID: "profile-a",
            friendCode: "g_001122334455",
            displayName: "Current User",
            xp: nil,
            level: nil,
            workouts: nil,
            statsAvailable: false,
            progressUpdatedAt: nil,
            privacy: SocialPrivacy(
                allowRequests: true,
                shareProgress: false,
                shareRecentWorkouts: false,
                shareRecords: false
            ),
            settingsRevision: 1
        )

        func dashboard(friend: SocialFriendSummary?) -> SocialDashboard {
            SocialDashboard(
                currentUser: currentUser,
                friends: friend.map { [$0] } ?? [],
                incoming: [],
                outgoing: [],
                blocked: [],
                pendingWorkoutInviteCount: 0
            )
        }

        XCTAssertTrue(liveInviteRecipientIsCurrent(recipient, in: dashboard(friend: recipient)))
        XCTAssertFalse(liveInviteRecipientIsCurrent(recipient, in: dashboard(friend: nil)))
        XCTAssertFalse(liveInviteRecipientIsCurrent(
            recipient,
            in: dashboard(friend: SocialFriendSummary(
                friendshipID: recipient.friendshipID,
                profileID: recipient.profileID,
                displayName: recipient.displayName,
                xp: nil,
                level: nil,
                workouts: nil,
                progressShared: false,
                statsAvailable: false,
                progressUpdatedAt: nil,
                friendshipRevision: recipient.friendshipRevision + 1
            ))
        ))
    }
}
