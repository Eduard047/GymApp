begin;

do $preflight$
begin
  if pg_catalog.to_regclass('public.garmin_devices') is null
     or pg_catalog.to_regprocedure('gymapp_private.garmin_device_token_hash(text)') is null
     or pg_catalog.to_regprocedure('gymapp_private.garmin_rate_limit_for_token(text,text)') is null
     or pg_catalog.to_regprocedure('gymapp_private.consume_garmin_device_rate_limit(uuid,text)') is null
     or pg_catalog.to_regprocedure('public.garmin_fetch_pending_plan(text)') is null
     or pg_catalog.to_regprocedure('public.garmin_ack_plan(text,uuid,bigint)') is null
     or pg_catalog.to_regprocedure('public.garmin_quarantine_pending_plan(text,uuid,bigint,text)') is null then
    raise exception 'GymApp Garmin rate-limit prerequisites are missing';
  end if;
end
$preflight$;

-- A valid-looking but nonexistent capability previously reached the indexed
-- garmin_devices lookup before any durable limiter was charged. Random tokens
-- could therefore bypass the per-device buckets. Use a fixed set of hash
-- shards before that lookup: abusive input cannot create rows, choose a stored
-- key directly, or grow this table beyond 3 actions x 64 shards.
create table gymapp_private.garmin_preauth_rate_limits (
  bucket_action text not null
    check (bucket_action in ('fetch_plan', 'ack_plan', 'quarantine_plan')),
  shard_id smallint not null
    check (shard_id between 0 and 63),
  tokens numeric(20, 9) not null
    check (tokens between 0 and 32),
  refilled_at timestamptz not null,
  primary key (bucket_action, shard_id)
);

comment on table gymapp_private.garmin_preauth_rate_limits is
  'Fixed pre-auth hash-shard token buckets that bound Garmin device lookups without storing raw capabilities or attacker-controlled keys.';

insert into gymapp_private.garmin_preauth_rate_limits (
  bucket_action,
  shard_id,
  tokens,
  refilled_at
)
select
  action.bucket_action,
  shard.shard_id::smallint,
  action.initial_tokens,
  pg_catalog.clock_timestamp()
from (
  values
    ('fetch_plan'::text, 32::numeric),
    ('ack_plan'::text, 16::numeric),
    ('quarantine_plan'::text, 4::numeric)
) as action(bucket_action, initial_tokens)
cross join pg_catalog.generate_series(0, 63) as shard(shard_id);

alter table gymapp_private.garmin_preauth_rate_limits
  enable row level security;
