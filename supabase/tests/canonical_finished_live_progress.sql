begin;

select plan(6);

select ok(
  gymapp_private.live_workout_progress_is_valid(
    '{"version":1,"completedSets":[],"undoableSetId":null,"finishedAt":null}'::jsonb
  ),
  'empty unfinished progress has no undo marker'
);

select ok(
  not gymapp_private.live_workout_progress_is_valid(
    '{"version":1,"completedSets":[],"undoableSetId":"s_01_01","finishedAt":null}'::jsonb
  ),
  'empty progress rejects an undo marker'
);

select ok(
  gymapp_private.live_workout_progress_is_valid(
    '{"version":1,"completedSets":[{"setId":"s_01_01","weight":80,"reps":8,"completedAt":"2026-08-10T09:00:00Z"}],"undoableSetId":"s_01_01","finishedAt":null}'::jsonb
  ),
  'unfinished progress may point at its latest completed set'
);

select ok(
  gymapp_private.live_workout_progress_is_valid(
    '{"version":1,"completedSets":[{"setId":"s_01_01","weight":80,"reps":8,"completedAt":"2026-08-10T09:00:00Z"}],"undoableSetId":null,"finishedAt":null}'::jsonb
  ),
  'server-reconciled unfinished progress may have no undo marker'
);

select ok(
  gymapp_private.live_workout_progress_is_valid(
    '{"version":1,"completedSets":[{"setId":"s_01_01","weight":80,"reps":8,"completedAt":"2026-08-10T09:00:00Z"}],"undoableSetId":null,"finishedAt":"2026-08-10T09:05:00Z"}'::jsonb
  ),
  'finished progress is canonical when its undo marker is cleared'
);

select ok(
  not gymapp_private.live_workout_progress_is_valid(
    '{"version":1,"completedSets":[{"setId":"s_01_01","weight":80,"reps":8,"completedAt":"2026-08-10T09:00:00Z"}],"undoableSetId":"s_01_01","finishedAt":"2026-08-10T09:05:00Z"}'::jsonb
  ),
  'finished progress rejects a retained undo marker'
);

select * from finish();

rollback;
