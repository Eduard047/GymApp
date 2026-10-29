begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regprocedure('gymapp_private.validate_user_state(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.consume_social_rate_limit(uuid,text)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_name_is_safe(text)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_ensure_friend_code(uuid)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_workout_inbox_page_storage_v2(timestamp with time zone,text,boolean,integer)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_send_workout_invite_direct_storage_v1(text,uuid,jsonb)') is null then
    raise exception 'GymApp plpgsql lint cleanup prerequisites are missing.';
  end if;
end
$preflight$;

-- plpgsql_check lint cleanup. Each function below is recreated with its
-- current definition minus unused or shadowed variable declarations: the
-- declared-but-unused loop counters (the FOR loop declares its own), the
-- unused JSON-scan accumulators in validate_user_state, and two variables
-- that were assigned but never read. Signatures, return types, volatility,
-- security mode, search_path, owner, comments, and grants are unchanged.
-- Behavior is unchanged: FOUND is still set by INSERT ... ON CONFLICT and by
-- PERFORM, which is all the former RETURNING/SELECT INTO targets were used for.

CREATE OR REPLACE FUNCTION gymapp_private.validate_user_state(p_state jsonb)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
begin
  if p_state is null then
    raise exception using errcode = '22023', message = 'GymApp cloud state must be a JSON object.';
  end if;
  perform gymapp_private.validate_user_state_global_budget(p_state);

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

