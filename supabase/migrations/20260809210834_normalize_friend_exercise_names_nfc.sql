begin;

set local lock_timeout = '5s';
set local statement_timeout = '15min';

do $preflight$
begin
  if pg_catalog.to_regprocedure('gymapp_private.social_normalize_name(text)') is null
     or pg_catalog.to_regprocedure('gymapp_private.validate_social_workout(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_activity_from_state(jsonb)') is null
     or pg_catalog.to_regclass('gymapp_private.social_activity_projection') is null
     or pg_catalog.to_regclass('gymapp_private.social_workout_invites') is null then
    raise exception 'GymApp social schema must be active before NFC normalization.';
  end if;
end
$preflight$;

-- PostgreSQL's one-argument pg_catalog.normalize uses NFC. Normalize before
-- the existing case, whitespace, apostrophe, and Russian-yo folding so the
-- database and all three clients assign one identity to canonically equivalent
-- exercise names.
create or replace function gymapp_private.social_normalize_name(p_value text)
returns text
language sql
immutable
strict
security invoker
set search_path = ''
as $function$
  select pg_catalog.replace(
    pg_catalog.replace(
      pg_catalog.replace(
        pg_catalog.lower(
          pg_catalog.btrim(
            pg_catalog.regexp_replace(
              pg_catalog.normalize(p_value),
              '[[:space:]]+',
              ' ',
              'g'
            )
          )
        ),
        pg_catalog.chr(700),
        ''''
      ),
      pg_catalog.chr(8217),
      ''''
    ),
    'ё',
    'е'
  )
$function$;

revoke all on function gymapp_private.social_normalize_name(text)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_name_is_safe(p_value text)
returns boolean
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $function$
declare
  character_index integer;
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

revoke all on function gymapp_private.social_name_is_safe(text)
  from public, anon, authenticated, service_role;

do $contract$
declare
  composed_name text := 'Café';
  decomposed_name text := 'Cafe' || pg_catalog.chr(769);
  plain_space_name text := 'Bench';
  non_breaking_edge_name text := pg_catalog.chr(160) || 'Bench' || pg_catalog.chr(160);
  non_breaking_only_name text := pg_catalog.chr(160);
begin
  if gymapp_private.social_normalize_name(composed_name)
       is distinct from gymapp_private.social_normalize_name(decomposed_name) then
    raise exception 'GymApp social name normalization is not NFC-stable.';
  end if;

  if gymapp_private.social_normalize_name(plain_space_name)
       is distinct from gymapp_private.social_normalize_name(non_breaking_edge_name) then
    raise exception 'GymApp social name normalization is not edge-whitespace-stable.';
  end if;

  if gymapp_private.social_name_is_safe(non_breaking_only_name) then
    raise exception 'Whitespace-only social exercise names remain valid.';
  end if;

  begin
    perform gymapp_private.validate_social_workout(
      pg_catalog.jsonb_build_object(
        'version', 1,
        'exercises', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            'name', composed_name,
            'sets', pg_catalog.jsonb_build_array(
              pg_catalog.jsonb_build_object('weight', 10, 'reps', 5)
            )
          ),
          pg_catalog.jsonb_build_object(
            'name', decomposed_name,
            'sets', pg_catalog.jsonb_build_array(
              pg_catalog.jsonb_build_object('weight', 10, 'reps', 5)
            )
          )
        )
      )
    );
    raise exception 'Canonically equivalent workout names were accepted as distinct.';
  exception
    when sqlstate '22023' then null;
  end;

  begin
    perform gymapp_private.validate_social_workout(
      pg_catalog.jsonb_build_object(
        'version', 1,
        'exercises', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            'name', plain_space_name,
            'sets', pg_catalog.jsonb_build_array(
              pg_catalog.jsonb_build_object('weight', 10, 'reps', 5)
            )
          ),
          pg_catalog.jsonb_build_object(
            'name', non_breaking_edge_name,
            'sets', pg_catalog.jsonb_build_array(
              pg_catalog.jsonb_build_object('weight', 10, 'reps', 5)
            )
          )
        )
      )
    );
    raise exception 'Whitespace-equivalent workout names were accepted as distinct.';
  exception
    when sqlstate '22023' then null;
  end;

  if pg_catalog.has_function_privilege(
       'anon', 'gymapp_private.social_normalize_name(text)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', 'gymapp_private.social_normalize_name(text)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'gymapp_private.social_normalize_name(text)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'gymapp_private.social_name_is_safe(text)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', 'gymapp_private.social_name_is_safe(text)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'gymapp_private.social_name_is_safe(text)', 'EXECUTE'
     ) then
    raise exception 'Private social normalizer execution privileges widened.';
  end if;
