begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Released clients keep using garmin_create_device(text). New clients supply
-- all retry material once, so an outcome-unknown request can return the exact
-- same credential without storing its raw bearer token. Historical rows remain
-- NULL and are unaffected by the partial unique index.
alter table public.garmin_devices
  add column if not exists creation_request_id uuid;

create unique index if not exists garmin_devices_creation_request_id_unique
  on public.garmin_devices (creation_request_id)
  where creation_request_id is not null;

comment on column public.garmin_devices.creation_request_id is
  'Globally unique UUIDv4 for outcome-idempotent creation; the raw token is never stored.';

-- A signed JWT whose exact Auth session has passed not_after is no longer a
-- current session. Keep the shared Garmin owner boundary aligned with session
-- deletion/revocation before exposing the new creator.
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
  current_session_id uuid;
begin
  if p_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;

  current_session_id := session_id_text::uuid;
  return exists (
    select 1
    from auth.sessions as session
    where session.id = current_session_id
      and session.user_id = p_user_id
      and (
        session.not_after is null
        or session.not_after > pg_catalog.clock_timestamp()
      )
  );
end
$function$;

revoke all on function gymapp_private.has_current_auth_session(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.garmin_create_device_idempotent(
  p_request_id uuid,
  p_device_id uuid,
  p_device_token text,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  clean_display_name text := pg_catalog.btrim(p_display_name);
  requested_token_hash text;
  found_device public.garmin_devices%rowtype;
  active_device_count integer;
  recent_device_count integer;
  created_at_value timestamptz := pg_catalog.clock_timestamp();
begin
  if not gymapp_private.has_current_auth_session(caller_user_id) then
    return pg_catalog.jsonb_build_object('error', 'Unauthorized');
  end if;
  if p_request_id is null
     or p_request_id::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or p_device_id is null
     or p_device_id::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or p_device_token is null
     or p_device_token !~ '^[a-f0-9]{64}$' then
    return pg_catalog.jsonb_build_object(
      'error', 'Invalid device creation request'
    );
  end if;
  if clean_display_name is null
     or pg_catalog.char_length(clean_display_name) not between 1 and 80
     or pg_catalog.octet_length(
       pg_catalog.convert_to(clean_display_name, 'UTF8')
     ) > 320
     or clean_display_name ~ '[[:cntrl:]]' then
    return pg_catalog.jsonb_build_object('error', 'Invalid display name');
  end if;

  requested_token_hash := gymapp_private.garmin_device_token_hash(
    p_device_token
  );

  -- The request UUID is globally owner-bound. This serializes an exact retry,
  -- a concurrent duplicate, and a wrong-owner replay before any quota or row
  -- mutation. Hash collisions only add harmless serialization.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_request_id::text, 719924)
  );

  select device.*
    into found_device
  from public.garmin_devices as device
  where device.creation_request_id = p_request_id;
  if found then
    if found_device.user_id = caller_user_id
       and found_device.id = p_device_id
       and found_device.device_token = requested_token_hash
       and found_device.display_name = clean_display_name
       and found_device.binding_version = 2
       and found_device.token_revision = 1
       and found_device.revoked_at is null then
      return pg_catalog.jsonb_build_object(
        'status', 'already_created',
        'device', pg_catalog.jsonb_build_object(
          'id', found_device.id,
          'device_token', p_device_token,
          'display_name', found_device.display_name,
          'created_at', found_device.created_at,
          'last_seen_at', found_device.last_seen_at,
          'binding_version', found_device.binding_version,
          'token_revision', found_device.token_revision
        )
      );
    end if;
    return pg_catalog.jsonb_build_object('status', 'conflict');
  end if;

  -- Share the legacy per-owner serialization and exact limits. Concurrent
  -- logical creates cannot overrun either the five-active or 20-per-day cap.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_user_id::text, 719922)
  );
  select
    pg_catalog.count(*) filter (
      where device.binding_version = 2 and device.revoked_at is null
    )::integer,
    pg_catalog.count(*) filter (
      where device.created_at >= created_at_value - interval '24 hours'
    )::integer
  into active_device_count, recent_device_count
  from public.garmin_devices as device
  where device.user_id = caller_user_id;
  if active_device_count >= 5 or recent_device_count >= 20 then
    return pg_catalog.jsonb_build_object(
      'error', 'Device creation limit reached'
    );
  end if;

  insert into public.garmin_devices (
    id,
    user_id,
    device_token,
    display_name,
    binding_version,
    token_revision,
    creation_request_id,
    created_at,
    last_seen_at,
    revoked_at
  ) values (
    p_device_id,
    caller_user_id,
    requested_token_hash,
    clean_display_name,
    2,
    1,
    p_request_id,
    created_at_value,
    null,
    null
  )
  on conflict do nothing
  returning * into found_device;
  if not found then
    return pg_catalog.jsonb_build_object('status', 'conflict');
  end if;

  return pg_catalog.jsonb_build_object(
    'status', 'created',
    'device', pg_catalog.jsonb_build_object(
      'id', found_device.id,
      'device_token', p_device_token,
      'display_name', found_device.display_name,
      'created_at', found_device.created_at,
      'last_seen_at', found_device.last_seen_at,
      'binding_version', found_device.binding_version,
      'token_revision', found_device.token_revision
    )
  );
end
$function$;

revoke all on function public.garmin_create_device_idempotent(
  uuid, uuid, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.garmin_create_device_idempotent(
  uuid, uuid, text, text
) to authenticated;

-- creation_request_id is internal replay metadata. Keep all direct device-table
-- access closed; clients use only the reviewed owner-bound RPCs.
revoke all on table public.garmin_devices
  from public, anon, authenticated;

do $privilege_guard$
begin
  if has_function_privilege(
       'anon',
       'public.garmin_create_device_idempotent(uuid,uuid,text,text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.garmin_create_device_idempotent(uuid,uuid,text,text)',
       'EXECUTE'
     ) then
    raise exception 'Idempotent Garmin device creation grants are invalid';
  end if;
end
$privilege_guard$;

notify pgrst, 'reload schema';

commit;
