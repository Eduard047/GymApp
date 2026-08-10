import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const sharedSource = await readFile("pwa/shared-workout.js", "utf8");
const liveSource = await readFile("pwa/live-workout.js", "utf8");

function contract() {
  const context = { TextEncoder };
  context.globalThis = context;
  vm.createContext(context);
  vm.runInContext(sharedSource, context);
  vm.runInContext(liveSource, context);
  return context.GymLiveWorkout;
}

const roomId = "lr_11111111111111111111111111111111";
const ownerProfile = {
  profileId: "p_11111111111111111111111111111111",
  displayName: "Owner"
};
const friendProfile = {
  profileId: "p_22222222222222222222222222222222",
  displayName: "Friend"
};

function livePlan() {
  return {
    version: 1,
    exercises: [{
      exerciseId: "e_01",
      catalogKey: "bench_press",
      name: "Bench Press",
      sets: [
        { setId: "s_01_01", weight: 80, reps: 8 },
        { setId: "s_01_02", weight: 82.5, reps: 6 }
      ]
    }]
  };
}

function planSummary() {
  return { exerciseCount: 1, setCount: 2, exerciseNames: ["Bench Press"] };
}

function activeSnapshot() {
  return {
    version: 1,
    room: {
      roomId,
      status: "active",
      roomRevision: 3,
      closeReason: null,
      createdAt: "2026-08-10T10:00:00Z",
      inviteExpiresAt: "2026-08-17T10:00:00Z",
      startedAt: "2026-08-10T10:05:00Z",
      activeExpiresAt: "2026-08-11T10:05:00Z",
      endedAt: null,
      summary: planSummary()
    },
    plan: livePlan(),
    participants: [{
      isSelf: true,
      profile: ownerProfile,
      role: "owner",
      state: "joined",
      membershipRevision: 1,
      joinedAt: "2026-08-10T10:00:00Z",
      finishedAt: null,
      departedAt: null,
      progress: {
        version: 1,
        revision: 2,
        completedSets: [{
          setId: "s_01_01",
          weight: 81,
          reps: 8,
          completedAt: "2026-08-10T10:06:00Z"
        }],
        undoableSetId: "s_01_01",
        finishedAt: null
      }
    }, {
      isSelf: false,
      profile: friendProfile,
      role: "participant",
      state: "joined",
      membershipRevision: 2,
      joinedAt: "2026-08-10T10:03:00Z",
      finishedAt: null,
      departedAt: null,
      progress: {
        version: 1,
        revision: 1,
        completedSets: [],
        undoableSetId: null,
        finishedAt: null
      }
    }]
  };
}

test("live snapshot preserves two independent progress lanes and canonical set ids", () => {
  const parsed = contract().snapshot(activeSnapshot());
  assert.equal(parsed.room.status, "active");
  assert.equal(parsed.participants.length, 2);
  assert.equal(parsed.participants[0].progress.completedSets[0].weight, 81);
  assert.equal(parsed.participants[1].progress.completedSets.length, 0);
  assert.deepEqual(JSON.parse(JSON.stringify(contract().sharedPlan(parsed.plan))), {
    version: 1,
    exercises: [{
      catalogKey: "bench_press",
      name: "Bench Press",
      sets: [{ weight: 80, reps: 8 }, { weight: 82.5, reps: 6 }]
    }]
  });
});

test("ready room accepts joined participants without progress before host start", () => {
  const value = activeSnapshot();
  value.room.status = "ready";
  value.room.roomRevision = 2;
  value.room.startedAt = null;
  value.room.activeExpiresAt = null;
  value.participants.forEach(participant => { participant.progress = null; });

  const parsed = contract().snapshot(value);
  assert.equal(parsed.room.status, "ready");
  assert.equal(parsed.participants.every(participant => participant.progress === null), true);
});

test("cancelled room may retain started timestamps for bounded recovery", () => {
  const value = activeSnapshot();
  value.room.status = "cancelled";
  value.room.closeReason = "left";
  value.room.endedAt = "2026-08-10T10:30:00Z";
  value.participants[1].state = "left";
  value.participants[1].departedAt = "2026-08-10T10:30:00Z";

  assert.equal(contract().snapshot(value).room.closeReason, "left");
});

test("contract rejects peer identity duplication, unknown fields and invalid calendar dates", () => {
  const duplicate = activeSnapshot();
  duplicate.participants[1].profile.profileId = ownerProfile.profileId;
  assert.throws(() => contract().snapshot(duplicate), /identities are inconsistent/);

  const extra = activeSnapshot();
  extra.room.note = "private";
  assert.throws(() => contract().snapshot(extra), /fields are invalid/);

  const invalidDate = activeSnapshot();
  invalidDate.room.createdAt = "2026-02-30T10:00:00Z";
  assert.throws(() => contract().snapshot(invalidDate), /timestamp is invalid/);
});

