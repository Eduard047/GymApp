begin;

alter table public.garmin_devices
  add column if not exists binding_version smallint;

-- Rows created before account/device binding v2 remain auditable, but their
-- bearer tokens must not be accepted or retained in plaintext by the new bridge.
update public.garmin_devices
set
  revoked_at = coalesce(revoked_at, pg_catalog.clock_timestamp()),
  device_token = pg_catalog.lower(
    pg_catalog.encode(
      pg_catalog.sha256(pg_catalog.convert_to(device_token, 'UTF8')),
      'hex'
    )
  )
where binding_version is null;

do $constraints$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.garmin_devices'::regclass
      and conname = 'garmin_devices_binding_version_check'
  ) then
    alter table public.garmin_devices
      add constraint garmin_devices_binding_version_check
      check (binding_version is null or binding_version = 2);
  end if;
end
$constraints$;

alter table public.garmin_plans
  add column if not exists plan_revision bigint not null default 1,
  add column if not exists validation_error text;

-- Prior migrations allowed authenticated owners to write arbitrary status
-- text. Preserve those rows for audit, but remove unknown states from every
-- delivery path before validating the new finite-state constraint.
update public.garmin_plans
set
  status = 'invalid',
  validation_error = pg_catalog.left(
    pg_catalog.concat(
      'Legacy unsupported status quarantined: ',
      pg_catalog.quote_literal(status)
    ),
    200
  )
where status not in ('pending', 'downloaded', 'completed', 'invalid', 'superseded');

alter table public.garmin_plans
  drop constraint if exists garmin_plans_status_check;
alter table public.garmin_plans
  add constraint garmin_plans_status_check
  check (status in ('pending', 'downloaded', 'completed', 'invalid', 'superseded'))
  not valid;
alter table public.garmin_plans validate constraint garmin_plans_status_check;

alter table public.garmin_plans
  drop constraint if exists garmin_plans_revision_check;
alter table public.garmin_plans
  add constraint garmin_plans_revision_check
  check (plan_revision between 1 and 2147483647);

do $constraints$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.garmin_plans'::regclass
      and conname = 'garmin_plans_validation_error_length_check'
  ) then
    alter table public.garmin_plans
      add constraint garmin_plans_validation_error_length_check
      check (validation_error is null or pg_catalog.char_length(validation_error) between 1 and 200);
  end if;
end
$constraints$;

create schema if not exists gymapp_private;
revoke all on schema gymapp_private from public, anon, authenticated;

create or replace function gymapp_private.garmin_device_token_hash(p_token text)
returns text
language sql
immutable
strict
security invoker
set search_path = ''
as $function$
  select pg_catalog.lower(
    pg_catalog.encode(
      pg_catalog.sha256(pg_catalog.convert_to(p_token, 'UTF8')),
      'hex'
    )
  )
$function$;

revoke all on function gymapp_private.garmin_device_token_hash(text)
  from public, anon, authenticated;

create or replace function gymapp_private.garmin_account_binding(p_user_id uuid)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  select pg_catalog.lower(
    pg_catalog.encode(
      pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.lower(p_user_id::text), 'UTF8')),
      'hex'
    )
  )
$function$;

revoke all on function gymapp_private.garmin_account_binding(uuid)
  from public, anon, authenticated;

create or replace function gymapp_private.garmin_plan_validation_error(p_plan jsonb)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  exercise_value jsonb;
  exercises_value jsonb;
  set_value jsonb;
  sets_value jsonb;
  weight_value numeric;
  reps_value numeric;
  order_value numeric;
  set_index integer := 0;
  total_sets integer := 0;
  total_exercise_name_bytes integer := 0;
