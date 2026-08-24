begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

-- Activity-only Garmin workouts cannot live in the strict schema-v2 user_state:
-- released clients either discard an empty workout or reject it once the local
-- duration extension has been stripped. Keep the complete owner-private
-- snapshot beside that legacy envelope. The pre-existing workout-duration RPC
-- intentionally remains untouched so mixed-version clients cannot erase it.
do $preflight$
begin
  if pg_catalog.to_regclass(
       'gymapp_private.workout_duration_sync_budgets'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.consume_workout_duration_sync_budget(uuid,numeric)'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.current_auth_session_is_live()'
     ) is null
     or pg_catalog.to_regprocedure(
       'extensions.digest(bytea,text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.social_sync_workout_durations(jsonb)'
     ) is null then
    raise exception 'GymApp activity-only workout synchronization prerequisites are missing.';
  end if;
end
$preflight$;

create table gymapp_private.activity_only_workout_sync_states (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 0,
  last_request_id uuid,
  last_expected_revision bigint,
  last_payload_digest bytea,
  last_synced_count integer,
  last_changed_count integer,
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint activity_only_workout_sync_revision_range check (
    revision between 0 and 9007199254740991
  ),
  constraint activity_only_workout_sync_replay_shape check (
    (
      last_request_id is null
      and last_expected_revision is null
      and last_payload_digest is null
      and last_synced_count is null
      and last_changed_count is null
    )
    or
    (
      last_request_id is not null
      and last_expected_revision between 0 and 9007199254740991
      and pg_catalog.octet_length(last_payload_digest) = 32
      and last_synced_count between 0 and 5000
      and last_changed_count between 0 and 10000
    )
  )
);

create table gymapp_private.activity_only_workouts (
  user_id uuid not null references
    gymapp_private.activity_only_workout_sync_states(user_id)
    on delete cascade,
  workout_started_at_millis bigint not null,
  duration_seconds integer not null,
  gym_calories numeric(9, 3) not null,
  garmin_calories integer,
  average_heart_rate smallint,
  maximum_heart_rate smallint,
  ending_heart_rate_zone smallint,
  note text,
  primary key (user_id, workout_started_at_millis),
  constraint activity_only_workouts_started_at_range check (
    workout_started_at_millis between -62135769600000 and 64092211200000
  ),
  constraint activity_only_workouts_duration_range check (
    duration_seconds between 1 and 604800
  ),
  constraint activity_only_workouts_gym_calories_range check (
    gym_calories between 0 and 100000
  ),
  constraint activity_only_workouts_garmin_calories_range check (
    garmin_calories is null or garmin_calories between 0 and 100000
  ),
  constraint activity_only_workouts_average_hr_range check (
    average_heart_rate is null or average_heart_rate between 0 and 240
  ),
  constraint activity_only_workouts_maximum_hr_range check (
    maximum_heart_rate is null or maximum_heart_rate between 0 and 240
  ),
  constraint activity_only_workouts_hr_order check (
    average_heart_rate is null
    or maximum_heart_rate is null
    or average_heart_rate <= maximum_heart_rate
  ),
  constraint activity_only_workouts_zone_range check (
    ending_heart_rate_zone is null or ending_heart_rate_zone between 0 and 5
  ),
  constraint activity_only_workouts_note_range check (
    note is null
    or (
      pg_catalog.char_length(note) <= 512
      and pg_catalog.octet_length(pg_catalog.convert_to(note, 'UTF8')) <= 2048
    )
  )
);

alter table gymapp_private.activity_only_workout_sync_states
  enable row level security;
alter table gymapp_private.activity_only_workout_sync_states
  force row level security;
alter table gymapp_private.activity_only_workouts
  enable row level security;
alter table gymapp_private.activity_only_workouts
  force row level security;

revoke all on table gymapp_private.activity_only_workout_sync_states
  from public, anon, authenticated, service_role;
revoke all on table gymapp_private.activity_only_workouts
  from public, anon, authenticated, service_role;

create function public.garmin_read_activity_only_workouts()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set statement_timeout = '8s'
as $function$
declare
  caller_user_id uuid := auth.uid();
  current_revision bigint := 0;
  result_items jsonb := '[]'::jsonb;