test("contract rejects duplicate and out-of-order canonical plan identities", () => {
  const duplicate = activeSnapshot();
  duplicate.plan.exercises.push({
    exerciseId: "e_02",
    name: "\u00a0bench press\u00a0",
    sets: [{ setId: "s_02_01", weight: 40, reps: 12 }]
  });
  duplicate.room.summary = {
    exerciseCount: 2,
    setCount: 3,
    exerciseNames: ["Bench Press", "\u00a0bench press\u00a0"]
  };
  assert.throws(() => contract().snapshot(duplicate), /identity is duplicated|summary is duplicated/);

  const order = activeSnapshot();
  order.plan.exercises[0].sets[0].setId = "s_01_02";
  assert.throws(() => contract().snapshot(order), /set is invalid/);
});

test("live inbox keeps invitations separate from joined rooms", () => {
  const parsed = contract().inbox({
    version: 1,
    invitations: [{
      roomId,
      status: "waiting",
      roomRevision: 1,
      createdAt: "2026-08-10T10:00:00Z",
      inviteExpiresAt: "2026-08-17T10:00:00Z",
      summary: planSummary(),
      owner: ownerProfile
    }],
    rooms: []
  });
  assert.equal(parsed.invitations[0].owner.displayName, "Owner");
  assert.equal(parsed.rooms.length, 0);

  assert.throws(() => contract().inbox({
    version: 1,
    invitations: [{
      roomId,
      status: "waiting",
      roomRevision: 1,
      createdAt: "2026-08-10T10:00:00Z",
      inviteExpiresAt: "2026-08-17T10:00:00Z",
      summary: planSummary(),
      owner: ownerProfile
    }],
    rooms: [{
      roomId,
      status: "ready",
      roomRevision: 2,
      role: "participant",
      memberState: "joined",
      membershipRevision: 2,
      createdAt: "2026-08-10T10:00:00Z",
      startedAt: null,
      activeExpiresAt: null,
      summary: planSummary(),
      peer: ownerProfile
    }]
  }), /duplicate rooms/);
});

test("mutation parsers bind result kind, ids, revisions and timestamps", () => {
  const api = contract();
  assert.equal(api.sendResult({
    version: 1,
    result: "submitted",
    roomId,
    status: "waiting",
    roomRevision: 1
  }).roomId, roomId);
  assert.equal(api.respondResult({
    version: 1,
    result: "joined",
    roomId,
    status: "ready",
    roomRevision: 2,
    membershipRevision: 2
  }).status, "ready");
  assert.equal(api.startResult({
    version: 1,
    result: "started",
    roomId,
    status: "active",
    roomRevision: 3,
    startedAt: "2026-08-10T10:05:00Z",
    activeExpiresAt: "2026-08-11T10:05:00Z",
    myProgressRevision: 1
  }).status, "active");
  assert.equal(api.applyResult({
    version: 1,
    result: "applied",
    roomId,
    roomRevision: 4,
    progressRevision: 2,
    kind: "complete_set",
    setId: "s_01_01",
    completedAt: "2026-08-10T10:06:00Z"
  }).progressRevision, 2);
  assert.equal(api.finishResult({
    version: 1,
    result: "finished",
    roomId,
    status: "active",
    roomRevision: 5,
    progressRevision: 3,
    membershipRevision: 2,
    finishedAt: "2026-08-10T10:30:00Z"
  }).result, "finished");

  assert.throws(() => api.applyResult({
    version: 1,
    result: "applied",
    roomId,
    roomRevision: 4,
    progressRevision: 2,
    kind: "undo_set",
    setId: "s_01_01",
    completedAt: "2026-08-10T10:06:00Z"
  }), /apply result is invalid/);
});

test("realtime event is a bounded invalidation hint, never a workout payload", () => {
  const api = contract();
  assert.deepEqual(JSON.parse(JSON.stringify(api.realtimeEvent({
    version: 1,
    kind: "progress",
    roomId,
    roomRevision: 7
  }))), { version: 1, kind: "progress", roomId, roomRevision: 7 });
  assert.throws(() => api.realtimeEvent({
    version: 1,
    kind: "progress",
    roomId,
    roomRevision: 7,
    weight: 200
  }), /fields are invalid/);
});