revoke all on table gymapp_private.garmin_preauth_rate_limits
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.consume_garmin_preauth_rate_limit(
  p_token_hash text,
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
  token_shard smallint;
  request_time timestamptz := pg_catalog.clock_timestamp();
  stored_tokens numeric(20, 9);
  stored_refilled_at timestamptz;
  elapsed_seconds numeric;
  available_tokens numeric(20, 9);
  retry_after_seconds bigint;
begin
  if p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$' then
    raise exception using
      errcode = '22023',
      message = 'A canonical Garmin token hash is required.';
  end if;

  case p_action
    -- Across 64 shards this permits an aggregate burst of 2048 and a sustained
    -- 32 lookups/second. The per-device fetch bucket remains the tighter layer
    -- after a capability resolves to an active watch.
    when 'fetch_plan' then
      bucket_capacity := 32;
      refill_per_second := 0.5;
    when 'ack_plan' then
      bucket_capacity := 16;
      refill_per_second := 0.25;
    when 'quarantine_plan' then
      bucket_capacity := 4;
      refill_per_second := 1.0 / 60.0;
    else
      raise exception using
        errcode = '22023',
        message = 'Unsupported Garmin pre-auth rate-limit action.';
  end case;

  token_shard := (
    pg_catalog.get_byte(
      pg_catalog.decode(pg_catalog.substr(p_token_hash, 1, 2), 'hex'),
      0
    ) % 64
  )::smallint;

  -- Never queue behind a hot attacker-controlled shard. A missing or locked
  -- fixed bucket fails closed with a short retry and performs no device lookup.
  select bucket.tokens, bucket.refilled_at
    into stored_tokens, stored_refilled_at
  from gymapp_private.garmin_preauth_rate_limits as bucket
  where bucket.bucket_action = p_action
    and bucket.shard_id = token_shard
  for update skip locked;

  if not found then
    return 1;
  end if;

  elapsed_seconds := extract(epoch from (request_time - stored_refilled_at));
  if elapsed_seconds < 0 then
    elapsed_seconds := 0;
  end if;
  available_tokens := least(
    bucket_capacity,
    stored_tokens + (elapsed_seconds * refill_per_second)
  );

  if available_tokens >= 1 then
    update gymapp_private.garmin_preauth_rate_limits
    set
      tokens = available_tokens - 1,
      refilled_at = request_time
    where bucket_action = p_action
      and shard_id = token_shard;
    return 0;
  end if;

  -- Rejected calls do not update the row, avoiding sustained WAL churn while
  -- elapsed time continues to refill the bucket deterministically.
  retry_after_seconds := pg_catalog.ceil(
    (1 - available_tokens) / refill_per_second
  )::bigint;
  return least(greatest(retry_after_seconds, 1), 3600)::integer;
end
$function$;

revoke all on function gymapp_private.consume_garmin_preauth_rate_limit(text, text)
  from public, anon, authenticated, service_role;

-- Keep every public RPC signature and response shape stable. The fixed shard
-- is charged after hashing but before the device-table lookup; a valid watch
-- then passes through the existing per-device bucket as a second layer.
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
  token_hash text;
  preauth_retry_after_seconds integer;
  found_device_id uuid;
begin
  if p_device_token is null or p_device_token !~ '^[A-Fa-f0-9]{64}$' then
    return null;
  end if;

  token_hash := gymapp_private.garmin_device_token_hash(p_device_token);
  preauth_retry_after_seconds :=
    gymapp_private.consume_garmin_preauth_rate_limit(token_hash, p_action);

  if preauth_retry_after_seconds is null then
    return 3600;
  end if;
  if preauth_retry_after_seconds > 0 then
    return preauth_retry_after_seconds;
  end if;

  select device.id
    into found_device_id
  from public.garmin_devices as device
  where device.device_token = token_hash
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

do $verify$
begin
  if (select pg_catalog.count(*) from gymapp_private.garmin_preauth_rate_limits) <> 192
     or exists (
       select 1
       from gymapp_private.garmin_preauth_rate_limits
       group by bucket_action
       having pg_catalog.count(*) <> 64
          or pg_catalog.min(shard_id) <> 0
          or pg_catalog.max(shard_id) <> 63
     ) then
    raise exception 'Garmin pre-auth rate-limit buckets are incomplete';
  end if;

  if has_table_privilege('anon', 'gymapp_private.garmin_preauth_rate_limits', 'SELECT, INSERT, UPDATE, DELETE')
     or has_table_privilege('authenticated', 'gymapp_private.garmin_preauth_rate_limits', 'SELECT, INSERT, UPDATE, DELETE')
     or has_table_privilege('service_role', 'gymapp_private.garmin_preauth_rate_limits', 'SELECT, INSERT, UPDATE, DELETE')
     or has_function_privilege('anon', 'gymapp_private.consume_garmin_preauth_rate_limit(text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'gymapp_private.consume_garmin_preauth_rate_limit(text,text)', 'EXECUTE')
     or has_function_privilege('service_role', 'gymapp_private.consume_garmin_preauth_rate_limit(text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'gymapp_private.garmin_rate_limit_for_token(text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'gymapp_private.garmin_rate_limit_for_token(text,text)', 'EXECUTE')
     or has_function_privilege('service_role', 'gymapp_private.garmin_rate_limit_for_token(text,text)', 'EXECUTE')
     or not has_function_privilege('anon', 'public.garmin_fetch_pending_plan(text)', 'EXECUTE')
     or not has_function_privilege('anon', 'public.garmin_ack_plan(text,uuid,bigint)', 'EXECUTE')
     or not has_function_privilege('anon', 'public.garmin_quarantine_pending_plan(text,uuid,bigint,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.garmin_fetch_pending_plan_core(text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.garmin_ack_plan_core(text,uuid,bigint)', 'EXECUTE')
     or has_function_privilege('anon', 'public.garmin_quarantine_pending_plan_core(text,uuid,bigint,text)', 'EXECUTE') then
    raise exception 'Garmin pre-auth rate-limit grants are broader than intended';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