CREATE OR REPLACE FUNCTION gymapp_private.consume_social_rate_limit(p_user_id uuid, p_action text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  bucket_capacity numeric(20, 9);
  refill_per_second numeric(20, 9);
  request_time timestamptz := pg_catalog.clock_timestamp();
begin
  select configuration.capacity, configuration.refill_rate
  into bucket_capacity, refill_per_second
  from (values
    ('dashboard', 120::numeric, 2::numeric),
    ('friend_details', 120::numeric, 2::numeric),
    ('send_friend', 12::numeric, (1::numeric / 300::numeric)),
    ('respond_friend', 30::numeric, (1::numeric / 30::numeric)),
    ('cancel_friend', 30::numeric, (1::numeric / 30::numeric)),
    ('remove_friend', 20::numeric, (1::numeric / 60::numeric)),
    ('block_profile', 30::numeric, (1::numeric / 30::numeric)),
    ('unblock_profile', 30::numeric, (1::numeric / 30::numeric)),
    ('update_privacy', 20::numeric, (1::numeric / 60::numeric)),
    ('workout_inbox', 120::numeric, 2::numeric),
    ('send_workout', 10::numeric, (1::numeric / 360::numeric)),
    ('respond_workout', 30::numeric, (1::numeric / 30::numeric)),
    ('cancel_workout', 30::numeric, (1::numeric / 30::numeric))
  ) as configuration(action, capacity, refill_rate)
  where configuration.action = p_action;

  if p_user_id is null or bucket_capacity is null then
    raise exception using errcode = '22023', message = 'Social rate-limit request is invalid.';
  end if;

  insert into gymapp_private.social_rate_limits (
    user_id, bucket_action, tokens, refilled_at
  ) values (
    p_user_id, p_action, bucket_capacity - 1, request_time
  )
  on conflict (user_id, bucket_action) do update
  set tokens = least(
        bucket_capacity,
        gymapp_private.social_rate_limits.tokens
          + greatest(
              extract(epoch from request_time - gymapp_private.social_rate_limits.refilled_at),
              0
            ) * refill_per_second
      ) - 1,
      refilled_at = request_time
  where least(
    bucket_capacity,
    gymapp_private.social_rate_limits.tokens
      + greatest(
          extract(epoch from request_time - gymapp_private.social_rate_limits.refilled_at),
          0
        ) * refill_per_second
  ) >= 1;

  if not found then
    raise exception using errcode = 'P0001', message = 'Social request limit exceeded.';
  end if;
end
$function$;

CREATE OR REPLACE FUNCTION gymapp_private.social_name_is_safe(p_value text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE STRICT
 SET search_path TO ''
AS $function$
declare
  code_point integer;
begin
  if p_value <> pg_catalog.btrim(p_value)
     or pg_catalog.char_length(p_value) not between 1 and 120
     or pg_catalog.octet_length(pg_catalog.convert_to(p_value, 'UTF8')) > 480
     or gymapp_private.social_normalize_name(p_value) = '' then
    return false;
  end if;

  for character_index in 1..pg_catalog.char_length(p_value) loop
    code_point := pg_catalog.ascii(pg_catalog.substr(p_value, character_index, 1));
    if code_point between 0 and 31
       or code_point between 127 and 159
       or code_point in (
         173, 1564, 1757, 1807, 2192, 2193, 2274, 6158, 8203, 8204, 8205,
         8206, 8207, 8232, 8233, 8234, 8235, 8236, 8237, 8238,
         8288, 8289, 8290, 8291, 8292, 8294, 8295, 8296, 8297,
         8298, 8299, 8300, 8301, 8302, 8303, 65279, 65529, 65530, 65531,
         69821, 69837,
         113824, 113825, 113826, 113827, 119155, 119156, 119157,
         119158, 119159, 119160, 119161, 119162, 917505
       )
       or code_point between 1536 and 1541
       or code_point between 6068 and 6069
       or code_point between 8288 and 8303
       or code_point between 78896 and 78943
       or code_point between 917536 and 917631 then
      return false;
    end if;
  end loop;
  return true;
end
$function$;

CREATE OR REPLACE FUNCTION gymapp_private.social_ensure_friend_code(p_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  candidate_friend_code text;
  stored_friend_code text;
begin
  if p_user_id is null
     or auth.uid() is distinct from p_user_id
     or not gymapp_private.has_current_auth_session(p_user_id) then
    raise exception using
      errcode = '42501',
      message = 'Friend-code creation requires the owner live session.';
  end if;

  -- Serialize lazy creation for this account. A hash collision can only add
  -- harmless contention; it cannot mix rows because user_id remains the key.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'gymapp-social-friend-code:' || p_user_id::text,
      0
    )
  );

  select code.friend_code into stored_friend_code
  from gymapp_private.social_friend_codes as code
  where code.user_id = p_user_id;
  if found then
    return stored_friend_code;
  end if;

  -- The first twelve UUIDv4 hex digits precede the fixed version nibble, so
  -- each candidate retains exactly 48 random bits. Unique collisions retry a
  -- fixed number of times rather than spinning or exposing another account.
  for generation_attempt in 1..16 loop
    candidate_friend_code := 'g_' || pg_catalog.left(
      pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', ''),
      12
    );

    insert into gymapp_private.social_friend_codes (
      user_id,
      friend_code,
      created_at
    ) values (
      p_user_id,
      candidate_friend_code,
      pg_catalog.clock_timestamp()
    )
    on conflict do nothing
    returning friend_code into stored_friend_code;

    if found then
      return stored_friend_code;
    end if;

    -- A concurrent privileged writer may have created the owner row. Return
    -- only that exact row; otherwise the conflict was on the random code.
    select code.friend_code into stored_friend_code
    from gymapp_private.social_friend_codes as code
    where code.user_id = p_user_id;
    if found then
      return stored_friend_code;
    end if;
  end loop;

  raise exception using
    errcode = 'P0001',
    message = 'Friend-code generation is temporarily unavailable.';
end
$function$;

CREATE OR REPLACE FUNCTION gymapp_private.social_workout_inbox_page_storage_v2(p_cursor_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_invite_id text DEFAULT NULL::text, p_cursor_pending boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_user_id uuid;
  read_time timestamptz := pg_catalog.clock_timestamp();
  incoming_json jsonb := '[]'::jsonb;
  outgoing_json jsonb := '[]'::jsonb;
  incoming_candidates jsonb;
  incoming_candidate_count integer;
  candidate_envelope jsonb;
  candidate_json jsonb;
  candidate_array jsonb;
  candidate_cursor jsonb;
  candidate_response jsonb;
  last_cursor jsonb := 'null'::jsonb;
  outgoing_row record;
  pending_incoming_count integer;
  effective_limit integer;
  has_more boolean := false;
  response_json jsonb;
  -- Keep 4 KiB below the clients' 256 KiB transport ceiling for the RPC/HTTP
  -- serializer envelope while measuring the exact JSON body produced here.
  response_byte_limit constant integer := 258048;
  -- This fixed array budget makes the outgoing snapshot independent from the
  -- incoming cursor/page size. Newest rows are kept; only the older tail can be
  -- omitted when unusually large summaries would otherwise exhaust the page.
  outgoing_array_byte_limit constant integer := 98304;
begin
  caller_user_id := gymapp_private.social_require_caller('workout_inbox');
  perform gymapp_private.social_purge_expired_workout_payloads(caller_user_id);
  perform gymapp_private.social_ensure_account_rows(caller_user_id);

  if p_limit is null or p_limit not between 1 and 20
     or not (
       (p_cursor_created_at is null
         and p_cursor_invite_id is null
         and p_cursor_pending is null)
       or (p_cursor_created_at is not null
         and p_cursor_invite_id is not null
         and p_cursor_pending is not null)
     )
     or (p_cursor_created_at is not null and (
       p_cursor_invite_id !~ '^wi_[0-9a-f]{32}$'
       or p_cursor_created_at > read_time
       or p_cursor_created_at < read_time - interval '38 days'
     )) then
    raise exception using errcode = '22023',
      message = 'Workout inbox page is invalid.';
  end if;
  effective_limit := p_limit;

  select pg_catalog.count(*)::integer into pending_incoming_count
  from gymapp_private.social_workout_invites as invite
  where invite.recipient_user_id = caller_user_id
    and invite.status = 'pending'
    and invite.expires_at > read_time
    and gymapp_private.social_pair_is_accepted(
      invite.sender_user_id, caller_user_id
    );

  -- Build the outgoing snapshot first under a cursor-independent exact UTF-8
  -- budget. Stopping at the first row that does not fit preserves a strict
  -- newest-first prefix and keeps the snapshot identical on following pages.
  for outgoing_row in
    with bounded as (
      select invite.*,
        case when invite.status = 'pending' and invite.expires_at <= read_time
          then 'expired' else invite.status end as effective_status,
        case when invite.status = 'pending' and invite.expires_at <= read_time
          then invite.expires_at else invite.responded_at end as effective_responded_at
      from gymapp_private.social_workout_invites as invite
      where invite.sender_user_id = caller_user_id
        and invite.summary is not null
        and (
          (invite.status = 'pending'
            and invite.expires_at > read_time - interval '24 hours')
          or (invite.status = 'accepted'
            and invite.responded_at > read_time - interval '30 days')
          or (invite.status in ('declined', 'cancelled', 'expired')
            and invite.responded_at > read_time - interval '24 hours')
        )
      order by invite.created_at desc, invite.id desc
      limit 20
    )
    select
      bounded.id,
      profile.public_id,
      gymapp_private.social_safe_display_name(profile.display_name) as display_name,
      bounded.effective_status,
      bounded.revision,
      bounded.created_at,
      bounded.expires_at,
      bounded.effective_responded_at,
      bounded.summary
    from bounded
    join public.profiles as profile on profile.user_id = bounded.recipient_user_id
    order by bounded.created_at desc, bounded.id desc
  loop
    candidate_json := pg_catalog.jsonb_build_object(
      'inviteId', outgoing_row.id,
      'profileId', outgoing_row.public_id,
      'displayName', outgoing_row.display_name,
      'status', outgoing_row.effective_status,
      'inviteRevision', outgoing_row.revision,
      'createdAt', outgoing_row.created_at,
      'expiresAt', outgoing_row.expires_at,
      'respondedAt', outgoing_row.effective_responded_at,
      'summary', outgoing_row.summary
    );
    candidate_array := outgoing_json || pg_catalog.jsonb_build_array(candidate_json);
    if pg_catalog.octet_length(
         pg_catalog.convert_to(candidate_array::text, 'UTF8')
       ) > outgoing_array_byte_limit then
      exit;
    end if;
    outgoing_json := candidate_array;
  end loop;

  -- Materialize at most one look-ahead row. This keeps database work bounded
  -- while allowing the response cursor to describe exactly the last emitted
  -- row when either another row exists or the byte budget ends the page early.
  with eligible as (
    select invite.*,
      invite.status = 'pending' and invite.expires_at > read_time as active_pending,
      case when invite.status = 'pending' and invite.expires_at <= read_time
        then 'expired' else invite.status end as effective_status,
      case when invite.status = 'pending' and invite.expires_at <= read_time
        then invite.expires_at else invite.responded_at end as effective_responded_at
    from gymapp_private.social_workout_invites as invite
    where invite.recipient_user_id = caller_user_id
      and invite.summary is not null
      and (
        (invite.status = 'accepted'
          and invite.responded_at > read_time - interval '30 days')
        or (invite.status = 'pending' and invite.expires_at > read_time)
      )
      and gymapp_private.social_pair_is_accepted(
        invite.sender_user_id, caller_user_id
      )
      and (
        p_cursor_created_at is null
        or (
          case when invite.status = 'pending' and invite.expires_at > read_time
            then 1 else 0 end,
          invite.created_at,
          invite.id
        ) < (
          case when p_cursor_pending then 1 else 0 end,
          p_cursor_created_at,
          p_cursor_invite_id
        )
      )
    order by active_pending desc, invite.created_at desc, invite.id desc
    limit effective_limit + 1
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'row', pg_catalog.jsonb_build_object(
        'inviteId', eligible.id,
        'profileId', profile.public_id,
        'displayName', gymapp_private.social_safe_display_name(profile.display_name),
        'status', eligible.effective_status,
        'inviteRevision', eligible.revision,
        'createdAt', eligible.created_at,
        'expiresAt', eligible.expires_at,
        'respondedAt', eligible.effective_responded_at,
        'summary', eligible.summary
      ),
      'createdAt', eligible.created_at,
      'inviteId', eligible.id,
      'pending', eligible.active_pending
    ) order by eligible.active_pending desc, eligible.created_at desc, eligible.id desc
  ), '[]'::jsonb)
  into incoming_candidates
  from eligible
  join public.profiles as profile on profile.user_id = eligible.sender_user_id;

  incoming_candidate_count := pg_catalog.jsonb_array_length(incoming_candidates);
  if incoming_candidate_count > 0 then
    for incoming_index in 0 .. least(
      effective_limit, incoming_candidate_count
    ) - 1 loop
      candidate_envelope := incoming_candidates->incoming_index;
      candidate_json := candidate_envelope->'row';
      candidate_array := incoming_json || pg_catalog.jsonb_build_array(candidate_json);
      has_more := incoming_index + 1 < incoming_candidate_count;
      candidate_cursor := pg_catalog.jsonb_build_object(
        'createdAt', candidate_envelope->'createdAt',
        'inviteId', candidate_envelope->'inviteId',
        'pending', candidate_envelope->'pending'
      );
      candidate_response := pg_catalog.jsonb_build_object(
        'version', 2,
        'pendingIncomingCount', pending_incoming_count,
        'incoming', candidate_array,
        'outgoing', outgoing_json,
        'nextCursor', case when has_more then candidate_cursor
          else 'null'::jsonb end
      );
      if pg_catalog.octet_length(
           pg_catalog.convert_to(candidate_response::text, 'UTF8')
         ) > response_byte_limit then
        -- Structurally valid summaries fit beside the fixed outgoing budget.
        -- Unexpected stored metadata fails closed without changing the outgoing
        -- snapshot between cursor pages or returning an unpageable cursor.
        if pg_catalog.jsonb_array_length(incoming_json) = 0 then
          raise exception using errcode = '54000',
            message = 'Workout inbox row exceeds the response limit.';
        else
          has_more := true;
          exit;
        end if;
      end if;
      incoming_json := candidate_array;
      last_cursor := candidate_cursor;
    end loop;
  end if;

  response_json := pg_catalog.jsonb_build_object(
    'version', 2,
    'pendingIncomingCount', pending_incoming_count,
    'incoming', incoming_json,
    'outgoing', outgoing_json,
    'nextCursor', case when has_more then last_cursor else 'null'::jsonb end
  );
  if pg_catalog.octet_length(
       pg_catalog.convert_to(response_json::text, 'UTF8')
     ) > response_byte_limit then
    raise exception using errcode = '54000',
      message = 'Workout inbox page exceeds the response limit.';
  end if;
  return response_json;