begin
  if p_plan is null or pg_catalog.jsonb_typeof(p_plan) is distinct from 'object' then
    return 'Plan must be a JSON object.';
  end if;
  if pg_catalog.octet_length(pg_catalog.convert_to(p_plan::text, 'UTF8')) > 65536 then
    return 'Plan exceeds 65536 encoded bytes.';
  end if;
  if pg_catalog.jsonb_typeof(p_plan->'source') is distinct from 'string'
     or pg_catalog.char_length(pg_catalog.btrim(p_plan->>'source')) not between 1 and 32 then
    return 'Plan source is invalid.';
  end if;
  if pg_catalog.jsonb_typeof(p_plan->'version') is distinct from 'number'
     or (p_plan->>'version')::numeric <> 1 then
    return 'Plan version must be 1.';
  end if;
  if pg_catalog.jsonb_typeof(p_plan->'title') is distinct from 'string'
     or pg_catalog.char_length(pg_catalog.btrim(p_plan->>'title')) not between 1 and 120 then
    return 'Plan title is invalid.';
  end if;
  if pg_catalog.jsonb_typeof(p_plan->'note') is distinct from 'string'
     or pg_catalog.char_length(pg_catalog.btrim(p_plan->>'note')) > 2000 then
    return 'Plan note is invalid.';
  end if;
  if pg_catalog.jsonb_typeof(p_plan->'createdAt') is distinct from 'string'
     or pg_catalog.char_length(p_plan->>'createdAt') not between 20 and 40
     or (p_plan->>'createdAt') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$' then
    return 'Plan createdAt is invalid.';
  end if;
  if pg_catalog.jsonb_typeof(p_plan->'startedAt') is distinct from 'string'
     or pg_catalog.char_length(p_plan->>'startedAt') not between 20 and 40
     or (p_plan->>'startedAt') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$' then
    return 'Plan startedAt is invalid.';
  end if;
  begin
    perform (p_plan->>'createdAt')::timestamptz;
    perform (p_plan->>'startedAt')::timestamptz;
  exception when others then
    return 'Plan timestamp cannot be parsed.';
  end;

  exercises_value := p_plan->'exercises';
  if pg_catalog.jsonb_typeof(exercises_value) is distinct from 'array'
     or pg_catalog.jsonb_array_length(exercises_value) not between 1 and 60 then
    return 'Plan exercise count is invalid.';
  end if;

  for exercise_value in
    select item.value
    from pg_catalog.jsonb_array_elements(exercises_value) as item(value)
  loop
    if pg_catalog.jsonb_typeof(exercise_value) is distinct from 'object'
       or pg_catalog.jsonb_typeof(exercise_value->'name') is distinct from 'string'
       or pg_catalog.char_length(exercise_value->>'name') not between 1 and 160
       or pg_catalog.char_length(pg_catalog.btrim(exercise_value->>'name')) not between 1 and 160
       or pg_catalog.octet_length(pg_catalog.convert_to(exercise_value->>'name', 'UTF8')) > 640 then
      return 'Plan exercise name is invalid.';
    end if;
    sets_value := exercise_value->'sets';
    if pg_catalog.jsonb_typeof(sets_value) is distinct from 'array'
       or pg_catalog.jsonb_array_length(sets_value) not between 1 and 60 then
      return 'Plan exercise set count is invalid.';
    end if;
    total_sets := total_sets + pg_catalog.jsonb_array_length(sets_value);
    if total_sets > 60 then
      return 'Plan exceeds 60 total sets.';
    end if;
    total_exercise_name_bytes := total_exercise_name_bytes
      + pg_catalog.octet_length(
          pg_catalog.convert_to(pg_catalog.btrim(exercise_value->>'name'), 'UTF8')
        ) * pg_catalog.jsonb_array_length(sets_value);
    if total_exercise_name_bytes > 12000 then
      return 'Plan exercise names exceed the Garmin storage byte limit.';
    end if;

    set_index := 0;
    for set_value in
      select item.value
      from pg_catalog.jsonb_array_elements(sets_value) as item(value)
    loop
      if pg_catalog.jsonb_typeof(set_value) is distinct from 'object'
         or pg_catalog.jsonb_typeof(set_value->'weight') is distinct from 'number'
         or pg_catalog.jsonb_typeof(set_value->'reps') is distinct from 'number' then
        return 'Plan set requires numeric weight and reps.';
      end if;
      weight_value := (set_value->>'weight')::numeric;
      reps_value := (set_value->>'reps')::numeric;
      if weight_value < 0 or weight_value > 1000000
         or reps_value < 1 or reps_value > 10000
         or reps_value <> pg_catalog.trunc(reps_value) then
        return 'Plan set values are outside the supported range.';
      end if;
      if set_value ? 'orderIndex' then
        if pg_catalog.jsonb_typeof(set_value->'orderIndex') is distinct from 'number' then
          return 'Plan set orderIndex must be numeric.';
        end if;
        order_value := (set_value->>'orderIndex')::numeric;
        if order_value <> set_index
           or order_value <> pg_catalog.trunc(order_value) then
          return 'Plan set orderIndex does not match its set position.';
        end if;
      end if;
      set_index := set_index + 1;
    end loop;
  end loop;

  return null;
