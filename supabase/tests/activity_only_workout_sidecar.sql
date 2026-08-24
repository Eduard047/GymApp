begin;

select plan(54);

select has_table(
  'gymapp_private',
  'activity_only_workout_sync_states',
  'activity-only CAS state is private'
);
select has_table(
  'gymapp_private',
  'activity_only_workouts',
  'activity-only workout rows are private'
);
select has_function(
  'public',
  'garmin_read_activity_only_workouts',
  array[]::text[],
  'owner read RPC exists'
);
select has_function(
  'public',
  'garmin_sync_activity_only_workouts',
  array['bigint', 'uuid', 'jsonb'],
  'owner CAS sync RPC exists'
);
select ok(
  (select table_value.relrowsecurity and table_value.relforcerowsecurity
   from pg_catalog.pg_class as table_value
   where table_value.oid =
     'gymapp_private.activity_only_workouts'::pg_catalog.regclass),
  'activity-only rows enable and force RLS'
);
select ok(
  (select table_value.relrowsecurity and table_value.relforcerowsecurity
   from pg_catalog.pg_class as table_value
   where table_value.oid =
     'gymapp_private.activity_only_workout_sync_states'::pg_catalog.regclass),
  'activity-only CAS state enables and forces RLS'
);
select ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'gymapp_private.activity_only_workouts', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'gymapp_private.activity_only_workouts', 'INSERT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'gymapp_private.activity_only_workouts', 'UPDATE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'gymapp_private.activity_only_workouts', 'DELETE'
  ),
  'authenticated clients have no direct activity-row privileges'
);
select ok(
  not pg_catalog.has_table_privilege(
    'authenticated',
    'gymapp_private.activity_only_workout_sync_states',
    'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'gymapp_private.activity_only_workout_sync_states',
    'INSERT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'gymapp_private.activity_only_workout_sync_states',
    'UPDATE'
  ),
  'authenticated clients have no direct replay-state privileges'
);
select ok(
  not pg_catalog.has_function_privilege(
    'anon', 'public.garmin_read_activity_only_workouts()', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.garmin_sync_activity_only_workouts(bigint,uuid,jsonb)',
    'EXECUTE'
  ),
  'anonymous clients cannot call either RPC'
);
select ok(
  pg_catalog.has_function_privilege(
    'authenticated', 'public.garmin_read_activity_only_workouts()', 'EXECUTE'
  )
  and pg_catalog.has_function_privilege(
    'authenticated',
    'public.garmin_sync_activity_only_workouts(bigint,uuid,jsonb)',
    'EXECUTE'
  ),
  'authenticated clients can call only the owner-bound RPCs'
);
select ok(
  (select procedure.prosecdef
   from pg_catalog.pg_proc as procedure
   where procedure.oid =
     'public.garmin_read_activity_only_workouts()'::pg_catalog.regprocedure)
  and
  (select procedure.prosecdef
   from pg_catalog.pg_proc as procedure
   where procedure.oid =
     'public.garmin_sync_activity_only_workouts(bigint,uuid,jsonb)'::pg_catalog.regprocedure),
  'both public RPCs are security definer'
);
select ok(
  (select 'search_path=""' = any(procedure.proconfig)
   from pg_catalog.pg_proc as procedure
   where procedure.oid =
     'public.garmin_read_activity_only_workouts()'::pg_catalog.regprocedure)
  and
  (select 'search_path=""' = any(procedure.proconfig)
   from pg_catalog.pg_proc as procedure
   where procedure.oid =
     'public.garmin_sync_activity_only_workouts(bigint,uuid,jsonb)'::pg_catalog.regprocedure),
  'both security-definer RPCs have an empty fixed search_path'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'public.social_sync_workout_durations(jsonb)'::pg_catalog.regprocedure
  ) not like '%activity_only_workout%',
  'the released duration RPC cannot delete the activity-only sidecar'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    'a4000000-0000-4000-8000-000000000001',
    'authenticated', 'authenticated', 'activity-owner-a@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a4000000-0000-4000-8000-000000000002',
    'authenticated', 'authenticated', 'activity-owner-b@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a4000000-0000-4000-8000-000000000003',
    'authenticated', 'authenticated', 'activity-expired@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

