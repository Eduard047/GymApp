begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
declare
  finish_owner text;
  validator_owner text;
begin
  if pg_catalog.to_regclass('gymapp_private.live_workout_progress') is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.live_workout_progress_is_valid(jsonb)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.social_finish_live_workout(uuid,uuid,text,uuid,bigint)'
     ) is null then
    raise exception 'Canonical live progress prerequisites are missing.';
  end if;

  if not exists (
       select 1
       from pg_catalog.pg_constraint as constraint_row
       where constraint_row.conrelid =
         'gymapp_private.live_workout_progress'::pg_catalog.regclass
         and constraint_row.conname = 'live_workout_progress_payload_check'
         and constraint_row.convalidated
     )
     or not exists (
       select 1
       from pg_catalog.pg_trigger as trigger_row
       where trigger_row.tgrelid =
         'gymapp_private.live_workout_progress'::pg_catalog.regclass
         and trigger_row.tgname = 'live_workout_progress_guard'
         and not trigger_row.tgisinternal
         and trigger_row.tgenabled = 'O'
     ) then
    raise exception 'Canonical live progress constraint or guard is missing.';
  end if;

  select procedure.proowner::text
    into strict finish_owner
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'public.social_finish_live_workout(uuid,uuid,text,uuid,bigint)'
  );
  select procedure.proowner::text
    into strict validator_owner
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'gymapp_private.live_workout_progress_is_valid(jsonb)'
  );
  perform pg_catalog.set_config(
    'gymapp_migration.live_finish_owner', finish_owner, true
  );
  perform pg_catalog.set_config(
    'gymapp_migration.live_progress_validator_owner', validator_owner, true
  );
end
$preflight$;

-- This short exclusive lock keeps the validator replacement, legacy-row
-- normalization, and finish-RPC replacement atomic with respect to live writes.
lock table gymapp_private.live_workout_progress in access exclusive mode;

create or replace function gymapp_private.live_workout_progress_is_valid(
  p_progress jsonb
)
returns boolean
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $function$
declare
  completed_set jsonb;
  set_id text;
  weight_value numeric;
  reps_value numeric;
  seen_set_ids jsonb := '{}'::jsonb;
  last_set_id text;
