begin;

-- Forward-only reconciliation for every previously documented GymApp baseline.
-- It never deletes or rewrites user_states rows. States accepted by an older
-- contract but rejected by this stricter boundary are privately quarantined,
-- excluded from the leaderboard, and assigned zero public progression until
-- their owner replaces them with a valid state.
create schema if not exists gymapp_private;
revoke all on schema gymapp_private from public, anon, authenticated;

create table if not exists gymapp_private.user_state_quarantine (
  user_id uuid primary key
    references public.user_states(user_id) on delete cascade,
  validation_error text not null
    check (pg_catalog.char_length(validation_error) between 1 and 200),
  quarantined_at timestamptz not null default pg_catalog.clock_timestamp()
);

comment on table gymapp_private.user_state_quarantine is
  'Private bounded reasons for legacy user_states excluded from public progression; raw owner state remains untouched.';
revoke all on table gymapp_private.user_state_quarantine
  from public, anon, authenticated;

alter table public.profiles
  add column if not exists progression_version integer not null default 1;

do $constraint$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_progression_version_check'
  ) then
    alter table public.profiles
      add constraint profiles_progression_version_check
      check (progression_version = 1);
  end if;
end
$constraint$;

create or replace function gymapp_private.state_name_is_valid(p_value text)
returns boolean
language sql
immutable
strict
security invoker
set search_path = ''
as $function$
  select pg_catalog.char_length(p_value) between 1 and 160
     and pg_catalog.char_length(pg_catalog.btrim(p_value)) between 1 and 160
     and pg_catalog.octet_length(pg_catalog.convert_to(p_value, 'UTF8')) <= 640
$function$;