insert into auth.sessions (id, user_id, not_after, created_at, updated_at) values
  (
    'b4000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000001',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'b4000000-0000-4000-8000-000000000002',
    'a4000000-0000-4000-8000-000000000002',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'b4000000-0000-4000-8000-000000000003',
    'a4000000-0000-4000-8000-000000000003',
    pg_catalog.clock_timestamp() - interval '1 minute',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

create temporary table activity_only_sync_results (
  case_name text primary key,
  payload jsonb not null
) on commit drop;

set local request.jwt.claim.sub = 'a4000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b4000000-0000-4000-8000-000000000001"}';

select is(
  public.garmin_read_activity_only_workouts()->>'version',
  '1',
  'an empty owner snapshot uses contract version one'
);
select is(
  public.garmin_read_activity_only_workouts()->>'revision',
  '0',
  'an owner without a snapshot starts at revision zero'
);
select is(
  public.garmin_read_activity_only_workouts()->'items',
  '[]'::jsonb,
  'an owner without a snapshot reads no rows'
);

insert into activity_only_sync_results values (
  'first',
  public.garmin_sync_activity_only_workouts(
    0,
    'c4000000-0000-4000-8000-000000000001',
    '[
      {
        "workoutStartedAt": 1700000000000,
        "durationSeconds": 900,
        "gymCalories": 42.125,
        "garminCalories": 44,
        "averageHeartRate": 118,
        "maximumHeartRate": 151,
        "endingHeartRateZone": 3,
        "note": "Free Garmin workout"
      },
      {
        "workoutStartedAt": 1700003600000,
        "durationSeconds": 600,
        "gymCalories": 30
      }
    ]'::jsonb
  )
);

select is(
  (select payload->>'status' from activity_only_sync_results where case_name = 'first'),
  'synced',
  'the first valid owner snapshot is committed'
);
select is(
  (select (payload->>'revision')::bigint
   from activity_only_sync_results where case_name = 'first'),
  1::bigint,
  'the first content change advances the CAS revision'
);
select is(
  (select (payload->>'syncedCount')::integer
   from activity_only_sync_results where case_name = 'first'),
  2,
  'the first response reports its full snapshot count'
);
select is(
  (select (payload->>'changedCount')::integer
   from activity_only_sync_results where case_name = 'first'),
  2,
  'the first response reports both inserted rows'
);
select is(
  (select (payload->>'replayed')::boolean
   from activity_only_sync_results where case_name = 'first'),
  false,
  'the first response is not marked as a replay'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.activity_only_workouts
   where user_id = 'a4000000-0000-4000-8000-000000000001'),
  2::bigint,
  'the owner stores exactly the supplied two rows'
);
select is(
  public.garmin_read_activity_only_workouts()->'items'->0->>'workoutStartedAt',
  '1700000000000',
  'owner reads are deterministically ordered by workout timestamp'
);
select is(
  public.garmin_read_activity_only_workouts()
    #>> '{items,0,maximumHeartRate}',
  '151',
  'the owner reads the bounded structured Garmin metrics'
);
select ok(
  not (
    public.garmin_read_activity_only_workouts()->'items'->1 ? 'note'
  ),
  'null optional fields are omitted from the response wire'
);

insert into activity_only_sync_results values (
  'replay',
  public.garmin_sync_activity_only_workouts(
    0,
    'c4000000-0000-4000-8000-000000000001',
    '[
      {
        "workoutStartedAt": 1700000000000,
        "durationSeconds": 900,
        "gymCalories": 42.125,
        "garminCalories": 44,
        "averageHeartRate": 118,
        "maximumHeartRate": 151,
        "endingHeartRateZone": 3,
        "note": "Free Garmin workout"
      },
      {
        "workoutStartedAt": 1700003600000,
        "durationSeconds": 600,
        "gymCalories": 30
      }
    ]'::jsonb
  )
);
select is(
  (select payload->>'status' from activity_only_sync_results where case_name = 'replay'),
  'synced',
  'an exact request replay returns the successful result'
);
select is(
  (select (payload->>'replayed')::boolean
   from activity_only_sync_results where case_name = 'replay'),
  true,
  'an exact request replay is explicit'
);
select is(
  (select (payload->>'revision')::bigint
   from activity_only_sync_results where case_name = 'replay'),
  1::bigint,
  'an exact request replay does not advance the revision'
);

