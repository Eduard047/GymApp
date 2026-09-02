begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
declare
  rpc_signature text;
begin
  if pg_catalog.to_regclass('auth.sessions') is null
     or pg_catalog.to_regclass(
       'gymapp_private.edge_preauth_windows'
     ) is null
     or pg_catalog.to_regclass(
       'gymapp_private.account_deletion_grants'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.has_current_auth_session(uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.garmin_list_devices()'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.require_live_session_for_account_deletion()'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.realtime_has_current_auth_session()'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.live_gateway_require_session(uuid,uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.social_live_gateway_debit_storage_v1(uuid,uuid,text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.social_domain_error_response(text,text,text,text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.social_update_workout_detail_privacy(boolean,bigint)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.social_friend_workout_detail_capability(text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.social_friend_workout_page(text,text,timestamptz,integer)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.social_friend_workout_page_base_v1(text,text,timestamptz,integer)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.social_workout_inbox_page(timestamptz,text,boolean,integer)'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.dispatch_push_notifications()'
     ) is null then
    raise exception 'GymApp deep-scan remediation prerequisites are missing.';
  end if;

  foreach rpc_signature in array array[
    'public.social_dashboard()',
    'public.social_friend_details(text)',
    'public.social_send_friend_request(text)',
    'public.social_respond_friend_request(text,text,bigint)',
    'public.social_cancel_friend_request(text,bigint)',
    'public.social_remove_friend(text,bigint)',
    'public.social_block_profile(text)',
    'public.social_unblock_profile(text)',
    'public.social_update_privacy(boolean,boolean,boolean,boolean,bigint)',
    'public.social_send_workout_invite(text,uuid,jsonb)',
    'public.social_workout_inbox()',
    'public.social_respond_workout_invite(text,text,bigint)',
    'public.social_cancel_workout_invite(text,bigint)',
    'public.social_workout_detail_privacy()',
    'public.social_workout_invite_plan(text,bigint)'
  ] loop
    if pg_catalog.to_regprocedure(rpc_signature) is null then
      raise exception 'GymApp direct social RPC % is missing.', rpc_signature;
    end if;
  end loop;
end
$preflight$;

-- Every write authorized by an exact Auth session must retain a key-share
-- lock until commit. Read-only PostgREST requests cannot acquire row locks, so
-- they keep the same bounded existence check without weakening write ordering.
create or replace function gymapp_private.has_current_auth_session(
  p_user_id uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  session_id_text text := auth.jwt() ->> 'session_id';
begin
  if p_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;

  if pg_catalog.current_setting('transaction_read_only')::boolean then
    return exists (
      select 1
      from auth.sessions as session
      where session.id = session_id_text::uuid
        and session.user_id = p_user_id
        and (
          session.not_after is null
          or session.not_after > pg_catalog.clock_timestamp()
        )
    );
  end if;

  perform 1
  from auth.sessions as session
  where session.id = session_id_text::uuid
    and session.user_id = p_user_id
    and (
      session.not_after is null
      or session.not_after > pg_catalog.clock_timestamp()
    )
  for key share;
  return found;
end
$function$;

revoke all on function gymapp_private.has_current_auth_session(uuid)
  from public, anon, authenticated, service_role;

comment on function gymapp_private.has_current_auth_session(uuid) is
  'Exact Auth-session predicate: lock-free in read-only transactions and key-share locked through every read-write caller commit.';

-- A STABLE caller executes through a read-only SPI path even when the outer
-- transaction can write. Keep every direct compatibility wrapper VOLATILE so
-- the shared predicate can take its write-side row lock when required.
alter function public.garmin_list_devices() volatile;
alter function public.require_live_session_for_account_deletion() volatile;
alter function gymapp_private.realtime_has_current_auth_session() volatile;

-- The expiry predicate must start with an indexed column. Foreground cleanup
-- remains opportunistic, but a caller can perform only one small ordered batch
-- while holding the single maintenance lease.
create index if not exists edge_preauth_windows_expiry_idx
  on gymapp_private.edge_preauth_windows (window_started_at, route, source_hash);

create or replace function gymapp_private.edge_preauth_debit(
  p_route text,
  p_source_hash text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  source_limit integer;
  current_window timestamptz := pg_catalog.date_trunc(
    'minute',
    pg_catalog.clock_timestamp()
  );
  source_allowed boolean;
begin
  if p_source_hash is null or p_source_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'Invalid verified identity.';
  end if;

  select limits.source_limit
  into source_limit
  from (values
    ('delete_account', 12),
    ('social_live', 180),
    ('social_gateway', 180)
  ) as limits(route, source_limit)
  where limits.route = p_route;
  if not found then
    raise exception using errcode = '22023', message = 'Invalid verified-identity route.';
  end if;

  insert into gymapp_private.edge_preauth_windows as budget (
    route, source_hash, window_started_at, request_count
  ) values (
    p_route, p_source_hash, current_window, 1
  )
  on conflict (route, source_hash) do update
  set window_started_at = case
        when budget.window_started_at < current_window then current_window
        else budget.window_started_at
      end,
      request_count = case
        when budget.window_started_at < current_window then 1
        else budget.request_count + 1
      end
  where budget.window_started_at < current_window
     or budget.request_count < source_limit
  returning true into source_allowed;

  -- A denied source returns before any maintenance work.
  if not coalesce(source_allowed, false) then
    return pg_catalog.jsonb_build_object(
      'allowed', false,
      'retryAfter', 60
    );
  end if;

  if pg_catalog.mod(pg_catalog.hashtextextended(p_source_hash, 0), 128) = 0
     and pg_catalog.pg_try_advisory_xact_lock(
       pg_catalog.hashtextextended('gymapp-edge-preauth-cleanup-v2', 0)
     ) then
    with expired as (
      select budget.route, budget.source_hash
      from gymapp_private.edge_preauth_windows as budget
      where budget.window_started_at < current_window - interval '10 minutes'
      order by budget.window_started_at, budget.route, budget.source_hash
      limit 128
      for update skip locked
    )
    delete from gymapp_private.edge_preauth_windows as budget
    using expired
    where budget.route = expired.route
      and budget.source_hash = expired.source_hash;
  end if;

  return pg_catalog.jsonb_build_object('allowed', true, 'retryAfter', 0);
end
$function$;

revoke all on function gymapp_private.edge_preauth_debit(text, text)
  from public, anon, authenticated, service_role;

comment on function gymapp_private.edge_preauth_debit(text, text) is
  'Durable verified-identity fixed-window budget with indexed, leased, bounded expiry maintenance.';

-- The authenticated gateway has a separate pre-validation perimeter, while
-- every valid direct or Edge route shares the social_live aggregate below.
-- Raw session identifiers never leave the private database boundary.
create or replace function gymapp_private.social_session_budget_hash(
  p_route text,
  p_session_id uuid
)
returns text
language sql
immutable
strict
security invoker
set search_path = ''
as $function$
  select pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        p_route || pg_catalog.chr(10) || 'session:' || p_session_id::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
$function$;

revoke all on function gymapp_private.social_session_budget_hash(text, uuid)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_session_aggregate_debit(
  p_route text,
  p_user_id uuid,
  p_session_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  aggregate_result jsonb;
begin
  if p_route not in ('social_live', 'social_gateway') then
    raise exception using errcode = '22023', message = 'Social aggregate route is invalid.';
  end if;
  perform gymapp_private.live_gateway_require_session(
    p_user_id,
    p_session_id
  );

  aggregate_result := gymapp_private.edge_preauth_debit(
    p_route,
    gymapp_private.social_session_budget_hash(
      p_route,
      p_session_id
    )
  );
  if aggregate_result ->> 'allowed' <> 'true' then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'allowed', false,
      'retryAfter', coalesce(
        (aggregate_result ->> 'retryAfter')::integer,
        60
      )
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'allowed', true,
    'retryAfter', 0
  );
end
$function$;

revoke all on function gymapp_private.social_session_aggregate_debit(text, uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_live_debit_budget(
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
  aggregate_result jsonb;
begin
  aggregate_result := gymapp_private.social_session_aggregate_debit(
    'social_live',
    p_user_id,
    p_session_id
  );
  if aggregate_result ->> 'allowed' <> 'true' then
    return aggregate_result;
  end if;

  return gymapp_private.social_live_gateway_debit_storage_v1(
    p_user_id,
    p_session_id,
    p_action
  );
end
$function$;

revoke all on function gymapp_private.social_live_debit_budget(uuid, uuid, text)
  from public, anon, authenticated, service_role;

create or replace function public.social_gateway_perimeter_debit(
  p_user_id uuid,
  p_session_id uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $function$
  select gymapp_private.social_session_aggregate_debit(
    'social_gateway',
    p_user_id,
    p_session_id
  )
$function$;

revoke all on function public.social_gateway_perimeter_debit(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.social_gateway_perimeter_debit(uuid, uuid)
  to service_role;

create or replace function public.social_live_gateway_debit(
  p_user_id uuid,
  p_session_id uuid,
  p_action text
)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $function$
  select gymapp_private.social_live_debit_budget(
    p_user_id,
    p_session_id,
    p_action
  )
$function$;

revoke all on function public.social_live_gateway_debit(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.social_live_gateway_debit(uuid, uuid, text)
  to service_role;

create or replace function gymapp_private.social_require_caller(p_action text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  session_id_text text := auth.jwt() ->> 'session_id';
  gateway_action text;
  debit_result jsonb;
begin
  if caller_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception using errcode = '42501', message = 'A live authenticated session is required.';
  end if;

  select mapping.gateway_action
  into gateway_action
  from (values
    ('dashboard', 'social_dashboard'),
    ('friend_details', 'social_friend_details'),
    ('send_friend', 'social_send_friend_request'),
    ('respond_friend', 'social_respond_friend_request'),
    ('cancel_friend', 'social_cancel_friend_request'),
    ('remove_friend', 'social_remove_friend'),
    ('block_profile', 'social_block_profile'),
    ('unblock_profile', 'social_unblock_profile'),
    ('update_privacy', 'social_update_privacy'),
    ('workout_inbox', 'social_workout_inbox'),
    ('send_workout', 'social_send_workout_invite'),
    ('respond_workout', 'social_respond_workout_invite'),
    ('cancel_workout', 'social_cancel_workout_invite')
  ) as mapping(domain_action, gateway_action)
  where mapping.domain_action = p_action;
  if not found then
    raise exception using errcode = '22023', message = 'Social action is invalid.';
  end if;

  debit_result := gymapp_private.social_live_debit_budget(
    caller_user_id,
    session_id_text::uuid,
    gateway_action
  );
  if debit_result ->> 'allowed' <> 'true' then
    raise exception using
      errcode = 'PT429',
      message = 'Social request budget exceeded.',
      detail = 'retry_after=' || coalesce(
        debit_result ->> 'retryAfter',
        '60'
      );
  end if;

  begin
    perform gymapp_private.consume_social_rate_limit(caller_user_id, p_action);
  exception
    when sqlstate 'P0001' then
      raise exception using
        errcode = 'PT429',
        message = 'Social request budget exceeded.',
        detail = 'retry_after=60';
  end;
  return caller_user_id;
end
$function$;

revoke all on function gymapp_private.social_require_caller(text)
  from public, anon, authenticated, service_role;

comment on function gymapp_private.social_require_caller(text) is
  'Exact-session social authorization with shared aggregate, gateway-action, and domain-action budgets.';

-- A few later compatibility RPCs still raise expected validation/domain
-- errors after social_require_caller. Reserve the shared aggregate outside
-- their exception subtransaction, release it while retaining the row lock,
-- and let the worker perform the normal single debit. On an expected rollback,
-- restore exactly one aggregate, mapped action, and domain-action debit before
-- returning the historical error.
create or replace function gymapp_private.social_begin_direct_request()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  session_id_text text := auth.jwt() ->> 'session_id';
  session_id uuid;
  source_hash text;
  reservation_result jsonb;
  reservation_released boolean;
begin
  if caller_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception using errcode = '42501', message = 'A live authenticated session is required.';
  end if;
  session_id := session_id_text::uuid;
  source_hash := gymapp_private.social_session_budget_hash(
    'social_live',
    session_id
  );
  reservation_result := gymapp_private.social_session_aggregate_debit(
    'social_live',
    caller_user_id,
    session_id
  );
  if reservation_result ->> 'allowed' <> 'true' then
    return reservation_result;
  end if;

  delete from gymapp_private.edge_preauth_windows as budget
  where budget.route = 'social_live'
    and budget.source_hash = source_hash
    and budget.request_count = 1
  returning true into reservation_released;
  if not found then
    update gymapp_private.edge_preauth_windows as budget
    set request_count = budget.request_count - 1
    where budget.route = 'social_live'
      and budget.source_hash = source_hash
      and budget.request_count > 1
    returning true into reservation_released;
  end if;
  if not coalesce(reservation_released, false) then
    raise exception 'GymApp social aggregate reservation could not be released.';
  end if;
  return reservation_result;
end
$function$;

revoke all on function gymapp_private.social_begin_direct_request()
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_commit_direct_rejection(
  p_action text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  session_id_text text := auth.jwt() ->> 'session_id';
  gateway_action text;
  debit_result jsonb;
begin
  if caller_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception using errcode = '42501', message = 'A live authenticated session is required.';
  end if;

  select mapping.gateway_action
  into gateway_action
  from (values
    ('dashboard', 'social_dashboard'),
    ('friend_details', 'social_friend_details'),
    ('send_friend', 'social_send_friend_request'),
    ('respond_friend', 'social_respond_friend_request'),
    ('cancel_friend', 'social_cancel_friend_request'),
    ('remove_friend', 'social_remove_friend'),
    ('block_profile', 'social_block_profile'),
    ('unblock_profile', 'social_unblock_profile'),
    ('update_privacy', 'social_update_privacy'),
    ('workout_inbox', 'social_workout_inbox'),
    ('send_workout', 'social_send_workout_invite'),
    ('respond_workout', 'social_respond_workout_invite'),
    ('cancel_workout', 'social_cancel_workout_invite')
  ) as mapping(domain_action, gateway_action)
  where mapping.domain_action = p_action;
  if not found then
    raise exception using errcode = '22023', message = 'Social action is invalid.';
  end if;

  debit_result := gymapp_private.social_live_debit_budget(
    caller_user_id,
    session_id_text::uuid,
    gateway_action
  );
  if debit_result ->> 'allowed' <> 'true' then
    return debit_result;
  end if;

  -- Keep aggregate/action changes outside the exception subtransaction. The
  -- legacy token bucket reports exhaustion with P0001, which is converted to a
  -- normal result so those already-durable debits are not rolled back.
  begin
    perform gymapp_private.consume_social_rate_limit(
      caller_user_id,
      p_action
    );
  exception
    when sqlstate 'P0001' then
      return pg_catalog.jsonb_build_object(
        'version', 1,
        'allowed', false,
        'retryAfter', 60
      );
  end;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'allowed', true,
    'retryAfter', 0
  );
end
$function$;

revoke all on function gymapp_private.social_commit_direct_rejection(text)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_rate_limit_response(
  p_detail text
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  retry_after integer := 60;
begin
  if coalesce(p_detail, '') ~ '^retry_after=[1-9][0-9]{0,3}$' then
    retry_after := greatest(
      1,
      least(3600, pg_catalog.substr(p_detail, 13)::integer)
    );
  end if;
  perform pg_catalog.set_config('response.status', '429', true);
  perform pg_catalog.set_config(
    'response.headers',
    pg_catalog.json_build_array(
      pg_catalog.json_build_object('Retry-After', retry_after::text)
    )::text,
    true
  );
  return pg_catalog.jsonb_build_object(
    'code', 'PT429',
    'details', 'retry_after=' || retry_after::text,
    'hint', null,
    'message', 'Social request budget exceeded.'
  );
end
$function$;

revoke all on function gymapp_private.social_rate_limit_response(text)
  from public, anon, authenticated, service_role;

alter function public.social_update_workout_detail_privacy(boolean, bigint)
  set schema gymapp_private;
alter function gymapp_private.social_update_workout_detail_privacy(boolean, bigint)
  rename to social_update_workout_detail_privacy_storage_v1;
revoke all on function gymapp_private.social_update_workout_detail_privacy_storage_v1(
  boolean, bigint
) from public, anon, authenticated, service_role;

create function public.social_update_workout_detail_privacy(
  p_share_workout_details boolean,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  reservation_result jsonb;
  rejection_result jsonb;
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  reservation_result := gymapp_private.social_begin_direct_request();
  if reservation_result ->> 'allowed' <> 'true' then
    return gymapp_private.social_rate_limit_response(
      'retry_after=' || coalesce(reservation_result ->> 'retryAfter', '60')
    );
  end if;
  begin
    return gymapp_private.social_update_workout_detail_privacy_storage_v1(
      p_share_workout_details,
      p_expected_revision
    );
  exception
    when sqlstate 'PT429' then
      get stacked diagnostics domain_error_detail = pg_exception_detail;
      rejection_result := gymapp_private.social_commit_direct_rejection(
        'update_privacy'
      );
      return gymapp_private.social_rate_limit_response(
        case
          when rejection_result ->> 'allowed' <> 'true' then
            'retry_after=' || coalesce(
              rejection_result ->> 'retryAfter',
              '60'
            )
          else domain_error_detail
        end
      );
    when sqlstate '22023' or sqlstate 'P0001' or sqlstate 'P0002' then
      get stacked diagnostics
        domain_error_code = returned_sqlstate,
        domain_error_message = message_text,
        domain_error_detail = pg_exception_detail,
        domain_error_hint = pg_exception_hint;
      rejection_result := gymapp_private.social_commit_direct_rejection(
        'update_privacy'
      );
      if rejection_result ->> 'allowed' <> 'true' then
        return gymapp_private.social_rate_limit_response(
          'retry_after=' || coalesce(
            rejection_result ->> 'retryAfter',
            '60'
          )
        );
      end if;
      return gymapp_private.social_domain_error_response(
        domain_error_code,
        domain_error_message,
        domain_error_detail,
        domain_error_hint
      );
  end;
end
$function$;

revoke all on function public.social_update_workout_detail_privacy(boolean, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.social_update_workout_detail_privacy(boolean, bigint)
  to authenticated;

alter function public.social_friend_workout_detail_capability(text)
  set schema gymapp_private;
alter function gymapp_private.social_friend_workout_detail_capability(text)
  rename to social_friend_workout_detail_capability_storage_v1;
revoke all on function gymapp_private.social_friend_workout_detail_capability_storage_v1(text)
  from public, anon, authenticated, service_role;

create function public.social_friend_workout_detail_capability(
  p_profile_id text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  reservation_result jsonb;
  rejection_result jsonb;
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  reservation_result := gymapp_private.social_begin_direct_request();
  if reservation_result ->> 'allowed' <> 'true' then
    return gymapp_private.social_rate_limit_response(
      'retry_after=' || coalesce(reservation_result ->> 'retryAfter', '60')
    );
  end if;
  begin
    return gymapp_private.social_friend_workout_detail_capability_storage_v1(
      p_profile_id
    );
  exception
    when sqlstate 'PT429' then
      get stacked diagnostics domain_error_detail = pg_exception_detail;
      rejection_result := gymapp_private.social_commit_direct_rejection(
        'friend_details'
      );
      return gymapp_private.social_rate_limit_response(
        case
          when rejection_result ->> 'allowed' <> 'true' then
            'retry_after=' || coalesce(
              rejection_result ->> 'retryAfter',
              '60'
            )
          else domain_error_detail
        end
      );
    when sqlstate '22023' or sqlstate 'P0001' or sqlstate 'P0002' then
      get stacked diagnostics
        domain_error_code = returned_sqlstate,
        domain_error_message = message_text,
        domain_error_detail = pg_exception_detail,
        domain_error_hint = pg_exception_hint;
      rejection_result := gymapp_private.social_commit_direct_rejection(
        'friend_details'
      );
      if rejection_result ->> 'allowed' <> 'true' then
        return gymapp_private.social_rate_limit_response(
          'retry_after=' || coalesce(
            rejection_result ->> 'retryAfter',
            '60'
          )
        );
      end if;
      return gymapp_private.social_domain_error_response(
        domain_error_code,
        domain_error_message,
        domain_error_detail,
        domain_error_hint
      );
  end;
end
$function$;

revoke all on function public.social_friend_workout_detail_capability(text)
  from public, anon, authenticated, service_role;
grant execute on function public.social_friend_workout_detail_capability(text)
  to authenticated;

alter function public.social_friend_workout_page_base_v1(
  text, text, timestamptz, integer
) set schema gymapp_private;
alter function gymapp_private.social_friend_workout_page_base_v1(
  text, text, timestamptz, integer
) rename to social_friend_workout_page_base_storage_v1;
revoke all on function gymapp_private.social_friend_workout_page_base_storage_v1(
  text, text, timestamptz, integer
) from public, anon, authenticated, service_role;

alter function public.social_friend_workout_page(text, text, timestamptz, integer)
  set schema gymapp_private;
alter function gymapp_private.social_friend_workout_page(
  text, text, timestamptz, integer
) rename to social_friend_workout_page_storage_v2;
revoke all on function gymapp_private.social_friend_workout_page_storage_v2(
  text, text, timestamptz, integer
) from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_friend_workout_page_storage_v2(
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
  base_result := gymapp_private.social_friend_workout_page_base_storage_v1(
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

revoke all on function gymapp_private.social_friend_workout_page_storage_v2(
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
  reservation_result jsonb;
  rejection_result jsonb;
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  reservation_result := gymapp_private.social_begin_direct_request();
  if reservation_result ->> 'allowed' <> 'true' then
    return gymapp_private.social_rate_limit_response(
      'retry_after=' || coalesce(reservation_result ->> 'retryAfter', '60')
    );
  end if;
  begin
    return gymapp_private.social_friend_workout_page_storage_v2(
      p_profile_id,
      p_cursor,
      p_expected_activity_revision,
      p_limit
    );
  exception
    when sqlstate 'PT429' then
      get stacked diagnostics domain_error_detail = pg_exception_detail;
      rejection_result := gymapp_private.social_commit_direct_rejection(
        'friend_details'
      );
      return gymapp_private.social_rate_limit_response(
        case
          when rejection_result ->> 'allowed' <> 'true' then
            'retry_after=' || coalesce(
              rejection_result ->> 'retryAfter',
              '60'
            )
          else domain_error_detail
        end
      );
    when sqlstate '22023' or sqlstate 'P0001' or sqlstate 'P0002' then
      get stacked diagnostics
        domain_error_code = returned_sqlstate,
        domain_error_message = message_text,
        domain_error_detail = pg_exception_detail,
        domain_error_hint = pg_exception_hint;
      rejection_result := gymapp_private.social_commit_direct_rejection(
        'friend_details'
      );
      if rejection_result ->> 'allowed' <> 'true' then
        return gymapp_private.social_rate_limit_response(
          'retry_after=' || coalesce(
            rejection_result ->> 'retryAfter',
            '60'
          )
        );
      end if;
      return gymapp_private.social_domain_error_response(
        domain_error_code,
        domain_error_message,
        domain_error_detail,
        domain_error_hint
      );
  end;
end
$function$;

revoke all on function public.social_friend_workout_page(
  text, text, timestamptz, integer
) from public, anon, authenticated, service_role;
grant execute on function public.social_friend_workout_page(
  text, text, timestamptz, integer
) to authenticated;

alter function public.social_workout_inbox_page(
  timestamptz, text, boolean, integer
) set schema gymapp_private;
alter function gymapp_private.social_workout_inbox_page(
  timestamptz, text, boolean, integer
) rename to social_workout_inbox_page_storage_v2;
revoke all on function gymapp_private.social_workout_inbox_page_storage_v2(
  timestamptz, text, boolean, integer
) from public, anon, authenticated, service_role;

create function public.social_workout_inbox_page(
  p_cursor_created_at timestamptz default null,
  p_cursor_invite_id text default null,
  p_cursor_pending boolean default null,
  p_limit integer default 10
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  reservation_result jsonb;
  rejection_result jsonb;
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  reservation_result := gymapp_private.social_begin_direct_request();
  if reservation_result ->> 'allowed' <> 'true' then
    return gymapp_private.social_rate_limit_response(
      'retry_after=' || coalesce(reservation_result ->> 'retryAfter', '60')
    );
  end if;
  begin
    return gymapp_private.social_workout_inbox_page_storage_v2(
      p_cursor_created_at,
      p_cursor_invite_id,
      p_cursor_pending,
      p_limit
    );
  exception
    when sqlstate 'PT429' then
      get stacked diagnostics domain_error_detail = pg_exception_detail;
      rejection_result := gymapp_private.social_commit_direct_rejection(
        'workout_inbox'
      );
      return gymapp_private.social_rate_limit_response(
        case
          when rejection_result ->> 'allowed' <> 'true' then
            'retry_after=' || coalesce(
              rejection_result ->> 'retryAfter',
              '60'
            )
          else domain_error_detail
        end
      );
    when sqlstate '22023' or sqlstate 'P0001' or sqlstate 'P0002' then
      get stacked diagnostics
        domain_error_code = returned_sqlstate,
        domain_error_message = message_text,
        domain_error_detail = pg_exception_detail,
        domain_error_hint = pg_exception_hint;
      rejection_result := gymapp_private.social_commit_direct_rejection(
        'workout_inbox'
      );
      if rejection_result ->> 'allowed' <> 'true' then
        return gymapp_private.social_rate_limit_response(
          'retry_after=' || coalesce(
            rejection_result ->> 'retryAfter',
            '60'
          )
        );
      end if;
      return gymapp_private.social_domain_error_response(
        domain_error_code,
        domain_error_message,
        domain_error_detail,
        domain_error_hint
      );
  end;
end
$function$;

revoke all on function public.social_workout_inbox_page(
  timestamptz, text, boolean, integer
) from public, anon, authenticated, service_role;
grant execute on function public.social_workout_inbox_page(
  timestamptz, text, boolean, integer
) to authenticated;

-- Put every remaining authenticated social RPC behind the same outer
-- reservation/recovery transaction. The existing implementations stay intact
-- as private workers, including their established response contracts.
alter function public.social_dashboard() set schema gymapp_private;
alter function gymapp_private.social_dashboard()
  rename to social_dashboard_direct_storage_v1;
revoke all on function gymapp_private.social_dashboard_direct_storage_v1()
  from public, anon, authenticated, service_role;

alter function public.social_friend_details(text) set schema gymapp_private;
alter function gymapp_private.social_friend_details(text)
  rename to social_friend_details_direct_storage_v1;
revoke all on function gymapp_private.social_friend_details_direct_storage_v1(text)
  from public, anon, authenticated, service_role;

alter function public.social_send_friend_request(text) set schema gymapp_private;
alter function gymapp_private.social_send_friend_request(text)
  rename to social_send_friend_request_direct_storage_v1;
revoke all on function gymapp_private.social_send_friend_request_direct_storage_v1(text)
  from public, anon, authenticated, service_role;

alter function public.social_respond_friend_request(text, text, bigint)
  set schema gymapp_private;
alter function gymapp_private.social_respond_friend_request(text, text, bigint)
  rename to social_respond_friend_request_direct_storage_v1;
revoke all on function gymapp_private.social_respond_friend_request_direct_storage_v1(
  text, text, bigint
) from public, anon, authenticated, service_role;

alter function public.social_cancel_friend_request(text, bigint)
  set schema gymapp_private;
alter function gymapp_private.social_cancel_friend_request(text, bigint)
  rename to social_cancel_friend_request_direct_storage_v1;
revoke all on function gymapp_private.social_cancel_friend_request_direct_storage_v1(
  text, bigint
) from public, anon, authenticated, service_role;

alter function public.social_remove_friend(text, bigint)
  set schema gymapp_private;
alter function gymapp_private.social_remove_friend(text, bigint)
  rename to social_remove_friend_direct_storage_v1;
revoke all on function gymapp_private.social_remove_friend_direct_storage_v1(
  text, bigint
) from public, anon, authenticated, service_role;

alter function public.social_block_profile(text) set schema gymapp_private;
alter function gymapp_private.social_block_profile(text)
  rename to social_block_profile_direct_storage_v1;
revoke all on function gymapp_private.social_block_profile_direct_storage_v1(text)
  from public, anon, authenticated, service_role;

alter function public.social_unblock_profile(text) set schema gymapp_private;
alter function gymapp_private.social_unblock_profile(text)
  rename to social_unblock_profile_direct_storage_v1;
revoke all on function gymapp_private.social_unblock_profile_direct_storage_v1(text)
  from public, anon, authenticated, service_role;

alter function public.social_update_privacy(
  boolean, boolean, boolean, boolean, bigint
) set schema gymapp_private;
alter function gymapp_private.social_update_privacy(
  boolean, boolean, boolean, boolean, bigint
) rename to social_update_privacy_direct_storage_v1;
revoke all on function gymapp_private.social_update_privacy_direct_storage_v1(
  boolean, boolean, boolean, boolean, bigint
) from public, anon, authenticated, service_role;

alter function public.social_send_workout_invite(text, uuid, jsonb)
  set schema gymapp_private;
alter function gymapp_private.social_send_workout_invite(text, uuid, jsonb)
  rename to social_send_workout_invite_direct_storage_v1;
revoke all on function gymapp_private.social_send_workout_invite_direct_storage_v1(
  text, uuid, jsonb
) from public, anon, authenticated, service_role;

alter function public.social_workout_inbox() set schema gymapp_private;
alter function gymapp_private.social_workout_inbox()
  rename to social_workout_inbox_direct_storage_v1;
revoke all on function gymapp_private.social_workout_inbox_direct_storage_v1()
  from public, anon, authenticated, service_role;

alter function public.social_respond_workout_invite(text, text, bigint)
  set schema gymapp_private;
alter function gymapp_private.social_respond_workout_invite(text, text, bigint)
  rename to social_respond_workout_invite_direct_storage_v1;
revoke all on function gymapp_private.social_respond_workout_invite_direct_storage_v1(
  text, text, bigint
) from public, anon, authenticated, service_role;

alter function public.social_cancel_workout_invite(text, bigint)
  set schema gymapp_private;
alter function gymapp_private.social_cancel_workout_invite(text, bigint)
  rename to social_cancel_workout_invite_direct_storage_v1;
revoke all on function gymapp_private.social_cancel_workout_invite_direct_storage_v1(
  text, bigint
) from public, anon, authenticated, service_role;

alter function public.social_workout_detail_privacy()
  set schema gymapp_private;
alter function gymapp_private.social_workout_detail_privacy()
  rename to social_workout_detail_privacy_direct_storage_v1;
revoke all on function gymapp_private.social_workout_detail_privacy_direct_storage_v1()
  from public, anon, authenticated, service_role;

alter function public.social_workout_invite_plan(text, bigint)
  set schema gymapp_private;
alter function gymapp_private.social_workout_invite_plan(text, bigint)
  rename to social_workout_invite_plan_direct_storage_v1;
revoke all on function gymapp_private.social_workout_invite_plan_direct_storage_v1(
  text, bigint
) from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_execute_direct_worker(
  p_worker text,
  p_args jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  domain_action text;
  reservation_result jsonb;
  rejection_result jsonb;
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  select mapping.domain_action
  into domain_action
  from (values
    ('social_dashboard', 'dashboard'),
    ('social_friend_details', 'friend_details'),
    ('social_send_friend_request', 'send_friend'),
    ('social_respond_friend_request', 'respond_friend'),
    ('social_cancel_friend_request', 'cancel_friend'),
    ('social_remove_friend', 'remove_friend'),
    ('social_block_profile', 'block_profile'),
    ('social_unblock_profile', 'unblock_profile'),
    ('social_update_privacy', 'update_privacy'),
    ('social_send_workout_invite', 'send_workout'),
    ('social_workout_inbox', 'workout_inbox'),
    ('social_respond_workout_invite', 'respond_workout'),
    ('social_cancel_workout_invite', 'cancel_workout'),
    ('social_workout_detail_privacy', 'update_privacy'),
    ('social_workout_invite_plan', 'workout_inbox')
  ) as mapping(worker, domain_action)
  where mapping.worker = p_worker;
  if not found or p_args is null or pg_catalog.jsonb_typeof(p_args) <> 'object' then
    raise exception using errcode = '22023', message = 'Social direct worker is invalid.';
  end if;

  reservation_result := gymapp_private.social_begin_direct_request();
  if reservation_result ->> 'allowed' <> 'true' then
    return gymapp_private.social_rate_limit_response(
      'retry_after=' || coalesce(reservation_result ->> 'retryAfter', '60')
    );
  end if;

  begin
    case p_worker
      when 'social_dashboard' then
        return gymapp_private.social_dashboard_direct_storage_v1();
      when 'social_friend_details' then
        return gymapp_private.social_friend_details_direct_storage_v1(
          p_args ->> 'profileId'
        );
      when 'social_send_friend_request' then
        return gymapp_private.social_send_friend_request_direct_storage_v1(
          p_args ->> 'friendCode'
        );
      when 'social_respond_friend_request' then
        return gymapp_private.social_respond_friend_request_direct_storage_v1(
          p_args ->> 'friendshipId',
          p_args ->> 'decision',
          (p_args ->> 'expectedRevision')::bigint
        );
      when 'social_cancel_friend_request' then
        return gymapp_private.social_cancel_friend_request_direct_storage_v1(
          p_args ->> 'friendshipId',
          (p_args ->> 'expectedRevision')::bigint
        );
      when 'social_remove_friend' then
        return gymapp_private.social_remove_friend_direct_storage_v1(
          p_args ->> 'friendshipId',
          (p_args ->> 'expectedRevision')::bigint
        );
      when 'social_block_profile' then
        return gymapp_private.social_block_profile_direct_storage_v1(
          p_args ->> 'profileId'
        );
      when 'social_unblock_profile' then
        return gymapp_private.social_unblock_profile_direct_storage_v1(
          p_args ->> 'profileId'
        );
      when 'social_update_privacy' then
        return gymapp_private.social_update_privacy_direct_storage_v1(
          (p_args ->> 'allowRequests')::boolean,
          (p_args ->> 'shareProgress')::boolean,
          (p_args ->> 'shareRecentWorkouts')::boolean,
          (p_args ->> 'shareRecords')::boolean,
          (p_args ->> 'expectedRevision')::bigint
        );
      when 'social_send_workout_invite' then
        return gymapp_private.social_send_workout_invite_direct_storage_v1(
          p_args ->> 'profileId',
          (p_args ->> 'clientRequestId')::uuid,
          p_args -> 'workout'
        );
      when 'social_workout_inbox' then
        return gymapp_private.social_workout_inbox_direct_storage_v1();
      when 'social_respond_workout_invite' then
        return gymapp_private.social_respond_workout_invite_direct_storage_v1(
          p_args ->> 'inviteId',
          p_args ->> 'decision',
          (p_args ->> 'expectedRevision')::bigint
        );
      when 'social_cancel_workout_invite' then
        return gymapp_private.social_cancel_workout_invite_direct_storage_v1(
          p_args ->> 'inviteId',
          (p_args ->> 'expectedRevision')::bigint
        );
      when 'social_workout_detail_privacy' then
        return gymapp_private.social_workout_detail_privacy_direct_storage_v1();
      when 'social_workout_invite_plan' then
        return gymapp_private.social_workout_invite_plan_direct_storage_v1(
          p_args ->> 'inviteId',
          (p_args ->> 'expectedRevision')::bigint
        );
      else
        raise exception using errcode = '22023', message = 'Social direct worker is invalid.';
    end case;
  exception
    when sqlstate 'PT429' then
      get stacked diagnostics domain_error_detail = pg_exception_detail;
      rejection_result := gymapp_private.social_commit_direct_rejection(
        domain_action
      );
      return gymapp_private.social_rate_limit_response(
        case
          when rejection_result ->> 'allowed' <> 'true' then
            'retry_after=' || coalesce(
              rejection_result ->> 'retryAfter',
              '60'
            )
          else domain_error_detail
        end
      );
    when sqlstate '22023' or sqlstate 'P0001' or sqlstate 'P0002' then
      get stacked diagnostics
        domain_error_code = returned_sqlstate,
        domain_error_message = message_text,
        domain_error_detail = pg_exception_detail,
        domain_error_hint = pg_exception_hint;
      rejection_result := gymapp_private.social_commit_direct_rejection(
        domain_action
      );
      if rejection_result ->> 'allowed' <> 'true' then
        return gymapp_private.social_rate_limit_response(
          'retry_after=' || coalesce(
            rejection_result ->> 'retryAfter',
            '60'
          )
        );
      end if;
      return gymapp_private.social_domain_error_response(
        domain_error_code,
        domain_error_message,
        domain_error_detail,
        domain_error_hint
      );
  end;
end
$function$;

revoke all on function gymapp_private.social_execute_direct_worker(text, jsonb)
  from public, anon, authenticated, service_role;

create function public.social_dashboard()
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_dashboard', '{}'::jsonb
  )
$function$;

create function public.social_friend_details(p_profile_id text)
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_friend_details',
    pg_catalog.jsonb_build_object('profileId', p_profile_id)
  )
$function$;

create function public.social_send_friend_request(p_friend_code text)
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_send_friend_request',
    pg_catalog.jsonb_build_object('friendCode', p_friend_code)
  )
$function$;

create function public.social_respond_friend_request(
  p_friendship_id text,
  p_decision text,
  p_expected_revision bigint
)
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_respond_friend_request',
    pg_catalog.jsonb_build_object(
      'friendshipId', p_friendship_id,
      'decision', p_decision,
      'expectedRevision', p_expected_revision
    )
  )
$function$;

create function public.social_cancel_friend_request(
  p_friendship_id text,
  p_expected_revision bigint
)
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_cancel_friend_request',
    pg_catalog.jsonb_build_object(
      'friendshipId', p_friendship_id,
      'expectedRevision', p_expected_revision
    )
  )
$function$;

create function public.social_remove_friend(
  p_friendship_id text,
  p_expected_revision bigint
)
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_remove_friend',
    pg_catalog.jsonb_build_object(
      'friendshipId', p_friendship_id,
      'expectedRevision', p_expected_revision
    )
  )
$function$;

create function public.social_block_profile(p_profile_id text)
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_block_profile',
    pg_catalog.jsonb_build_object('profileId', p_profile_id)
  )
$function$;

create function public.social_unblock_profile(p_profile_id text)
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_unblock_profile',
    pg_catalog.jsonb_build_object('profileId', p_profile_id)
  )
$function$;

create function public.social_update_privacy(
  p_allow_requests boolean,
  p_share_progress boolean,
  p_share_recent_workouts boolean,
  p_share_records boolean,
  p_expected_revision bigint
)
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_update_privacy',
    pg_catalog.jsonb_build_object(
      'allowRequests', p_allow_requests,
      'shareProgress', p_share_progress,
      'shareRecentWorkouts', p_share_recent_workouts,
      'shareRecords', p_share_records,
      'expectedRevision', p_expected_revision
    )
  )
$function$;

create function public.social_send_workout_invite(
  p_profile_id text,
  p_client_request_id uuid,
  p_workout jsonb
)
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_send_workout_invite',
    pg_catalog.jsonb_build_object(
      'profileId', p_profile_id,
      'clientRequestId', p_client_request_id,
      'workout', p_workout
    )
  )
$function$;

create function public.social_workout_inbox()
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_workout_inbox', '{}'::jsonb
  )
$function$;

create function public.social_respond_workout_invite(
  p_invite_id text,
  p_decision text,
  p_expected_revision bigint
)
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_respond_workout_invite',
    pg_catalog.jsonb_build_object(
      'inviteId', p_invite_id,
      'decision', p_decision,
      'expectedRevision', p_expected_revision
    )
  )
$function$;

create function public.social_cancel_workout_invite(
  p_invite_id text,
  p_expected_revision bigint
)
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_cancel_workout_invite',
    pg_catalog.jsonb_build_object(
      'inviteId', p_invite_id,
      'expectedRevision', p_expected_revision
    )
  )
$function$;

create function public.social_workout_detail_privacy()
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_workout_detail_privacy', '{}'::jsonb
  )
$function$;

create function public.social_workout_invite_plan(
  p_invite_id text,
  p_expected_revision bigint
)
returns jsonb language sql volatile security definer set search_path = ''
as $function$
  select gymapp_private.social_execute_direct_worker(
    'social_workout_invite_plan',
    pg_catalog.jsonb_build_object(
      'inviteId', p_invite_id,
      'expectedRevision', p_expected_revision
    )
  )
$function$;

revoke all on function public.social_dashboard()
  from public, anon, authenticated, service_role;
revoke all on function public.social_friend_details(text)
  from public, anon, authenticated, service_role;
revoke all on function public.social_send_friend_request(text)
  from public, anon, authenticated, service_role;
revoke all on function public.social_respond_friend_request(text, text, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.social_cancel_friend_request(text, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.social_remove_friend(text, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.social_block_profile(text)
  from public, anon, authenticated, service_role;
revoke all on function public.social_unblock_profile(text)
  from public, anon, authenticated, service_role;
revoke all on function public.social_update_privacy(
  boolean, boolean, boolean, boolean, bigint
) from public, anon, authenticated, service_role;
revoke all on function public.social_send_workout_invite(text, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.social_workout_inbox()
  from public, anon, authenticated, service_role;
revoke all on function public.social_respond_workout_invite(text, text, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.social_cancel_workout_invite(text, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.social_workout_detail_privacy()
  from public, anon, authenticated, service_role;
revoke all on function public.social_workout_invite_plan(text, bigint)
  from public, anon, authenticated, service_role;

grant execute on function public.social_dashboard() to authenticated;
grant execute on function public.social_friend_details(text) to authenticated;
grant execute on function public.social_send_friend_request(text) to authenticated;
grant execute on function public.social_respond_friend_request(text, text, bigint)
  to authenticated;
grant execute on function public.social_cancel_friend_request(text, bigint)
  to authenticated;
grant execute on function public.social_remove_friend(text, bigint)
  to authenticated;
grant execute on function public.social_block_profile(text) to authenticated;
grant execute on function public.social_unblock_profile(text) to authenticated;
grant execute on function public.social_update_privacy(
  boolean, boolean, boolean, boolean, bigint
) to authenticated;
grant execute on function public.social_send_workout_invite(text, uuid, jsonb)
  to authenticated;
grant execute on function public.social_workout_inbox() to authenticated;
grant execute on function public.social_respond_workout_invite(text, text, bigint)
  to authenticated;
grant execute on function public.social_cancel_workout_invite(text, bigint)
  to authenticated;
grant execute on function public.social_workout_detail_privacy()
  to authenticated;
grant execute on function public.social_workout_invite_plan(text, bigint)
  to authenticated;

comment on function gymapp_private.social_execute_direct_worker(text, jsonb) is
  'Private allowlisted dispatcher that durably accounts every direct social request, including rejected workers.';

-- Existing rows may contain more than one grant for an owner. Keep only the
-- newest before adding the permanent one-owner/one-purpose invariant.
with ranked as (
  select
    deletion_grant.grant_hash,
    pg_catalog.row_number() over (
      partition by deletion_grant.user_id, deletion_grant.purpose
      order by deletion_grant.created_at desc, deletion_grant.grant_hash desc
    ) as position
  from gymapp_private.account_deletion_grants as deletion_grant
)
delete from gymapp_private.account_deletion_grants as deletion_grant
using ranked
where deletion_grant.grant_hash = ranked.grant_hash
  and ranked.position > 1;

create unique index if not exists account_deletion_grants_one_owner_purpose_idx
  on gymapp_private.account_deletion_grants (user_id, purpose);
create index if not exists account_deletion_grants_expiry_idx
  on gymapp_private.account_deletion_grants (expires_at, grant_hash);

create or replace function public.prepare_account_deletion()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  session_id_text text := auth.jwt() ->> 'session_id';
  caller_session_id uuid;
  raw_grant uuid;
  expiry timestamptz;
  budget_result jsonb;
begin
  if caller_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or not gymapp_private.current_password_auth_is_recent(interval '5 minutes') then
    raise exception using errcode = '42501', message = 'Recent password authentication is required.';
  end if;
  caller_session_id := session_id_text::uuid;

  perform 1
  from auth.sessions as session
  where session.id = caller_session_id
    and session.user_id = caller_user_id
    and (
      session.not_after is null
      or session.not_after > pg_catalog.clock_timestamp()
    )
  for key share;
  if not found then
    raise exception using errcode = '42501', message = 'A current authenticated session is required.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'gymapp-account-deletion:' || caller_user_id::text,
      0
    )
  );

  budget_result := gymapp_private.edge_preauth_debit(
    'delete_account',
    pg_catalog.encode(
      extensions.digest(
        pg_catalog.convert_to(
          'delete_account' || pg_catalog.chr(10) || 'account:' || caller_user_id::text,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    )
  );
  if budget_result ->> 'allowed' <> 'true' then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'error', 'rate_limited',
      'retryAfter', coalesce(
        (budget_result ->> 'retryAfter')::integer,
        60
      )
    );
  end if;

  delete from gymapp_private.account_deletion_grants as deletion_grant
  where deletion_grant.user_id = caller_user_id
    and deletion_grant.purpose = 'delete_account';

  raw_grant := pg_catalog.gen_random_uuid();
  expiry := pg_catalog.clock_timestamp() + interval '5 minutes';
  insert into gymapp_private.account_deletion_grants (
    grant_hash, user_id, session_id, purpose, expires_at
  ) values (
    extensions.digest(
      pg_catalog.convert_to(raw_grant::text, 'UTF8'),
      'sha256'
    ),
    caller_user_id,
    caller_session_id,
    'delete_account',
    expiry
  );

  -- Consumed grants retain their five-minute expiry. Cleaning only the indexed
  -- expiry order keeps the foreground absence check bounded without an OR scan.
  if pg_catalog.pg_try_advisory_xact_lock(
       pg_catalog.hashtextextended('gymapp-account-deletion-cleanup-v1', 0)
     ) then
    with expired as (
      select deletion_grant.grant_hash
      from gymapp_private.account_deletion_grants as deletion_grant
      where deletion_grant.expires_at <= pg_catalog.clock_timestamp()
      order by deletion_grant.expires_at, deletion_grant.grant_hash
      limit 64
      for update skip locked
    )
    delete from gymapp_private.account_deletion_grants as deletion_grant
    using expired
    where deletion_grant.grant_hash = expired.grant_hash;
  end if;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'grant', raw_grant::text,
    'expiresAt', expiry
  );
end
$function$;

revoke all on function public.prepare_account_deletion()
  from public, anon, authenticated, service_role;
grant execute on function public.prepare_account_deletion()
  to authenticated;

comment on function public.prepare_account_deletion() is
  'Rate-limited replacement of the sole five-minute, single-use deletion capability after recent password authentication.';

-- The scheduler and Edge worker use two independent ingress credentials. A
-- copied value must never silently collapse those two checks into one secret.
create or replace function gymapp_private.dispatch_push_notifications()
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  dispatch_url text;
  server_key text;
  dispatch_token text;
  request_id bigint;
begin
  select secret.decrypted_secret into dispatch_url
  from vault.decrypted_secrets as secret
  where secret.name = 'gymapp_push_dispatch_url'
  order by secret.created_at desc
  limit 1;
  select secret.decrypted_secret into server_key
  from vault.decrypted_secrets as secret
  where secret.name = 'gymapp_push_dispatch_server_key'
  order by secret.created_at desc
  limit 1;
  select secret.decrypted_secret into dispatch_token
  from vault.decrypted_secrets as secret
  where secret.name = 'gymapp_push_dispatch_token'
  order by secret.created_at desc
  limit 1;

  if dispatch_url is null or server_key is null or dispatch_token is null then
    return null;
  end if;
  if dispatch_url !~ '^https://[a-z0-9]{20}\.supabase\.co/functions/v1/push-dispatch$'
     or pg_catalog.octet_length(dispatch_url) > 128
     or pg_catalog.octet_length(server_key) not between 32 and 8192
     or server_key ~ '[[:space:]]'
     or pg_catalog.octet_length(dispatch_token) not between 43 and 256
     or dispatch_token !~ '^[A-Za-z0-9_-]+$'
     or server_key = dispatch_token then
    return null;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gymapp-push-dispatch-scheduler-v1', 0)
  );
  if exists (
    select 1
    from gymapp_private.push_dispatch_requests as tracked
    where tracked.outcome = 'pending'
      and tracked.requested_at >= pg_catalog.clock_timestamp() - interval '5 minutes'
  ) then
    return null;
  end if;

  select net.http_post(
    url := dispatch_url,
    headers := pg_catalog.jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', server_key,
      'X-GymApp-Push-Dispatch-Token', dispatch_token
    ),
    body := pg_catalog.jsonb_build_object('version', 1, 'batchSize', 10),
    timeout_milliseconds := 120000
  ) into request_id;
  insert into gymapp_private.push_dispatch_requests (request_id)
  values (request_id);
  return request_id;
end
$function$;

revoke all on function gymapp_private.dispatch_push_notifications()
  from public, anon, authenticated, service_role;

do $verify$
declare
  session_source text;
  limiter_source text;
  social_source text;
  rejection_source text;
  deletion_source text;
  push_source text;
  rpc_signature text;
  private_signature text;
  wrapper_source text;
begin
  select procedure.prosrc into strict session_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'gymapp_private.has_current_auth_session(uuid)'
  );
  select procedure.prosrc into strict limiter_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'gymapp_private.edge_preauth_debit(text,text)'
  );
  select procedure.prosrc into strict social_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'gymapp_private.social_require_caller(text)'
  );
  select procedure.prosrc into strict rejection_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'gymapp_private.social_commit_direct_rejection(text)'
  );
  select procedure.prosrc into strict deletion_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'public.prepare_account_deletion()'
  );
  select procedure.prosrc into strict push_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'gymapp_private.dispatch_push_notifications()'
  );

  foreach rpc_signature in array array[
    'public.social_update_workout_detail_privacy(boolean,bigint)',
    'public.social_friend_workout_detail_capability(text)',
    'public.social_friend_workout_page(text,text,timestamptz,integer)',
    'public.social_workout_inbox_page(timestamptz,text,boolean,integer)'
  ] loop
    select procedure.prosrc into strict wrapper_source
    from pg_catalog.pg_proc as procedure
    where procedure.oid = pg_catalog.to_regprocedure(rpc_signature);
    if pg_catalog.has_function_privilege('anon', rpc_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege(
         'service_role', rpc_signature, 'EXECUTE'
       )
       or not pg_catalog.has_function_privilege(
         'authenticated', rpc_signature, 'EXECUTE'
       )
       or pg_catalog.strpos(
         pg_catalog.lower(wrapper_source),
         'social_begin_direct_request'
       ) = 0 then
      raise exception 'GymApp direct social RPC ACL verification failed for %.',
        rpc_signature;
    end if;
  end loop;

  foreach rpc_signature in array array[
    'public.social_dashboard()',
    'public.social_friend_details(text)',
    'public.social_send_friend_request(text)',
    'public.social_respond_friend_request(text,text,bigint)',
    'public.social_cancel_friend_request(text,bigint)',
    'public.social_remove_friend(text,bigint)',
    'public.social_block_profile(text)',
    'public.social_unblock_profile(text)',
    'public.social_update_privacy(boolean,boolean,boolean,boolean,bigint)',
    'public.social_send_workout_invite(text,uuid,jsonb)',
    'public.social_workout_inbox()',
    'public.social_respond_workout_invite(text,text,bigint)',
    'public.social_cancel_workout_invite(text,bigint)',
    'public.social_workout_detail_privacy()',
    'public.social_workout_invite_plan(text,bigint)'
  ] loop
    select procedure.prosrc into strict wrapper_source
    from pg_catalog.pg_proc as procedure
    where procedure.oid = pg_catalog.to_regprocedure(rpc_signature);
    if pg_catalog.has_function_privilege('anon', rpc_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege(
         'service_role', rpc_signature, 'EXECUTE'
       )
       or not pg_catalog.has_function_privilege(
         'authenticated', rpc_signature, 'EXECUTE'
       )
       or pg_catalog.strpos(
         pg_catalog.lower(wrapper_source),
         'social_execute_direct_worker'
       ) = 0 then
      raise exception 'GymApp direct social RPC wrapper verification failed for %.',
        rpc_signature;
    end if;
  end loop;

  foreach private_signature in array array[
    'gymapp_private.social_session_budget_hash(text,uuid)',
    'gymapp_private.social_session_aggregate_debit(text,uuid,uuid)',
    'gymapp_private.social_live_debit_budget(uuid,uuid,text)',
    'gymapp_private.social_begin_direct_request()',
    'gymapp_private.social_commit_direct_rejection(text)',
    'gymapp_private.social_rate_limit_response(text)',
    'gymapp_private.social_execute_direct_worker(text,jsonb)',
    'gymapp_private.social_update_workout_detail_privacy_storage_v1(boolean,bigint)',
    'gymapp_private.social_friend_workout_detail_capability_storage_v1(text)',
    'gymapp_private.social_friend_workout_page_base_storage_v1(text,text,timestamptz,integer)',
    'gymapp_private.social_friend_workout_page_storage_v2(text,text,timestamptz,integer)',
    'gymapp_private.social_workout_inbox_page_storage_v2(timestamptz,text,boolean,integer)',
    'gymapp_private.social_dashboard_direct_storage_v1()',
    'gymapp_private.social_friend_details_direct_storage_v1(text)',
    'gymapp_private.social_send_friend_request_direct_storage_v1(text)',
    'gymapp_private.social_respond_friend_request_direct_storage_v1(text,text,bigint)',
    'gymapp_private.social_cancel_friend_request_direct_storage_v1(text,bigint)',
    'gymapp_private.social_remove_friend_direct_storage_v1(text,bigint)',
    'gymapp_private.social_block_profile_direct_storage_v1(text)',
    'gymapp_private.social_unblock_profile_direct_storage_v1(text)',
    'gymapp_private.social_update_privacy_direct_storage_v1(boolean,boolean,boolean,boolean,bigint)',
    'gymapp_private.social_send_workout_invite_direct_storage_v1(text,uuid,jsonb)',
    'gymapp_private.social_workout_inbox_direct_storage_v1()',
    'gymapp_private.social_respond_workout_invite_direct_storage_v1(text,text,bigint)',
    'gymapp_private.social_cancel_workout_invite_direct_storage_v1(text,bigint)',
    'gymapp_private.social_workout_detail_privacy_direct_storage_v1()',
    'gymapp_private.social_workout_invite_plan_direct_storage_v1(text,bigint)'
  ] loop
    if pg_catalog.has_function_privilege('anon', private_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege(
         'authenticated', private_signature, 'EXECUTE'
       )
       or pg_catalog.has_function_privilege(
         'service_role', private_signature, 'EXECUTE'
       ) then
      raise exception 'GymApp private social helper ACL verification failed for %.',
        private_signature;
    end if;
  end loop;

  if pg_catalog.strpos(pg_catalog.lower(session_source), 'for key share') = 0
     or pg_catalog.strpos(pg_catalog.lower(session_source), 'transaction_read_only') = 0
     or pg_catalog.strpos(pg_catalog.lower(limiter_source), 'limit 128') = 0
     or pg_catalog.strpos(pg_catalog.lower(limiter_source), 'for update skip locked') = 0
     or pg_catalog.strpos(pg_catalog.lower(limiter_source), 'garmin_legacy') <> 0
     or pg_catalog.strpos(pg_catalog.lower(limiter_source), 'social_gateway') = 0
     or pg_catalog.strpos(pg_catalog.lower(social_source), 'social_live_debit_budget') = 0
     or pg_catalog.strpos(pg_catalog.lower(social_source), 'pt429') = 0
     or pg_catalog.strpos(pg_catalog.lower(social_source), 'p0001') = 0
     or pg_catalog.strpos(pg_catalog.lower(rejection_source), 'social_live_debit_budget') = 0
     or pg_catalog.strpos(pg_catalog.lower(rejection_source), 'consume_social_rate_limit') = 0
     or pg_catalog.strpos(pg_catalog.lower(rejection_source), 'p0001') = 0
     or pg_catalog.strpos(pg_catalog.lower(deletion_source), 'delete_account') = 0
     or pg_catalog.strpos(pg_catalog.lower(deletion_source), 'limit 64') = 0
     or pg_catalog.strpos(pg_catalog.lower(push_source), 'server_key = dispatch_token') = 0
     or exists (
       select 1
       from pg_catalog.pg_proc as procedure
       join pg_catalog.pg_namespace as namespace
         on namespace.oid = procedure.pronamespace
       where namespace.nspname = 'public'
         and pg_catalog.strpos(
           pg_catalog.lower(procedure.prosrc),
           'social_require_caller'
         ) > 0
     )
     or (
       select pg_catalog.count(*)
       from pg_catalog.pg_proc as procedure
       where procedure.oid in (
         pg_catalog.to_regprocedure('public.garmin_list_devices()'),
         pg_catalog.to_regprocedure(
           'public.require_live_session_for_account_deletion()'
         ),
         pg_catalog.to_regprocedure(
           'gymapp_private.realtime_has_current_auth_session()'
         )
       )
         and procedure.provolatile = 'v'
     ) <> 3
     or pg_catalog.has_function_privilege(
       'anon',
       'public.social_live_gateway_debit(uuid,uuid,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.social_live_gateway_debit(uuid,uuid,text)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.social_live_gateway_debit(uuid,uuid,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.social_gateway_perimeter_debit(uuid,uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.social_gateway_perimeter_debit(uuid,uuid)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.social_gateway_perimeter_debit(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'GymApp deep-scan database remediation verification failed.';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
