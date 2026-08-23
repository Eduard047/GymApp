begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regclass('gymapp_private.workout_durations') is null
     or pg_catalog.to_regprocedure(
       'public.social_sync_workout_durations(jsonb)'
     ) is null then
    raise exception 'GymApp workout-duration synchronization prerequisites are missing.';
  end if;
end
$preflight$;

create table gymapp_private.workout_duration_sync_budgets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  tokens numeric(20, 6) not null check (tokens between 0 and 600),
  refilled_at timestamptz not null
);

alter table gymapp_private.workout_duration_sync_budgets enable row level security;
revoke all on table gymapp_private.workout_duration_sync_budgets
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.consume_workout_duration_sync_budget(
  p_user_id uuid,
  p_cost numeric
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  request_time timestamptz := pg_catalog.clock_timestamp();
  capacity constant numeric := 600;
  refill_per_second constant numeric := 1;
  stored_tokens numeric;
  stored_refilled_at timestamptz;
  available_tokens numeric;
begin
  if p_user_id is null
     or p_cost is null
     or p_cost < 1
     or p_cost > capacity then
    raise exception using errcode = '22023', message = 'Workout duration sync cost is invalid.';
  end if;

  insert into gymapp_private.workout_duration_sync_budgets (
    user_id, tokens, refilled_at
  ) values (
    p_user_id, capacity, request_time
  ) on conflict (user_id) do nothing;

  select budget.tokens, budget.refilled_at
  into strict stored_tokens, stored_refilled_at
  from gymapp_private.workout_duration_sync_budgets as budget
  where budget.user_id = p_user_id
  for update;

  available_tokens := least(
    capacity,
    stored_tokens + greatest(
      0,
      extract(epoch from request_time - stored_refilled_at)
    ) * refill_per_second
  );
  if available_tokens < p_cost then
    update gymapp_private.workout_duration_sync_budgets as budget
    set tokens = available_tokens,
        refilled_at = request_time
    where budget.user_id = p_user_id;
    return greatest(
      1,
      least(600, pg_catalog.ceil(p_cost - available_tokens)::integer)
    );
  end if;

  update gymapp_private.workout_duration_sync_budgets as budget
  set tokens = available_tokens - p_cost,
      refilled_at = request_time
  where budget.user_id = p_user_id;
  return 0;
end
$function$;

revoke all on function gymapp_private.consume_workout_duration_sync_budget(uuid, numeric)
  from public, anon, authenticated, service_role;

create or replace function public.social_sync_workout_durations(p_items jsonb)
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
  payload_bytes integer := pg_catalog.coalesce(pg_catalog.pg_column_size(p_items), 0);
  request_cost numeric;
  retry_after integer;
  deleted_count integer := 0;
  upserted_count integer := 0;
begin
  if caller_user_id is null
     or not gymapp_private.current_auth_session_is_live() then
    raise exception using errcode = '42501', message = 'A live authenticated session is required.';
  end if;

  -- Serialize one owner's snapshot replacements before any expansion or write.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'gymapp-workout-duration-sync:' || caller_user_id::text,
      0
    )
  );

  if pg_catalog.jsonb_typeof(p_items) is distinct from 'array' then
    request_cost := greatest(1, pg_catalog.ceil(payload_bytes::numeric / 4096));
    retry_after := gymapp_private.consume_workout_duration_sync_budget(
      caller_user_id,
      least(request_cost, 600)
    );
    return pg_catalog.jsonb_build_object(
      'version', 2,
      'error', case when retry_after > 0 then 'rate_limited' else 'invalid_payload' end,
      'retryAfter', case when retry_after > 0 then retry_after else 0 end
    );
  end if;

  item_count := pg_catalog.jsonb_array_length(p_items);
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
      'version', 2,
      'error', 'rate_limited',
      'retryAfter', retry_after
    );
  end if;
  if payload_bytes > 262144 or item_count > 5000 then
    return pg_catalog.jsonb_build_object(
      'version', 2,
      'error', 'invalid_payload',
      'retryAfter', 0
    );
  end if;

  for item_value in
    select entry.value
    from pg_catalog.jsonb_array_elements(p_items) as entry(value)
  loop
    if pg_catalog.jsonb_typeof(item_value) is distinct from 'object'
       or not item_value ?& array['workoutStartedAt', 'durationSeconds']
       or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(item_value)) <> 2
       or pg_catalog.jsonb_typeof(item_value->'workoutStartedAt') is distinct from 'number'
       or pg_catalog.jsonb_typeof(item_value->'durationSeconds') is distinct from 'number'
       or item_value->>'workoutStartedAt' !~ '^-?(0|[1-9][0-9]{0,14})$'
       or item_value->>'durationSeconds' !~ '^(0|[1-9][0-9]{0,6})$'
       or (item_value->>'workoutStartedAt')::numeric < -62135769600000
       or (item_value->>'workoutStartedAt')::numeric > 64092211200000
       or (item_value->>'durationSeconds')::numeric > 604800 then
      return pg_catalog.jsonb_build_object(
        'version', 2,
        'error', 'invalid_payload',
        'retryAfter', 0
      );
    end if;
  end loop;

  if (
    select pg_catalog.count(*)
    from (
      select item.value->>'workoutStartedAt' as started_at
      from pg_catalog.jsonb_array_elements(p_items) as item(value)
      group by item.value->>'workoutStartedAt'
    ) as distinct_items
  ) <> item_count then
    return pg_catalog.jsonb_build_object(
      'version', 2,
      'error', 'invalid_payload',
      'retryAfter', 0
    );
  end if;

  delete from gymapp_private.workout_durations as duration
  where duration.user_id = caller_user_id
    and not exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_items) as item(value)
      where (item.value->>'workoutStartedAt')::bigint =
        duration.workout_started_at_millis
    );
  get diagnostics deleted_count = row_count;

  insert into gymapp_private.workout_durations (
    user_id, workout_started_at_millis, duration_seconds, updated_at
  )
  select
    caller_user_id,
    (item.value->>'workoutStartedAt')::bigint,
    (item.value->>'durationSeconds')::integer,
    pg_catalog.clock_timestamp()
  from pg_catalog.jsonb_array_elements(p_items) as item(value)
  on conflict (user_id, workout_started_at_millis) do update
  set duration_seconds = excluded.duration_seconds,
      updated_at = excluded.updated_at
  where gymapp_private.workout_durations.duration_seconds
    is distinct from excluded.duration_seconds;
  get diagnostics upserted_count = row_count;

  return pg_catalog.jsonb_build_object(
    'version', 2,
    'syncedCount', item_count,
    'changedCount', deleted_count + upserted_count
  );
end
$function$;

revoke all on function public.social_sync_workout_durations(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.social_sync_workout_durations(jsonb)
  to authenticated;

comment on function public.social_sync_workout_durations(jsonb) is
  'Owner-serialized, byte-bounded, durably budgeted differential workout-duration synchronization.';

notify pgrst, 'reload schema';

commit;