end
$contract$;

-- Rebuild current safe projections with the corrected identity function. The
-- conflict predicate prevents an older snapshot from overwriting a concurrent
-- state-trigger projection with a newer source revision.
do $backfill$
declare
  state_row record;
  activity record;
begin
  for state_row in
    select state.user_id, state.state, state.updated_at
    from public.user_states as state
    join gymapp_private.user_state_progression as progression
      on progression.user_id = state.user_id
     and progression.source_revision = state.updated_at
    where not exists (
      select 1
      from gymapp_private.user_state_quarantine as quarantine
      where quarantine.user_id = state.user_id
    )
    order by state.user_id
  loop
    select * into strict activity
    from gymapp_private.social_activity_from_state(state_row.state);

    insert into gymapp_private.social_activity_projection (
      user_id, source_revision, recent_workouts, exercise_records, projected_at
    )
    select
      current_state.user_id,
      current_state.updated_at,
      activity.recent_workouts,
      activity.exercise_records,
      pg_catalog.clock_timestamp()
    from public.user_states as current_state
    join gymapp_private.user_state_progression as current_progression
      on current_progression.user_id = current_state.user_id
     and current_progression.source_revision = current_state.updated_at
    where current_state.user_id = state_row.user_id
      and current_state.updated_at = state_row.updated_at
      and not exists (
        select 1
        from gymapp_private.user_state_quarantine as current_quarantine
        where current_quarantine.user_id = current_state.user_id
      )
    on conflict (user_id) do update
    set source_revision = excluded.source_revision,
        recent_workouts = excluded.recent_workouts,
        exercise_records = excluded.exercise_records,
        projected_at = excluded.projected_at
    where gymapp_private.social_activity_projection.source_revision = excluded.source_revision;
  end loop;
end
$backfill$;

-- Tombstone any pre-release invite that was valid only under the old identity
-- rule. The feature has not shipped yet and the table is expected to be empty;
-- the one-time scan remains statement-time-bounded and locks one row at a time.
do $repair_invites$
declare
  invite_row record;
  repair_time timestamptz;
begin
  for invite_row in
    select invite.id, invite.workout
    from gymapp_private.social_workout_invites as invite
    where invite.workout is not null
    order by invite.id
    for update
  loop
    begin
      perform gymapp_private.validate_social_workout(invite_row.workout);
    exception
      when sqlstate '22023' or sqlstate '54000' then
        repair_time := pg_catalog.clock_timestamp();
        update gymapp_private.social_workout_invites as invite
        set status = case when invite.status = 'pending' then 'expired' else invite.status end,
            responded_at = coalesce(invite.responded_at, repair_time),
            workout = null,
            summary = null,
            payload_purged_at = repair_time,
            revision = case
              when invite.revision < 2147483647 then invite.revision + 1
              else invite.revision
            end,
            updated_at = repair_time
        where invite.id = invite_row.id;
    end;
  end loop;
end
$repair_invites$;

do $verify$
begin
  if exists (
    select 1
    from public.user_states as state
    join gymapp_private.user_state_progression as progression
      on progression.user_id = state.user_id
     and progression.source_revision = state.updated_at
    where not exists (
      select 1
      from gymapp_private.user_state_quarantine as quarantine
      where quarantine.user_id = state.user_id
    )
      and not exists (
        select 1
        from gymapp_private.social_activity_projection as projection
        where projection.user_id = state.user_id
          and projection.source_revision = state.updated_at
      )
  ) then
    raise exception 'A valid GymApp state is missing its NFC-safe social projection.';
  end if;

  if exists (
    select 1
    from gymapp_private.social_activity_projection as projection
    join gymapp_private.user_state_quarantine as quarantine using (user_id)
  ) then
    raise exception 'A quarantined state retained a social activity projection.';
  end if;
end
$verify$;

select pg_catalog.pg_notify('pgrst', 'reload schema');

commit;
