begin;

-- Bound the gateway cutover so a live fetch/ack transaction cannot leave the
-- deployment waiting indefinitely for relation or function locks. PostgreSQL
-- rolls the whole migration back when either limit is reached, allowing a
-- deliberate retry after the active request completes.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- The Edge Function authenticates v3 HMAC capabilities before PostgREST and
-- bounds temporary legacy v2 tokens to an indexed lookup. Direct anonymous RPC
-- access would bypass that version gate, so only the backend role may execute
-- watch delivery functions.
revoke all on function public.garmin_fetch_pending_plan(text)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_ack_plan(text, uuid, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_quarantine_pending_plan(text, uuid, bigint, text)
  from public, anon, authenticated, service_role;

grant execute on function public.garmin_fetch_pending_plan(text)
  to service_role;
grant execute on function public.garmin_ack_plan(text, uuid, bigint)
  to service_role;
grant execute on function public.garmin_quarantine_pending_plan(text, uuid, bigint, text)
  to service_role;

alter table public.garmin_devices
  add column if not exists legacy_capability_last_seen_at timestamptz,
  add column if not exists v3_capability_last_seen_at timestamptz;

comment on column public.garmin_devices.legacy_capability_last_seen_at is
  'Hour-coalesced server observation used only to retire 64-hex Garmin capabilities safely.';
comment on column public.garmin_devices.v3_capability_last_seen_at is
  'Hour-coalesced server observation of an HMAC-authenticated g3 Garmin capability.';

-- HMAC-invalid v3 envelopes are rejected before the database. Temporary v2
-- nonces require one indexed lookup, but direct API access is closed and an
-- unknown nonce creates no row or limiter write. A valid capability can consume
-- only its own durable per-device bucket.
create or replace function gymapp_private.garmin_rate_limit_for_token(
  p_device_token text,
  p_action text
)
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  found_device_id uuid;
begin
  if p_device_token is null or p_device_token !~ '^[a-f0-9]{64}$' then
    return null;
  end if;

  select device.id
    into found_device_id
  from public.garmin_devices as device
  where device.device_token = gymapp_private.garmin_device_token_hash(
      p_device_token
    )
    and device.binding_version = 2
    and device.revoked_at is null
  for update;

  if not found then
    return null;
  end if;

  return gymapp_private.consume_garmin_device_rate_limit(
    found_device_id,
    p_action
  );
end
$function$;

revoke all on function gymapp_private.garmin_rate_limit_for_token(text, text)
  from public, anon, authenticated, service_role;

-- Record only an already-resolved device, at most once per capability version
-- per hour. Invalid nonces update no row, and repeated traffic cannot turn
-- migration telemetry into unbounded write amplification.
create or replace function public.garmin_record_capability_use(
  p_device_token text,
  p_capability_version smallint
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  observation_time timestamptz := pg_catalog.clock_timestamp();
begin
  if p_device_token is null
     or p_device_token !~ '^[a-f0-9]{64}$'
     or p_capability_version is null
     or p_capability_version not in (2, 3) then
    return false;
  end if;

  if p_capability_version = 2 then
    update public.garmin_devices as device
    set legacy_capability_last_seen_at = observation_time
    where device.device_token = gymapp_private.garmin_device_token_hash(
        p_device_token
      )
      and device.binding_version = 2
      and device.revoked_at is null
      and (
        device.legacy_capability_last_seen_at is null
        or device.legacy_capability_last_seen_at <
          observation_time - interval '1 hour'
      );
  else
    update public.garmin_devices as device
    set v3_capability_last_seen_at = observation_time
    where device.device_token = gymapp_private.garmin_device_token_hash(
        p_device_token
      )
      and device.binding_version = 2
      and device.revoked_at is null
      and (
        device.v3_capability_last_seen_at is null
        or device.v3_capability_last_seen_at <
          observation_time - interval '1 hour'
      );
  end if;

  return found;
end
$function$;

revoke all on function public.garmin_record_capability_use(text, smallint)
  from public, anon, authenticated, service_role;
grant execute on function public.garmin_record_capability_use(text, smallint)
  to service_role;

-- Retire the global shared buckets. They are no longer on a request path and
-- retaining them would make future code likely to reintroduce cross-device
-- collateral denial of service.
drop function if exists gymapp_private.consume_garmin_preauth_rate_limit(
  text,
  text
);
drop table if exists gymapp_private.garmin_preauth_rate_limits;

do $verify$
begin
  if has_function_privilege(
       'anon',
       'public.garmin_fetch_pending_plan(text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.garmin_fetch_pending_plan(text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.garmin_ack_plan(text,uuid,bigint)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.garmin_ack_plan(text,uuid,bigint)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.garmin_quarantine_pending_plan(text,uuid,bigint,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.garmin_quarantine_pending_plan(text,uuid,bigint,text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'public.garmin_fetch_pending_plan(text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'public.garmin_ack_plan(text,uuid,bigint)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'public.garmin_quarantine_pending_plan(text,uuid,bigint,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.garmin_record_capability_use(text,smallint)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.garmin_record_capability_use(text,smallint)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'public.garmin_record_capability_use(text,smallint)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'gymapp_private.garmin_rate_limit_for_token(text,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'gymapp_private.garmin_rate_limit_for_token(text,text)',
       'EXECUTE'
     ) then
    raise exception 'Garmin capability gateway grants are broader than intended';
  end if;

  if pg_catalog.to_regclass(
       'gymapp_private.garmin_preauth_rate_limits'
     ) is not null
     or pg_catalog.to_regprocedure(
       'gymapp_private.consume_garmin_preauth_rate_limit(text,text)'
     ) is not null then
    raise exception 'Shared Garmin pre-auth limiter state remains installed';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
