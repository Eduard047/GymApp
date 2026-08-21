-- Keep workout durations outside public.user_states. The released v2.2.9
-- workout envelope is intentionally strict, so adding a session key there
-- would make a new client's upload unreadable by an older client.
--
-- This owner-bound sidecar stores only a workout timestamp and bounded elapsed
-- seconds. Friend reads remain behind the existing accepted-friend and explicit
-- workout-detail sharing checks in social_friend_workout_page.

create table if not exists gymapp_private.workout_durations (
  user_id uuid not null references auth.users(id) on delete cascade,
  workout_started_at_millis bigint not null,
  duration_seconds integer not null,
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (user_id, workout_started_at_millis),
  constraint workout_durations_started_at_range check (
    workout_started_at_millis between -62135769600000 and 64092211200000
  ),
  constraint workout_durations_elapsed_range check (
    duration_seconds between 0 and 604800
  )
);

alter table gymapp_private.workout_durations enable row level security;

revoke all on table gymapp_private.workout_durations
  from public, anon, authenticated, service_role;

create or replace function public.social_sync_workout_durations(p_items jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  item_value jsonb;
  item_count integer;
  started_at_value numeric;
  duration_value numeric;
begin
  if caller_user_id is null
     or not gymapp_private.has_current_auth_session(caller_user_id) then
    raise exception using errcode = '42501', message = 'A live authenticated session is required.';
  end if;
  if pg_catalog.jsonb_typeof(p_items) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'Workout duration payload is invalid.';
  end if;

  item_count := pg_catalog.jsonb_array_length(p_items);
  if item_count > 5000 then
    raise exception using errcode = '22023', message = 'Workout duration payload is too large.';
  end if;

  for item_value in
    select entry.value
    from pg_catalog.jsonb_array_elements(p_items) as entry(value)
  loop
    if pg_catalog.jsonb_typeof(item_value) is distinct from 'object'
       or not item_value ?& array['workoutStartedAt', 'durationSeconds']
       or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(item_value)) <> 2
       or pg_catalog.jsonb_typeof(item_value->'workoutStartedAt') is distinct from 'number'
       or pg_catalog.jsonb_typeof(item_value->'durationSeconds') is distinct from 'number' then
      raise exception using errcode = '22023', message = 'Workout duration item is invalid.';
    end if;

    started_at_value := (item_value->>'workoutStartedAt')::numeric;
    duration_value := (item_value->>'durationSeconds')::numeric;
    if started_at_value <> pg_catalog.trunc(started_at_value)
       or started_at_value < -62135769600000
       or started_at_value > 64092211200000
       or duration_value <> pg_catalog.trunc(duration_value)
       or duration_value < 0
       or duration_value > 604800 then
      raise exception using errcode = '22023', message = 'Workout duration item is out of range.';
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
    raise exception using errcode = '22023', message = 'Workout duration payload contains duplicates.';
  end if;

  delete from gymapp_private.workout_durations as duration
  where duration.user_id = caller_user_id;

  insert into gymapp_private.workout_durations (
    user_id, workout_started_at_millis, duration_seconds, updated_at
  )
  select
    caller_user_id,
    (item.value->>'workoutStartedAt')::bigint,
    (item.value->>'durationSeconds')::integer,
    pg_catalog.clock_timestamp()
  from pg_catalog.jsonb_array_elements(p_items) as item(value);

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'syncedCount', item_count
  );
end
$function$;

revoke all on function public.social_sync_workout_durations(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.social_sync_workout_durations(jsonb)
  to authenticated;

alter function public.social_friend_workout_page(text, text, timestamptz, integer)
  rename to social_friend_workout_page_base_v1;

revoke all on function public.social_friend_workout_page_base_v1(
  text, text, timestamptz, integer
) from public, anon, authenticated, service_role;

create function public.social_friend_workout_page(
  p_profile_id text,
  p_cursor text default null,
  p_expected_activity_revision timestamptz default null,
  p_limit integer default 5
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  base_result jsonb;
  target_user_id uuid;
  enriched_items jsonb;
begin
  -- The base function performs live-session validation, rate limiting,
  -- accepted-friend authorization, block checks, sharing-consent checks,
  -- quarantine checks, and bounded workout projection.
  base_result := public.social_friend_workout_page_base_v1(
    p_profile_id,
    p_cursor,
    p_expected_activity_revision,
    p_limit
  );

  if pg_catalog.jsonb_typeof(base_result->'items') is distinct from 'array'
     or pg_catalog.jsonb_array_length(base_result->'items') = 0
     or pg_catalog.jsonb_typeof(base_result->'friend') is distinct from 'object' then
    return base_result;
  end if;

  select profile.user_id
  into target_user_id
  from public.profiles as profile
  where profile.public_id = base_result->'friend'->>'profileId';
  if not found then
    return base_result;
  end if;

  with response_items as (
    select
      item.ordinality,
      case when duration.duration_seconds is null then item.value
        else pg_catalog.jsonb_set(
          item.value,
          '{durationSeconds}',
          pg_catalog.to_jsonb(duration.duration_seconds),
          true
        )
      end as item_value
    from pg_catalog.jsonb_array_elements(base_result->'items')
      with ordinality as item(value, ordinality)
    left join gymapp_private.workout_durations as duration
      on duration.user_id = target_user_id
     and duration.workout_started_at_millis = (
       extract(epoch from (item.value->>'startedAt')::timestamptz) * 1000
     )::bigint
  )
  select pg_catalog.coalesce(
    pg_catalog.jsonb_agg(item.item_value order by item.ordinality),
    '[]'::jsonb
  )
  into enriched_items
  from response_items as item;

  return pg_catalog.jsonb_set(base_result, '{items}', enriched_items, false);
end
$function$;

revoke all on function public.social_friend_workout_page(
  text, text, timestamptz, integer
) from public, anon, authenticated, service_role;
grant execute on function public.social_friend_workout_page(
  text, text, timestamptz, integer
) to authenticated;

comment on function public.social_sync_workout_durations(jsonb) is
  'Atomically replaces the authenticated owner bounded workout-duration sidecar.';
comment on function public.social_friend_workout_page(text, text, timestamptz, integer) is
  'Accepted-friend-only, detail-consent-gated workout page with optional bounded durationSeconds.';

do $verify$
begin
  if pg_catalog.has_table_privilege(
       'authenticated', 'gymapp_private.workout_durations', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'gymapp_private.workout_durations', 'INSERT'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'public.social_sync_workout_durations(jsonb)', 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', 'public.social_sync_workout_durations(jsonb)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.social_friend_workout_page_base_v1(text,text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Workout duration privileges are invalid.';
  end if;
end
$verify$;
