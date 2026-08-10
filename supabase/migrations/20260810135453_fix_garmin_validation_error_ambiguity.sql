begin;

-- CREATE OR REPLACE preserves each core function's owner and existing OID.
-- Snapshot the owners so this migration also fails closed if that invariant
-- changes under a future PostgreSQL/tooling version.
do $snapshot_core_owners$
declare
  fetch_owner oid;
  ack_owner oid;
begin
  select procedure.proowner
    into fetch_owner
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'public.garmin_fetch_pending_plan_core(text)'
  );
  select procedure.proowner
    into ack_owner
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'public.garmin_ack_plan_core(text,uuid,bigint)'
  );
  if fetch_owner is null or ack_owner is null then
    raise exception 'Required Garmin core functions are missing';
  end if;
  perform pg_catalog.set_config(
    'gymapp_migration.fetch_core_owner',
    fetch_owner::text,
    true
  );
  perform pg_catalog.set_config(
    'gymapp_migration.ack_core_owner',
    ack_owner::text,
    true
  );
end
$snapshot_core_owners$;

create or replace function public.garmin_fetch_pending_plan_core(
  p_device_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  found_device public.garmin_devices%rowtype;
  found_plan public.garmin_plans%rowtype;
  plan_validation_message text;
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

  plan_validation_message := gymapp_private.garmin_plan_validation_error(
    found_plan.plan
  );
  if plan_validation_message is not null then
    update public.garmin_plans as target_plan
    set
      status = 'invalid',
      validation_error = pg_catalog.left(plan_validation_message, 200)
    where target_plan.id = found_plan.id;
    return pg_catalog.jsonb_build_object(
      'status', 'invalid',
      'planId', found_plan.id,
      'planRevision', found_plan.plan_revision
    );
  end if;

  if found_plan.device_id is null then
    update public.garmin_plans as target_plan
    set device_id = found_device.id
    where target_plan.id = found_plan.id;
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

create or replace function public.garmin_ack_plan_core(
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
  plan_validation_message text;
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
  plan_validation_message := gymapp_private.garmin_plan_validation_error(
    found_plan.plan
  );
  if plan_validation_message is not null then
    update public.garmin_plans as target_plan
    set
      status = 'invalid',
      validation_error = pg_catalog.left(plan_validation_message, 200)
    where target_plan.id = found_plan.id;
    return pg_catalog.jsonb_build_object('status', 'invalid');
  end if;
  update public.garmin_plans as target_plan
  set
    status = 'downloaded',
    device_id = found_device.id,
    downloaded_at = pg_catalog.clock_timestamp(),
    validation_error = null
  where target_plan.id = found_plan.id;
  return pg_catalog.jsonb_build_object(
    'status', 'acknowledged',
    'planId', found_plan.id,
    'planRevision', found_plan.plan_revision
  );
end
$function$;

revoke all on function public.garmin_fetch_pending_plan_core(text)
  from public, anon, authenticated, service_role;
revoke all on function public.garmin_ack_plan_core(text, uuid, bigint)
  from public, anon, authenticated, service_role;

do $verify_core_contract$
declare
  fetch_function pg_catalog.pg_proc%rowtype;
  ack_function pg_catalog.pg_proc%rowtype;
  fetch_wrapper_source text;
  ack_wrapper_source text;
begin
  select procedure.*
    into strict fetch_function
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'public.garmin_fetch_pending_plan_core(text)'
  );
  select procedure.*
    into strict ack_function
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'public.garmin_ack_plan_core(text,uuid,bigint)'
  );
  if fetch_function.proowner::text <>
       pg_catalog.current_setting('gymapp_migration.fetch_core_owner')
     or ack_function.proowner::text <>
       pg_catalog.current_setting('gymapp_migration.ack_core_owner') then
    raise exception 'Garmin core function ownership changed';
  end if;
  if not fetch_function.prosecdef or not ack_function.prosecdef
     or not (fetch_function.proconfig @> array['search_path=""'])
     or not (ack_function.proconfig @> array['search_path=""']) then
    raise exception 'Garmin core security contract changed';
  end if;
  if pg_catalog.has_function_privilege(
       'anon', 'public.garmin_fetch_pending_plan_core(text)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', 'public.garmin_fetch_pending_plan_core(text)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'public.garmin_fetch_pending_plan_core(text)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'public.garmin_ack_plan_core(text,uuid,bigint)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', 'public.garmin_ack_plan_core(text,uuid,bigint)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'public.garmin_ack_plan_core(text,uuid,bigint)', 'EXECUTE'
     ) then
    raise exception 'Garmin core functions became API-executable';
  end if;

  select procedure.prosrc
    into strict fetch_wrapper_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'public.garmin_fetch_pending_plan(text)'
  );
  select procedure.prosrc
    into strict ack_wrapper_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'public.garmin_ack_plan(text,uuid,bigint)'
  );
  if pg_catalog.strpos(fetch_wrapper_source, 'garmin_rate_limit_for_token') = 0
     or pg_catalog.strpos(fetch_wrapper_source, 'garmin_fetch_pending_plan_core') = 0
     or pg_catalog.strpos(ack_wrapper_source, 'garmin_rate_limit_for_token') = 0
     or pg_catalog.strpos(ack_wrapper_source, 'garmin_ack_plan_core') = 0 then
    raise exception 'Garmin rate-limited wrappers changed unexpectedly';
  end if;
end
$verify_core_contract$;

commit;