begin
  if caller_user_id is null
     or not gymapp_private.current_auth_session_is_live() then
    raise exception using
      errcode = '42501',
      message = 'A live authenticated session is required.';
  end if;

  -- Revision and items must share one READ COMMITTED statement snapshot. Two
  -- separate SELECTs could otherwise straddle a concurrent CAS commit and make
  -- a valid client perform an avoidable conflict/re-read cycle.
  select
    coalesce(state.revision, 0),
    coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_strip_nulls(
          pg_catalog.jsonb_build_object(
            'workoutStartedAt', workout.workout_started_at_millis,
            'durationSeconds', workout.duration_seconds,
            'gymCalories', workout.gym_calories,
            'garminCalories', workout.garmin_calories,
            'averageHeartRate', workout.average_heart_rate,
            'maximumHeartRate', workout.maximum_heart_rate,
            'endingHeartRateZone', workout.ending_heart_rate_zone,
            'note', workout.note
          )
        )
        order by workout.workout_started_at_millis
      ) filter (where workout.workout_started_at_millis is not null),
      '[]'::jsonb
    )
  into current_revision, result_items
  from (
    select caller_user_id as user_id
  ) as caller
  left join gymapp_private.activity_only_workout_sync_states as state
    on state.user_id = caller.user_id
  left join gymapp_private.activity_only_workouts as workout
    on workout.user_id = caller.user_id
  group by state.revision;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'revision', current_revision,
    'items', result_items
  );
end
$function$;