end
$function$;

comment on function gymapp_private.garmin_plan_validation_error(jsonb) is
  'Returns a bounded Garmin plan validation error or NULL for a valid v1 plan.';

revoke all on function gymapp_private.garmin_plan_validation_error(jsonb)
  from public, anon, authenticated;

-- Preserve existing invalid rows for audit while removing them from the
-- pending delivery queue. No workout plan is deleted by this migration.
with inspected as materialized (
  select
    plan.id,
    gymapp_private.garmin_plan_validation_error(plan.plan) as validation_error
  from public.garmin_plans as plan
  where plan.status = 'pending'
)
update public.garmin_plans as plan
set
  status = 'invalid',
  validation_error = pg_catalog.left(inspected.validation_error, 200)
from inspected
where plan.id = inspected.id
  and inspected.validation_error is not null;

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
begin
  if tg_op = 'INSERT' then
    if new.user_id is null
       or (caller_user_id is not null and caller_user_id <> new.user_id) then
      raise exception using errcode = '42501', message = 'A Garmin plan can only belong to its authenticated owner.';
    end if;
    validation_error := gymapp_private.garmin_plan_validation_error(new.plan);
    if validation_error is not null then
      raise exception using errcode = '22023', message = validation_error;
    end if;
    if new.device_id is null or not exists (
      select 1
      from public.garmin_devices as device
      where device.id = new.device_id
        and device.user_id = new.user_id
        and device.binding_version = 2
        and device.revoked_at is null
    ) then
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
    -- These values describe server delivery state, not client input.
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
     or new.plan_revision is distinct from old.plan_revision then
    raise exception using errcode = '22023', message = 'Garmin plan identity and payload are immutable.';
  end if;
  if auth.uid() is not null and (
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
  from public, anon, authenticated;

drop trigger if exists garmin_plans_security_guard on public.garmin_plans;
create trigger garmin_plans_security_guard
before insert or update
on public.garmin_plans
for each row
execute function gymapp_private.guard_garmin_plan();

create or replace function public.garmin_create_device(p_display_name text default 'Garmin watch')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  clean_display_name text := pg_catalog.btrim(p_display_name);
  created_device public.garmin_devices%rowtype;
  generated_token text;
  active_device_count integer;
  recent_device_count integer;
begin
  if caller_user_id is null then
    return pg_catalog.jsonb_build_object('error', 'Unauthorized');
  end if;
  if clean_display_name is null
     or pg_catalog.char_length(clean_display_name) not between 1 and 80
     or pg_catalog.octet_length(pg_catalog.convert_to(clean_display_name, 'UTF8')) > 320 then
    return pg_catalog.jsonb_build_object('error', 'Invalid display name');
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_user_id::text, 719922)
  );
  select
    pg_catalog.count(*) filter (
      where device.binding_version = 2 and device.revoked_at is null
    )::integer,
    pg_catalog.count(*) filter (
      where device.created_at >= pg_catalog.clock_timestamp() - interval '24 hours'
    )::integer
  into active_device_count, recent_device_count
  from public.garmin_devices as device
  where device.user_id = caller_user_id;
  if active_device_count >= 5 or recent_device_count >= 20 then
    return pg_catalog.jsonb_build_object('error', 'Device creation limit reached');
  end if;
  generated_token := pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '')
    || pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '');
  insert into public.garmin_devices (
    user_id, device_token, display_name, binding_version,
    created_at, last_seen_at, revoked_at
  ) values (
    caller_user_id, gymapp_private.garmin_device_token_hash(generated_token), clean_display_name, 2,
    pg_catalog.clock_timestamp(), null, null
  )
  returning * into strict created_device;
  return pg_catalog.jsonb_build_object(
    'device', pg_catalog.jsonb_build_object(
      'id', created_device.id,
      'device_token', generated_token,
      'display_name', created_device.display_name,
      'created_at', created_device.created_at,
      'binding_version', created_device.binding_version
    )
  );
end
$function$;