insert into activity_only_sync_results values (
  'request-conflict',
  public.garmin_sync_activity_only_workouts(
    0,
    'c4000000-0000-4000-8000-000000000001',
    '[{"workoutStartedAt":1700000000000,"durationSeconds":901,"gymCalories":42.125}]'::jsonb
  )
);
select is(
  (select payload->>'status' from activity_only_sync_results
   where case_name = 'request-conflict'),
  'request_conflict',
  'a request ID cannot be replayed with a changed snapshot'
);
select is(
  (select revision
   from gymapp_private.activity_only_workout_sync_states
   where user_id = 'a4000000-0000-4000-8000-000000000001'),
  1::bigint,
  'a changed-payload replay has no revision side effect'
);

insert into activity_only_sync_results values (
  'stale',
  public.garmin_sync_activity_only_workouts(
    0,
    'c4000000-0000-4000-8000-000000000002',
    '[{"workoutStartedAt":1700000000000,"durationSeconds":901,"gymCalories":42.125}]'::jsonb
  )
);
select is(
  (select payload->>'status' from activity_only_sync_results where case_name = 'stale'),
  'conflict',
  'a stale device snapshot fails its CAS instead of overwriting newer data'
);
select is(
  (select payload->>'revision' from activity_only_sync_results where case_name = 'stale'),
  '1',
  'a stale client receives the current revision for read-merge-retry'
);

select is(
  public.garmin_sync_activity_only_workouts(
    1,
    'c4000000-0000-4000-8000-000000000003',
    '[{"workoutStartedAt":1700000000000,"durationSeconds":900,"gymCalories":42,"unknown":true}]'::jsonb
  )->>'status',
  'invalid_payload',
  'unknown item keys fail closed'
);
select is(
  public.garmin_sync_activity_only_workouts(
    1,
    'c4000000-0000-4000-8000-000000000004',
    '[
      {"workoutStartedAt":1700003600000,"durationSeconds":600,"gymCalories":30},
      {"workoutStartedAt":1700000000000,"durationSeconds":900,"gymCalories":42}
    ]'::jsonb
  )->>'status',
  'invalid_payload',
  'snapshots must be unique and strictly timestamp-ordered'
);
select is(
  public.garmin_sync_activity_only_workouts(
    1,
    'c4000000-0000-4000-8000-000000000005',
    '[{"workoutStartedAt":1700000000000,"durationSeconds":900,"gymCalories":42,"averageHeartRate":170,"maximumHeartRate":150}]'::jsonb
  )->>'status',
  'invalid_payload',
  'average heart rate cannot exceed maximum heart rate'
);
select is(
  public.garmin_sync_activity_only_workouts(
    1,
    'c4000000-0000-4000-8000-000000000006',
    '[{"workoutStartedAt":1700000000000,"durationSeconds":900,"gymCalories":1.2345}]'::jsonb
  )->>'status',
  'invalid_payload',
  'calories are bounded to three decimal places'
);
select is(
  (select revision
   from gymapp_private.activity_only_workout_sync_states
   where user_id = 'a4000000-0000-4000-8000-000000000001'),
  1::bigint,
  'invalid snapshots leave the prior CAS state unchanged'
);

insert into activity_only_sync_results values (
  'replace',
  public.garmin_sync_activity_only_workouts(
    1,
    'c4000000-0000-4000-8000-000000000007',
    '[{"workoutStartedAt":1700000000000,"durationSeconds":1000,"gymCalories":45,"garminCalories":47}]'::jsonb
  )
);
select is(
  (select payload->>'status' from activity_only_sync_results where case_name = 'replace'),
  'synced',
  'a current revision atomically replaces the owner snapshot'
);
select is(
  (select (payload->>'changedCount')::integer
   from activity_only_sync_results where case_name = 'replace'),
  2,
  'replacement counts one deleted and one updated row'
);
select is(
  (select (payload->>'revision')::bigint
   from activity_only_sync_results where case_name = 'replace'),
  2::bigint,
  'a changed replacement advances the revision once'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.activity_only_workouts
   where user_id = 'a4000000-0000-4000-8000-000000000001'),
  1::bigint,
  'replacement commits as one complete snapshot'
);

