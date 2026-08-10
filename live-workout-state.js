(function (root, factory) {
  const api = factory(root.GymLiveWorkout);
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  root.GymLiveWorkoutState = api;
})(typeof globalThis !== "undefined" ? globalThis : window, function buildLiveWorkoutState(contract) {
  "use strict";

  const VERSION = 1;
  const MAX_BYTES = 96 * 1024;
  const MAX_OPERATIONS = 256;
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const PROFILE_ID = /^p_[0-9a-f]{32}$/;
  const ROOM_ID = /^lr_[0-9a-f]{32}$/;
  const SET_ID = /^s_[0-9]{2}_[0-9]{2}$/;

  function fail() {
    throw new TypeError("Live workout local state is invalid.");
  }

  function exactObject(value, required) {
    if (!value || typeof value !== "object" || Array.isArray(value) ||
        Object.keys(value).length !== required.length ||
        required.some(key => !Object.hasOwn(value, key))) fail();
    return value;
  }

  function text(value, pattern, maximum) {
    if (typeof value !== "string" || value.length > maximum || (pattern && !pattern.test(value))) fail();
    return value;
  }

  function integer(value, minimum = 1) {
    if (!Number.isSafeInteger(value) || value < minimum || value > 2_147_483_647) fail();
    return value;
  }

  function nullableInteger(value) {
    return value === null ? null : integer(value);
  }

  function nullableTimestamp(value) {
    if (value === null) return null;
    if (!Number.isSafeInteger(value) || value < 1 || value > 8_640_000_000_000_000) fail();
    return value;
  }

  function operation(value, mapping) {
    const legacyKeys = [
      "clientOperationId", "kind", "expectedProgressRevision", "serverSetId", "weight", "reps"
    ];
    const currentKeys = [...legacyKeys, "localMutationAt"];
    if (!value || typeof value !== "object" || Array.isArray(value) ||
        ![legacyKeys.length, currentKeys.length].includes(Object.keys(value).length) ||
        legacyKeys.some(key => !Object.hasOwn(value, key)) ||
        (Object.keys(value).length === currentKeys.length && !Object.hasOwn(value, "localMutationAt"))) fail();
    const row = value;
    const kind = row.kind;
    if (!UUID.test(row.clientOperationId) || !["complete_set", "undo_set", "finish"].includes(kind)) fail();
    const expectedProgressRevision = integer(row.expectedProgressRevision);
    const localMutationAt = Object.hasOwn(row, "localMutationAt")
      ? nullableTimestamp(row.localMutationAt)
      : null;
    if (kind === "finish") {
      if (row.serverSetId !== null || row.weight !== null || row.reps !== null) fail();
    } else {
      if (typeof row.serverSetId !== "string" || !mapping.has(row.serverSetId)) fail();
      if (kind === "complete_set") {
        if (typeof row.weight !== "number" || !Number.isFinite(row.weight) || row.weight < 0 ||
            row.weight > 1_000_000 || !Number.isInteger(row.reps) || row.reps < 1 || row.reps > 10_000) fail();
      } else if (row.weight !== null || row.reps !== null) fail();
    }
    return Object.freeze({
      clientOperationId: row.clientOperationId.toLowerCase(),
      kind,
      expectedProgressRevision,
      serverSetId: row.serverSetId,
      weight: row.weight === 0 ? 0 : row.weight,
      reps: row.reps,
      localMutationAt
    });
  }

  function normalize(value, expectedUserId = null, expectedSessionId = null) {
    const row = exactObject(value, [
      "version", "userId", "sessionId", "roomId", "role", "peerProfileId", "peerDisplayName",
      "roomRevision", "membershipRevision", "progressRevision", "localWorkoutId",
      "serverToLocalSetIds", "pendingOperations"
    ]);
    if (row.version !== VERSION || !UUID.test(row.userId) || !UUID.test(row.sessionId) ||
        (expectedUserId !== null && row.userId !== expectedUserId) ||
        (expectedSessionId !== null && row.sessionId !== expectedSessionId) ||
        !ROOM_ID.test(row.roomId) || !["owner", "participant"].includes(row.role) ||
        !PROFILE_ID.test(row.peerProfileId) || typeof row.peerDisplayName !== "string" ||
        !row.peerDisplayName || row.peerDisplayName.startsWith(" ") || row.peerDisplayName.endsWith(" ") ||
        [...row.peerDisplayName].length > 40 || new TextEncoder().encode(row.peerDisplayName).length > 160 ||
        /[\p{Cc}\p{Cf}\u2028\u2029]/u.test(row.peerDisplayName)) fail();
    const mappingObject = row.serverToLocalSetIds;
    if (!mappingObject || typeof mappingObject !== "object" || Array.isArray(mappingObject)) fail();
    const mappingEntries = Object.entries(mappingObject);
    if (mappingEntries.length < 1 || mappingEntries.length > (contract?.LIMITS?.totalSets || 120) ||
        mappingEntries.some(([serverId, localId]) => !SET_ID.test(serverId) ||
          !Number.isSafeInteger(localId) || localId < 1)) fail();
    const localIds = mappingEntries.map(([, localId]) => localId);
    if (new Set(localIds).size !== localIds.length) fail();
    const mapping = new Map(mappingEntries);
    if (!Array.isArray(row.pendingOperations) || row.pendingOperations.length > MAX_OPERATIONS) fail();
    const pendingOperations = row.pendingOperations.map(value => operation(value, mapping));
    if (new Set(pendingOperations.map(item => item.clientOperationId)).size !== pendingOperations.length) fail();
    return Object.freeze({
      version: VERSION,
      userId: row.userId.toLowerCase(),
      sessionId: row.sessionId.toLowerCase(),
      roomId: row.roomId,
      role: row.role,
      peerProfileId: row.peerProfileId,
      peerDisplayName: row.peerDisplayName,
      roomRevision: integer(row.roomRevision),
      membershipRevision: integer(row.membershipRevision),
      progressRevision: integer(row.progressRevision),
      localWorkoutId: integer(row.localWorkoutId),
      serverToLocalSetIds: Object.freeze(Object.fromEntries(mappingEntries)),
      pendingOperations: Object.freeze(pendingOperations)
    });
  }

  function decode(raw, expectedUserId, expectedSessionId) {
    if (typeof raw !== "string" || new TextEncoder().encode(raw).length > MAX_BYTES) fail();
    return normalize(JSON.parse(raw), expectedUserId, expectedSessionId);
  }

  function encode(value) {
    const normalized = normalize(value);
    const encoded = JSON.stringify(normalized);
    if (new TextEncoder().encode(encoded).length > MAX_BYTES) fail();
    return encoded;
  }

  function bindSnapshot({ userId, sessionId, snapshot, localWorkout }) {
    const parsed = contract?.snapshot?.(snapshot);
    const self = parsed?.participants?.find(row => row.isSelf);
    const peer = parsed?.participants?.find(row => !row.isSelf);
    if (!parsed || parsed.room.status !== "active" || !self?.progress || !peer ||
        !localWorkout || !Number.isSafeInteger(localWorkout.id) || localWorkout.id < 1 ||
        !Array.isArray(localWorkout.blocks) || localWorkout.blocks.length !== parsed.plan.exercises.length) fail();
    const mapping = {};
    parsed.plan.exercises.forEach((exercise, exerciseIndex) => {
      const block = localWorkout.blocks[exerciseIndex];
      if (!block || block.exerciseName !== exercise.name || !Array.isArray(block.sets) ||
          block.sets.length !== exercise.sets.length) fail();
      exercise.sets.forEach((set, setIndex) => {
        const localSet = block.sets[setIndex];
        if (!localSet || !Number.isSafeInteger(localSet.id) || localSet.id < 1) fail();
        mapping[set.setId] = localSet.id;
      });
    });
    return normalize({
      version: VERSION,
      userId,
      sessionId,
      roomId: parsed.room.roomId,
      role: self.role,
      peerProfileId: peer.profile.profileId,
      peerDisplayName: peer.profile.displayName,
      roomRevision: parsed.room.roomRevision,
      membershipRevision: self.membershipRevision,
      progressRevision: self.progress.revision,
      localWorkoutId: localWorkout.id,
      serverToLocalSetIds: mapping,
      pendingOperations: []
    }, userId, sessionId);
  }

  function localToServer(value, localSetId) {
    const state = normalize(value);
    return Object.entries(state.serverToLocalSetIds)
      .find(([, candidate]) => candidate === localSetId)?.[0] || null;
  }

  function enqueue(value, requested) {
    const state = normalize(value);
    if (state.pendingOperations.length >= MAX_OPERATIONS) fail();
    const kind = requested?.kind;
    const serverSetId = requested?.serverSetId ?? null;
    const operationValue = {
      clientOperationId: text(requested?.clientOperationId, UUID, 36).toLowerCase(),
      kind,
      expectedProgressRevision: state.progressRevision + state.pendingOperations.length,
      serverSetId,
      weight: kind === "complete_set" ? requested.weight : null,
      reps: kind === "complete_set" ? requested.reps : null,
      localMutationAt: nullableTimestamp(requested?.localMutationAt ?? null)
    };
    operation(operationValue, new Map(Object.entries(state.serverToLocalSetIds)));
    return normalize({ ...state, pendingOperations: [...state.pendingOperations, operationValue] });
  }

  function acknowledge(value, clientOperationId, progressRevision, roomRevision = null, membershipRevision = null) {
    const state = normalize(value);
    const first = state.pendingOperations[0];
    if (!first || first.clientOperationId !== clientOperationId || progressRevision < state.progressRevision) fail();
    return normalize({
      ...state,
      progressRevision: integer(progressRevision),
      roomRevision: roomRevision === null ? state.roomRevision : integer(roomRevision),
      membershipRevision: membershipRevision === null ? state.membershipRevision : integer(membershipRevision),
      pendingOperations: state.pendingOperations.slice(1).map((item, index) => ({
        ...item,
        expectedProgressRevision: progressRevision + index
      }))
    });
  }

  function rebase(value, progressRevision, replacementOperationId, roomRevision = null, membershipRevision = null) {
    const state = normalize(value);
    if (!state.pendingOperations.length || !UUID.test(replacementOperationId || "")) fail();
    const nextProgressRevision = integer(progressRevision);
    return normalize({
      ...state,
      progressRevision: nextProgressRevision,
      roomRevision: roomRevision === null ? state.roomRevision : integer(roomRevision),
      membershipRevision: membershipRevision === null ? state.membershipRevision : integer(membershipRevision),
      pendingOperations: state.pendingOperations.map((item, index) => ({
        ...item,
        clientOperationId: index === 0 ? replacementOperationId.toLowerCase() : item.clientOperationId,
        expectedProgressRevision: nextProgressRevision + index
      }))
    });
  }

  return Object.freeze({
    VERSION,
    MAX_BYTES,
    MAX_OPERATIONS,
    normalize,
    decode,
    encode,
    bindSnapshot,
    localToServer,
    enqueue,
    acknowledge,
    rebase
  });
});