create or replace function gymapp_private.state_id_is_valid(p_value jsonb)
returns boolean
language sql
immutable
strict
security invoker
set search_path = ''
as $function$
  select case pg_catalog.jsonb_typeof(p_value)
    when 'number' then
      (p_value #>> '{}')::numeric between 1 and 9007199254740991
      and (p_value #>> '{}')::numeric = pg_catalog.trunc((p_value #>> '{}')::numeric)
    when 'string' then case
      when (p_value #>> '{}') ~ '^[0-9]{1,15}$' then
        (p_value #>> '{}')::numeric between 1 and 9007199254740991
      else false
    end
    else false
  end
$function$;

create or replace function gymapp_private.state_timestamp_is_valid(p_value jsonb)
returns boolean
language sql
immutable
strict
security invoker
set search_path = ''
as $function$
  select case when pg_catalog.jsonb_typeof(p_value) = 'number' then
    (p_value #>> '{}')::numeric = pg_catalog.trunc((p_value #>> '{}')::numeric)
    and (p_value #>> '{}')::numeric between -62135769600000 and 64092211200000
  else false end
$function$;

revoke all on function gymapp_private.state_name_is_valid(text)
  from public, anon, authenticated;
revoke all on function gymapp_private.state_id_is_valid(jsonb)
  from public, anon, authenticated;
revoke all on function gymapp_private.state_timestamp_is_valid(jsonb)
  from public, anon, authenticated;

-- This is the complete database boundary for direct PostgREST writes to
-- user_states. Unknown schema-v2 fields remain forward-compatible, but their
-- depth, node count, key names, string size, and total encoded size are bounded.
create or replace function gymapp_private.validate_user_state(p_state jsonb)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  root_field text;
  root_array jsonb;
  item_value jsonb;
  sessions_value jsonb;
  session_value jsonb;
  exercises_value jsonb;
  exercise_value jsonb;
  exercise_names_value jsonb;
  exercise_name_value jsonb;
  sets_value jsonb;
  flat_sets_value jsonb;
  set_value jsonb;
  owner_value jsonb;
  summary_value jsonb;
  profile_value jsonb;
  mapping_entry record;
  muscle_value jsonb;
  exercise_name text;
  exercise_name_key text;
  numeric_value numeric;
  nested_exercise_count integer;
  flat_set_count integer;
  set_count integer;
  total_set_count integer := 0;
  current_exercise_set_count integer;
  mapping_count integer;
  known_exercise_name_count integer := 0;
  session_name_key_count integer;
  has_timestamp boolean;
  known_exercise_names jsonb := '{}'::jsonb;
  session_name_keys jsonb;
  session_set_counts jsonb;
  json_node_count bigint;
  json_max_depth integer;
  json_has_forbidden_key boolean;
  json_has_oversized_string boolean;
begin
  if p_state is null or pg_catalog.jsonb_typeof(p_state) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'GymApp cloud state must be a JSON object.';
  end if;
  if pg_catalog.octet_length(pg_catalog.convert_to(p_state::text, 'UTF8')) > 8388608 then
    raise exception using errcode = '54000', message = 'GymApp cloud state exceeds 8 MiB.';
  end if;

  with recursive json_walk(value, depth, object_key) as (
    select p_state, 0, null::text
    union all
    select child.value, parent.depth + 1, child.object_key
    from json_walk as parent
    cross join lateral (
      select object_item.value, object_item.key
      from pg_catalog.jsonb_each(
        case when pg_catalog.jsonb_typeof(parent.value) = 'object'
          then parent.value else '{}'::jsonb end
      ) as object_item(key, value)
      union all
      select array_item.value, null::text
      from pg_catalog.jsonb_array_elements(
        case when pg_catalog.jsonb_typeof(parent.value) = 'array'
          then parent.value else '[]'::jsonb end
      ) as array_item(value)
    ) as child(value, object_key)
    where parent.depth < 9
  )
  select
    pg_catalog.count(*)::bigint,
    coalesce(pg_catalog.max(depth), 0)::integer,
    coalesce(pg_catalog.bool_or(object_key in ('__proto__', 'prototype', 'constructor')), false),
    coalesce(pg_catalog.bool_or(
      (object_key is not null and
       pg_catalog.octet_length(pg_catalog.convert_to(object_key, 'UTF8')) > 65536)
      or (pg_catalog.jsonb_typeof(value) = 'string' and
          pg_catalog.octet_length(pg_catalog.convert_to(value #>> '{}', 'UTF8')) > 65536)
    ), false)
  into json_node_count, json_max_depth, json_has_forbidden_key, json_has_oversized_string
  from json_walk;

  if json_node_count > 1000000 then
    raise exception using errcode = '54000', message = 'GymApp cloud state contains too many JSON values.';
  end if;
  if json_max_depth > 8 then
    raise exception using errcode = '54000', message = 'GymApp cloud state exceeds the JSON nesting limit.';
  end if;
  if json_has_forbidden_key then
    raise exception using errcode = '22023', message = 'GymApp cloud state contains a forbidden object key.';
  end if;
  if json_has_oversized_string then
    raise exception using errcode = '54000', message = 'GymApp cloud state contains an oversized JSON string.';
  end if;

  if p_state ? 'schemaVersion' and p_state->'schemaVersion' <> 'null'::jsonb then
    if pg_catalog.jsonb_typeof(p_state->'schemaVersion') is distinct from 'number'
       or (p_state->>'schemaVersion')::numeric <> 2 then
      raise exception using errcode = '22023', message = 'Unsupported GymApp cloud state schema version.';
    end if;
  end if;
  if p_state ? 'exportedAt' and p_state->'exportedAt' <> 'null'::jsonb
     and not gymapp_private.state_timestamp_is_valid(p_state->'exportedAt') then
    raise exception using errcode = '22023', message = 'GymApp export timestamp is invalid.';
  end if;
  foreach root_field in array array['app', 'source'] loop
    if p_state ? root_field and p_state->root_field <> 'null'::jsonb then
      if pg_catalog.jsonb_typeof(p_state->root_field) is distinct from 'string'
         or pg_catalog.octet_length(pg_catalog.convert_to(p_state->>root_field, 'UTF8')) > 128 then
        raise exception using errcode = '22023', message = 'GymApp cloud metadata is invalid.';
      end if;
    end if;
  end loop;
  if p_state ? 'diagnostics' and p_state->'diagnostics' <> 'null'::jsonb
     and pg_catalog.jsonb_typeof(p_state->'diagnostics') is distinct from 'boolean' then
    raise exception using errcode = '22023', message = 'GymApp diagnostics flag must be boolean.';
  end if;
  if p_state ? 'language' and p_state->'language' <> 'null'::jsonb
     and (pg_catalog.jsonb_typeof(p_state->'language') is distinct from 'string'
          or p_state->>'language' not in ('en', 'uk')) then
    raise exception using errcode = '22023', message = 'GymApp language is invalid.';
  end if;

  if p_state ? 'owner' and p_state->'owner' <> 'null'::jsonb then
    owner_value := p_state->'owner';
    if pg_catalog.jsonb_typeof(owner_value) is distinct from 'object' then
      raise exception using errcode = '22023', message = 'GymApp cloud owner must be an object.';
    end if;
    foreach root_field in array array['accountId', 'userId', 'email'] loop
      if owner_value ? root_field and owner_value->root_field <> 'null'::jsonb then
        if pg_catalog.jsonb_typeof(owner_value->root_field) is distinct from 'string'
           or pg_catalog.octet_length(pg_catalog.convert_to(owner_value->>root_field, 'UTF8')) >
              (case when root_field = 'email' then 320 else 512 end) then
          raise exception using errcode = '22023', message = 'GymApp cloud owner field is invalid.';
        end if;
      end if;
    end loop;
    if owner_value ? 'remote' and owner_value->'remote' <> 'null'::jsonb
       and not (
         pg_catalog.jsonb_typeof(owner_value->'remote') = 'boolean'
         or (
           pg_catalog.jsonb_typeof(owner_value->'remote') = 'string'
           and owner_value->>'remote' = 'supabase'
         )
       ) then
      raise exception using errcode = '22023', message = 'GymApp cloud owner remote flag is unsupported.';
    end if;
  end if;

  if p_state ? 'summary' and p_state->'summary' <> 'null'::jsonb then
    summary_value := p_state->'summary';
    if pg_catalog.jsonb_typeof(summary_value) is distinct from 'object' then
      raise exception using errcode = '22023', message = 'GymApp cloud summary must be an object.';
    end if;
    foreach root_field in array array['exerciseCount', 'sessionCount', 'setCount'] loop
      if pg_catalog.jsonb_typeof(summary_value->root_field) is distinct from 'number' then
        raise exception using errcode = '22023', message = 'GymApp cloud summary counts are invalid.';
      end if;
      numeric_value := (summary_value->>root_field)::numeric;
      if numeric_value < 0 or numeric_value <> pg_catalog.trunc(numeric_value)
         or (root_field = 'exerciseCount' and numeric_value > 2000)
         or (root_field = 'sessionCount' and numeric_value > 5000)
         or (root_field = 'setCount' and numeric_value > 100000) then
        raise exception using errcode = '22023', message = 'GymApp cloud summary counts are outside the supported range.';
      end if;
    end loop;
    if pg_catalog.jsonb_typeof(summary_value->'totalVolume') is distinct from 'number'
       or (summary_value->>'totalVolume')::numeric < 0
       or (summary_value->>'totalVolume')::numeric > 1000000000000000 then
      raise exception using errcode = '22023', message = 'GymApp cloud summary volume is invalid.';
    end if;
  end if;

  foreach root_field in array array['exercises', 'exerciseCatalog'] loop
    if not (p_state ? root_field) or p_state->root_field = 'null'::jsonb then
      continue;
    end if;
    root_array := p_state->root_field;
    if pg_catalog.jsonb_typeof(root_array) is distinct from 'array'
       or pg_catalog.jsonb_array_length(root_array) > 2000 then
      raise exception using errcode = '54000', message = 'GymApp cloud exercise catalog is invalid or oversized.';
    end if;
    for item_value in
      select entry.value from pg_catalog.jsonb_array_elements(root_array) as entry(value)
    loop
      if pg_catalog.jsonb_typeof(item_value) = 'string' then
        exercise_name := item_value #>> '{}';
      elsif pg_catalog.jsonb_typeof(item_value) = 'object'
            and pg_catalog.jsonb_typeof(item_value->'name') = 'string' then
        exercise_name := item_value->>'name';
      else
        raise exception using errcode = '22023', message = 'Every GymApp catalog exercise requires a name.';
      end if;
      if not gymapp_private.state_name_is_valid(exercise_name) then
        raise exception using errcode = '22023', message = 'GymApp exercise name is invalid.';
      end if;
      if pg_catalog.jsonb_typeof(item_value) = 'object' then
        if item_value ? 'id' and item_value->'id' <> 'null'::jsonb
           and not gymapp_private.state_id_is_valid(item_value->'id') then
          raise exception using errcode = '22023', message = 'GymApp exercise id is invalid.';
        end if;
        if item_value ? 'catalogKey' and item_value->'catalogKey' <> 'null'::jsonb
           and (pg_catalog.jsonb_typeof(item_value->'catalogKey') is distinct from 'string'
                or (item_value->>'catalogKey') !~ '^[A-Za-z0-9_-]{1,80}$') then
          raise exception using errcode = '22023', message = 'GymApp exercise catalog key is invalid.';
        end if;
      end if;
      exercise_name_key := pg_catalog.lower(pg_catalog.btrim(exercise_name));
      if not (known_exercise_names ? exercise_name_key) then
        if known_exercise_name_count >= 2000 then
          raise exception using errcode = '54000', message = 'GymApp cloud state exceeds the distinct exercise limit.';
        end if;
        known_exercise_names := known_exercise_names || pg_catalog.jsonb_build_object(exercise_name_key, true);
        known_exercise_name_count := known_exercise_name_count + 1;
      end if;
    end loop;
  end loop;

  if p_state ? 'mappings' and p_state->'mappings' <> 'null'::jsonb then
    if pg_catalog.jsonb_typeof(p_state->'mappings') is distinct from 'object' then
      raise exception using errcode = '54000', message = 'GymApp muscle mappings are invalid or oversized.';
    end if;
    select pg_catalog.count(*)::integer into mapping_count
    from (
      select key
      from pg_catalog.jsonb_object_keys(p_state->'mappings') as mapping_key(key)
      limit 2001
    ) as bounded_mapping_keys;
    if mapping_count > 2000 then
      raise exception using errcode = '54000', message = 'GymApp muscle mappings are invalid or oversized.';
    end if;
    for mapping_entry in
      select entry.key, entry.value from pg_catalog.jsonb_each(p_state->'mappings') as entry(key, value)
    loop
      if not gymapp_private.state_name_is_valid(mapping_entry.key)
         or pg_catalog.jsonb_typeof(mapping_entry.value) is distinct from 'array'
         or pg_catalog.jsonb_array_length(mapping_entry.value) > 32 then
        raise exception using errcode = '22023', message = 'GymApp muscle mapping is invalid.';
      end if;
      for muscle_value in
        select entry.value from pg_catalog.jsonb_array_elements(mapping_entry.value) as entry(value)
      loop
        if pg_catalog.jsonb_typeof(muscle_value) is distinct from 'string'
           or pg_catalog.char_length(pg_catalog.btrim(muscle_value #>> '{}')) not between 1 and 64
           or pg_catalog.octet_length(pg_catalog.convert_to(muscle_value #>> '{}', 'UTF8')) > 256 then
          raise exception using errcode = '22023', message = 'GymApp muscle id is invalid.';
        end if;
      end loop;
    end loop;
  end if;

  if p_state ? 'profile' and p_state->'profile' <> 'null'::jsonb then
    profile_value := p_state->'profile';
    if pg_catalog.jsonb_typeof(profile_value) is distinct from 'object' then
      raise exception using errcode = '22023', message = 'GymApp training profile must be an object.';
    end if;
    if profile_value ? 'split' and
       (pg_catalog.jsonb_typeof(profile_value->'split') is distinct from 'string'
        or profile_value->>'split' not in ('Upper / Lower', 'Full Body', 'Push Pull Legs', 'Custom')) then
      raise exception using errcode = '22023', message = 'GymApp training split is invalid.';
    end if;
    if profile_value ? 'goal' and
       (pg_catalog.jsonb_typeof(profile_value->'goal') is distinct from 'string'
        or profile_value->>'goal' not in ('Aesthetic Cut', 'Muscle Gain', 'Strength', 'Balanced')) then
      raise exception using errcode = '22023', message = 'GymApp training goal is invalid.';
    end if;
    if profile_value ? 'calories' and
       (pg_catalog.jsonb_typeof(profile_value->'calories') is distinct from 'string'
        or profile_value->>'calories' not in ('Deficit', 'Maintenance', 'Surplus')) then
      raise exception using errcode = '22023', message = 'GymApp calorie mode is invalid.';
    end if;
    if profile_value ? 'days' and
       (pg_catalog.jsonb_typeof(profile_value->'days') is distinct from 'number'
        or (profile_value->>'days')::numeric <> pg_catalog.trunc((profile_value->>'days')::numeric)
        or (profile_value->>'days')::numeric not between 2 and 6) then
      raise exception using errcode = '22023', message = 'GymApp training days are invalid.';
    end if;
  end if;
  if p_state ? 'progressExerciseId' and p_state->'progressExerciseId' <> 'null'::jsonb
     and not gymapp_private.state_id_is_valid(p_state->'progressExerciseId') then
    raise exception using errcode = '22023', message = 'GymApp progress exercise id is invalid.';
  end if;

  if not (p_state ? 'sessions') or p_state->'sessions' = 'null'::jsonb then
    sessions_value := '[]'::jsonb;
  else
    sessions_value := p_state->'sessions';
  end if;
  if pg_catalog.jsonb_typeof(sessions_value) is distinct from 'array'
     or pg_catalog.jsonb_array_length(sessions_value) > 5000 then
    raise exception using errcode = '54000', message = 'GymApp cloud sessions are invalid or oversized.';
  end if;

  for session_value in
    select entry.value from pg_catalog.jsonb_array_elements(sessions_value) as entry(value)
  loop
    if pg_catalog.jsonb_typeof(session_value) is distinct from 'object' then
      raise exception using errcode = '22023', message = 'Every GymApp workout must be a JSON object.';
    end if;
    if session_value ? 'id' and session_value->'id' <> 'null'::jsonb
       and not gymapp_private.state_id_is_valid(session_value->'id') then
      raise exception using errcode = '22023', message = 'GymApp workout id is invalid.';
    end if;
    has_timestamp := false;
    foreach root_field in array array['date', 'startedAt'] loop
      if session_value ? root_field and session_value->root_field <> 'null'::jsonb then
        has_timestamp := true;
        if not gymapp_private.state_timestamp_is_valid(session_value->root_field) then
          raise exception using errcode = '22023', message = 'GymApp workout timestamp is invalid.';
        end if;
      end if;
    end loop;
    if not has_timestamp then
      raise exception using errcode = '22023', message = 'GymApp workout timestamp is required.';
    end if;
    if session_value ? 'date' and session_value->'date' <> 'null'::jsonb
       and session_value ? 'startedAt' and session_value->'startedAt' <> 'null'::jsonb
       and (session_value->>'date')::numeric <> (session_value->>'startedAt')::numeric then
      raise exception using errcode = '22023', message = 'GymApp workout timestamps disagree.';
    end if;
    if session_value ? 'note' and session_value->'note' <> 'null'::jsonb
       and (pg_catalog.jsonb_typeof(session_value->'note') is distinct from 'string'
            or pg_catalog.char_length(session_value->>'note') > 4000
            or pg_catalog.octet_length(pg_catalog.convert_to(session_value->>'note', 'UTF8')) > 16000) then
      raise exception using errcode = '22023', message = 'GymApp workout note is invalid.';
    end if;

    exercises_value := case
      when session_value ? 'exercises' and session_value->'exercises' <> 'null'::jsonb
        then session_value->'exercises' else '[]'::jsonb end;
    flat_sets_value := case
      when session_value ? 'sets' and session_value->'sets' <> 'null'::jsonb
        then session_value->'sets' else '[]'::jsonb end;
    exercise_names_value := case
      when session_value ? 'exerciseNames' and session_value->'exerciseNames' <> 'null'::jsonb
        then session_value->'exerciseNames' else '[]'::jsonb end;
    if pg_catalog.jsonb_typeof(exercises_value) is distinct from 'array'
       or pg_catalog.jsonb_typeof(flat_sets_value) is distinct from 'array'
       or pg_catalog.jsonb_typeof(exercise_names_value) is distinct from 'array' then
      raise exception using errcode = '22023', message = 'GymApp workout collections must be arrays.';
    end if;
    nested_exercise_count := pg_catalog.jsonb_array_length(exercises_value);
    flat_set_count := pg_catalog.jsonb_array_length(flat_sets_value);
    if nested_exercise_count > 100 or flat_set_count > 10000
       or pg_catalog.jsonb_array_length(exercise_names_value) > 100 then
      raise exception using errcode = '54000', message = 'GymApp workout collection exceeds its limit.';
    end if;
    session_name_keys := '{}'::jsonb;
    session_name_key_count := 0;
    session_set_counts := '{}'::jsonb;
    for exercise_name_value in
      select entry.value from pg_catalog.jsonb_array_elements(exercise_names_value) as entry(value)
    loop
      if pg_catalog.jsonb_typeof(exercise_name_value) is distinct from 'string'
         or not gymapp_private.state_name_is_valid(exercise_name_value #>> '{}') then
        raise exception using errcode = '22023', message = 'GymApp exercise name is invalid.';
      end if;
      exercise_name := exercise_name_value #>> '{}';
      exercise_name_key := pg_catalog.lower(pg_catalog.btrim(exercise_name));
      if not (session_name_keys ? exercise_name_key) then
        session_name_keys := session_name_keys || pg_catalog.jsonb_build_object(exercise_name_key, true);
        session_name_key_count := session_name_key_count + 1;
      end if;
      if not (known_exercise_names ? exercise_name_key) then
        if known_exercise_name_count >= 2000 then
          raise exception using errcode = '54000', message = 'GymApp cloud state exceeds the distinct exercise limit.';
        end if;
        known_exercise_names := known_exercise_names || pg_catalog.jsonb_build_object(exercise_name_key, true);
        known_exercise_name_count := known_exercise_name_count + 1;
      end if;
    end loop;

    if nested_exercise_count > 0 then
      for exercise_value in
        select entry.value from pg_catalog.jsonb_array_elements(exercises_value) as entry(value)
      loop
        if pg_catalog.jsonb_typeof(exercise_value) is distinct from 'object'
           or pg_catalog.jsonb_typeof(exercise_value->'name') is distinct from 'string'
           or not gymapp_private.state_name_is_valid(exercise_value->>'name') then
          raise exception using errcode = '22023', message = 'Every GymApp workout exercise requires a bounded name.';
        end if;
        exercise_name := exercise_value->>'name';
        exercise_name_key := pg_catalog.lower(pg_catalog.btrim(exercise_name));
        if not (session_name_keys ? exercise_name_key) then
          session_name_keys := session_name_keys || pg_catalog.jsonb_build_object(exercise_name_key, true);
          session_name_key_count := session_name_key_count + 1;
          if session_name_key_count > 100 then
            raise exception using errcode = '54000', message = 'A GymApp workout exceeds the exercise limit.';
          end if;
        end if;
        if not (known_exercise_names ? exercise_name_key) then
          if known_exercise_name_count >= 2000 then
            raise exception using errcode = '54000', message = 'GymApp cloud state exceeds the distinct exercise limit.';
          end if;
          known_exercise_names := known_exercise_names || pg_catalog.jsonb_build_object(exercise_name_key, true);
          known_exercise_name_count := known_exercise_name_count + 1;
        end if;
        if exercise_value ? 'catalogKey' and exercise_value->'catalogKey' <> 'null'::jsonb
           and (pg_catalog.jsonb_typeof(exercise_value->'catalogKey') is distinct from 'string'
                or (exercise_value->>'catalogKey') !~ '^[A-Za-z0-9_-]{1,80}$') then
          raise exception using errcode = '22023', message = 'GymApp exercise catalog key is invalid.';
        end if;
        sets_value := case
          when exercise_value ? 'sets' and exercise_value->'sets' <> 'null'::jsonb
            then exercise_value->'sets' else '[]'::jsonb end;
        if pg_catalog.jsonb_typeof(sets_value) is distinct from 'array' then
          raise exception using errcode = '22023', message = 'GymApp exercise sets must be an array.';
        end if;
        set_count := pg_catalog.jsonb_array_length(sets_value);
        current_exercise_set_count := coalesce((session_set_counts->>exercise_name_key)::integer, 0) + set_count;
        if set_count > 100 or current_exercise_set_count > 100
           or (flat_set_count = 0 and total_set_count + set_count > 100000) then
          raise exception using errcode = '54000', message = 'GymApp set collection exceeds its limit.';
        end if;
        session_set_counts := session_set_counts || pg_catalog.jsonb_build_object(exercise_name_key, current_exercise_set_count);
        if flat_set_count = 0 then
          total_set_count := total_set_count + set_count;
        end if;
        for set_value in
          select entry.value from pg_catalog.jsonb_array_elements(sets_value) as entry(value)
        loop
          if pg_catalog.jsonb_typeof(set_value) is distinct from 'object'
             or pg_catalog.jsonb_typeof(set_value->'weight') is distinct from 'number'
             or pg_catalog.jsonb_typeof(set_value->'reps') is distinct from 'number' then
            raise exception using errcode = '22023', message = 'Every GymApp set requires numeric weight and reps.';
          end if;
          numeric_value := (set_value->>'weight')::numeric;
          if numeric_value < 0 or numeric_value > 1000000 then
            raise exception using errcode = '22023', message = 'GymApp set weight is invalid.';
          end if;
          numeric_value := (set_value->>'reps')::numeric;
          if numeric_value < 1 or numeric_value > 10000 or numeric_value <> pg_catalog.trunc(numeric_value) then
            raise exception using errcode = '22023', message = 'GymApp set reps are invalid.';
          end if;
          if set_value ? 'id' and set_value->'id' <> 'null'::jsonb
             and not gymapp_private.state_id_is_valid(set_value->'id') then
            raise exception using errcode = '22023', message = 'GymApp set id is invalid.';
          end if;
          if set_value ? 'orderIndex' and set_value->'orderIndex' <> 'null'::jsonb
             and (pg_catalog.jsonb_typeof(set_value->'orderIndex') is distinct from 'number'
                  or (set_value->>'orderIndex')::numeric <> pg_catalog.trunc((set_value->>'orderIndex')::numeric)
                  or (set_value->>'orderIndex')::numeric not between 0 and 9999) then
            raise exception using errcode = '22023', message = 'GymApp set order is invalid.';
          end if;
        end loop;
      end loop;
    end if;
    if flat_set_count > 0 then
      -- A schema-v2 PWA export may carry both a nested presentation and the
      -- current flat representation. The flat form is canonical for PWA state;
      -- validate it with an independent per-exercise budget.
      session_set_counts := '{}'::jsonb;
      if total_set_count + flat_set_count > 100000 then
        raise exception using errcode = '54000', message = 'GymApp cloud state exceeds the total set limit.';
      end if;
      total_set_count := total_set_count + flat_set_count;
      for set_value in
        select entry.value from pg_catalog.jsonb_array_elements(flat_sets_value) as entry(value)
      loop
        if pg_catalog.jsonb_typeof(set_value) is distinct from 'object' then
          raise exception using errcode = '22023', message = 'Every legacy GymApp set must be an object.';
        end if;
        if set_value ? 'exerciseName' and set_value->'exerciseName' <> 'null'::jsonb then
          if pg_catalog.jsonb_typeof(set_value->'exerciseName') is distinct from 'string' then
            raise exception using errcode = '22023', message = 'Legacy GymApp exercise name must be a string.';
          end if;
          exercise_name := set_value->>'exerciseName';
        elsif set_value ? 'name' and set_value->'name' <> 'null'::jsonb then
          if pg_catalog.jsonb_typeof(set_value->'name') is distinct from 'string' then
            raise exception using errcode = '22023', message = 'Legacy GymApp exercise name must be a string.';
          end if;
          exercise_name := set_value->>'name';
        else
          raise exception using errcode = '22023', message = 'Every legacy GymApp set requires an exercise name.';
        end if;
        if not gymapp_private.state_name_is_valid(exercise_name)
           or pg_catalog.jsonb_typeof(set_value->'weight') is distinct from 'number'
           or pg_catalog.jsonb_typeof(set_value->'reps') is distinct from 'number' then
          raise exception using errcode = '22023', message = 'Every legacy GymApp set requires a bounded name, weight, and reps.';
        end if;
        exercise_name_key := pg_catalog.lower(pg_catalog.btrim(exercise_name));
        if not (session_name_keys ? exercise_name_key) then
          session_name_keys := session_name_keys || pg_catalog.jsonb_build_object(exercise_name_key, true);
          session_name_key_count := session_name_key_count + 1;
          if session_name_key_count > 100 then
            raise exception using errcode = '54000', message = 'A legacy GymApp workout exceeds the exercise limit.';
          end if;
        end if;
        current_exercise_set_count := coalesce((session_set_counts->>exercise_name_key)::integer, 0) + 1;
        if current_exercise_set_count > 100 then
          raise exception using errcode = '54000', message = 'A legacy GymApp exercise exceeds the set limit.';
        end if;
        session_set_counts := session_set_counts || pg_catalog.jsonb_build_object(exercise_name_key, current_exercise_set_count);
        if not (known_exercise_names ? exercise_name_key) then
          if known_exercise_name_count >= 2000 then
            raise exception using errcode = '54000', message = 'GymApp cloud state exceeds the distinct exercise limit.';
          end if;
          known_exercise_names := known_exercise_names || pg_catalog.jsonb_build_object(exercise_name_key, true);
          known_exercise_name_count := known_exercise_name_count + 1;
        end if;
        numeric_value := (set_value->>'weight')::numeric;
        if numeric_value < 0 or numeric_value > 1000000 then
          raise exception using errcode = '22023', message = 'Legacy GymApp set weight is invalid.';
        end if;
        numeric_value := (set_value->>'reps')::numeric;
        if numeric_value < 1 or numeric_value > 10000 or numeric_value <> pg_catalog.trunc(numeric_value) then
          raise exception using errcode = '22023', message = 'Legacy GymApp set reps are invalid.';
        end if;
        if set_value ? 'id' and set_value->'id' <> 'null'::jsonb
           and not gymapp_private.state_id_is_valid(set_value->'id') then
          raise exception using errcode = '22023', message = 'GymApp set id is invalid.';
        end if;
        if set_value ? 'orderIndex' and set_value->'orderIndex' <> 'null'::jsonb
           and (pg_catalog.jsonb_typeof(set_value->'orderIndex') is distinct from 'number'
                or (set_value->>'orderIndex')::numeric <> pg_catalog.trunc((set_value->>'orderIndex')::numeric)
                or (set_value->>'orderIndex')::numeric not between 0 and 9999) then
          raise exception using errcode = '22023', message = 'GymApp set order is invalid.';
        end if;
      end loop;
    end if;
    if nested_exercise_count > 0 and flat_set_count > 0 and exists (
      select 1
      from (
        select
          pg_catalog.lower(pg_catalog.btrim(nested_exercise.value->>'name')) as exercise_name,
          (nested_set.value->>'weight')::numeric as weight,
          (nested_set.value->>'reps')::numeric as reps,
          pg_catalog.count(*)::integer as set_count
        from pg_catalog.jsonb_array_elements(exercises_value) as nested_exercise(value)
        cross join lateral pg_catalog.jsonb_array_elements(
          case when nested_exercise.value ? 'sets' and nested_exercise.value->'sets' <> 'null'::jsonb
            then nested_exercise.value->'sets' else '[]'::jsonb end
        ) as nested_set(value)
        group by 1, 2, 3
      ) as nested_sets
      full join (
        select
          pg_catalog.lower(pg_catalog.btrim(
            coalesce(flat_item.value->>'exerciseName', flat_item.value->>'name')
          )) as exercise_name,
          (flat_item.value->>'weight')::numeric as weight,
          (flat_item.value->>'reps')::numeric as reps,
          pg_catalog.count(*)::integer as set_count
        from pg_catalog.jsonb_array_elements(flat_sets_value) as flat_item(value)
        group by 1, 2, 3
      ) as flat_sets using (exercise_name, weight, reps)
      where coalesce(nested_sets.set_count, 0) <> coalesce(flat_sets.set_count, 0)
    ) then
      raise exception using errcode = '22023', message = 'GymApp nested and flat workout representations disagree.';
    end if;
  end loop;

  return;
end
$function$;

revoke all on function gymapp_private.validate_user_state(jsonb)
  from public, anon, authenticated;

create or replace function gymapp_private.progression_from_state(p_state jsonb)
returns table (xp integer, level integer, workouts integer)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  sessions_value jsonb;
  session_value jsonb;
  exercises_value jsonb;
  exercise_value jsonb;
  sets_value jsonb;
  set_value jsonb;
  exercise_names_value jsonb;
  exercise_name_value jsonb;
  session_exercise_count integer;
  session_set_count integer;
  flat_set_count integer;
  max_sets_for_one_exercise integer;
  total_set_count integer := 0;
  workout_count integer := 0;
  session_volume double precision := 0;
  weight_value double precision;
  reps_value double precision;
  total_xp bigint := 0;
  session_xp bigint;
  progression_level integer := 1;
  level_low integer := 1;
  level_high integer := 2;
  level_middle integer;
  level_stage bigint;
  cumulative_xp bigint;
begin
  perform gymapp_private.validate_user_state(p_state);
  if p_state is null or pg_catalog.jsonb_typeof(p_state) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'GymApp cloud state must be a JSON object.';
  end if;
  if p_state ? 'schemaVersion' and p_state->'schemaVersion' <> 'null'::jsonb then
    if pg_catalog.jsonb_typeof(p_state->'schemaVersion') is distinct from 'number'
       or (p_state->>'schemaVersion')::numeric <> 2 then
      raise exception using errcode = '22023', message = 'Unsupported GymApp cloud state schema version.';
    end if;
  end if;

  sessions_value := case
    when p_state ? 'sessions' and p_state->'sessions' <> 'null'::jsonb
      then p_state->'sessions'
    else '[]'::jsonb
  end;
  if pg_catalog.jsonb_typeof(sessions_value) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'GymApp cloud state sessions must be an array.';
  end if;
  if pg_catalog.jsonb_array_length(sessions_value) > 5000 then
    raise exception using errcode = '54000', message = 'GymApp cloud state exceeds the workout limit.';
  end if;

  for session_value in
    select item.value
    from pg_catalog.jsonb_array_elements(sessions_value) as item(value)
  loop
    if pg_catalog.jsonb_typeof(session_value) is distinct from 'object' then
      raise exception using errcode = '22023', message = 'Every GymApp workout must be a JSON object.';
    end if;
    session_exercise_count := 0;
    session_set_count := 0;
    session_volume := 0;

    if pg_catalog.jsonb_typeof(session_value->'exercises') = 'array'
       and not (session_value ? 'sets'
                and pg_catalog.jsonb_typeof(session_value->'sets') = 'array'
                and pg_catalog.jsonb_array_length(session_value->'sets') > 0) then
      exercises_value := session_value->'exercises';
      if pg_catalog.jsonb_typeof(exercises_value) is distinct from 'array' then
        raise exception using errcode = '22023', message = 'GymApp backup-v2 exercises must be an array.';
      end if;
      session_exercise_count := pg_catalog.jsonb_array_length(exercises_value);
      if session_exercise_count > 100 then
        raise exception using errcode = '54000', message = 'A GymApp workout exceeds the exercise limit.';
      end if;

      for exercise_value in
        select item.value
        from pg_catalog.jsonb_array_elements(exercises_value) as item(value)
      loop
        if pg_catalog.jsonb_typeof(exercise_value) is distinct from 'object'
           or pg_catalog.jsonb_typeof(exercise_value->'name') is distinct from 'string'
           or not gymapp_private.state_name_is_valid(exercise_value->>'name') then
          raise exception using errcode = '22023', message = 'Every GymApp workout exercise requires a bounded name.';
        end if;
        sets_value := case
          when exercise_value ? 'sets' and exercise_value->'sets' <> 'null'::jsonb
            then exercise_value->'sets'
          else '[]'::jsonb
        end;
        if pg_catalog.jsonb_typeof(sets_value) is distinct from 'array' then
          raise exception using errcode = '22023', message = 'GymApp backup-v2 exercise sets must be an array.';
        end if;
        flat_set_count := pg_catalog.jsonb_array_length(sets_value);
        if flat_set_count > 100 then
          raise exception using errcode = '54000', message = 'A GymApp exercise exceeds the set limit.';
        end if;
        if total_set_count + flat_set_count > 100000 then
          raise exception using errcode = '54000', message = 'GymApp cloud state exceeds the total set limit.';
        end if;
        total_set_count := total_set_count + flat_set_count;
        session_set_count := session_set_count + flat_set_count;

        for set_value in
          select item.value
          from pg_catalog.jsonb_array_elements(sets_value) as item(value)
        loop
          if pg_catalog.jsonb_typeof(set_value) is distinct from 'object'
             or pg_catalog.jsonb_typeof(set_value->'weight') is distinct from 'number'
             or pg_catalog.jsonb_typeof(set_value->'reps') is distinct from 'number' then
            raise exception using errcode = '22023', message = 'Every GymApp set requires numeric weight and reps.';
          end if;
          weight_value := (set_value->>'weight')::numeric;
          reps_value := (set_value->>'reps')::numeric;
          if weight_value < 0 or weight_value > 1000000
             or reps_value < 1 or reps_value > 10000
             or reps_value <> pg_catalog.trunc(reps_value) then
            raise exception using errcode = '22023', message = 'GymApp set values are outside the supported range.';
          end if;
          session_volume := session_volume + weight_value * reps_value;
        end loop;
      end loop;
      select pg_catalog.count(distinct pg_catalog.lower(pg_catalog.btrim(item.value->>'name')))::integer
        into session_exercise_count
      from pg_catalog.jsonb_array_elements(exercises_value) as item(value)
      where pg_catalog.jsonb_array_length(
        case when item.value ? 'sets' and item.value->'sets' <> 'null'::jsonb
          then item.value->'sets' else '[]'::jsonb end
      ) > 0;
    else
      sets_value := case
        when session_value ? 'sets' and session_value->'sets' <> 'null'::jsonb
          then session_value->'sets'
        else '[]'::jsonb
      end;
      exercise_names_value := case
        when session_value ? 'exerciseNames' and session_value->'exerciseNames' <> 'null'::jsonb
          then session_value->'exerciseNames'
        else '[]'::jsonb
      end;
      if pg_catalog.jsonb_typeof(sets_value) is distinct from 'array' then
        raise exception using errcode = '22023', message = 'Legacy GymApp session sets must be an array.';
      end if;
      if pg_catalog.jsonb_typeof(exercise_names_value) is distinct from 'array' then
        raise exception using errcode = '22023', message = 'Legacy GymApp exercise names must be an array.';
      end if;

      -- Check both legacy collection lengths and the global budget before any
      -- jsonb_array_elements traversal.
      flat_set_count := pg_catalog.jsonb_array_length(sets_value);
      if flat_set_count > 10000 then
        raise exception using errcode = '54000', message = 'A legacy GymApp workout exceeds the set limit.';
      end if;
      if pg_catalog.jsonb_array_length(exercise_names_value) > 100 then
        raise exception using errcode = '54000', message = 'A legacy GymApp workout exceeds the exercise-name limit.';
      end if;
      if total_set_count + flat_set_count > 100000 then
        raise exception using errcode = '54000', message = 'GymApp cloud state exceeds the total set limit.';
      end if;
      total_set_count := total_set_count + flat_set_count;
      session_set_count := flat_set_count;

      for exercise_name_value in
        select item.value
        from pg_catalog.jsonb_array_elements(exercise_names_value) as item(value)
      loop
        if pg_catalog.jsonb_typeof(exercise_name_value) is distinct from 'string'
           or not gymapp_private.state_name_is_valid(exercise_name_value #>> '{}') then
          raise exception using errcode = '22023', message = 'Legacy GymApp exercise names must be bounded strings.';
        end if;
      end loop;

      for set_value in
        select item.value
        from pg_catalog.jsonb_array_elements(sets_value) as item(value)
      loop
        if pg_catalog.jsonb_typeof(set_value) is distinct from 'object'
           or (pg_catalog.jsonb_typeof(set_value->'exerciseName') is distinct from 'string'
               and pg_catalog.jsonb_typeof(set_value->'name') is distinct from 'string')
           or not gymapp_private.state_name_is_valid(
             coalesce(set_value->>'exerciseName', set_value->>'name')
           )
           or pg_catalog.jsonb_typeof(set_value->'weight') is distinct from 'number'
           or pg_catalog.jsonb_typeof(set_value->'reps') is distinct from 'number' then
          raise exception using errcode = '22023', message = 'Every legacy GymApp set requires an exercise name, weight, and reps.';
        end if;
        weight_value := (set_value->>'weight')::numeric;
        reps_value := (set_value->>'reps')::numeric;
        if weight_value < 0 or weight_value > 1000000
           or reps_value < 1 or reps_value > 10000
           or reps_value <> pg_catalog.trunc(reps_value) then
          raise exception using errcode = '22023', message = 'Legacy GymApp set values are outside the supported range.';
        end if;
        session_volume := session_volume + weight_value * reps_value;
      end loop;

      select coalesce(pg_catalog.max(grouped.set_count), 0)::integer
        into max_sets_for_one_exercise
      from (
        select pg_catalog.count(*)::integer as set_count
        from pg_catalog.jsonb_array_elements(sets_value) as item(value)
        group by pg_catalog.lower(pg_catalog.btrim(
          coalesce(item.value->>'exerciseName', item.value->>'name')
        ))
      ) as grouped;
      if max_sets_for_one_exercise > 100 then
        raise exception using errcode = '54000', message = 'A legacy GymApp exercise exceeds the set limit.';
      end if;

      select pg_catalog.count(distinct names.exercise_name)::integer
        into session_exercise_count
      from (
        select pg_catalog.lower(pg_catalog.btrim(
          coalesce(item.value->>'exerciseName', item.value->>'name')
        )) as exercise_name
        from pg_catalog.jsonb_array_elements(sets_value) as item(value)
      ) as names;
      if session_exercise_count > 100 then
        raise exception using errcode = '54000', message = 'A legacy GymApp workout exceeds the exercise limit.';
      end if;
    end if;

    -- Empty placeholders are neither workouts nor XP-bearing sessions.
    if session_set_count > 0 then
      workout_count := workout_count + 1;
      session_xp := least(
        5000::bigint,
        90
          + session_exercise_count::bigint * 16
          + session_set_count::bigint * 8
          + pg_catalog.floor(session_volume / 80.0::double precision + 0.5)::bigint
      );
      total_xp := total_xp + greatest(session_xp, 0::bigint);
      if total_xp > 2147483647 then
        raise exception using errcode = '22003', message = 'GymApp progression exceeds the supported XP range.';
      end if;
    end if;
  end loop;

  -- Closed-form cumulative XP with a bounded binary search. This avoids a
  -- client-controlled linear loop even at the maximum supported XP.
  while level_high < 65536 loop
    level_stage := level_high - 1;
    cumulative_xp := 200 * level_stage
      + 85 * level_stage * (level_stage - 1) / 2
      + 8 * level_stage * (level_stage - 1) * (2 * level_stage - 1) / 6;
    exit when cumulative_xp > total_xp;
    level_low := level_high;
    level_high := level_high * 2;
  end loop;
  while level_low + 1 < level_high loop
    level_middle := (level_low + level_high) / 2;
    level_stage := level_middle - 1;
    cumulative_xp := 200 * level_stage
      + 85 * level_stage * (level_stage - 1) / 2
      + 8 * level_stage * (level_stage - 1) * (2 * level_stage - 1) / 6;
    if cumulative_xp <= total_xp then
      level_low := level_middle;
    else
      level_high := level_middle;
    end if;
  end loop;
  progression_level := level_low;

  return query select total_xp::integer, progression_level, workout_count;
end
$function$;

comment on function gymapp_private.progression_from_state(jsonb) is
  'Validates bounded GymApp state and derives canonical progression v1 from non-empty workouts only.';
revoke all on function gymapp_private.progression_from_state(jsonb)
  from public, anon, authenticated;

-- Older validators accepted a wider set of states. Quarantine only expected
-- contract/range failures per row; unexpected database/runtime errors still
-- abort this migration so implementation defects cannot be silently hidden.
do $quarantine_existing_states$
declare
  state_row record;
  validation_error text;
begin
  for state_row in select user_id, state from public.user_states loop
    validation_error := null;
    if pg_catalog.jsonb_typeof(state_row.state->'owner') = 'object'
       and pg_catalog.jsonb_typeof(state_row.state->'owner'->'userId') = 'string'
       and pg_catalog.btrim(state_row.state->'owner'->>'userId') <> ''
       and pg_catalog.lower(pg_catalog.btrim(state_row.state->'owner'->>'userId')) <> state_row.user_id::text then
      validation_error := 'Stored GymApp state owner does not match its database row.';
    else
      begin
        perform * from gymapp_private.progression_from_state(state_row.state);
      exception
        when sqlstate '22023' or sqlstate '22003' or sqlstate '54000' then
          validation_error := pg_catalog.left(sqlerrm, 200);
      end;
    end if;

    if validation_error is null then
      delete from gymapp_private.user_state_quarantine as quarantine
      where quarantine.user_id = state_row.user_id;
    else
      insert into gymapp_private.user_state_quarantine (
        user_id, validation_error, quarantined_at
      ) values (
        state_row.user_id, pg_catalog.left(validation_error, 200), pg_catalog.clock_timestamp()
      )
      on conflict (user_id) do update
      set validation_error = excluded.validation_error,
          quarantined_at = excluded.quarantined_at;
    end if;
  end loop;
end
$quarantine_existing_states$;

-- Keep quarantined legacy rows out of the cross-account leaderboard. The raw
-- state and its profile remain owner-readable under their existing RLS rules.
create or replace function public.leaderboard_public_rows()
returns table (
  profile_id text,
  display_name text,
  xp bigint,
  level bigint,
  workouts bigint,
  is_current_user boolean
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    profile.public_id::text,
    coalesce(
      public.safe_leaderboard_display_name(profile.display_name::text),
      'GymApp user'
    )::text,
    greatest(coalesce(profile.xp, 0), 0)::bigint,
    greatest(coalesce(profile.level, 1), 1)::bigint,
    greatest(coalesce(profile.workouts, 0), 0)::bigint,
    coalesce(profile.user_id = (select auth.uid()), false)
  from public.profiles as profile
  where profile.user_id is not null
    and not exists (
      select 1
      from gymapp_private.user_state_quarantine as quarantine
      where quarantine.user_id = profile.user_id
    )
$function$;

revoke all on function public.leaderboard_public_rows()
  from public, anon, authenticated;
grant execute on function public.leaderboard_public_rows()
  to authenticated, service_role;

create or replace function gymapp_private.guard_profile_progression()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  state_value jsonb;
  state_is_quarantined boolean;
  progression record;
begin
  if caller_user_id is not null and caller_user_id <> new.user_id then
    raise exception using errcode = '42501', message = 'A profile can only derive progression for its owner.';
  end if;
  select state.state into state_value
  from public.user_states as state
  where state.user_id = new.user_id;
  select pg_catalog.count(*) > 0 into state_is_quarantined
  from gymapp_private.user_state_quarantine as quarantine
  where quarantine.user_id = new.user_id;
  if state_value is null or state_is_quarantined then
    new.xp := 0;
    new.level := 1;
    new.workouts := 0;
  else
    select * into strict progression
    from gymapp_private.progression_from_state(state_value);
    new.xp := progression.xp;
    new.level := progression.level;
    new.workouts := progression.workouts;
  end if;
  new.progression_version := 1;
  new.updated_at := pg_catalog.clock_timestamp();
  return new;
end
$function$;

revoke all on function gymapp_private.guard_profile_progression()
  from public, anon, authenticated;

create or replace function gymapp_private.refresh_profile_progression()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  owner_user_id uuid;
  progression record;
begin
  owner_user_id := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
  if tg_op = 'UPDATE' and old.user_id is distinct from new.user_id then
    raise exception using errcode = '22023', message = 'GymApp cloud state owner is immutable.';
  end if;
  if caller_user_id is not null and caller_user_id <> owner_user_id then
    raise exception using errcode = '42501', message = 'Cloud state can only refresh its owner profile.';
  end if;
  if tg_op = 'DELETE' then
    update public.profiles
    set xp = 0, level = 1, workouts = 0, progression_version = 1,
        updated_at = pg_catalog.clock_timestamp()
    where user_id = owner_user_id;
    return old;
  end if;
  if pg_catalog.jsonb_typeof(new.state->'owner') = 'object'
     and pg_catalog.jsonb_typeof(new.state->'owner'->'userId') = 'string'
     and pg_catalog.btrim(new.state->'owner'->>'userId') <> ''
     and pg_catalog.lower(pg_catalog.btrim(new.state->'owner'->>'userId')) <> new.user_id::text then
    raise exception using errcode = '42501', message = 'GymApp cloud state owner does not match its authenticated row.';
  end if;
  select * into strict progression
  from gymapp_private.progression_from_state(new.state);
  delete from gymapp_private.user_state_quarantine as quarantine
  where quarantine.user_id = new.user_id;
  update public.profiles
  set xp = progression.xp,
      level = progression.level,
      workouts = progression.workouts,
      progression_version = 1,
      updated_at = pg_catalog.clock_timestamp()
  where user_id = new.user_id;
  return new;
end
$function$;

revoke all on function gymapp_private.refresh_profile_progression()
  from public, anon, authenticated;

drop trigger if exists profiles_canonical_progression_guard on public.profiles;
create trigger profiles_canonical_progression_guard
before insert or update of user_id, xp, level, workouts
on public.profiles
for each row
execute function gymapp_private.guard_profile_progression();

drop trigger if exists user_states_refresh_profile_progression on public.user_states;
create trigger user_states_refresh_profile_progression
after insert or update of user_id, state or delete
on public.user_states
for each row
execute function gymapp_private.refresh_profile_progression();

with eligible_states as materialized (
  select state.user_id, state.state
  from public.user_states as state
  where not exists (
    select 1
    from gymapp_private.user_state_quarantine as quarantine
    where quarantine.user_id = state.user_id
  )
), derived as materialized (
  select
    state.user_id,
    progression.xp,
    progression.level,
    progression.workouts
  from eligible_states as state
  cross join lateral gymapp_private.progression_from_state(state.state) as progression
), expected as (
  select
    profile.user_id,
    coalesce(derived.xp, 0) as xp,
    coalesce(derived.level, 1) as level,
    coalesce(derived.workouts, 0) as workouts
  from public.profiles as profile
  left join derived using (user_id)
)
update public.profiles as profile
set xp = expected.xp,
    level = expected.level,
    workouts = expected.workouts,
    progression_version = 1,
    updated_at = pg_catalog.clock_timestamp()
from expected
where profile.user_id = expected.user_id;

do $verify$
declare
  mismatch_count integer;
begin
  with eligible_states as materialized (
    select state.user_id, state.state
    from public.user_states as state
    where not exists (
      select 1
      from gymapp_private.user_state_quarantine as quarantine
      where quarantine.user_id = state.user_id
    )
  ), derived as materialized (
    select state.user_id, progression.xp, progression.level, progression.workouts
    from eligible_states as state
    cross join lateral gymapp_private.progression_from_state(state.state) as progression
  )
  select pg_catalog.count(*)::integer into mismatch_count
  from public.profiles as profile
  left join derived using (user_id)
  where profile.xp <> coalesce(derived.xp, 0)
     or profile.level <> coalesce(derived.level, 1)
     or profile.workouts <> coalesce(derived.workouts, 0)
     or profile.progression_version <> 1;
  if mismatch_count <> 0 then
    raise exception 'Canonical progression reconciliation left % mismatched profiles', mismatch_count;
  end if;
  if exists (
    select 1
    from public.profiles as profile
    join gymapp_private.user_state_quarantine as quarantine using (user_id)
    where profile.xp <> 0 or profile.level <> 1 or profile.workouts <> 0
  ) then
    raise exception 'A quarantined GymApp state retained public progression';
  end if;
  if has_function_privilege('anon', 'gymapp_private.progression_from_state(jsonb)', 'EXECUTE')
     or has_function_privilege('authenticated', 'gymapp_private.progression_from_state(jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'gymapp_private.guard_profile_progression()', 'EXECUTE')
     or has_function_privilege('authenticated', 'gymapp_private.guard_profile_progression()', 'EXECUTE')
     or has_function_privilege('anon', 'gymapp_private.refresh_profile_progression()', 'EXECUTE')
     or has_function_privilege('authenticated', 'gymapp_private.refresh_profile_progression()', 'EXECUTE') then
    raise exception 'Canonical progression helpers remain client-executable';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