comment on column public.garmin_devices.device_token is
  'SHA-256 hash of the v2 bearer token. The raw token is returned only at device creation.';

create or replace function public.garmin_revoke_device(p_device_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  found_device public.garmin_devices%rowtype;
begin
  if caller_user_id is null then
    return pg_catalog.jsonb_build_object('error', 'Unauthorized');
  end if;
  select device.*
    into found_device
  from public.garmin_devices as device
  where device.id = p_device_id
    and device.user_id = caller_user_id
    and device.binding_version = 2
  for update;
  if not found then
    return pg_catalog.jsonb_build_object('error', 'Device not found');
  end if;
  if found_device.revoked_at is not null then
    return pg_catalog.jsonb_build_object('status', 'already_revoked');
  end if;
  update public.garmin_devices
  set revoked_at = pg_catalog.clock_timestamp()
  where id = found_device.id;
  return pg_catalog.jsonb_build_object('status', 'revoked');
end
$function$;

create or replace function public.garmin_fetch_pending_plan(p_device_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  found_device public.garmin_devices%rowtype;
  found_plan public.garmin_plans%rowtype;
  validation_error text;
begin
  if p_device_token is null or p_device_token !~ '^[A-Fa-f0-9]{64}$' then
    return pg_catalog.jsonb_build_object('error', 'Invalid device');
  end if;
  select device.*
    into found_device
  from public.garmin_devices as device
  where device.device_token = gymapp_private.garmin_device_token_hash(p_device_token)
    and device.binding_version = 2
    and device.revoked_at is null
  for update;
  if not found then
    return pg_catalog.jsonb_build_object('error', 'Invalid device');
  end if;

  -- Serialize delivery selection with inserts for this account. This ensures a
  -- fetch cannot select an older committed row while a newer row is being
  -- assigned its monotonic revision.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(found_device.user_id::text, 719921)
  );

  select plan.*
    into found_plan
  from public.garmin_plans as plan
  where plan.user_id = found_device.user_id
    and plan.status = 'pending'
    and (plan.device_id is null or plan.device_id = found_device.id)
  order by plan.plan_revision desc, plan.created_at desc, plan.id
  limit 1
  for update skip locked;
  if not found then
    update public.garmin_devices
    set last_seen_at = pg_catalog.clock_timestamp()
    where id = found_device.id;
    return pg_catalog.jsonb_build_object('status', 'empty');
  end if;

  validation_error := gymapp_private.garmin_plan_validation_error(found_plan.plan);
  if validation_error is not null then
    update public.garmin_plans
    set
      status = 'invalid',
      validation_error = pg_catalog.left(validation_error, 200)
    where id = found_plan.id;
    return pg_catalog.jsonb_build_object(
      'status', 'invalid',
      'planId', found_plan.id,
      'planRevision', found_plan.plan_revision
    );
  end if;

  -- Bind an unscoped legacy plan to the first device that fetches it. The row
  -- remains pending until an explicit, idempotent acknowledgement arrives.
  if found_plan.device_id is null then
    update public.garmin_plans
    set device_id = found_device.id
    where id = found_plan.id;
  end if;
  update public.garmin_plans as older_plan
  set
    status = 'superseded',
    validation_error = 'Superseded by a newer pending plan.'
  where older_plan.user_id = found_device.user_id
    and older_plan.status = 'pending'
    and older_plan.id <> found_plan.id
    and (older_plan.device_id is null or older_plan.device_id = found_device.id)
    and (
      older_plan.plan_revision < found_plan.plan_revision
      or (
        older_plan.plan_revision = found_plan.plan_revision
        and (older_plan.created_at, older_plan.id) < (found_plan.created_at, found_plan.id)
      )
    );

  update public.garmin_devices
  set last_seen_at = pg_catalog.clock_timestamp()
  where id = found_device.id;
  return pg_catalog.jsonb_build_object(
    'status', 'candidate',
    'bindingVersion', 2,
    'accountBinding', gymapp_private.garmin_account_binding(found_device.user_id),
    'deviceBinding', found_device.id,
    'planId', found_plan.id,
    'planRevision', found_plan.plan_revision,
    'plan', found_plan.plan
  );
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
  found_device public.garmin_devices%rowtype;
  found_plan public.garmin_plans%rowtype;
  validation_error text;
begin
  if p_device_token is null or p_device_token !~ '^[A-Fa-f0-9]{64}$'
     or p_plan_id is null or p_plan_revision is null
     or p_plan_revision not between 1 and 2147483647 then
    return pg_catalog.jsonb_build_object('error', 'Invalid acknowledgement');
  end if;
  select device.* into found_device
  from public.garmin_devices as device
  where device.device_token = gymapp_private.garmin_device_token_hash(p_device_token)
    and device.binding_version = 2
    and device.revoked_at is null
  for update;
  if not found then
    return pg_catalog.jsonb_build_object('error', 'Invalid device');
  end if;
  select plan.* into found_plan
  from public.garmin_plans as plan
  where plan.id = p_plan_id
    and plan.user_id = found_device.user_id
    and plan.status in ('pending', 'downloaded')
    and plan.plan_revision = p_plan_revision
    and plan.device_id = found_device.id
  for update;
  if not found then
    return pg_catalog.jsonb_build_object('status', 'conflict');
  end if;
  if found_plan.status = 'downloaded' then
    return pg_catalog.jsonb_build_object(
      'status', 'already_acknowledged',
      'planId', found_plan.id,
      'planRevision', found_plan.plan_revision
    );
  end if;
  validation_error := gymapp_private.garmin_plan_validation_error(found_plan.plan);
  if validation_error is not null then
    update public.garmin_plans
    set status = 'invalid', validation_error = pg_catalog.left(validation_error, 200)
    where id = found_plan.id;
    return pg_catalog.jsonb_build_object('status', 'invalid');
  end if;
  update public.garmin_plans
  set
    status = 'downloaded',
    device_id = found_device.id,
    downloaded_at = pg_catalog.clock_timestamp(),
    validation_error = null
  where id = found_plan.id;
  return pg_catalog.jsonb_build_object(
    'status', 'acknowledged',
    'planId', found_plan.id,
    'planRevision', found_plan.plan_revision
  );
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
  found_device public.garmin_devices%rowtype;
  found_plan public.garmin_plans%rowtype;
  clean_reason text := pg_catalog.btrim(p_reason);
begin
  if clean_reason is null or pg_catalog.char_length(clean_reason) not between 1 and 200 then
    return pg_catalog.jsonb_build_object('error', 'Invalid quarantine reason');
  end if;
  if p_device_token is null or p_device_token !~ '^[A-Fa-f0-9]{64}$'
     or p_plan_id is null or p_plan_revision is null
     or p_plan_revision not between 1 and 2147483647 then
    return pg_catalog.jsonb_build_object('error', 'Invalid quarantine request');
  end if;
  select device.* into found_device
  from public.garmin_devices as device
  where device.device_token = gymapp_private.garmin_device_token_hash(p_device_token)
    and device.binding_version = 2
    and device.revoked_at is null
  for update;
  if not found then
    return pg_catalog.jsonb_build_object('error', 'Invalid device');
  end if;
  select plan.* into found_plan
  from public.garmin_plans as plan
  where plan.id = p_plan_id
    and plan.user_id = found_device.user_id
    and plan.status = 'pending'
    and plan.plan_revision = p_plan_revision
    and plan.device_id = found_device.id
  for update;
  if not found then
    return pg_catalog.jsonb_build_object('status', 'conflict');
  end if;
  update public.garmin_plans
  set status = 'invalid', validation_error = clean_reason
  where id = found_plan.id;
  return pg_catalog.jsonb_build_object('status', 'quarantined');
end
$function$;

alter function public.garmin_create_device(text) set search_path = '';
alter function public.garmin_revoke_device(uuid) set search_path = '';
alter function public.garmin_fetch_pending_plan(text) set search_path = '';
alter function public.garmin_ack_plan(text, uuid, bigint) set search_path = '';
alter function public.garmin_quarantine_pending_plan(text, uuid, bigint, text) set search_path = '';

revoke all on function public.garmin_create_device(text) from public, anon, authenticated;
revoke all on function public.garmin_revoke_device(uuid) from public, anon, authenticated;
revoke all on function public.garmin_fetch_pending_plan(text) from public, anon, authenticated;
revoke all on function public.garmin_ack_plan(text, uuid, bigint) from public, anon, authenticated;
revoke all on function public.garmin_quarantine_pending_plan(text, uuid, bigint, text) from public, anon, authenticated;
grant execute on function public.garmin_create_device(text) to authenticated;
grant execute on function public.garmin_revoke_device(uuid) to authenticated;
grant execute on function public.garmin_fetch_pending_plan(text) to anon;
grant execute on function public.garmin_ack_plan(text, uuid, bigint) to anon;
grant execute on function public.garmin_quarantine_pending_plan(text, uuid, bigint, text) to anon;

-- Table privileges are a separate gate from RLS. Reassert the complete matrix
-- so the migration is safe on projects that do not auto-grant public-schema
-- tables as well as older projects that inherited broader defaults.
revoke all on table public.garmin_devices, public.garmin_plans
  from public, anon, authenticated;

-- Table-level REVOKE does not necessarily remove historical privileges that
-- were granted directly on individual columns. Remove those grants before the
-- two reviewed table-level capabilities are restored below.
do $column_revoke$
declare
  column_grant record;
  grantee_sql text;
begin
  for column_grant in
    select distinct table_name, grantee, privilege_type, column_name
    from information_schema.column_privileges
    where table_schema = 'public'
      and table_name in ('garmin_devices', 'garmin_plans')
      and grantee in ('PUBLIC', 'anon', 'authenticated')
      and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'REFERENCES')
  loop
    grantee_sql := case
      when column_grant.grantee = 'PUBLIC' then 'PUBLIC'
      else pg_catalog.format('%I', column_grant.grantee)
    end;
    execute pg_catalog.format(
      'revoke %s (%I) on table public.%I from %s',
      column_grant.privilege_type,
      column_grant.column_name,
      column_grant.table_name,
      grantee_sql
    );
  end loop;