begin
  if pg_catalog.jsonb_typeof(p_progress) is distinct from 'object'
     or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_progress)) <> 4
     or not (p_progress ? 'version')
     or not (p_progress ? 'completedSets')
     or not (p_progress ? 'undoableSetId')
     or not (p_progress ? 'finishedAt')
     or pg_catalog.jsonb_typeof(p_progress->'version') is distinct from 'number'
     or (p_progress->>'version')::numeric <> 1
     or pg_catalog.jsonb_typeof(p_progress->'completedSets') is distinct from 'array'
     or pg_catalog.jsonb_array_length(p_progress->'completedSets') > 120
     or pg_catalog.pg_column_size(p_progress) > 65536 then
    return false;
  end if;

  if pg_catalog.jsonb_typeof(p_progress->'undoableSetId') not in ('null', 'string')
     or pg_catalog.jsonb_typeof(p_progress->'finishedAt') not in ('null', 'string') then
    return false;
  end if;
  if pg_catalog.jsonb_typeof(p_progress->'undoableSetId') = 'string'
     and (p_progress->>'undoableSetId') !~ '^s_[0-9]{2}_[0-9]{2}$' then
    return false;
  end if;
  if pg_catalog.jsonb_typeof(p_progress->'finishedAt') = 'string'
     and (
       pg_catalog.char_length(p_progress->>'finishedAt') not between 20 and 40
       or (p_progress->>'finishedAt') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T]'
     ) then
    return false;
  end if;

  for completed_set in
    select item.value
    from pg_catalog.jsonb_array_elements(p_progress->'completedSets') as item(value)
  loop
    if pg_catalog.jsonb_typeof(completed_set) is distinct from 'object'
       or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(completed_set)) <> 4
       or not (completed_set ? 'setId')
       or not (completed_set ? 'weight')
       or not (completed_set ? 'reps')
       or not (completed_set ? 'completedAt')
       or pg_catalog.jsonb_typeof(completed_set->'setId') is distinct from 'string'
       or pg_catalog.jsonb_typeof(completed_set->'weight') is distinct from 'number'
       or pg_catalog.jsonb_typeof(completed_set->'reps') is distinct from 'number'
       or pg_catalog.jsonb_typeof(completed_set->'completedAt') is distinct from 'string' then
      return false;
    end if;

    set_id := completed_set->>'setId';
    if set_id !~ '^s_[0-9]{2}_[0-9]{2}$'
       or seen_set_ids ? set_id
       or pg_catalog.char_length(completed_set->>'completedAt') not between 20 and 40
       or (completed_set->>'completedAt') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T]' then
      return false;
    end if;
    weight_value := (completed_set->>'weight')::numeric;
    reps_value := (completed_set->>'reps')::numeric;
    if weight_value not between 0 and 1000000
       or reps_value not between 1 and 10000
       or reps_value <> pg_catalog.trunc(reps_value) then
      return false;
    end if;
    seen_set_ids := seen_set_ids || pg_catalog.jsonb_build_object(set_id, true);
    last_set_id := set_id;
  end loop;

  -- Finished progress is sealed. Empty progress can never have an undo marker.
  -- For non-empty unfinished progress, a null marker is also canonical after
  -- server reconciliation; when present, the marker must name the latest set.
  if pg_catalog.jsonb_typeof(p_progress->'finishedAt') = 'string'
     and pg_catalog.jsonb_typeof(p_progress->'undoableSetId') <> 'null' then
    return false;
  end if;
  if pg_catalog.jsonb_array_length(p_progress->'completedSets') = 0 then
    return pg_catalog.jsonb_typeof(p_progress->'undoableSetId') = 'null';
  end if;
  if pg_catalog.jsonb_typeof(p_progress->'undoableSetId') = 'null' then
    return true;
  end if;
  return p_progress->>'undoableSetId' = last_set_id;
exception
  when data_exception then
    return false;
end
$function$;

revoke all on function gymapp_private.live_workout_progress_is_valid(jsonb)
  from public, anon, authenticated, service_role;

do $bound_backfill$
declare
  candidate_count integer;
begin
  select pg_catalog.count(*)
    into candidate_count
  from (
    select 1
    from gymapp_private.live_workout_progress as progress
    where pg_catalog.jsonb_typeof(progress.payload->'finishedAt') = 'string'
      and pg_catalog.jsonb_typeof(progress.payload->'undoableSetId') = 'string'
    limit 10001
  ) as candidates;

  if candidate_count > 10000 then
    raise exception
      'Canonical finished live-progress backfill exceeds the 10000-row safety bound.';
  end if;
end
$bound_backfill$;

-- The normal guard correctly forbids mutation after membership finishes. The
-- access-exclusive lock makes this migration-only trigger bypass race-free,
-- and transaction rollback restores the trigger automatically on any failure.
alter table gymapp_private.live_workout_progress
  disable trigger live_workout_progress_guard;

update gymapp_private.live_workout_progress as progress
set payload = pg_catalog.jsonb_set(
      progress.payload,
      '{undoableSetId}',
      'null'::jsonb,
      false
    )
where pg_catalog.jsonb_typeof(progress.payload->'finishedAt') = 'string'
  and pg_catalog.jsonb_typeof(progress.payload->'undoableSetId') = 'string';

alter table gymapp_private.live_workout_progress
  enable trigger live_workout_progress_guard;

do $verify_backfill$
begin
  if exists (
       select 1
       from gymapp_private.live_workout_progress as progress
       where not gymapp_private.live_workout_progress_is_valid(progress.payload)
     )
     or not exists (
       select 1
       from pg_catalog.pg_trigger as trigger_row
       where trigger_row.tgrelid =
         'gymapp_private.live_workout_progress'::pg_catalog.regclass
         and trigger_row.tgname = 'live_workout_progress_guard'
         and not trigger_row.tgisinternal
         and trigger_row.tgenabled = 'O'
     ) then
    raise exception 'Canonical live progress backfill or guard restoration failed.';
  end if;
