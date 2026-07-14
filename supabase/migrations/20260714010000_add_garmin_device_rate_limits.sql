begin;

-- A pending plan without an explicit device binding can be claimed by whichever
-- watch asks first. Preserve legacy rows for owner-visible recovery, but remove
-- them from delivery instead of silently choosing a device.
update public.garmin_plans
set
  status = 'invalid',
  validation_error = 'Legacy pending plan has no device binding; recreate it for a selected Garmin device.'
where status = 'pending'
  and device_id is null;

-- Earlier revocations did not retire their queued plans. Keep the records for
-- audit/recovery while releasing the per-owner pending quota. This also closes
-- legacy cross-owner device references that older table policies could admit.
update public.garmin_plans as plan
set
  status = 'invalid',
  validation_error = 'Legacy pending plan has no active owner-matched Garmin device; recreate it.'
where plan.status = 'pending'
  and plan.device_id is not null
  and not exists (
    select 1
    from public.garmin_devices as device
    where device.id = plan.device_id
      and device.user_id = plan.user_id
      and device.binding_version = 2
      and device.revoked_at is null
  );

alter table public.garmin_plans
  drop constraint if exists garmin_plans_pending_device_check;
alter table public.garmin_plans
  add constraint garmin_plans_pending_device_check
  check (status <> 'pending' or device_id is not null)
  not valid;
alter table public.garmin_plans
  validate constraint garmin_plans_pending_device_check;

-- Every bearer-token replacement is a compare-and-swap transition. Existing
-- devices start at revision one; clients must present the revision observed in
-- list/create metadata before a rotation can advance it.
alter table public.garmin_devices
  add column token_revision bigint not null default 1;
alter table public.garmin_devices
  add constraint garmin_devices_token_revision_check
  check (token_revision between 1 and 2147483647)
  not valid;
alter table public.garmin_devices
  validate constraint garmin_devices_token_revision_check;

comment on column public.garmin_devices.token_revision is
  'Server-owned monotonic CAS revision for idempotent bearer-token rotation.';

-- Preserve every historical plan while assigning it a stable request key.
-- New clients provide one UUID per logical enqueue operation; the owner/key
-- uniqueness constraint turns transport retries into deterministic lookups.
alter table public.garmin_plans
  add column client_request_id uuid;
update public.garmin_plans
set client_request_id = id
where client_request_id is null;
alter table public.garmin_plans
  alter column client_request_id set not null;
alter table public.garmin_plans
  add constraint garmin_plans_owner_request_key
  unique (user_id, client_request_id);

comment on column public.garmin_plans.client_request_id is
  'Owner-scoped idempotency key supplied once per logical plan enqueue.';

-- Durable token buckets are shared by every Edge Function isolate. The primary
-- key keeps storage to one bounded row per active device and action; revocation
-- deletes those rows through the trigger below.
create table gymapp_private.garmin_device_rate_limits (
  device_id uuid not null
    references public.garmin_devices(id) on delete cascade,
  bucket_action text not null
    check (bucket_action in ('fetch_plan', 'ack_plan', 'quarantine_plan', 'rotate_token')),
  tokens numeric(20, 9) not null
    check (tokens between 0 and 8),
  refilled_at timestamptz not null,
  primary key (device_id, bucket_action)
);

comment on table gymapp_private.garmin_device_rate_limits is
  'Atomic per-device token buckets for Garmin capability RPCs; contains no raw device tokens.';

alter table gymapp_private.garmin_device_rate_limits enable row level security;
revoke all on table gymapp_private.garmin_device_rate_limits
  from public, anon, authenticated, service_role;

-- Sensitive owner-management RPCs must stop working as soon as the backing
-- Supabase session is removed (for example, after sign-out or administrative
-- revocation). JWT signature/expiry checks alone leave that window open until
-- the access token expires. The session id is supplied by the signed JWT and
-- is never accepted as an RPC argument.
create or replace function gymapp_private.has_current_auth_session(
  p_user_id uuid
)
returns boolean
language plpgsql
stable
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
  );
end
$function$;