end
$column_revoke$;

grant select on table public.garmin_plans to authenticated;
grant insert on table public.garmin_plans to authenticated;
revoke update on table public.garmin_devices, public.garmin_plans from authenticated;

create index if not exists garmin_plans_pending_delivery_idx
  on public.garmin_plans (user_id, plan_revision desc)
  where status = 'pending';

do $verify$
begin
  if exists (
    select 1 from public.garmin_devices
    where binding_version is null and revoked_at is null
  ) then
    raise exception 'Legacy unbound Garmin devices remain active';
  end if;
  if exists (
    select 1 from public.garmin_plans
    where status = 'pending'
      and gymapp_private.garmin_plan_validation_error(plan) is not null
  ) then
    raise exception 'Invalid Garmin plans remain pending';
  end if;
  if has_function_privilege('authenticated', 'public.garmin_fetch_pending_plan(text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.garmin_create_device(text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.garmin_revoke_device(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'gymapp_private.garmin_plan_validation_error(jsonb)', 'EXECUTE') then
    raise exception 'Garmin function grants are broader than intended';
  end if;
  if has_table_privilege('anon', 'public.garmin_devices', 'SELECT')
     or has_table_privilege('anon', 'public.garmin_plans', 'SELECT')
     or has_table_privilege('authenticated', 'public.garmin_devices', 'UPDATE')
     or has_table_privilege('authenticated', 'public.garmin_devices', 'INSERT')
     or has_table_privilege('authenticated', 'public.garmin_plans', 'UPDATE')
     or has_table_privilege('authenticated', 'public.garmin_devices', 'SELECT')
     or not has_table_privilege('authenticated', 'public.garmin_plans', 'SELECT')
     or not has_table_privilege('authenticated', 'public.garmin_plans', 'INSERT') then
    raise exception 'Garmin table grants do not match the intended least-privilege matrix';
  end if;
  if exists (
    select 1
    from pg_catalog.pg_attribute as attribute
    join pg_catalog.pg_class as relation on relation.oid = attribute.attrelid
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    cross join lateral pg_catalog.aclexplode(attribute.attacl) as column_acl
    left join pg_catalog.pg_roles as grantee on grantee.oid = column_acl.grantee
    where namespace.nspname = 'public'
      and relation.relname in ('garmin_devices', 'garmin_plans')
      and attribute.attnum > 0
      and not attribute.attisdropped
      and (column_acl.grantee = 0 or grantee.rolname in ('anon', 'authenticated'))
      and column_acl.privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'REFERENCES')
  ) then
    raise exception 'Legacy Garmin column grants remain';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