create function public.garmin_sync_activity_only_workouts(
  p_expected_revision bigint,
  p_request_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set statement_timeout = '8s'
set lock_timeout = '2s'
as $function$
declare
  caller_user_id uuid := auth.uid();
  item_value jsonb;
  item_count integer := 0;
  payload_bytes integer := coalesce(pg_catalog.pg_column_size(p_items), 0);
  payload_digest bytea;
  request_cost numeric;
  retry_after integer;
  current_revision bigint := 0;
  last_request_id uuid;
  last_expected_revision bigint;
  last_payload_digest bytea;
  last_synced_count integer;
  last_changed_count integer;
  started_at_value numeric;
  previous_started_at_value numeric := null;
  duration_value numeric;
  gym_calories_value numeric;
  optional_numeric_value numeric;
  average_heart_rate_value integer;
  maximum_heart_rate_value integer;
  deleted_count integer := 0;
  upserted_count integer := 0;
  changed_count integer := 0;
  next_revision bigint;
begin
  if caller_user_id is null
     or not gymapp_private.current_auth_session_is_live() then
    raise exception using
      errcode = '42501',
      message = 'A live authenticated session is required.';
  end if;

  if pg_catalog.jsonb_typeof(p_items) = 'array' then
    item_count := pg_catalog.jsonb_array_length(p_items);
  end if;

  -- Debit the durable owner bucket before accepting or rejecting the public
  -- body. Oversized and malformed authenticated requests must not get a free
  -- database-CPU path. Exact replays still pay for their bounded validation.
  request_cost := greatest(
    1,
    1 + pg_catalog.ceil(item_count::numeric / 25)
      + pg_catalog.ceil(payload_bytes::numeric / 4096)
  );
  retry_after := gymapp_private.consume_workout_duration_sync_budget(
    caller_user_id,
    least(request_cost, 600)
  );
  if retry_after > 0 then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'status', 'rate_limited',
      'retryAfter', retry_after
    );
  end if;

  if p_expected_revision is null
     or p_expected_revision < 0
     or p_expected_revision > 9007199254740991
     or p_request_id is null
     or pg_catalog.jsonb_typeof(p_items) is distinct from 'array'
     or payload_bytes > 1048576
     or item_count > 5000 then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'status', 'invalid_payload'
    );
  end if;

  for item_value in
    select entry.value
    from pg_catalog.jsonb_array_elements(p_items) as entry(value)
  loop
    if pg_catalog.jsonb_typeof(item_value) is distinct from 'object'
       or not item_value ?& array[
         'workoutStartedAt', 'durationSeconds', 'gymCalories'
       ]
       or exists (
         select 1
         from pg_catalog.jsonb_object_keys(item_value) as item_key(value)
         where item_key.value <> all(array[
           'workoutStartedAt', 'durationSeconds', 'gymCalories',
           'garminCalories', 'averageHeartRate', 'maximumHeartRate',
           'endingHeartRateZone', 'note'
         ])
       )
       or pg_catalog.jsonb_typeof(
         item_value->'workoutStartedAt'
       ) is distinct from 'number'
       or pg_catalog.jsonb_typeof(
         item_value->'durationSeconds'
       ) is distinct from 'number'
       or pg_catalog.jsonb_typeof(
         item_value->'gymCalories'
       ) is distinct from 'number' then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'status', 'invalid_payload'
      );
    end if;

    if (item_value ? 'garminCalories'
        and item_value->'garminCalories' <> 'null'::jsonb
        and pg_catalog.jsonb_typeof(
          item_value->'garminCalories'
        ) is distinct from 'number')
       or (item_value ? 'averageHeartRate'
        and item_value->'averageHeartRate' <> 'null'::jsonb
        and pg_catalog.jsonb_typeof(
          item_value->'averageHeartRate'
        ) is distinct from 'number')
       or (item_value ? 'maximumHeartRate'
        and item_value->'maximumHeartRate' <> 'null'::jsonb
        and pg_catalog.jsonb_typeof(
          item_value->'maximumHeartRate'
        ) is distinct from 'number')
       or (item_value ? 'endingHeartRateZone'
        and item_value->'endingHeartRateZone' <> 'null'::jsonb
        and pg_catalog.jsonb_typeof(
          item_value->'endingHeartRateZone'
        ) is distinct from 'number')
       or (item_value ? 'note'
        and item_value->'note' <> 'null'::jsonb
        and pg_catalog.jsonb_typeof(
          item_value->'note'
        ) is distinct from 'string') then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'status', 'invalid_payload'
      );
    end if;

    started_at_value := (item_value->'workoutStartedAt')::numeric;
    if started_at_value < -62135769600000
       or started_at_value > 64092211200000 then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'status', 'invalid_payload'
      );
    end if;
    if started_at_value <> pg_catalog.trunc(started_at_value) then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'status', 'invalid_payload'
      );
    end if;
    if previous_started_at_value is not null
       and started_at_value <= previous_started_at_value then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'status', 'invalid_payload'
      );
    end if;
    previous_started_at_value := started_at_value;

    duration_value := (item_value->'durationSeconds')::numeric;
    if duration_value < 1 or duration_value > 604800 then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'status', 'invalid_payload'
      );
    end if;
    if duration_value <> pg_catalog.trunc(duration_value) then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'status', 'invalid_payload'
      );
    end if;

    gym_calories_value := (item_value->'gymCalories')::numeric;
    if gym_calories_value < 0 or gym_calories_value > 100000 then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'status', 'invalid_payload'
      );
    end if;
    if gym_calories_value * 1000 <>
       pg_catalog.trunc(gym_calories_value * 1000) then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'status', 'invalid_payload'
      );
    end if;

    if item_value ? 'garminCalories'
       and item_value->'garminCalories' <> 'null'::jsonb then
      optional_numeric_value := (item_value->'garminCalories')::numeric;
      if optional_numeric_value < 0 or optional_numeric_value > 100000 then
        return pg_catalog.jsonb_build_object(
          'version', 1,
          'status', 'invalid_payload'
        );
      end if;
      if optional_numeric_value <> pg_catalog.trunc(optional_numeric_value) then
        return pg_catalog.jsonb_build_object(
          'version', 1,
          'status', 'invalid_payload'
        );
      end if;
    end if;

    average_heart_rate_value := null;
    if item_value ? 'averageHeartRate'
       and item_value->'averageHeartRate' <> 'null'::jsonb then
      optional_numeric_value := (item_value->'averageHeartRate')::numeric;
      if optional_numeric_value < 0 or optional_numeric_value > 240 then
        return pg_catalog.jsonb_build_object(
          'version', 1,
          'status', 'invalid_payload'
        );
      end if;
      if optional_numeric_value <> pg_catalog.trunc(optional_numeric_value) then
        return pg_catalog.jsonb_build_object(
          'version', 1,
          'status', 'invalid_payload'
        );
      end if;
      average_heart_rate_value := optional_numeric_value::integer;
    end if;

    maximum_heart_rate_value := null;
    if item_value ? 'maximumHeartRate'
       and item_value->'maximumHeartRate' <> 'null'::jsonb then
      optional_numeric_value := (item_value->'maximumHeartRate')::numeric;
      if optional_numeric_value < 0 or optional_numeric_value > 240 then
        return pg_catalog.jsonb_build_object(
          'version', 1,
          'status', 'invalid_payload'
        );
      end if;
      if optional_numeric_value <> pg_catalog.trunc(optional_numeric_value) then
        return pg_catalog.jsonb_build_object(
          'version', 1,
          'status', 'invalid_payload'
        );
      end if;
      maximum_heart_rate_value := optional_numeric_value::integer;
    end if;
    if average_heart_rate_value is not null
       and maximum_heart_rate_value is not null
       and average_heart_rate_value > maximum_heart_rate_value then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'status', 'invalid_payload'
      );
    end if;

    if item_value ? 'endingHeartRateZone'
       and item_value->'endingHeartRateZone' <> 'null'::jsonb then
      optional_numeric_value := (item_value->'endingHeartRateZone')::numeric;
      if optional_numeric_value < 0 or optional_numeric_value > 5 then
        return pg_catalog.jsonb_build_object(
          'version', 1,
          'status', 'invalid_payload'
        );
      end if;
      if optional_numeric_value <> pg_catalog.trunc(optional_numeric_value) then
        return pg_catalog.jsonb_build_object(
          'version', 1,
          'status', 'invalid_payload'
        );
      end if;
    end if;

    if item_value ? 'note' and item_value->'note' <> 'null'::jsonb
       and (
         pg_catalog.char_length(item_value->>'note') > 512
         or pg_catalog.octet_length(
           pg_catalog.convert_to(item_value->>'note', 'UTF8')
         ) > 2048
       ) then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'status', 'invalid_payload'
      );
    end if;
  end loop;

  payload_digest := extensions.digest(
    pg_catalog.convert_to(p_items::text, 'UTF8'),
    'sha256'
  );

  -- One owner has exactly one CAS sequence. The lock is taken only after the
  -- byte/count/type validation above, so malformed input cannot hold it while
  -- PostgreSQL expands attacker-selected structures.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'gymapp-activity-only-workout-sync:' || caller_user_id::text,
      0
    )
  );

  select
    state.revision,
    state.last_request_id,
    state.last_expected_revision,
    state.last_payload_digest,
    state.last_synced_count,
    state.last_changed_count
  into
    current_revision,
    last_request_id,
    last_expected_revision,
    last_payload_digest,
    last_synced_count,
    last_changed_count
  from gymapp_private.activity_only_workout_sync_states as state
  where state.user_id = caller_user_id
  for update;
  if not found then
    current_revision := 0;
    last_request_id := null;
  end if;

  if last_request_id = p_request_id then
    if last_expected_revision = p_expected_revision
       and last_payload_digest = payload_digest then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'status', 'synced',
        'revision', current_revision,
        'syncedCount', last_synced_count,
        'changedCount', last_changed_count,
        'replayed', true
      );
    end if;
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'status', 'request_conflict',
      'revision', current_revision
    );
  end if;

  if p_expected_revision <> current_revision then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'status', 'conflict',
      'revision', current_revision
    );
  end if;
  if current_revision = 9007199254740991 then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'status', 'revision_exhausted',
      'revision', current_revision
    );
  end if;

  insert into gymapp_private.activity_only_workout_sync_states (
    user_id, revision
  ) values (
    caller_user_id, current_revision
  ) on conflict (user_id) do nothing;

  delete from gymapp_private.activity_only_workouts as workout
  where workout.user_id = caller_user_id
    and not exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_items) as item(value)
      where (item.value->'workoutStartedAt')::bigint =
        workout.workout_started_at_millis
    );
  get diagnostics deleted_count = row_count;

  insert into gymapp_private.activity_only_workouts (
    user_id,
    workout_started_at_millis,
    duration_seconds,
    gym_calories,
    garmin_calories,
    average_heart_rate,
    maximum_heart_rate,
    ending_heart_rate_zone,
    note
  )
  select
    caller_user_id,
    (item.value->'workoutStartedAt')::bigint,
    (item.value->'durationSeconds')::integer,
    (item.value->'gymCalories')::numeric,
    case
      when item.value->'garminCalories' is null
        or item.value->'garminCalories' = 'null'::jsonb then null
      else (item.value->'garminCalories')::integer
    end,
    case
      when item.value->'averageHeartRate' is null
        or item.value->'averageHeartRate' = 'null'::jsonb then null
      else (item.value->'averageHeartRate')::smallint
    end,
    case
      when item.value->'maximumHeartRate' is null
        or item.value->'maximumHeartRate' = 'null'::jsonb then null
      else (item.value->'maximumHeartRate')::smallint
    end,
    case
      when item.value->'endingHeartRateZone' is null
        or item.value->'endingHeartRateZone' = 'null'::jsonb then null
      else (item.value->'endingHeartRateZone')::smallint
    end,
    case
      when item.value->'note' is null
        or item.value->'note' = 'null'::jsonb then null
      else item.value->>'note'
    end
  from pg_catalog.jsonb_array_elements(p_items) as item(value)
  on conflict (user_id, workout_started_at_millis) do update
  set duration_seconds = excluded.duration_seconds,
      gym_calories = excluded.gym_calories,
      garmin_calories = excluded.garmin_calories,
      average_heart_rate = excluded.average_heart_rate,
      maximum_heart_rate = excluded.maximum_heart_rate,
      ending_heart_rate_zone = excluded.ending_heart_rate_zone,
      note = excluded.note
  where (
    gymapp_private.activity_only_workouts.duration_seconds,
    gymapp_private.activity_only_workouts.gym_calories,
    gymapp_private.activity_only_workouts.garmin_calories,
    gymapp_private.activity_only_workouts.average_heart_rate,
    gymapp_private.activity_only_workouts.maximum_heart_rate,
    gymapp_private.activity_only_workouts.ending_heart_rate_zone,
    gymapp_private.activity_only_workouts.note
  ) is distinct from (
    excluded.duration_seconds,
    excluded.gym_calories,
    excluded.garmin_calories,
    excluded.average_heart_rate,
    excluded.maximum_heart_rate,
    excluded.ending_heart_rate_zone,
    excluded.note
  );
  get diagnostics upserted_count = row_count;

  changed_count := deleted_count + upserted_count;
  next_revision := current_revision + case when changed_count > 0 then 1 else 0 end;

  update gymapp_private.activity_only_workout_sync_states as state
  set revision = next_revision,
      last_request_id = p_request_id,
      last_expected_revision = p_expected_revision,
      last_payload_digest = payload_digest,
      last_synced_count = item_count,
      last_changed_count = changed_count,
      updated_at = pg_catalog.clock_timestamp()
  where state.user_id = caller_user_id;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'status', 'synced',
    'revision', next_revision,
    'syncedCount', item_count,
    'changedCount', changed_count,
    'replayed', false
  );