revoke all on function gymapp_private.has_current_auth_session(uuid)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.consume_garmin_device_rate_limit(
  p_device_id uuid,
  p_action text
)
returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  bucket_capacity numeric(20, 9);
  refill_per_second numeric(20, 9);
  request_time timestamptz := pg_catalog.clock_timestamp();
  stored_tokens numeric(20, 9);
  stored_refilled_at timestamptz;
  elapsed_seconds numeric;
  available_tokens numeric(20, 9);
  retry_after_seconds bigint;
begin
  if p_device_id is null then
    raise exception using errcode = '22023', message = 'Garmin rate-limit device is required.';
  end if;

  case p_action
    -- The watch makes at most four automatic attempts, five seconds apart. An
    -- eight-request burst and one refill every five seconds leaves retry room
    -- while bounding sustained polling to twelve requests per minute.
    when 'fetch_plan' then
      bucket_capacity := 8;
      refill_per_second := 0.2;
    when 'ack_plan' then
      bucket_capacity := 8;
      refill_per_second := 0.2;
    -- Quarantine is a defensive fallback for contract drift, not a normal
    -- watch action, so it receives a deliberately smaller budget.
    when 'quarantine_plan' then
      bucket_capacity := 2;
      refill_per_second := 1.0 / 60.0;
    -- Rotation keeps the stable device binding but replaces a bearer secret.
    -- A small burst supports setup retries without permitting rapid churn.
    when 'rotate_token' then
      bucket_capacity := 3;
      refill_per_second := 1.0 / 21600.0;
    else
      raise exception using errcode = '22023', message = 'Unsupported Garmin rate-limit action.';
  end case;

  insert into gymapp_private.garmin_device_rate_limits (
    device_id,
    bucket_action,
    tokens,
    refilled_at
  ) values (
    p_device_id,
    p_action,
    bucket_capacity - 1,
    request_time
  )
  on conflict (device_id, bucket_action) do nothing;

  if found then
    return 0;
  end if;

  select bucket.tokens, bucket.refilled_at
    into strict stored_tokens, stored_refilled_at
  from gymapp_private.garmin_device_rate_limits as bucket
  where bucket.device_id = p_device_id
    and bucket.bucket_action = p_action
  for update;

  elapsed_seconds := extract(epoch from (request_time - stored_refilled_at));
  if elapsed_seconds < 0 then
    elapsed_seconds := 0;
  end if;
  available_tokens := least(
    bucket_capacity,
    stored_tokens + (elapsed_seconds * refill_per_second)
  );

  if available_tokens >= 1 then
    update gymapp_private.garmin_device_rate_limits
    set
      tokens = available_tokens - 1,
      refilled_at = request_time
    where device_id = p_device_id
      and bucket_action = p_action;
    return 0;
  end if;

  -- Rejected calls do not write the row. This avoids turning an abusive retry
  -- loop into sustained WAL churn while the lock still makes the decision
  -- atomic across Edge Function isolates.
  retry_after_seconds := pg_catalog.ceil(
    (1 - available_tokens) / refill_per_second
  )::bigint;
  return least(greatest(retry_after_seconds, 1), 3600)::integer;
end
$function$;

revoke all on function gymapp_private.consume_garmin_device_rate_limit(uuid, text)
  from public, anon, authenticated, service_role;

-- Resolve the limiter identity from the validated bearer capability. Callers
-- can never choose another device id, and the row lock serializes rate checks
-- with device revocation before the original delivery RPC is entered.
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
  if p_device_token is null or p_device_token !~ '^[A-Fa-f0-9]{64}$' then
    return null;
  end if;

  select device.id
    into found_device_id
  from public.garmin_devices as device
  where device.device_token = gymapp_private.garmin_device_token_hash(p_device_token)
    and device.binding_version = 2
    and device.revoked_at is null
  for update;

  if not found then
    return null;
  end if;

  return gymapp_private.consume_garmin_device_rate_limit(found_device_id, p_action);
end
$function$;

revoke all on function gymapp_private.garmin_rate_limit_for_token(text, text)
  from public, anon, authenticated, service_role;

-- Permit only the exact server cancellation used by the revocation trigger.
-- Authenticated clients still have no table UPDATE grant; this narrow guard is
-- defense in depth if a future grant is accidentally broadened.
create or replace function gymapp_private.guard_garmin_plan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  validation_error text;
  caller_user_id uuid := auth.uid();
  recent_plan_count integer;
  pending_plan_count integer;
  next_plan_revision bigint;
  is_revocation_cancellation boolean := false;
  legacy_request_hash text;
  existing_legacy_plan public.garmin_plans%rowtype;