insert into activity_only_sync_results values (
  'no-change',
  public.garmin_sync_activity_only_workouts(
    2,
    'c4000000-0000-4000-8000-000000000008',
    '[{"workoutStartedAt":1700000000000,"durationSeconds":1000,"gymCalories":45,"garminCalories":47}]'::jsonb
  )
);
select is(
  (select (payload->>'changedCount')::integer
   from activity_only_sync_results where case_name = 'no-change'),
  0,
  'an equal snapshot performs no row rewrite'
);
select is(
  (select (payload->>'revision')::bigint
   from activity_only_sync_results where case_name = 'no-change'),
  2::bigint,
  'an equal snapshot preserves the content revision'
);

select is(
  public.social_sync_workout_durations('[]'::jsonb)->>'version',
  '2',
  'the released mixed-version duration RPC remains callable'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.activity_only_workouts
   where user_id = 'a4000000-0000-4000-8000-000000000001'),
  1::bigint,
  'an old-client duration snapshot cannot erase activity-only rows'
);
select is(
  (select revision
   from gymapp_private.activity_only_workout_sync_states
   where user_id = 'a4000000-0000-4000-8000-000000000001'),
  2::bigint,
  'an old-client duration snapshot cannot advance activity-only CAS state'
);

set local request.jwt.claim.sub = 'a4000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"a4000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"b4000000-0000-4000-8000-000000000002"}';
select is(
  public.garmin_read_activity_only_workouts()->'items',
  '[]'::jsonb,
  'another owner cannot read the first owner snapshot'
);
select is(
  public.garmin_sync_activity_only_workouts(
    0,
    'c4000000-0000-4000-8000-000000000009',
    '[{"workoutStartedAt":1700000000000,"durationSeconds":300,"gymCalories":10}]'::jsonb
  )->>'status',
  'synced',
  'another owner receives an independent CAS sequence'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.activity_only_workouts
   where user_id = 'a4000000-0000-4000-8000-000000000002'),
  1::bigint,
  'another owner writes only its own row'
);

set local request.jwt.claim.sub = 'a4000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b4000000-0000-4000-8000-000000000001"}';
select is(
  public.garmin_read_activity_only_workouts()->'items'->0->>'durationSeconds',
  '1000',
  'switching back restores only the first owner snapshot'
);

set local request.jwt.claim.sub = 'a4000000-0000-4000-8000-000000000003';
set local request.jwt.claims =
  '{"sub":"a4000000-0000-4000-8000-000000000003","role":"authenticated","session_id":"b4000000-0000-4000-8000-000000000003"}';
select throws_ok(
  $$select public.garmin_read_activity_only_workouts()$$,
  '42501',
  'A live authenticated session is required.',
  'an expired exact Auth session cannot read the sidecar'
);
select throws_ok(
  $$
    select public.garmin_sync_activity_only_workouts(
      0,
      'c4000000-0000-4000-8000-000000000010',
      '[]'::jsonb
    )
  $$,
  '42501',
  'A live authenticated session is required.',
  'an expired exact Auth session cannot mutate the sidecar'
);

delete from auth.users
where id = 'a4000000-0000-4000-8000-000000000002';
select is(
  (select pg_catalog.count(*)
   from gymapp_private.activity_only_workout_sync_states
   where user_id = 'a4000000-0000-4000-8000-000000000002'),
  0::bigint,
  'account deletion cascades through activity-only replay state'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.activity_only_workouts
   where user_id = 'a4000000-0000-4000-8000-000000000002'),
  0::bigint,
  'account deletion cascades through activity-only rows'
);

select * from finish();

rollback;