end
$function$;

revoke all on function public.garmin_read_activity_only_workouts()
  from public, anon, authenticated, service_role;
grant execute on function public.garmin_read_activity_only_workouts()
  to authenticated;

revoke all on function public.garmin_sync_activity_only_workouts(
  bigint, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.garmin_sync_activity_only_workouts(
  bigint, uuid, jsonb
) to authenticated;

comment on table gymapp_private.activity_only_workouts is
  'Owner-private activity-only Garmin summaries kept outside the strict schema-v2 user_state.';
comment on function public.garmin_read_activity_only_workouts() is
  'Reads the live authenticated owner activity-only workout CAS snapshot.';
comment on function public.garmin_sync_activity_only_workouts(bigint, uuid, jsonb) is
  'Atomically CAS-replaces the live authenticated owner activity-only workout snapshot with exact request replay.';

do $verify$
declare
  old_duration_definition text;
begin
  old_duration_definition := pg_catalog.pg_get_functiondef(
    'public.social_sync_workout_durations(jsonb)'::pg_catalog.regprocedure
  );

  if not (
       select table_value.relrowsecurity and table_value.relforcerowsecurity
       from pg_catalog.pg_class as table_value
       where table_value.oid =
         'gymapp_private.activity_only_workouts'::pg_catalog.regclass
     )
     or not (
       select table_value.relrowsecurity and table_value.relforcerowsecurity
       from pg_catalog.pg_class as table_value
       where table_value.oid =
         'gymapp_private.activity_only_workout_sync_states'::pg_catalog.regclass
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'gymapp_private.activity_only_workouts', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'gymapp_private.activity_only_workouts', 'INSERT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated',
       'gymapp_private.activity_only_workout_sync_states',
       'SELECT'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'public.garmin_read_activity_only_workouts()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.garmin_sync_activity_only_workouts(bigint,uuid,jsonb)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.garmin_read_activity_only_workouts()',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.garmin_sync_activity_only_workouts(bigint,uuid,jsonb)',
       'EXECUTE'
     )
     or old_duration_definition like '%activity_only_workout%' then
    raise exception 'GymApp activity-only workout security contract is invalid.';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
