import assert from "node:assert/strict";
import test from "node:test";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
globalThis.GymSharedWorkout = require("../pwa/shared-workout.js");
globalThis.GymLiveWorkout = require("../pwa/live-workout.js");
const stateContract = require("../pwa/live-workout-state.js");

const USER_ID = "11111111-1111-4111-8111-111111111111";
const SESSION_ID = "22222222-2222-4222-8222-222222222222";
const ROOM_ID = `lr_${"a".repeat(32)}`;
const timestamp = "2026-08-10T08:00:00Z";

function snapshot() {
  return {
    version: 1,
    room: {
      roomId: ROOM_ID,
      status: "active",
      roomRevision: 3,
      closeReason: null,
      createdAt: "2026-08-10T07:50:00Z",
      inviteExpiresAt: "2026-08-10T08:20:00Z",
      startedAt: timestamp,
      activeExpiresAt: "2026-08-10T14:00:00Z",
      endedAt: null,
      summary: { exerciseCount: 1, setCount: 2, exerciseNames: ["Bench Press"] }
    },
    plan: {
      version: 1,
      exercises: [{
        exerciseId: "e_01",
        catalogKey: "bench_press",
        name: "Bench Press",
        sets: [
          { setId: "s_01_01", weight: 80, reps: 8 },
          { setId: "s_01_02", weight: 80, reps: 8 }
        ]
      }]
    },
    participants: [
      {
        isSelf: true,
        profile: { profileId: `p_${"1".repeat(32)}`, displayName: "Me" },
        role: "owner",
        state: "joined",
        membershipRevision: 2,
        joinedAt: "2026-08-10T07:50:00Z",
        finishedAt: null,
        departedAt: null,
        progress: { version: 1, revision: 1, completedSets: [], undoableSetId: null, finishedAt: null }
      },
      {
        isSelf: false,
        profile: { profileId: `p_${"2".repeat(32)}`, displayName: "Friend" },
        role: "participant",
        state: "joined",
        membershipRevision: 2,
        joinedAt: "2026-08-10T07:55:00Z",
        finishedAt: null,
        departedAt: null,
        progress: { version: 1, revision: 1, completedSets: [], undoableSetId: null, finishedAt: null }
      }
    ]
  };
}

function localWorkout() {
  return {
    id: 100,
    blocks: [{
      exerciseName: "Bench Press",
      sets: [{ id: 101 }, { id: 102 }]
    }]
  };
}

test("binds canonical server set ids to local active set ids", () => {
  const value = stateContract.bindSnapshot({
    userId: USER_ID,
    sessionId: SESSION_ID,
    snapshot: snapshot(),
    localWorkout: localWorkout()
  });
  assert.equal(value.serverToLocalSetIds.s_01_01, 101);
  assert.equal(stateContract.localToServer(value, 102), "s_01_02");
  assert.deepEqual(stateContract.decode(stateContract.encode(value), USER_ID, SESSION_ID), value);
});

test("queues local-first operations with stable sequential revisions", () => {
  const bound = stateContract.bindSnapshot({
    userId: USER_ID,
    sessionId: SESSION_ID,
    snapshot: snapshot(),
    localWorkout: localWorkout()
  });
  const first = stateContract.enqueue(bound, {
    clientOperationId: "33333333-3333-4333-8333-333333333333",
    kind: "complete_set",
    serverSetId: "s_01_01",
    weight: 82.5,
    reps: 7,
    localMutationAt: 1_786_334_400_000
  });
  const second = stateContract.enqueue(first, {
    clientOperationId: "44444444-4444-4444-8444-444444444444",
    kind: "undo_set",
    serverSetId: "s_01_01"
  });
  assert.deepEqual(second.pendingOperations.map(value => value.expectedProgressRevision), [1, 2]);
  assert.equal(second.pendingOperations[0].localMutationAt, 1_786_334_400_000);
  assert.equal(second.pendingOperations[1].localMutationAt, null);

  const acknowledged = stateContract.acknowledge(
    second,
    first.pendingOperations[0].clientOperationId,
    2,
    4
  );
  assert.equal(acknowledged.progressRevision, 2);
  assert.equal(acknowledged.roomRevision, 4);
  assert.equal(acknowledged.pendingOperations[0].expectedProgressRevision, 2);

  const rebased = stateContract.rebase(
    second,
    7,
    "55555555-5555-4555-8555-555555555555",
    9,
    4
  );
  assert.equal(rebased.progressRevision, 7);
  assert.equal(rebased.roomRevision, 9);
  assert.equal(rebased.membershipRevision, 4);
  assert.equal(rebased.pendingOperations[0].expectedProgressRevision, 7);
  assert.equal(rebased.pendingOperations[1].expectedProgressRevision, 8);
  assert.equal(rebased.pendingOperations[0].clientOperationId, "55555555-5555-4555-8555-555555555555");
});

test("fails closed for another account, duplicate mapping or malformed queue", () => {
  const bound = stateContract.bindSnapshot({
    userId: USER_ID,
    sessionId: SESSION_ID,
    snapshot: snapshot(),
    localWorkout: localWorkout()
  });
  assert.throws(() => stateContract.decode(
    stateContract.encode(bound),
    "99999999-9999-4999-8999-999999999999",
    SESSION_ID
  ));
  assert.throws(() => stateContract.normalize({
    ...bound,
    serverToLocalSetIds: { s_01_01: 101, s_01_02: 101 }
  }));
  assert.throws(() => stateContract.enqueue(bound, {
    clientOperationId: "33333333-3333-4333-8333-333333333333",
    kind: "complete_set",
    serverSetId: "s_99_99",
    weight: 10,
    reps: 10
  }));
});