begin
  if tg_op = 'INSERT' then
    if new.user_id is null
       or (caller_user_id is not null and caller_user_id <> new.user_id) then
      raise exception using errcode = '42501', message = 'A Garmin plan can only belong to its authenticated owner.';
    end if;
    if caller_user_id is not null
       and not gymapp_private.has_current_auth_session(caller_user_id) then
      raise exception using errcode = '42501', message = 'An active authenticated session is required.';
    end if;
    validation_error := gymapp_private.garmin_plan_validation_error(new.plan);
    if validation_error is not null then
      raise exception using errcode = '22023', message = validation_error;
    end if;
    if new.device_id is null then
      raise exception using errcode = '42501', message = 'Garmin plan device binding is invalid.';
    end if;

    -- The released browser client can insert only its four historical columns
    -- and cannot choose client_request_id. (The older iOS shape omitted
    -- device_id and remains intentionally rejected rather than restoring an
    -- ambiguous first-watch claim.) Derive a canonical version-5-shaped UUID
    -- from the owner, selected device, and canonical jsonb payload. An
    -- identical transport retry is a no-op before quota/revision work.
    if new.client_request_id is null then
      legacy_request_hash := pg_catalog.lower(
        pg_catalog.encode(
          pg_catalog.sha256(
            pg_catalog.convert_to(
              pg_catalog.lower(new.user_id::text) || ':' ||
              pg_catalog.lower(new.device_id::text) || ':' ||
              new.plan::text,
              'UTF8'
            )
          ),
          'hex'
        )
      );
      new.client_request_id := (
        pg_catalog.substr(legacy_request_hash, 1, 8) || '-' ||
        pg_catalog.substr(legacy_request_hash, 9, 4) || '-5' ||
        pg_catalog.substr(legacy_request_hash, 14, 3) || '-8' ||
        pg_catalog.substr(legacy_request_hash, 18, 3) || '-' ||
        pg_catalog.substr(legacy_request_hash, 21, 12)
      )::uuid;

      perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
          new.user_id::text || ':' || new.client_request_id::text,
          719923
        )
      );
      select plan.*
        into existing_legacy_plan
      from public.garmin_plans as plan
      where plan.user_id = new.user_id
        and plan.client_request_id = new.client_request_id;
      if found then
        if existing_legacy_plan.device_id is not distinct from new.device_id
           and existing_legacy_plan.plan = new.plan then
          return null;
        end if;
        raise exception using
          errcode = '23505',
          message = 'Garmin legacy request key collision.';
      end if;
    end if;

    -- Hold the same device-row lock used by revoke, rotate, and watch delivery.
    -- If revocation wins, PostgreSQL rechecks revoked_at after the wait; if this
    -- insert wins, the revocation trigger observes and retires the new plan.
    perform 1
    from public.garmin_devices as device
    where device.id = new.device_id
      and device.user_id = new.user_id
      and device.binding_version = 2
      and device.revoked_at is null
    for update;
    if not found then
      raise exception using errcode = '42501', message = 'Garmin plan device binding is invalid.';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(new.user_id::text, 719921)
    );
    select
      pg_catalog.count(*) filter (
        where plan.created_at >= pg_catalog.clock_timestamp() - interval '24 hours'
      )::integer,
      pg_catalog.count(*) filter (where plan.status = 'pending')::integer,
      coalesce(pg_catalog.max(plan.plan_revision), 0) + 1
    into recent_plan_count, pending_plan_count, next_plan_revision
    from public.garmin_plans as plan
    where plan.user_id = new.user_id;
    if caller_user_id is not null
       and (recent_plan_count >= 10 or pending_plan_count >= 5) then
      raise exception using errcode = '54000', message = 'Garmin plan creation limit reached.';
    end if;
    if next_plan_revision > 2147483647 then
      raise exception using errcode = '54000', message = 'Garmin plan revision limit reached.';
    end if;
    new.id := pg_catalog.gen_random_uuid();
    new.status := 'pending';
    new.plan_revision := next_plan_revision;
    new.created_at := pg_catalog.clock_timestamp();
    new.downloaded_at := null;
    new.completed_at := null;
    new.result := null;
    new.validation_error := null;
    return new;
  end if;

  if new.user_id is distinct from old.user_id
     or new.plan is distinct from old.plan
     or new.plan_revision is distinct from old.plan_revision
     or new.client_request_id is distinct from old.client_request_id then
    raise exception using errcode = '22023', message = 'Garmin plan identity and payload are immutable.';
  end if;

  is_revocation_cancellation :=
    old.status = 'pending'
    and new.status = 'invalid'
    and new.device_id is not distinct from old.device_id
    and new.downloaded_at is not distinct from old.downloaded_at
    and new.completed_at is not distinct from old.completed_at
    and new.result is not distinct from old.result
    and new.validation_error = 'Garmin device was revoked before this plan was delivered.'
    and exists (
      select 1
      from public.garmin_devices as device
      where device.id = old.device_id
        and device.user_id = old.user_id
        and device.revoked_at is not null
    );

  if auth.uid() is not null and not is_revocation_cancellation and (
    new.status is distinct from old.status
    or new.device_id is distinct from old.device_id
    or new.validation_error is distinct from old.validation_error
    or new.downloaded_at is distinct from old.downloaded_at
  ) then
    raise exception using errcode = '42501', message = 'Garmin delivery state is server-controlled.';
  end if;
  return new;