end
$function$;

CREATE OR REPLACE FUNCTION gymapp_private.social_send_workout_invite_direct_storage_v1(p_profile_id text, p_client_request_id uuid, p_workout jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_user_id uuid;
  target_user_id uuid;
  canonical_workout jsonb;
  workout_summary jsonb;
  sender_pending_count integer;
  recipient_pending_count integer;
  request_time timestamptz := pg_catalog.clock_timestamp();
begin
  caller_user_id := gymapp_private.social_require_caller('send_workout');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);
  if p_client_request_id is null
     or p_client_request_id::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;
  if p_workout is null then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;
  begin
    canonical_workout := gymapp_private.validate_social_workout(p_workout);
    workout_summary := gymapp_private.social_workout_summary(canonical_workout);
  exception
    when sqlstate '22023' or sqlstate '54000' then
      return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'gymapp-social-workout-request:' || caller_user_id::text || ':' || p_client_request_id::text,
      0
    )
  );
  perform invite.id
  from gymapp_private.social_workout_invites as invite
  where invite.sender_user_id = caller_user_id
    and invite.client_request_id = p_client_request_id;
  if found then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

  if p_profile_id is null or p_profile_id !~ '^p_[0-9a-f]{32}$' then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;
  select profile.user_id into target_user_id
  from public.profiles as profile
  where profile.public_id = p_profile_id;
  if not found or target_user_id = caller_user_id then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

  perform gymapp_private.social_lock_pair(caller_user_id, target_user_id);
  if not gymapp_private.social_pair_is_accepted(caller_user_id, target_user_id) then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;
  select pg_catalog.count(*)::integer into sender_pending_count
  from gymapp_private.social_workout_invites as invite
  where invite.sender_user_id = caller_user_id
    and invite.status = 'pending'
    and invite.expires_at > request_time;
  select pg_catalog.count(*)::integer into recipient_pending_count
  from gymapp_private.social_workout_invites as invite
  where invite.recipient_user_id = target_user_id
    and invite.status = 'pending'
    and invite.expires_at > request_time;
  if sender_pending_count >= 25 or recipient_pending_count >= 25 then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

  insert into gymapp_private.social_workout_invites (
    sender_user_id, recipient_user_id, client_request_id,
    status, workout, summary, revision,
    created_at, expires_at, responded_at, updated_at
  ) values (
    caller_user_id, target_user_id, p_client_request_id,
    'pending', canonical_workout, workout_summary, 1,
    request_time, request_time + interval '7 days', null, request_time
  );
  return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
end
$function$;

commit;
