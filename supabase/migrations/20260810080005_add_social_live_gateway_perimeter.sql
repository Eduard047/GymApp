begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regclass('auth.sessions') is null
     or pg_catalog.to_regclass('auth.users') is null then
    raise exception 'GymApp social/live gateway prerequisites are missing.';
  end if;
end
$preflight$;

create table gymapp_private.social_live_gateway_rate_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  bucket_action text not null check (bucket_action in (
    'social_dashboard', 'social_friend_details', 'social_send_friend_request',
    'social_respond_friend_request', 'social_cancel_friend_request',
    'social_remove_friend', 'social_block_profile', 'social_unblock_profile',
    'social_update_privacy', 'social_workout_inbox',
    'social_send_workout_invite', 'social_respond_workout_invite',
    'social_cancel_workout_invite',
    'live_inbox', 'live_send_invite', 'live_respond_invite', 'live_start',
    'live_snapshot', 'live_apply', 'live_finish', 'live_leave', 'live_cancel'
  )),
  tokens numeric(20, 9) not null check (tokens between 0 and 240),
  refilled_at timestamptz not null,
  primary key (user_id, bucket_action)
);

comment on table gymapp_private.social_live_gateway_rate_limits is
  'Durable Edge-perimeter token buckets. Each debit commits in its own PostgREST transaction before the domain RPC runs.';

alter table gymapp_private.social_live_gateway_rate_limits enable row level security;
revoke all on table gymapp_private.social_live_gateway_rate_limits
  from public, anon, authenticated, service_role;

create or replace function public.social_live_gateway_debit(
  p_user_id uuid,
  p_session_id uuid,
  p_action text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  bucket_capacity numeric(20, 9);
  refill_per_second numeric(20, 9);
  request_time timestamptz := pg_catalog.clock_timestamp();
  stored_tokens numeric(20, 9);
  stored_refilled_at timestamptz;
  available_tokens numeric(20, 9);
  retry_after integer;
begin
  select configuration.capacity, configuration.refill_rate
  into bucket_capacity, refill_per_second
  from (values
    ('social_dashboard', 120::numeric, 2::numeric),
    ('social_friend_details', 120::numeric, 2::numeric),
    ('social_send_friend_request', 12::numeric, (1::numeric / 300::numeric)),
    ('social_respond_friend_request', 30::numeric, (1::numeric / 30::numeric)),
    ('social_cancel_friend_request', 30::numeric, (1::numeric / 30::numeric)),
    ('social_remove_friend', 20::numeric, (1::numeric / 60::numeric)),
    ('social_block_profile', 30::numeric, (1::numeric / 30::numeric)),
    ('social_unblock_profile', 30::numeric, (1::numeric / 30::numeric)),
    ('social_update_privacy', 20::numeric, (1::numeric / 60::numeric)),
    ('social_workout_inbox', 120::numeric, 2::numeric),
    ('social_send_workout_invite', 10::numeric, (1::numeric / 360::numeric)),
    ('social_respond_workout_invite', 30::numeric, (1::numeric / 30::numeric)),
    ('social_cancel_workout_invite', 30::numeric, (1::numeric / 30::numeric)),
    ('live_inbox', 120::numeric, 2::numeric),
    ('live_send_invite', 10::numeric, (1::numeric / 360::numeric)),
    ('live_respond_invite', 30::numeric, (1::numeric / 30::numeric)),
    ('live_start', 30::numeric, (1::numeric / 30::numeric)),
    ('live_snapshot', 120::numeric, 2::numeric),
    ('live_apply', 240::numeric, 4::numeric),
    ('live_finish', 60::numeric, 1::numeric),
    ('live_leave', 30::numeric, (1::numeric / 30::numeric)),
    ('live_cancel', 30::numeric, (1::numeric / 30::numeric))
  ) as configuration(action, capacity, refill_rate)
  where configuration.action = p_action;

  if p_user_id is null
     or p_session_id is null
     or bucket_capacity is null then
    raise exception using errcode = '22023', message = 'Gateway debit request is invalid.';
  end if;

  -- The Edge Function obtained both values only after Auth getUser succeeded.
  -- Recheck the exact, still-live pair under a key-share lock so service-role
  -- execution never relies on auth.uid()/auth.jwt() from the service JWT.
  perform 1
  from auth.sessions as session
  where session.id = p_session_id
    and session.user_id = p_user_id
  for key share;
  if not found then
    raise exception using errcode = '42501', message = 'A current authenticated session is required.';
  end if;

  insert into gymapp_private.social_live_gateway_rate_limits (
    user_id, bucket_action, tokens, refilled_at
  ) values (
    p_user_id, p_action, bucket_capacity, request_time
  ) on conflict (user_id, bucket_action) do nothing;

  select bucket.tokens, bucket.refilled_at
  into strict stored_tokens, stored_refilled_at
  from gymapp_private.social_live_gateway_rate_limits as bucket
  where bucket.user_id = p_user_id
    and bucket.bucket_action = p_action
  for update;

  available_tokens := least(
    bucket_capacity,
    stored_tokens + greatest(
      extract(epoch from request_time - stored_refilled_at),
      0
    ) * refill_per_second
  );
  if available_tokens < 1 then
    retry_after := greatest(
      1,
      least(3600, pg_catalog.ceil((1 - available_tokens) / refill_per_second)::integer)
    );
    update gymapp_private.social_live_gateway_rate_limits as bucket
    set tokens = available_tokens,
        refilled_at = request_time
    where bucket.user_id = p_user_id
      and bucket.bucket_action = p_action;
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'allowed', false,
      'retryAfter', retry_after
    );
  end if;

  update gymapp_private.social_live_gateway_rate_limits as bucket
  set tokens = available_tokens - 1,
      refilled_at = request_time
  where bucket.user_id = p_user_id
    and bucket.bucket_action = p_action;
  return pg_catalog.jsonb_build_object('version', 1, 'allowed', true);
end
$function$;

revoke all on function public.social_live_gateway_debit(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.social_live_gateway_debit(uuid, uuid, text)
  to service_role;

do $verify$
begin
  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'gymapp_private'
      and relation.relname = 'social_live_gateway_rate_limits'
      and relation.relrowsecurity
  )
     or pg_catalog.has_table_privilege(
       'anon', 'gymapp_private.social_live_gateway_rate_limits', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'gymapp_private.social_live_gateway_rate_limits', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'service_role', 'gymapp_private.social_live_gateway_rate_limits', 'SELECT'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'public.social_live_gateway_debit(uuid,uuid,text)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', 'public.social_live_gateway_debit(uuid,uuid,text)', 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role', 'public.social_live_gateway_debit(uuid,uuid,text)', 'EXECUTE'
     ) then
    raise exception 'Social/live gateway perimeter grants are not least privilege.';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