end
$verify_backfill$;

create or replace function public.social_finish_live_workout(
  p_caller_user_id uuid,
  p_session_id uuid,
  p_room_id text,
  p_client_operation_id uuid,
  p_expected_progress_revision bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  peer_user_id uuid;
  room_row record;
  caller_member record;
  progress_row record;
  request_json jsonb;
  result_json jsonb;
  replayed_result jsonb;
  all_finished boolean;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  perform gymapp_private.live_gateway_require_session(p_caller_user_id, p_session_id);
  if p_room_id is null or p_room_id !~ '^lr_[0-9a-f]{32}$'
     or p_client_operation_id is null
     or p_expected_progress_revision is null
     or p_expected_progress_revision not between 1 and 2147483647 then
    raise exception using errcode = '22023', message = 'Live workout finish is invalid.';
  end if;
  request_json := pg_catalog.jsonb_build_object(
    'kind', 'finish', 'expectedProgressRevision', p_expected_progress_revision
  );
  peer_user_id := gymapp_private.live_workout_lock_pair_for_room(
    p_room_id, p_caller_user_id
  );
  select room.* into strict room_row
  from gymapp_private.live_workout_rooms as room
  where room.id = p_room_id
  for update;
  perform 1
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
  order by member.user_id
  for update;
  select member.* into strict caller_member
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
    and member.user_id = p_caller_user_id;
  select progress.* into strict progress_row
  from gymapp_private.live_workout_progress as progress
  where progress.room_id = p_room_id
    and progress.user_id = p_caller_user_id
  for update;

  if not gymapp_private.social_pair_is_accepted(p_caller_user_id, peer_user_id) then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  replayed_result := gymapp_private.live_workout_receipt_replay(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json
  );
  if replayed_result is not null then
    return replayed_result;
  end if;
  if room_row.status = 'active'
     and room_row.active_expires_at <= mutation_time then
    update gymapp_private.live_workout_rooms as room
    set status = 'expired', close_reason = 'expired',
        revision = room.revision + 1, ended_at = mutation_time,
        last_activity_at = greatest(room.last_activity_at, mutation_time),
        updated_at = mutation_time
    where room.id = p_room_id
    returning * into strict room_row;
    update gymapp_private.live_workout_members as member
    set state = 'revoked', revision = member.revision + 1,
        departed_at = mutation_time, updated_at = mutation_time
    where member.room_id = p_room_id
      and member.state = 'joined';
    result_json := pg_catalog.jsonb_build_object(
      'version', 1, 'result', 'closed', 'roomId', room_row.id,
      'status', room_row.status, 'roomRevision', room_row.revision,
      'endedAt', room_row.ended_at
    );
    perform gymapp_private.live_workout_store_receipt(
      p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
    );
    return result_json;
  end if;
  if room_row.status <> 'active'
     or caller_member.state <> 'joined'
     or progress_row.payload->>'finishedAt' is not null then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  if progress_row.revision <> p_expected_progress_revision
     or progress_row.revision >= 2147483647
     or caller_member.revision >= 2147483647
     or room_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Live workout progress changed.';
  end if;

  -- Progress must finish while the caller is still joined and the room active;
  -- the storage guard intentionally rejects the reverse order. Sealing clears
  -- the undo marker in the same guarded revision update as finishedAt.
  update gymapp_private.live_workout_progress as progress
  set payload = progress.payload || pg_catalog.jsonb_build_object(
        'undoableSetId', null,
        'finishedAt', mutation_time
      ),
      revision = progress.revision + 1,
      updated_at = mutation_time
  where progress.room_id = p_room_id
    and progress.user_id = p_caller_user_id
  returning * into strict progress_row;
  update gymapp_private.live_workout_members as member
  set state = 'finished', revision = member.revision + 1,
      finished_at = mutation_time, updated_at = mutation_time
  where member.room_id = p_room_id
    and member.user_id = p_caller_user_id
  returning * into strict caller_member;

  select pg_catalog.bool_and(member.state = 'finished')
  into all_finished
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id;
  update gymapp_private.live_workout_rooms as room
  set status = case when all_finished then 'completed' else room.status end,
      close_reason = case when all_finished then 'completed' else null end,
      revision = room.revision + 1,
      ended_at = case when all_finished then mutation_time else null end,
      last_activity_at = greatest(room.last_activity_at, mutation_time),
      updated_at = mutation_time
  where room.id = p_room_id
  returning * into strict room_row;

  result_json := pg_catalog.jsonb_build_object(
    'version', 1, 'result', 'finished', 'roomId', room_row.id,
    'status', room_row.status, 'roomRevision', room_row.revision,
    'progressRevision', progress_row.revision,
    'membershipRevision', caller_member.revision,
    'finishedAt', mutation_time
  );
  perform gymapp_private.live_workout_store_receipt(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
  );
  return result_json;
end
$function$;

revoke all on function public.social_finish_live_workout(uuid, uuid, text, uuid, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.social_finish_live_workout(uuid, uuid, text, uuid, bigint)
  to service_role;

comment on function public.social_finish_live_workout(uuid, uuid, text, uuid, bigint) is
  'Service-gateway-only caller finish. Progress clears its undo marker and seals before membership and room lifecycle advance.';

do $verify$
declare
  finish_function record;
  validator_function record;
  completed_set jsonb := pg_catalog.jsonb_build_object(
    'setId', 's_01_01',
    'weight', 80,
    'reps', 8,
    'completedAt', '2026-08-10T09:00:00Z'
  );
begin
  select procedure.*
    into strict finish_function
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'public.social_finish_live_workout(uuid,uuid,text,uuid,bigint)'
  );
  select procedure.*
    into strict validator_function
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'gymapp_private.live_workout_progress_is_valid(jsonb)'
  );

  if finish_function.proowner::text <>
       pg_catalog.current_setting('gymapp_migration.live_finish_owner')
     or validator_function.proowner::text <>
       pg_catalog.current_setting('gymapp_migration.live_progress_validator_owner')
     or not finish_function.prosecdef
     or finish_function.provolatile <> 'v'
     or not (finish_function.proconfig @> array['search_path=""'])
     or validator_function.prosecdef
     or validator_function.provolatile <> 'i'
     or not (validator_function.proconfig @> array['search_path=""']) then
    raise exception 'Canonical live progress function security contract changed.';
  end if;

  if pg_catalog.has_function_privilege(
       'anon',
       'public.social_finish_live_workout(uuid,uuid,text,uuid,bigint)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.social_finish_live_workout(uuid,uuid,text,uuid,bigint)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.social_finish_live_workout(uuid,uuid,text,uuid,bigint)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'gymapp_private.live_workout_progress_is_valid(jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Canonical live progress function grants changed.';
  end if;

  if not gymapp_private.live_workout_progress_is_valid(
       pg_catalog.jsonb_build_object(
         'version', 1,
         'completedSets', pg_catalog.jsonb_build_array(),
         'undoableSetId', null,
         'finishedAt', null
       )
     )
     or not gymapp_private.live_workout_progress_is_valid(
       pg_catalog.jsonb_build_object(
         'version', 1,
         'completedSets', pg_catalog.jsonb_build_array(completed_set),
         'undoableSetId', null,
         'finishedAt', '2026-08-10T09:05:00Z'
       )
     )
     or not gymapp_private.live_workout_progress_is_valid(
       pg_catalog.jsonb_build_object(
         'version', 1,
         'completedSets', pg_catalog.jsonb_build_array(completed_set),
         'undoableSetId', null,
         'finishedAt', null
       )
     )
     or gymapp_private.live_workout_progress_is_valid(
       pg_catalog.jsonb_build_object(
         'version', 1,
         'completedSets', pg_catalog.jsonb_build_array(completed_set),
         'undoableSetId', 's_01_01',
         'finishedAt', '2026-08-10T09:05:00Z'
       )
     ) then
    raise exception 'Canonical finished live progress validation failed.';
  end if;
end
$verify$;

commit;
