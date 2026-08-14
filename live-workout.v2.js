(function (root, factory) {
  const api = factory(root.GymSharedWorkout);
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  root.GymLiveWorkout = api;
})(typeof globalThis !== "undefined" ? globalThis : window, function buildLiveWorkoutContract(sharedWorkout) {
  "use strict";

  const VERSION = 1;
  const LIMITS = Object.freeze({
    rooms: 25,
    exercises: 20,
    setsPerExercise: 12,
    totalSets: 120,
    nameCharacters: 120,
    nameBytes: 480,
    displayNameCharacters: 40,
    displayNameBytes: 160,
    planBytes: 65_536,
    responseBytes: 256 * 1024,
    weightMax: 1_000_000,
    repsMax: 10_000,
    revisionMax: 2_147_483_647
  });
  const ROOM_ID = /^lr_[0-9a-f]{32}$/;
  const PROFILE_ID = /^p_[0-9a-f]{32}$/;
  const EXERCISE_ID = /^e_[0-9]{2}$/;
  const SET_ID = /^s_[0-9]{2}_[0-9]{2}$/;
  const CATALOG_KEY = /^[a-z0-9_]{1,64}$/;
  const RFC3339 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;

  function fail(message) {
    throw new TypeError(message);
  }

  function utf8Length(value) {
    return new TextEncoder().encode(value).length;
  }

  function exactObject(value, required, optional = []) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      fail("Live workout object is invalid.");
    }
    const allowed = new Set([...required, ...optional]);
    const keys = Object.keys(value);
    if (keys.length < required.length || keys.some(key => !allowed.has(key)) ||
        required.some(key => !Object.hasOwn(value, key))) {
      fail("Live workout object fields are invalid.");
    }
    return value;
  }

  function integer(value, minimum, maximum, label = "integer") {
    if (!Number.isInteger(value) || value < minimum || value > maximum) {
      fail(`Live workout ${label} is invalid.`);
    }
    return value;
  }

  function identifier(value, pattern, label) {
    if (typeof value !== "string" || !pattern.test(value)) {
      fail(`Live workout ${label} is invalid.`);
    }
    return value;
  }

  function timestamp(value, nullable = false) {
    if (nullable && value === null) return null;
    if (typeof value !== "string" || value.length > 40 || !RFC3339.test(value) ||
        !Number.isFinite(Date.parse(value))) {
      fail("Live workout timestamp is invalid.");
    }
    const match = value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/);
    const date = new Date(value);
    const year = Number(match?.[1]);
    const month = Number(match?.[2]);
    const day = Number(match?.[3]);
    const hour = Number(match?.[4]);
    const minute = Number(match?.[5]);
    const second = Number(match?.[6]);
    const calendarCheck = new Date(Date.UTC(year, month - 1, day));
    if (!match || year < 2020 || year > 2200 || month < 1 || month > 12 || day < 1 ||
        calendarCheck.getUTCFullYear() !== year || calendarCheck.getUTCMonth() !== month - 1 ||
        calendarCheck.getUTCDate() !== day || hour > 23 || minute > 59 || second > 59 ||
        date.getUTCFullYear() < 2019 || date.getUTCFullYear() > 2201) {
      fail("Live workout timestamp is invalid.");
    }
    return value;
  }

  function safeText(value, characterLimit, byteLimit, label) {
    if (typeof value !== "string" || !value || value.startsWith(" ") || value.endsWith(" ") ||
        [...value].length > characterLimit || utf8Length(value) > byteLimit ||
        /[\p{Cc}\p{Cf}\u2028\u2029]/u.test(value)) {
      fail(`Live workout ${label} is invalid.`);
    }
    return value;
  }

  function profile(value) {
    const row = exactObject(value, ["profileId", "displayName"]);
    return Object.freeze({
      profileId: identifier(row.profileId, PROFILE_ID, "profile id"),
      displayName: safeText(
        row.displayName,
        LIMITS.displayNameCharacters,
        LIMITS.displayNameBytes,
        "display name"
      )
    });
  }

  function summary(value) {
    const row = exactObject(value, ["exerciseCount", "setCount", "exerciseNames"]);
    const exerciseCount = integer(row.exerciseCount, 1, LIMITS.exercises, "exercise count");
    const setCount = integer(row.setCount, 1, LIMITS.totalSets, "set count");
    if (!Array.isArray(row.exerciseNames) || row.exerciseNames.length !== exerciseCount) {
      fail("Live workout exercise summary is invalid.");
    }
    const exerciseNames = row.exerciseNames.map(name => safeText(
      name,
      LIMITS.nameCharacters,
      LIMITS.nameBytes,
      "exercise name"
    ));
    if (new Set(exerciseNames.map(portableNameKey)).size !== exerciseNames.length) {
      fail("Live workout exercise summary is duplicated.");
    }
    return Object.freeze({ exerciseCount, setCount, exerciseNames: Object.freeze(exerciseNames) });
  }

  function portableNameKey(value) {
    if (typeof sharedWorkout?.portableNameKey !== "function") {
      fail("Live workout identity normalizer is unavailable.");
    }
    return sharedWorkout.portableNameKey(value);
  }

  function plan(value) {
    const root = exactObject(value, ["version", "exercises"]);
    if (root.version !== VERSION || !Array.isArray(root.exercises) ||
        root.exercises.length < 1 || root.exercises.length > LIMITS.exercises ||
        utf8Length(JSON.stringify(root)) > LIMITS.planBytes) {
      fail("Live workout plan is invalid.");
    }
    let totalSets = 0;
    const nameKeys = new Set();
    const catalogKeys = new Set();
    const setIds = new Set();
    const exercises = root.exercises.map((value, exerciseIndex) => {
      const row = exactObject(value, ["exerciseId", "name", "sets"], ["catalogKey"]);
      const exerciseId = identifier(row.exerciseId, EXERCISE_ID, "exercise id");
      if (exerciseId !== `e_${String(exerciseIndex + 1).padStart(2, "0")}`) {
        fail("Live workout exercise order is invalid.");
      }
      const name = safeText(row.name, LIMITS.nameCharacters, LIMITS.nameBytes, "exercise name");
      const nameKey = portableNameKey(name);
      if (!nameKey || nameKeys.has(nameKey)) fail("Live workout exercise identity is duplicated.");
      nameKeys.add(nameKey);
      let catalogKey;
      if (Object.hasOwn(row, "catalogKey")) {
        catalogKey = identifier(row.catalogKey, CATALOG_KEY, "catalog key");
        if (catalogKeys.has(catalogKey)) fail("Live workout catalog identity is duplicated.");
        catalogKeys.add(catalogKey);
      }
      if (!Array.isArray(row.sets) || row.sets.length < 1 || row.sets.length > LIMITS.setsPerExercise) {
        fail("Live workout set list is invalid.");
      }
      totalSets += row.sets.length;
      if (totalSets > LIMITS.totalSets) fail("Live workout has too many sets.");
      const sets = row.sets.map((value, setIndex) => {
        const set = exactObject(value, ["setId", "weight", "reps"]);
        const setId = identifier(set.setId, SET_ID, "set id");
        const expectedId = `s_${String(exerciseIndex + 1).padStart(2, "0")}_${String(setIndex + 1).padStart(2, "0")}`;
        if (setId !== expectedId || setIds.has(setId) || typeof set.weight !== "number" ||
            !Number.isFinite(set.weight) || set.weight < 0 || set.weight > LIMITS.weightMax ||
            !Number.isInteger(set.reps) || set.reps < 1 || set.reps > LIMITS.repsMax) {
          fail("Live workout set is invalid.");
        }
        setIds.add(setId);
        return Object.freeze({ setId, weight: Object.is(set.weight, -0) ? 0 : set.weight, reps: set.reps });
      });
      return Object.freeze({
        exerciseId,
        ...(catalogKey ? { catalogKey } : {}),
        name,
        sets: Object.freeze(sets)
      });
    });
    return Object.freeze({ version: VERSION, exercises: Object.freeze(exercises) });
  }

  function summaryMatchesPlan(value, parsedPlan) {
    return value.exerciseCount === parsedPlan.exercises.length &&
      value.setCount === parsedPlan.exercises.reduce((count, exercise) => count + exercise.sets.length, 0) &&
      value.exerciseNames.every((name, index) => name === parsedPlan.exercises[index].name);
  }

  function progress(value, parsedPlan) {
    const row = exactObject(value, ["version", "revision", "completedSets", "undoableSetId", "finishedAt"]);
    if (row.version !== VERSION || !Array.isArray(row.completedSets) ||
        row.completedSets.length > LIMITS.totalSets) {
      fail("Live workout progress is invalid.");
    }
    const validSetIds = new Set(parsedPlan.exercises.flatMap(exercise => exercise.sets.map(set => set.setId)));
    const completedIds = new Set();
    const completedSets = row.completedSets.map(value => {
      const set = exactObject(value, ["setId", "weight", "reps", "completedAt"]);
      const setId = identifier(set.setId, SET_ID, "completed set id");
      if (!validSetIds.has(setId) || completedIds.has(setId) || typeof set.weight !== "number" ||
          !Number.isFinite(set.weight) || set.weight < 0 || set.weight > LIMITS.weightMax ||
          !Number.isInteger(set.reps) || set.reps < 1 || set.reps > LIMITS.repsMax) {
        fail("Live workout completed set is invalid.");
      }
      completedIds.add(setId);
      return Object.freeze({
        setId,
        weight: Object.is(set.weight, -0) ? 0 : set.weight,
        reps: set.reps,
        completedAt: timestamp(set.completedAt)
      });
    });
    const undoableSetId = row.undoableSetId === null
      ? null
      : identifier(row.undoableSetId, SET_ID, "undoable set id");
    if (undoableSetId !== null && (!completedIds.has(undoableSetId) ||
        completedSets.at(-1)?.setId !== undoableSetId)) {
      fail("Live workout undo state is invalid.");
    }
    const finishedAt = timestamp(row.finishedAt, true);
    if ((finishedAt !== null) !== (undoableSetId === null && completedSets.length > 0)) {
      // A finished participant has no undo. An unfinished participant may also have no undo
      // immediately after a bulk/server reconciliation, so only reject the impossible inverse.
      if (finishedAt !== null && undoableSetId !== null) fail("Live workout finish state is invalid.");
    }
    return Object.freeze({
      version: VERSION,
      revision: integer(row.revision, 1, LIMITS.revisionMax, "progress revision"),
      completedSets: Object.freeze(completedSets),
      undoableSetId,
      finishedAt
    });
  }

  function room(value) {
    const row = exactObject(value, [
      "roomId", "status", "roomRevision", "closeReason", "createdAt", "inviteExpiresAt",
      "startedAt", "activeExpiresAt", "endedAt", "summary"
    ]);
    const status = row.status;
    if (!["waiting", "ready", "active", "completed", "cancelled", "expired"].includes(status)) {
      fail("Live workout room status is invalid.");
    }
    const createdAt = timestamp(row.createdAt);
    const inviteExpiresAt = timestamp(row.inviteExpiresAt);
    const startedAt = timestamp(row.startedAt, true);
    const activeExpiresAt = timestamp(row.activeExpiresAt, true);
    const endedAt = timestamp(row.endedAt, true);
    const open = status === "waiting" || status === "ready" || status === "active";
    const terminal = ["completed", "cancelled", "expired"].includes(status);
    const closeReasons = new Set([
      "completed", "declined", "cancelled", "left", "friend_removed", "blocked",
      "account_deleted", "expired"
    ]);
    const startedFieldsMatch = startedAt === null ? activeExpiresAt === null : activeExpiresAt !== null;
    if (Date.parse(inviteExpiresAt) <= Date.parse(createdAt) ||
        !startedFieldsMatch ||
        (["waiting", "ready"].includes(status) && startedAt !== null) ||
        (["active", "completed"].includes(status) && startedAt === null) ||
        terminal !== (endedAt !== null) || open === (row.closeReason !== null) ||
        (row.closeReason !== null && !closeReasons.has(row.closeReason)) ||
        (status === "completed" && row.closeReason !== "completed") ||
        (status === "expired" && row.closeReason !== "expired") ||
        (activeExpiresAt !== null && Date.parse(activeExpiresAt) <= Date.parse(startedAt))) {
      fail("Live workout room lifecycle is inconsistent.");
    }
    return Object.freeze({
      roomId: identifier(row.roomId, ROOM_ID, "room id"),
      status,
      roomRevision: integer(row.roomRevision, 1, LIMITS.revisionMax, "room revision"),
      closeReason: row.closeReason,
      createdAt,
      inviteExpiresAt,
      startedAt,
      activeExpiresAt,
      endedAt,
      summary: summary(row.summary)
    });
  }

  function participant(value, parsedPlan, roomStatus) {
    const row = exactObject(value, [
      "isSelf", "profile", "role", "state", "membershipRevision", "joinedAt",
      "finishedAt", "departedAt", "progress"
    ]);
    if (typeof row.isSelf !== "boolean" || !["owner", "participant"].includes(row.role) ||
        !["invited", "joined", "finished", "left", "revoked"].includes(row.state)) {
      fail("Live workout participant is invalid.");
    }
    const joinedAt = timestamp(row.joinedAt, true);
    const finishedAt = timestamp(row.finishedAt, true);
    const departedAt = timestamp(row.departedAt, true);
    if ((row.state === "invited") !== (joinedAt === null && finishedAt === null && departedAt === null) ||
        (row.state === "joined") !== (joinedAt !== null && finishedAt === null && departedAt === null) ||
        (row.state === "finished") !== (joinedAt !== null && finishedAt !== null && departedAt === null) ||
        (["left", "revoked"].includes(row.state) && departedAt === null)) {
      fail("Live workout participant lifecycle is inconsistent.");
    }
    const parsedProgress = row.progress === null ? null : progress(row.progress, parsedPlan);
    if ((["waiting", "ready"].includes(roomStatus) && parsedProgress !== null) ||
        (["active", "completed"].includes(roomStatus) &&
          ["joined", "finished"].includes(row.state) && parsedProgress === null) ||
        (row.state === "finished" && parsedProgress?.finishedAt === null)) {
      fail("Live workout participant progress is inconsistent.");
    }
    return Object.freeze({
      isSelf: row.isSelf,
      profile: profile(row.profile),
      role: row.role,
      state: row.state,
      membershipRevision: integer(row.membershipRevision, 1, LIMITS.revisionMax, "membership revision"),
      joinedAt,
      finishedAt,
      departedAt,
      progress: parsedProgress
    });
  }

  function snapshot(value) {
    const root = exactObject(value, ["version", "room", "plan", "participants"]);
    if (root.version !== VERSION || !Array.isArray(root.participants) || root.participants.length !== 2) {
      fail("Live workout snapshot is invalid.");
    }
    const parsedPlan = plan(root.plan);
    const parsedRoom = room(root.room);
    if (!summaryMatchesPlan(parsedRoom.summary, parsedPlan)) {
      fail("Live workout plan summary is inconsistent.");
    }
    const participants = root.participants.map(value => participant(value, parsedPlan, parsedRoom.status));
    if (participants.filter(value => value.isSelf).length !== 1 ||
        new Set(participants.map(value => value.role)).size !== 2 ||
        new Set(participants.map(value => value.profile.profileId)).size !== 2) {
      fail("Live workout participant identities are inconsistent.");
    }
    return Object.freeze({
      version: VERSION,
      room: parsedRoom,
      plan: parsedPlan,
      participants: Object.freeze(participants)
    });
  }

  function inbox(value) {
    const root = exactObject(value, ["version", "invitations", "rooms"]);
    if (root.version !== VERSION || !Array.isArray(root.invitations) ||
        root.invitations.length > LIMITS.rooms || !Array.isArray(root.rooms) || root.rooms.length > LIMITS.rooms) {
      fail("Live workout inbox is invalid.");
    }
    const invitations = root.invitations.map(value => {
      const row = exactObject(value, [
        "roomId", "status", "roomRevision", "createdAt", "inviteExpiresAt", "summary", "owner"
      ]);
      if (row.status !== "waiting" || Date.parse(timestamp(row.inviteExpiresAt)) <= Date.parse(timestamp(row.createdAt))) {
        fail("Live workout invitation is invalid.");
      }
      return Object.freeze({
        roomId: identifier(row.roomId, ROOM_ID, "room id"),
        status: row.status,
        roomRevision: integer(row.roomRevision, 1, LIMITS.revisionMax, "room revision"),
        createdAt: row.createdAt,
        inviteExpiresAt: row.inviteExpiresAt,
        summary: summary(row.summary),
        owner: profile(row.owner)
      });
    });
    const rooms = root.rooms.map(value => {
      const row = exactObject(value, [
        "roomId", "status", "roomRevision", "role", "memberState", "membershipRevision",
        "createdAt", "startedAt", "activeExpiresAt", "summary", "peer"
      ]);
      if (!["waiting", "ready", "active"].includes(row.status) ||
          !["owner", "participant"].includes(row.role) ||
          !["joined", "finished"].includes(row.memberState)) {
        fail("Live workout room list item is invalid.");
      }
      const startedAt = timestamp(row.startedAt, true);
      const activeExpiresAt = timestamp(row.activeExpiresAt, true);
      if ((row.status === "active") !== (startedAt !== null && activeExpiresAt !== null)) {
        fail("Live workout room list lifecycle is inconsistent.");
      }
      return Object.freeze({
        roomId: identifier(row.roomId, ROOM_ID, "room id"),
        status: row.status,
        roomRevision: integer(row.roomRevision, 1, LIMITS.revisionMax, "room revision"),
        role: row.role,
        memberState: row.memberState,
        membershipRevision: integer(row.membershipRevision, 1, LIMITS.revisionMax, "membership revision"),
        createdAt: timestamp(row.createdAt),
        startedAt,
        activeExpiresAt,
        summary: summary(row.summary),
        peer: profile(row.peer)
      });
    });
    const ids = [...invitations, ...rooms].map(value => value.roomId);
    if (new Set(ids).size !== ids.length) fail("Live workout inbox contains duplicate rooms.");
    return Object.freeze({ version: VERSION, invitations: Object.freeze(invitations), rooms: Object.freeze(rooms) });
  }

  function sharedPlan(parsedPlan) {
    const parsed = plan(parsedPlan);
    return Object.freeze({
      version: VERSION,
      exercises: Object.freeze(parsed.exercises.map(exercise => Object.freeze({
        ...(exercise.catalogKey ? { catalogKey: exercise.catalogKey } : {}),
        name: exercise.name,
        sets: Object.freeze(exercise.sets.map(set => Object.freeze({ weight: set.weight, reps: set.reps })))
      })))
    });
  }

  function nullableRoomResultFields(row) {
    const allNull = row.roomId === null && row.status === null && row.roomRevision === null;
    if (!allNull) {
      identifier(row.roomId, ROOM_ID, "room id");
      integer(row.roomRevision, 1, LIMITS.revisionMax, "room revision");
    }
    return allNull;
  }

  function sendResult(value) {
    const row = exactObject(value, ["version", "result", "roomId", "status", "roomRevision"]);
    if (row.version !== VERSION || !["submitted", "submitted_or_unavailable"].includes(row.result)) {
      fail("Live workout send result is invalid.");
    }
    const unavailable = nullableRoomResultFields(row);
    if ((row.result === "submitted") === unavailable || (!unavailable && row.status !== "waiting")) {
      fail("Live workout send result is inconsistent.");
    }
    return Object.freeze({ ...row });
  }

  function closedResult(value) {
    const row = exactObject(value, [
      "version", "result", "roomId", "status", "roomRevision", "endedAt"
    ]);
    if (row.version !== VERSION || row.result !== "closed" || row.status !== "expired") {
      fail("Live workout closed result is invalid.");
    }
    return Object.freeze({
      ...row,
      roomId: identifier(row.roomId, ROOM_ID, "room id"),
      roomRevision: integer(row.roomRevision, 1, LIMITS.revisionMax, "room revision"),
      endedAt: timestamp(row.endedAt)
    });
  }

  function respondResult(value) {
    if (value?.result === "closed") return closedResult(value);
    const joined = value?.result === "joined";
    const required = joined
      ? ["version", "result", "roomId", "status", "roomRevision", "membershipRevision"]
      : [
          "version", "result", "roomId", "status", "roomRevision", "membershipRevision", "endedAt"
        ];
    const row = exactObject(value, required);
    if (row.version !== VERSION || !["joined", "declined"].includes(row.result) ||
        (joined ? !["ready", "active"].includes(row.status) : row.status !== "cancelled")) {
      fail("Live workout response result is invalid.");
    }
    return Object.freeze({
      ...row,
      roomId: identifier(row.roomId, ROOM_ID, "room id"),
      roomRevision: integer(row.roomRevision, 1, LIMITS.revisionMax, "room revision"),
      membershipRevision: integer(
        row.membershipRevision,
        1,
        LIMITS.revisionMax,
        "membership revision"
      ),
      ...(joined ? {} : { endedAt: timestamp(row.endedAt) })
    });
  }

  function startResult(value) {
    if (value?.result === "closed") return closedResult(value);
    const row = exactObject(value, [
      "version", "result", "roomId", "status", "roomRevision", "startedAt",
      "activeExpiresAt", "myProgressRevision"
    ]);
    const startedAt = timestamp(row.startedAt);
    const activeExpiresAt = timestamp(row.activeExpiresAt);
    if (row.version !== VERSION || row.result !== "started" || row.status !== "active" ||
        Date.parse(activeExpiresAt) <= Date.parse(startedAt)) {
      fail("Live workout start result is invalid.");
    }
    return Object.freeze({
      ...row,
      roomId: identifier(row.roomId, ROOM_ID, "room id"),
      roomRevision: integer(row.roomRevision, 1, LIMITS.revisionMax, "room revision"),
      startedAt,
      activeExpiresAt,
      myProgressRevision: integer(
        row.myProgressRevision,
        1,
        LIMITS.revisionMax,
        "progress revision"
      )
    });
  }

  function applyResult(value) {
    if (value?.result === "closed") return closedResult(value);
    const row = exactObject(value, [
      "version", "result", "roomId", "roomRevision", "progressRevision", "kind",
      "setId", "completedAt"
    ]);
    if (row.version !== VERSION || row.result !== "applied" ||
        !["complete_set", "undo_set"].includes(row.kind) ||
        (row.kind === "complete_set") !== (row.completedAt !== null)) {
      fail("Live workout apply result is invalid.");
    }
    return Object.freeze({
      ...row,
      roomId: identifier(row.roomId, ROOM_ID, "room id"),
      roomRevision: integer(row.roomRevision, 1, LIMITS.revisionMax, "room revision"),
      progressRevision: integer(row.progressRevision, 1, LIMITS.revisionMax, "progress revision"),
      setId: identifier(row.setId, SET_ID, "set id"),
      completedAt: timestamp(row.completedAt, true)
    });
  }

  function finishResult(value) {
    if (value?.result === "closed") return closedResult(value);
    const row = exactObject(value, [
      "version", "result", "roomId", "status", "roomRevision", "progressRevision",
      "membershipRevision", "finishedAt"
    ]);
    if (row.version !== VERSION || row.result !== "finished" ||
        !["active", "completed"].includes(row.status)) {
      fail("Live workout finish result is invalid.");
    }
    return Object.freeze({
      ...row,
      roomId: identifier(row.roomId, ROOM_ID, "room id"),
      roomRevision: integer(row.roomRevision, 1, LIMITS.revisionMax, "room revision"),
      progressRevision: integer(row.progressRevision, 1, LIMITS.revisionMax, "progress revision"),
      membershipRevision: integer(
        row.membershipRevision,
        1,
        LIMITS.revisionMax,
        "membership revision"
      ),
      finishedAt: timestamp(row.finishedAt)
    });
  }

  function terminalResult(value, expectedResult) {
    if (value?.result === "closed") return closedResult(value);
    const row = exactObject(value, [
      "version", "result", "roomId", "status", "roomRevision", "membershipRevision", "endedAt"
    ]);
    if (row.version !== VERSION || row.result !== expectedResult || row.status !== "cancelled") {
      fail("Live workout terminal result is invalid.");
    }
    return Object.freeze({
      ...row,
      roomId: identifier(row.roomId, ROOM_ID, "room id"),
      roomRevision: integer(row.roomRevision, 1, LIMITS.revisionMax, "room revision"),
      membershipRevision: integer(
        row.membershipRevision,
        1,
        LIMITS.revisionMax,
        "membership revision"
      ),
      endedAt: timestamp(row.endedAt)
    });
  }

  function realtimeEvent(value) {
    const row = exactObject(value, ["version", "kind", "roomId", "roomRevision"]);
    if (row.version !== VERSION || ![
      "invite", "joined", "started", "progress", "participant_finished", "room_closed"
    ].includes(row.kind)) {
      fail("Live workout realtime event is invalid.");
    }
    return Object.freeze({
      version: VERSION,
      kind: row.kind,
      roomId: identifier(row.roomId, ROOM_ID, "room id"),
      roomRevision: integer(row.roomRevision, 1, LIMITS.revisionMax, "room revision")
    });
  }

  return Object.freeze({
    VERSION,
    LIMITS,
    patterns: Object.freeze({ ROOM_ID, PROFILE_ID, EXERCISE_ID, SET_ID, CATALOG_KEY }),
    exactObject,
    plan,
    summary,
    progress,
    room,
    snapshot,
    inbox,
    sharedPlan,
    sendResult,
    respondResult,
    startResult,
    applyResult,
    finishResult,
    leaveResult: value => terminalResult(value, "left"),
    cancelResult: value => terminalResult(value, "cancelled"),
    realtimeEvent
  });
});
