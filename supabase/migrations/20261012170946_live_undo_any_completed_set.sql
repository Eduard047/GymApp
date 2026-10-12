begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

-- Live-workout undo is widened from "latest own set only" to "any own
-- completed set". The function keeps its signature, security-definer
-- settings, empty search_path, service-role-only grants, input bounds,
-- receipt replay, lifecycle checks and progress CAS. The progress payload
-- format is unchanged: after removing one set, undoableSetId names the latest
-- remaining set (or null), which the live_workout_progress_is_valid CHECK and
-- every client snapshot validator already require.
--
-- Recovery: re-apply the function body from
-- 20260810075721_activate_live_shared_workout_api.sql. No rows change.
do $preflight$
begin
  if pg_catalog.to_regprocedure(
       'public.social_apply_live_workout_operation(uuid,uuid,text,uuid,bigint,jsonb)'
     ) is null
     or pg_catalog.to_regprocedure('gymapp_private.live_workout_progress_is_valid(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.live_workout_receipt_replay(text,uuid,uuid,jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.live_workout_store_receipt(text,uuid,uuid,jsonb,jsonb)') is null then
    raise exception 'GymApp live-workout apply prerequisites are missing.';
  end if;
end
$preflight$;

create or replace function public.social_apply_live_workout_operation(
  p_caller_user_id uuid,
  p_session_id uuid,
  p_room_id text,
  p_client_operation_id uuid,
  p_expected_progress_revision bigint,
  p_operation jsonb
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
  operation_kind text;
  set_id text;
  weight_value numeric;
  reps_value numeric;
  completed_sets jsonb;
  previous_set_id text;
  completion_time timestamptz;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  perform gymapp_private.live_gateway_require_session(p_caller_user_id, p_session_id);
  if p_room_id is null or p_room_id !~ '^lr_[0-9a-f]{32}$'
     or p_client_operation_id is null
     or p_expected_progress_revision is null
     or p_expected_progress_revision not between 1 and 2147483647
     or p_operation is null
     or pg_catalog.jsonb_typeof(p_operation) is distinct from 'object'
     or pg_catalog.pg_column_size(p_operation) > 4096
     or pg_catalog.jsonb_typeof(p_operation->'kind') is distinct from 'string'
     or pg_catalog.jsonb_typeof(p_operation->'setId') is distinct from 'string' then
    raise exception using errcode = '22023', message = 'Live workout operation is invalid.';
  end if;
  operation_kind := p_operation->>'kind';
  set_id := p_operation->>'setId';
  if set_id !~ '^s_[0-9]{2}_[0-9]{2}$'
     or operation_kind not in ('complete_set', 'undo_set') then
    raise exception using errcode = '22023', message = 'Live workout operation is invalid.';
  end if;

  if operation_kind = 'complete_set' then
    if (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_operation)) <> 4
       or not (p_operation ? 'weight')
       or not (p_operation ? 'reps')
       or pg_catalog.jsonb_typeof(p_operation->'weight') is distinct from 'number'
       or pg_catalog.jsonb_typeof(p_operation->'reps') is distinct from 'number' then
      raise exception using errcode = '22023', message = 'Live workout completion is invalid.';
    end if;
    weight_value := (p_operation->>'weight')::numeric;
    reps_value := (p_operation->>'reps')::numeric;
    if weight_value not between 0 and 1000000
       or reps_value not between 1 and 10000
       or reps_value <> pg_catalog.trunc(reps_value) then
      raise exception using errcode = '22023', message = 'Live workout completion values are invalid.';
    end if;
  elsif (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_operation)) <> 2 then
    raise exception using errcode = '22023', message = 'Live workout undo is invalid.';
  end if;

  request_json := pg_catalog.jsonb_build_object(
    'kind', 'apply',
    'expectedProgressRevision', p_expected_progress_revision,
    'operation', p_operation
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
     or room_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Live workout progress changed.';
  end if;
  if not exists (
    select 1
    from pg_catalog.jsonb_array_elements(room_row.plan->'exercises') as exercise(value)
    cross join lateral pg_catalog.jsonb_array_elements(exercise.value->'sets') as set_item(value)
    where set_item.value->>'setId' = set_id
  ) then
    raise exception using errcode = '22023', message = 'Live workout set is invalid.';
  end if;

  if operation_kind = 'complete_set' then
    if exists (
      select 1
      from pg_catalog.jsonb_array_elements(progress_row.payload->'completedSets') as completed(value)
      where completed.value->>'setId' = set_id
    ) then
      raise exception using errcode = 'P0001', message = 'Live workout set was already completed.';
    end if;
    if pg_catalog.jsonb_array_length(progress_row.payload->'completedSets') >= 120 then
      raise exception using errcode = 'P0001', message = 'Live workout progress is full.';
    end if;
    completion_time := mutation_time;
    completed_sets := progress_row.payload->'completedSets'
      || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'setId', set_id,
        'weight', case when weight_value = 0 then 0 else weight_value end,
        'reps', reps_value::integer,
        'completedAt', completion_time
      ));
  else
    -- Any own completed set may be undone, not only the latest. The set must
    -- be present in this caller's own progress; the payload shape and the
    -- "marker names the latest remaining set" invariant are unchanged.
    if not exists (
      select 1
      from pg_catalog.jsonb_array_elements(progress_row.payload->'completedSets') as completed(value)
      where completed.value->>'setId' = set_id
    ) then
      raise exception using errcode = 'P0001', message = 'Live workout set is not completed.';
    end if;
    select coalesce(
      pg_catalog.jsonb_agg(completed.value order by completed.ordinality),
      '[]'::jsonb
    )
    into completed_sets
    from pg_catalog.jsonb_array_elements(progress_row.payload->'completedSets')
      with ordinality as completed(value, ordinality)
    where completed.value->>'setId' is distinct from set_id;
    if pg_catalog.jsonb_array_length(completed_sets) > 0 then
      previous_set_id := completed_sets -> -1 ->> 'setId';
    end if;
  end if;

  update gymapp_private.live_workout_progress as progress
  set payload = pg_catalog.jsonb_build_object(
        'version', 1,
        'completedSets', completed_sets,
        'undoableSetId', case when operation_kind = 'complete_set'
          then set_id else previous_set_id end,
        'finishedAt', null
      ),
      revision = progress.revision + 1,
      updated_at = mutation_time
  where progress.room_id = p_room_id
    and progress.user_id = p_caller_user_id
  returning * into strict progress_row;

  update gymapp_private.live_workout_rooms as room
  set revision = room.revision + 1,
      last_activity_at = greatest(room.last_activity_at, mutation_time),
      updated_at = mutation_time
  where room.id = p_room_id
  returning * into strict room_row;

  result_json := pg_catalog.jsonb_build_object(
    'version', 1, 'result', 'applied', 'roomId', room_row.id,
    'roomRevision', room_row.revision,
    'progressRevision', progress_row.revision,
    'kind', operation_kind,
    'setId', set_id,
    'completedAt', completion_time
  );
  perform gymapp_private.live_workout_store_receipt(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
  );
  return result_json;
end
$function$;

revoke all on function public.social_apply_live_workout_operation(uuid, uuid, text, uuid, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.social_apply_live_workout_operation(uuid, uuid, text, uuid, bigint, jsonb)
  to service_role;

comment on function public.social_apply_live_workout_operation(uuid, uuid, text, uuid, bigint, jsonb) is
  'Service-gateway-only caller-owned complete/undo operation (undo accepts any own completed set) with progress CAS and idempotency receipt.';

do $verify$
declare
  rpc_signature constant text :=
    'public.social_apply_live_workout_operation(uuid,uuid,text,uuid,bigint,jsonb)';
begin
  if not exists (
       select 1
       from pg_catalog.pg_proc as proc
       where proc.oid = rpc_signature::regprocedure
         and proc.prosecdef
         and proc.proconfig @> array['search_path=""']
     )
     or pg_catalog.has_function_privilege('anon', rpc_signature, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', rpc_signature, 'EXECUTE')
     or not pg_catalog.has_function_privilege('service_role', rpc_signature, 'EXECUTE') then
    raise exception 'Live-workout apply RPC is not exactly service-gateway-only.';
  end if;
end
$verify$;

select pg_catalog.pg_notify('pgrst', 'reload schema');

commit;