end
$function$;

revoke all on function gymapp_private.guard_garmin_plan()
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.handle_garmin_device_revocation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if old.revoked_at is null and new.revoked_at is not null then
    update public.garmin_plans
    set
      status = 'invalid',
      validation_error = 'Garmin device was revoked before this plan was delivered.'
    where device_id = new.id
      and user_id = new.user_id
      and status = 'pending';

    delete from gymapp_private.garmin_device_rate_limits
    where device_id = new.id;
  end if;
  return new;
end
$function$;

revoke all on function gymapp_private.handle_garmin_device_revocation()
  from public, anon, authenticated, service_role;

drop trigger if exists garmin_devices_handle_revocation
  on public.garmin_devices;
drop trigger if exists garmin_devices_clear_rate_limits
  on public.garmin_devices;
create trigger garmin_devices_handle_revocation
after update of revoked_at
on public.garmin_devices
for each row
execute function gymapp_private.handle_garmin_device_revocation();

-- Move the existing transition logic behind ungranted core names, then reuse
-- the original public signatures for the limited wrappers. This lets the
-- migration go live before the Edge Function without a fetch/ack outage.
alter function public.garmin_fetch_pending_plan(text)
  rename to garmin_fetch_pending_plan_core;
alter function public.garmin_ack_plan(text, uuid, bigint)
  rename to garmin_ack_plan_core;
alter function public.garmin_quarantine_pending_plan(text, uuid, bigint, text)
  rename to garmin_quarantine_pending_plan_core;
alter function public.garmin_create_device(text)
  rename to garmin_create_device_core;
alter function public.garmin_revoke_device(uuid)
  rename to garmin_revoke_device_core;

