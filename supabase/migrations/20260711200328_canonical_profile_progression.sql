begin;

-- Canonical progression rules v1:
--   session XP = 90 + exercises * 16 + sets * 8 + round(volume / 80)
--   permanent XP = sum(session XP), with no calendar-sensitive bonuses
--   XP needed for a level = 200 + stage * 85 + stage^2 * 8
--
-- `user_states.state` is still client-authored workout data in phase 1, but XP,
-- level, and workout count are no longer trusted client assertions. Triggers
-- derive those public profile fields from the owner's stored state for both the
-- Android/iOS backup-v2 shape and the legacy PWA flat-session shape.

create schema if not exists gymapp_private;
revoke all on schema gymapp_private from public, anon, authenticated;

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
  total_set_count integer := 0;
  workout_count integer;
  session_volume numeric := 0;
  weight_value numeric;
  reps_value numeric;
  total_xp bigint := 0;
  session_xp bigint;
  progression_level integer := 1;
  remaining_xp bigint;
  level_stage bigint;
  level_requirement bigint;
begin
  if p_state is null or pg_catalog.jsonb_typeof(p_state) <> 'object' then
    raise exception using
      errcode = '22023',
      message = 'GymApp cloud state must be a JSON object.';
  end if;

  if p_state ? 'schemaVersion' then
    if pg_catalog.jsonb_typeof(p_state->'schemaVersion') <> 'number'
       or p_state->>'schemaVersion' <> '2' then
      raise exception using
        errcode = '22023',
        message = 'Unsupported GymApp cloud state schema version.';
    end if;
  end if;

  sessions_value := coalesce(p_state->'sessions', '[]'::jsonb);
  if pg_catalog.jsonb_typeof(sessions_value) <> 'array' then
    raise exception using
      errcode = '22023',
      message = 'GymApp cloud state sessions must be an array.';
  end if;

  workout_count := pg_catalog.jsonb_array_length(sessions_value);
  if workout_count > 5000 then
    raise exception using
      errcode = '54000',
      message = 'GymApp cloud state exceeds the workout limit.';
  end if;

  for session_value in
    select item.value
    from pg_catalog.jsonb_array_elements(sessions_value) as item(value)
  loop
    if pg_catalog.jsonb_typeof(session_value) <> 'object' then
      raise exception using
        errcode = '22023',
        message = 'Every GymApp workout must be a JSON object.';
    end if;

    session_exercise_count := 0;
    session_set_count := 0;
    session_volume := 0;

    if session_value ? 'exercises' then
      exercises_value := session_value->'exercises';
      if pg_catalog.jsonb_typeof(exercises_value) <> 'array' then
        raise exception using
          errcode = '22023',
          message = 'GymApp backup-v2 exercises must be an array.';
      end if;

      session_exercise_count := pg_catalog.jsonb_array_length(exercises_value);
      if session_exercise_count > 100 then
        raise exception using
          errcode = '54000',
          message = 'A GymApp workout exceeds the exercise limit.';
      end if;

      for exercise_value in
        select item.value
        from pg_catalog.jsonb_array_elements(exercises_value) as item(value)
      loop
        if pg_catalog.jsonb_typeof(exercise_value) <> 'object' then
          raise exception using
            errcode = '22023',
            message = 'Every GymApp workout exercise must be a JSON object.';
        end if;

        sets_value := coalesce(exercise_value->'sets', '[]'::jsonb);
        if pg_catalog.jsonb_typeof(sets_value) <> 'array' then
          raise exception using
            errcode = '22023',
            message = 'GymApp backup-v2 exercise sets must be an array.';
        end if;
        if pg_catalog.jsonb_array_length(sets_value) > 100 then
          raise exception using
            errcode = '54000',
            message = 'A GymApp exercise exceeds the set limit.';
        end if;

        for set_value in
          select item.value
          from pg_catalog.jsonb_array_elements(sets_value) as item(value)
        loop
          if pg_catalog.jsonb_typeof(set_value) <> 'object'
             or pg_catalog.jsonb_typeof(set_value->'weight') <> 'number'
             or pg_catalog.jsonb_typeof(set_value->'reps') <> 'number' then
            raise exception using
              errcode = '22023',
              message = 'Every GymApp set requires numeric weight and reps.';
          end if;

          weight_value := (set_value->>'weight')::numeric;
          reps_value := (set_value->>'reps')::numeric;
          if weight_value < 0 or weight_value > 1000000
             or reps_value <= 0 or reps_value > 10000
             or reps_value <> pg_catalog.trunc(reps_value) then
            raise exception using
              errcode = '22023',
              message = 'GymApp set values are outside the supported range.';
          end if;

          session_set_count := session_set_count + 1;
          total_set_count := total_set_count + 1;
          session_volume := session_volume + weight_value * reps_value;
        end loop;
      end loop;
    else
      -- Legacy PWA sessions keep one flat set array and an optional list of
      -- exercise names. Count the same distinct union that the PWA displays.
      sets_value := coalesce(session_value->'sets', '[]'::jsonb);
      if pg_catalog.jsonb_typeof(sets_value) <> 'array' then
        raise exception using
          errcode = '22023',
          message = 'Legacy GymApp session sets must be an array.';
      end if;

      exercise_names_value := coalesce(session_value->'exerciseNames', '[]'::jsonb);
      if pg_catalog.jsonb_typeof(exercise_names_value) <> 'array' then
        raise exception using
          errcode = '22023',
          message = 'Legacy GymApp exercise names must be an array.';
      end if;
      if pg_catalog.jsonb_array_length(exercise_names_value) > 100 then
        raise exception using
          errcode = '54000',
          message = 'A legacy GymApp workout exceeds the exercise-name limit.';
      end if;

      for exercise_name_value in
        select item.value
        from pg_catalog.jsonb_array_elements(exercise_names_value) as item(value)
      loop
        if pg_catalog.jsonb_typeof(exercise_name_value) <> 'string'
           or char_length(pg_catalog.btrim(exercise_name_value #>> '{}')) not between 1 and 160 then
          raise exception using
            errcode = '22023',
            message = 'Legacy GymApp exercise names must be non-empty strings.';
        end if;
      end loop;

      for set_value in
        select item.value
        from pg_catalog.jsonb_array_elements(sets_value) as item(value)
      loop
        if pg_catalog.jsonb_typeof(set_value) <> 'object'
           or pg_catalog.jsonb_typeof(set_value->'exerciseName') <> 'string'
           or char_length(pg_catalog.btrim(set_value->>'exerciseName')) not between 1 and 160
           or pg_catalog.jsonb_typeof(set_value->'weight') <> 'number'
           or pg_catalog.jsonb_typeof(set_value->'reps') <> 'number' then
          raise exception using
            errcode = '22023',
            message = 'Every legacy GymApp set requires an exercise name, weight, and reps.';
        end if;

        weight_value := (set_value->>'weight')::numeric;
        reps_value := (set_value->>'reps')::numeric;
        if weight_value < 0 or weight_value > 1000000
           or reps_value <= 0 or reps_value > 10000
           or reps_value <> pg_catalog.trunc(reps_value) then
          raise exception using
            errcode = '22023',
            message = 'Legacy GymApp set values are outside the supported range.';
        end if;

        session_set_count := session_set_count + 1;
        total_set_count := total_set_count + 1;
        session_volume := session_volume + weight_value * reps_value;
      end loop;

      select pg_catalog.count(distinct names.exercise_name)::integer
        into session_exercise_count
      from (
        select pg_catalog.btrim(item.value #>> '{}') as exercise_name
        from pg_catalog.jsonb_array_elements(exercise_names_value) as item(value)
        union all
        select pg_catalog.btrim(item.value->>'exerciseName') as exercise_name
        from pg_catalog.jsonb_array_elements(sets_value) as item(value)
      ) as names;

      if session_exercise_count > 100 then
        raise exception using
          errcode = '54000',
          message = 'A legacy GymApp workout exceeds the exercise limit.';
      end if;
    end if;

    if total_set_count > 100000 then
      raise exception using
        errcode = '54000',
        message = 'GymApp cloud state exceeds the total set limit.';
    end if;

    session_xp := 90
      + session_exercise_count::bigint * 16
      + session_set_count::bigint * 8
      + pg_catalog.round(session_volume / 80)::bigint;
    total_xp := total_xp + greatest(session_xp, 0::bigint);

    if total_xp > 2147483647 then
      raise exception using
        errcode = '22003',
        message = 'GymApp progression exceeds the supported XP range.';
    end if;
  end loop;

  remaining_xp := total_xp;
  loop
    level_stage := progression_level - 1;
    level_requirement := 200
      + level_stage * 85
      + level_stage * level_stage * 8;
    exit when remaining_xp < level_requirement;
    remaining_xp := remaining_xp - level_requirement;
    progression_level := progression_level + 1;
  end loop;

  return query
  select total_xp::integer, progression_level, workout_count;
end
$function$;

comment on function gymapp_private.progression_from_state(jsonb) is
  'Validates GymApp backup-v2 or legacy PWA state and derives canonical progression v1.';

revoke all on function gymapp_private.progression_from_state(jsonb)
  from public, anon, authenticated;

-- Abort before changing profile data if any existing state cannot be derived.
do $validate_existing_states$
declare
  state_row record;
begin
  for state_row in
    select user_id, state
    from public.user_states
  loop
    perform *
    from gymapp_private.progression_from_state(state_row.state);
  end loop;
end
$validate_existing_states$;

-- Backfill every existing profile. Profiles without a cloud-state row are an
-- empty progression until the first state save arrives.
with derived as materialized (
  select
    state.user_id,
    progression.xp,
    progression.level,
    progression.workouts
  from public.user_states as state
  cross join lateral gymapp_private.progression_from_state(state.state) as progression
)
update public.profiles as profile
set
  xp = coalesce(derived.xp, 0),
  level = coalesce(derived.level, 1),
  workouts = coalesce(derived.workouts, 0),
  progression_version = 1,
  updated_at = pg_catalog.clock_timestamp()
from (
  select
    profile_row.user_id,
    derived_row.xp,
    derived_row.level,
    derived_row.workouts
  from public.profiles as profile_row
  left join derived as derived_row using (user_id)
) as derived
where profile.user_id = derived.user_id;

create or replace function gymapp_private.guard_profile_progression()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  state_value jsonb;
  progression record;
begin
  if caller_user_id is not null and caller_user_id <> new.user_id then
    raise exception using
      errcode = '42501',
      message = 'A profile can only derive progression for its owner.';
  end if;

  select state.state
    into state_value
  from public.user_states as state
  where state.user_id = new.user_id;

  if state_value is null then
    new.xp := 0;
    new.level := 1;
    new.workouts := 0;
  else
    select *
      into strict progression
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

comment on function gymapp_private.guard_profile_progression() is
  'Overrides client-supplied profile XP, level, and workout count with canonical state-derived values.';

revoke all on function gymapp_private.guard_profile_progression()
  from public, anon, authenticated;

drop trigger if exists profiles_canonical_progression_guard on public.profiles;
create trigger profiles_canonical_progression_guard
before insert or update of user_id, xp, level, workouts
on public.profiles
for each row
execute function gymapp_private.guard_profile_progression();

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
  if caller_user_id is not null and caller_user_id <> owner_user_id then
    raise exception using
      errcode = '42501',
      message = 'Cloud state can only refresh its owner profile.';
  end if;

  if tg_op = 'DELETE' then
    update public.profiles
    set
      xp = 0,
      level = 1,
      workouts = 0,
      progression_version = 1,
      updated_at = pg_catalog.clock_timestamp()
    where user_id = owner_user_id;
    return old;
  end if;

  select *
    into strict progression
  from gymapp_private.progression_from_state(new.state);

  update public.profiles
  set
    xp = progression.xp,
    level = progression.level,
    workouts = progression.workouts,
    progression_version = 1,
    updated_at = pg_catalog.clock_timestamp()
  where user_id = new.user_id;

  return new;
end
$function$;

comment on function gymapp_private.refresh_profile_progression() is
  'Refreshes canonical public profile progression after an owner state write or deletion.';

revoke all on function gymapp_private.refresh_profile_progression()
  from public, anon, authenticated;

drop trigger if exists user_states_refresh_profile_progression on public.user_states;
create trigger user_states_refresh_profile_progression
after insert or update of user_id, state or delete
on public.user_states
for each row
execute function gymapp_private.refresh_profile_progression();

-- Fail closed if the backfill did not converge every stored profile.
do $verify_backfill$
declare
  mismatch_count integer;
begin
  select pg_catalog.count(*)::integer
    into mismatch_count
  from public.profiles as profile
  left join (
    select
      state.user_id,
      progression.xp,
      progression.level,
      progression.workouts
    from public.user_states as state
    cross join lateral gymapp_private.progression_from_state(state.state) as progression
  ) as derived using (user_id)
  where profile.xp <> coalesce(derived.xp, 0)
     or profile.level <> coalesce(derived.level, 1)
     or profile.workouts <> coalesce(derived.workouts, 0)
     or profile.progression_version <> 1;

  if mismatch_count <> 0 then
    raise exception 'Canonical GymApp progression backfill left % mismatched profiles', mismatch_count;
  end if;

  if has_function_privilege(
      'anon',
      'gymapp_private.progression_from_state(jsonb)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'gymapp_private.progression_from_state(jsonb)',
      'EXECUTE'
    )
    or has_function_privilege(
      'anon',
      'gymapp_private.guard_profile_progression()',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'gymapp_private.guard_profile_progression()',
      'EXECUTE'
    )
    or has_function_privilege(
      'anon',
      'gymapp_private.refresh_profile_progression()',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'gymapp_private.refresh_profile_progression()',
      'EXECUTE'
    ) then
    raise exception 'Canonical progression helper functions remain client-executable';
  end if;
end
$verify_backfill$;

notify pgrst, 'reload schema';

commit;
