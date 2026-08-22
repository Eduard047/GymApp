-- PostgreSQL implements COALESCE as syntax rather than a schema-qualified
-- function. The duration wrapper introduced in 20260821200800 used
-- pg_catalog.coalesce, which compiled when the function was created but failed
-- when an authorized friend page contained at least one workout item.

create or replace function public.social_friend_workout_page(
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
  select coalesce(
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

comment on function public.social_friend_workout_page(text, text, timestamptz, integer) is
  'Accepted-friend-only, detail-consent-gated workout page with optional bounded durationSeconds.';

do $verify$
begin
  if pg_catalog.has_function_privilege(
       'anon',
       'public.social_friend_workout_page(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.social_friend_workout_page(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.social_friend_workout_page_base_v1(text,text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Friend workout duration enrichment privileges are invalid.';
  end if;
end
$verify$;