create or replace function public.garmin_fetch_pending_plan(
  p_device_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  retry_after_seconds integer;
begin
  retry_after_seconds := gymapp_private.garmin_rate_limit_for_token(
    p_device_token,
    'fetch_plan'
  );
  if retry_after_seconds is null then
    return pg_catalog.jsonb_build_object('error', 'Invalid device');
  end if;
  if retry_after_seconds > 0 then
    return pg_catalog.jsonb_build_object(
      'status', 'rate_limited',
      'retryAfter', retry_after_seconds
    );
  end if;
  return public.garmin_fetch_pending_plan_core(p_device_token);
end
$function$;

create or replace function public.garmin_ack_plan(
  p_device_token text,
  p_plan_id uuid,
  p_plan_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  retry_after_seconds integer;
begin
  retry_after_seconds := gymapp_private.garmin_rate_limit_for_token(
    p_device_token,
    'ack_plan'
  );
  if retry_after_seconds is null then
    return pg_catalog.jsonb_build_object('error', 'Invalid device');
  end if;
  if retry_after_seconds > 0 then
    return pg_catalog.jsonb_build_object(
      'status', 'rate_limited',
      'retryAfter', retry_after_seconds
    );
  end if;
  return public.garmin_ack_plan_core(p_device_token, p_plan_id, p_plan_revision);
end
$function$;

create or replace function public.garmin_quarantine_pending_plan(
  p_device_token text,
  p_plan_id uuid,
  p_plan_revision bigint,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  retry_after_seconds integer;
begin
  retry_after_seconds := gymapp_private.garmin_rate_limit_for_token(
    p_device_token,
    'quarantine_plan'
  );
  if retry_after_seconds is null then
    return pg_catalog.jsonb_build_object('error', 'Invalid device');
  end if;
  if retry_after_seconds > 0 then
    return pg_catalog.jsonb_build_object(
      'status', 'rate_limited',
      'retryAfter', retry_after_seconds
    );
  end if;
  return public.garmin_quarantine_pending_plan_core(
    p_device_token,
    p_plan_id,
    p_plan_revision,
    p_reason
  );
end
$function$;

-- Keep the original client-facing signatures while putting an immediate
-- server-side session-existence check in front of the established device
-- creation/revocation logic. The renamed cores are not granted to API roles.
create or replace function public.garmin_create_device(
  p_display_name text default 'Garmin watch'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  created_result jsonb;
  created_device_id uuid;
  created_token_revision bigint;
begin
  if not gymapp_private.has_current_auth_session(caller_user_id) then
    return pg_catalog.jsonb_build_object('error', 'Unauthorized');
  end if;
  if p_display_name is null or p_display_name ~ '[[:cntrl:]]' then
    return pg_catalog.jsonb_build_object('error', 'Invalid display name');
  end if;
  created_result := public.garmin_create_device_core(p_display_name);
  if created_result ? 'error' then
    return created_result;
  end if;

  -- Any mismatch here is an internal invariant violation. Raise so the device
  -- creation is rolled back instead of committing a credential the caller did
  -- not receive.
  created_device_id := (created_result #>> '{device,id}')::uuid;
  select device.token_revision
    into strict created_token_revision
  from public.garmin_devices as device
  where device.id = created_device_id
    and device.user_id = caller_user_id;

  return pg_catalog.jsonb_set(
    created_result,
    '{device,token_revision}',
    pg_catalog.to_jsonb(created_token_revision),
    true
  );
end
$function$;

create or replace function public.garmin_revoke_device(p_device_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
begin
  if not gymapp_private.has_current_auth_session(caller_user_id) then
    return pg_catalog.jsonb_build_object('error', 'Unauthorized');
  end if;
  return public.garmin_revoke_device_core(p_device_id);
end
$function$;

-- Queue a plan through a single owner/session/device boundary. The request key
-- is durable and owner-scoped: an exact retry returns the already-created plan,
-- while reusing the key for different content or a different device conflicts.
create or replace function public.garmin_enqueue_plan(
  p_device_id uuid,
  p_plan jsonb,
  p_client_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  validation_error text;
  found_plan public.garmin_plans%rowtype;
begin
  if not gymapp_private.has_current_auth_session(caller_user_id) then
    return pg_catalog.jsonb_build_object('error', 'Unauthorized');
  end if;
  if p_device_id is null
     or p_client_request_id is null
     or p_client_request_id::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return pg_catalog.jsonb_build_object('error', 'Invalid enqueue request');
  end if;

  validation_error := gymapp_private.garmin_plan_validation_error(p_plan);
  if validation_error is not null then
    return pg_catalog.jsonb_build_object('error', 'Invalid Garmin plan');
  end if;

  -- Serialize only retries of this owner's logical request. Distinct requests
  -- still meet at the existing per-owner quota/revision lock in the trigger.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      caller_user_id::text || ':' || p_client_request_id::text,
      719923
    )
  );

  select plan.*
    into found_plan
  from public.garmin_plans as plan
  where plan.user_id = caller_user_id
    and plan.client_request_id = p_client_request_id;
  if found then
    if found_plan.device_id is not distinct from p_device_id
       and found_plan.plan = p_plan then
      return pg_catalog.jsonb_build_object(
        'status', 'already_queued',
        'planId', found_plan.id,
        'planRevision', found_plan.plan_revision,
        'planStatus', found_plan.status
      );
    end if;
    return pg_catalog.jsonb_build_object('status', 'conflict');
  end if;

  -- This lock shares the revoke/rotate/fetch ordering. Revocation cannot race a
  -- new queue entry onto a device that has already become inactive.
  perform 1
  from public.garmin_devices as device
  where device.id = p_device_id
    and device.user_id = caller_user_id
    and device.binding_version = 2
    and device.revoked_at is null
  for update;
  if not found then
    return pg_catalog.jsonb_build_object('error', 'Device not found');
  end if;

  begin
    insert into public.garmin_plans (
      user_id,
      device_id,
      status,
      plan,
      client_request_id
    ) values (
      caller_user_id,
      p_device_id,
      'pending',
      p_plan,
      p_client_request_id
    )
    returning * into strict found_plan;
  exception
    when sqlstate '54000' then
      return pg_catalog.jsonb_build_object(
        'error', 'Plan creation limit reached'
      );
  end;

  return pg_catalog.jsonb_build_object(
    'status', 'queued',
    'planId', found_plan.id,
    'planRevision', found_plan.plan_revision,
    'planStatus', found_plan.status
  );
end
$function$;

-- Owner-scoped metadata lets a client select an existing stable device UUID
-- without exposing the stored bearer-token hash or another account's devices.
create or replace function public.garmin_list_devices()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  active_devices jsonb;
begin
  if not gymapp_private.has_current_auth_session(caller_user_id) then
    return pg_catalog.jsonb_build_object('error', 'Unauthorized');
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', device.id,
        'display_name', device.display_name,
        'created_at', device.created_at,
        'last_seen_at', device.last_seen_at,
        'binding_version', device.binding_version,
        'token_revision', device.token_revision
      ) order by device.created_at, device.id
    ),
    '[]'::jsonb
  )
  into active_devices
  from public.garmin_devices as device
  where device.user_id = caller_user_id
    and device.binding_version = 2
    and device.revoked_at is null;

  return pg_catalog.jsonb_build_object('devices', active_devices);
end
$function$;

-- Rotate a compromised or lost capability while preserving the device UUID
-- already pinned by Garmin and by queued plans. The raw token is returned once.
create or replace function public.garmin_rotate_device_token(
  p_device_id uuid,
  p_replacement_token text,
  p_expected_token_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  found_device public.garmin_devices%rowtype;
  replacement_token_hash text;
  retry_after_seconds integer;
  next_token_revision bigint;
begin
  if not gymapp_private.has_current_auth_session(caller_user_id) then
    return pg_catalog.jsonb_build_object('error', 'Unauthorized');
  end if;
  if p_replacement_token is null
     or p_replacement_token !~ '^[a-f0-9]{64}$'
     or p_expected_token_revision is null
     or p_expected_token_revision not between 1 and 2147483646 then
    return pg_catalog.jsonb_build_object('error', 'Invalid rotation request');
  end if;

  replacement_token_hash := gymapp_private.garmin_device_token_hash(
    p_replacement_token
  );

  select device.*
    into found_device
  from public.garmin_devices as device
  where device.id = p_device_id
    and device.user_id = caller_user_id
    and device.binding_version = 2
    and device.revoked_at is null
  for update;
  if not found then
    return pg_catalog.jsonb_build_object('error', 'Device not found');
  end if;

  -- A retry with the same expected revision and replacement secret is a
  -- successful replay of the already-committed transition. A different stale
  -- request cannot overwrite the winner or return a credential that has
  -- already become invalid.
  if found_device.token_revision = p_expected_token_revision + 1
     and found_device.device_token = replacement_token_hash then
    return pg_catalog.jsonb_build_object(
      'status', 'already_rotated',
      'device', pg_catalog.jsonb_build_object(
        'id', found_device.id,
        'display_name', found_device.display_name,
        'created_at', found_device.created_at,
        'last_seen_at', found_device.last_seen_at,
        'binding_version', found_device.binding_version,
        'token_revision', found_device.token_revision
      )
    );
  end if;

  if found_device.token_revision <> p_expected_token_revision then
    return pg_catalog.jsonb_build_object(
      'status', 'conflict',
      'tokenRevision', found_device.token_revision
    );
  end if;
  if found_device.device_token = replacement_token_hash then
    return pg_catalog.jsonb_build_object('error', 'Replacement token unchanged');
  end if;

  -- Only a transition that can actually replace the credential consumes the
  -- rotation budget. Exact retries and stale CAS conflicts are read-only and
  -- cannot strand recovery by draining the bucket.
  retry_after_seconds := gymapp_private.consume_garmin_device_rate_limit(
    found_device.id,
    'rotate_token'
  );
  if retry_after_seconds > 0 then
    return pg_catalog.jsonb_build_object(
      'status', 'rate_limited',
      'retryAfter', retry_after_seconds
    );
  end if;

  next_token_revision := found_device.token_revision + 1;
  update public.garmin_devices
  set
    device_token = replacement_token_hash,
    token_revision = next_token_revision
  where id = found_device.id;

  return pg_catalog.jsonb_build_object(
    'status', 'rotated',
    'device', pg_catalog.jsonb_build_object(
      'id', found_device.id,
      'display_name', found_device.display_name,
      'created_at', found_device.created_at,
      'last_seen_at', found_device.last_seen_at,
      'binding_version', found_device.binding_version,
      'token_revision', next_token_revision
    )
  );
end
$function$;

revoke all on function public.garmin_fetch_pending_plan_core(text)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_ack_plan_core(text, uuid, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_quarantine_pending_plan_core(text, uuid, bigint, text)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_create_device_core(text)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_revoke_device_core(uuid)
  from public, anon, authenticated, service_role;

revoke all on function public.garmin_fetch_pending_plan(text)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_ack_plan(text, uuid, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_quarantine_pending_plan(text, uuid, bigint, text)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_list_devices()
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_rotate_device_token(uuid, text, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_create_device(text)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_revoke_device(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_enqueue_plan(uuid, jsonb, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.garmin_fetch_pending_plan(text)
  to anon;
grant execute on function public.garmin_ack_plan(text, uuid, bigint)
  to anon;
grant execute on function public.garmin_quarantine_pending_plan(text, uuid, bigint, text)
  to anon;
grant execute on function public.garmin_list_devices()
  to authenticated;
grant execute on function public.garmin_rotate_device_token(uuid, text, bigint)
  to authenticated;
grant execute on function public.garmin_create_device(text)
  to authenticated;
grant execute on function public.garmin_revoke_device(uuid)
  to authenticated;
grant execute on function public.garmin_enqueue_plan(uuid, jsonb, uuid)
  to authenticated;

-- New clients use the idempotent RPC. Preserve only the exact four-column
-- INSERT shape used by the released browser client; the trigger derives its
-- request key and owns every server-controlled field. Remove any historical
-- broader grant before restoring that compatibility capability.
revoke insert on table public.garmin_plans from public, anon, authenticated;
do $revoke_plan_insert_columns$
declare
  granted_column record;
  grantee_sql text;
begin
  for granted_column in
    select distinct privilege.grantee, privilege.column_name
    from information_schema.column_privileges as privilege
    where privilege.table_schema = 'public'
      and privilege.table_name = 'garmin_plans'
      and privilege.grantee in ('PUBLIC', 'anon', 'authenticated')
      and privilege.privilege_type = 'INSERT'
  loop
    grantee_sql := case
      when granted_column.grantee = 'PUBLIC' then 'PUBLIC'
      else pg_catalog.format('%I', granted_column.grantee)
    end;
    execute pg_catalog.format(
      'revoke insert (%I) on table public.garmin_plans from %s',
      granted_column.column_name,
      grantee_sql
    );
  end loop;
end
$revoke_plan_insert_columns$;
grant insert (user_id, device_id, status, plan)
  on table public.garmin_plans to authenticated;

do $verify$
begin
  if exists (
    select 1
    from public.garmin_plans
    where status = 'pending' and device_id is null
  ) then
    raise exception 'Unbound pending Garmin plans remain deliverable';
  end if;

  if has_function_privilege('anon', 'public.garmin_fetch_pending_plan_core(text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.garmin_ack_plan_core(text,uuid,bigint)', 'EXECUTE')
     or has_function_privilege('anon', 'public.garmin_quarantine_pending_plan_core(text,uuid,bigint,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.garmin_create_device_core(text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.garmin_revoke_device_core(uuid)', 'EXECUTE')
     or not has_function_privilege('anon', 'public.garmin_fetch_pending_plan(text)', 'EXECUTE')
     or not has_function_privilege('anon', 'public.garmin_ack_plan(text,uuid,bigint)', 'EXECUTE')
     or not has_function_privilege('anon', 'public.garmin_quarantine_pending_plan(text,uuid,bigint,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.garmin_list_devices()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.garmin_rotate_device_token(uuid,text,bigint)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.garmin_create_device(text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.garmin_revoke_device(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.garmin_enqueue_plan(uuid,jsonb,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.garmin_list_devices()', 'EXECUTE')
     or has_function_privilege('anon', 'public.garmin_rotate_device_token(uuid,text,bigint)', 'EXECUTE')
     or has_function_privilege('anon', 'public.garmin_create_device(text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.garmin_revoke_device(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.garmin_enqueue_plan(uuid,jsonb,uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.garmin_fetch_pending_plan_core(text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'gymapp_private.has_current_auth_session(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'gymapp_private.has_current_auth_session(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'gymapp_private.garmin_rate_limit_for_token(text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'gymapp_private.consume_garmin_device_rate_limit(uuid,text)', 'EXECUTE') then
    raise exception 'Garmin rate-limit function grants are broader than intended';
  end if;

  if has_table_privilege('authenticated', 'public.garmin_plans', 'INSERT')
     or has_table_privilege('anon', 'public.garmin_plans', 'INSERT')
     or not has_column_privilege('authenticated', 'public.garmin_plans', 'user_id', 'INSERT')
     or not has_column_privilege('authenticated', 'public.garmin_plans', 'device_id', 'INSERT')
     or not has_column_privilege('authenticated', 'public.garmin_plans', 'status', 'INSERT')
     or not has_column_privilege('authenticated', 'public.garmin_plans', 'plan', 'INSERT')
     or has_column_privilege('authenticated', 'public.garmin_plans', 'id', 'INSERT')
     or has_column_privilege('authenticated', 'public.garmin_plans', 'client_request_id', 'INSERT')
     or has_column_privilege('authenticated', 'public.garmin_plans', 'plan_revision', 'INSERT')
     or exists (
       select 1
       from information_schema.column_privileges as privilege
       where privilege.table_schema = 'public'
         and privilege.table_name = 'garmin_plans'
         and privilege.grantee = 'authenticated'
         and privilege.privilege_type = 'INSERT'
         and privilege.column_name not in ('user_id', 'device_id', 'status', 'plan')
     )
     or exists (
       select 1
       from information_schema.column_privileges as privilege
       where privilege.table_schema = 'public'
         and privilege.table_name = 'garmin_plans'
         and privilege.grantee in ('PUBLIC', 'anon')
         and privilege.privilege_type = 'INSERT'
     ) then
    raise exception 'Authenticated Garmin legacy INSERT grant is not narrowly scoped';
  end if;

  if has_table_privilege('anon', 'gymapp_private.garmin_device_rate_limits', 'SELECT')
     or has_table_privilege('authenticated', 'gymapp_private.garmin_device_rate_limits', 'SELECT')
     or has_table_privilege('service_role', 'gymapp_private.garmin_device_rate_limits', 'SELECT')
     or has_table_privilege('anon', 'gymapp_private.garmin_device_rate_limits', 'INSERT')
     or has_table_privilege('authenticated', 'gymapp_private.garmin_device_rate_limits', 'UPDATE') then
    raise exception 'Garmin rate-limit table is exposed';
  end if;

  if exists (
    select 1
    from public.garmin_plans as plan
    join public.garmin_devices as device on device.id = plan.device_id
    where plan.status = 'pending'
      and device.revoked_at is not null
  ) then
    raise exception 'Revoked Garmin devices retain pending plans';
  end if;

  if exists (
    select 1
    from public.garmin_plans as plan
    where plan.status = 'pending'
      and not exists (
        select 1
        from public.garmin_devices as device
        where device.id = plan.device_id
          and device.user_id = plan.user_id
          and device.binding_version = 2
          and device.revoked_at is null
      )
  ) then
    raise exception 'Pending Garmin plan has no active owner-matched device';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
