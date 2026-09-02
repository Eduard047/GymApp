begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regclass('gymapp_private.garmin_gateway_preauth_buckets') is not null
     or pg_catalog.to_regprocedure(
       'public.garmin_gateway_preauth_debit(text,integer)'
     ) is not null then
    raise exception 'GymApp Garmin gateway pre-auth budget already exists.';
  end if;
end
$preflight$;

create table gymapp_private.garmin_gateway_preauth_buckets (
  bucket_lane text not null check (
    bucket_lane in ('global', 'jwt', 'capability')
  ),
  shard_id smallint not null check (shard_id between 0 and 63),
  capacity numeric(20, 9) not null check (capacity between 1 and 1000),
  refill_per_second numeric(20, 9) not null check (
    refill_per_second > 0 and refill_per_second <= 100
  ),
  tokens numeric(20, 9) not null check (tokens between 0 and 1000),
  refilled_at timestamptz not null,
  primary key (bucket_lane, shard_id),
  constraint garmin_gateway_preauth_token_capacity_check
    check (tokens <= capacity)
);

comment on table gymapp_private.garmin_gateway_preauth_buckets is
  'Fixed-cardinality Garmin Edge ingress buckets. Exactly 64 global, JWT, and signed-capability shards bound unauthenticated work without storing credential material.';

alter table gymapp_private.garmin_gateway_preauth_buckets
  enable row level security;
alter table gymapp_private.garmin_gateway_preauth_buckets
  force row level security;
revoke all on table gymapp_private.garmin_gateway_preauth_buckets
  from public, anon, authenticated, service_role;

insert into gymapp_private.garmin_gateway_preauth_buckets (
  bucket_lane,
  shard_id,
  capacity,
  refill_per_second,
  tokens,
  refilled_at
)
select
  configuration.bucket_lane,
  shard.shard_id,
  configuration.capacity,
  configuration.refill_per_second,
  configuration.capacity,
  pg_catalog.clock_timestamp()
from (values
  ('global'::text, 40::numeric, 5::numeric),
  ('jwt'::text, 16::numeric, 2::numeric),
  ('capability'::text, 32::numeric, 4::numeric)
) as configuration(bucket_lane, capacity, refill_per_second)
cross join pg_catalog.generate_series(0, 63) as shard(shard_id);

create or replace function gymapp_private.consume_garmin_gateway_preauth_budget(
  p_lane text,
  p_shard integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  request_time timestamptz := pg_catalog.clock_timestamp();
  global_row gymapp_private.garmin_gateway_preauth_buckets%rowtype;
  lane_row gymapp_private.garmin_gateway_preauth_buckets%rowtype;
  global_available numeric(20, 9);
  lane_available numeric(20, 9);
  retry_after integer := 1;
begin
  if p_lane is null
     or p_lane not in ('jwt', 'capability')
     or p_shard is null
     or p_shard not between 0 and 63 then
    raise exception using
      errcode = '22023',
      message = 'Garmin gateway budget request is invalid.';
  end if;

  -- All requests lock the shared breaker before their lane row. The order is
  -- identical for every caller and both rows already exist, so attacker input
  -- cannot create state or invert the lock order.
  select bucket.* into strict global_row
  from gymapp_private.garmin_gateway_preauth_buckets as bucket
  where bucket.bucket_lane = 'global'
    and bucket.shard_id = p_shard
  for update;

  select bucket.* into strict lane_row
  from gymapp_private.garmin_gateway_preauth_buckets as bucket
  where bucket.bucket_lane = p_lane
    and bucket.shard_id = p_shard
  for update;

  global_available := least(
    global_row.capacity,
    global_row.tokens + greatest(
      extract(epoch from request_time - global_row.refilled_at),
      0
    ) * global_row.refill_per_second
  );
  lane_available := least(
    lane_row.capacity,
    lane_row.tokens + greatest(
      extract(epoch from request_time - lane_row.refilled_at),
      0
    ) * lane_row.refill_per_second
  );

  if global_available < 1 or lane_available < 1 then
    if global_available < 1 then
      retry_after := greatest(
        retry_after,
        pg_catalog.ceil(
          (1 - global_available) / global_row.refill_per_second
        )::integer
      );
    end if;
    if lane_available < 1 then
      retry_after := greatest(
        retry_after,
        pg_catalog.ceil(
          (1 - lane_available) / lane_row.refill_per_second
        )::integer
      );
    end if;

    update gymapp_private.garmin_gateway_preauth_buckets as bucket
    set tokens = global_available,
        refilled_at = request_time
    where bucket.bucket_lane = 'global'
      and bucket.shard_id = p_shard;
    update gymapp_private.garmin_gateway_preauth_buckets as bucket
    set tokens = lane_available,
        refilled_at = request_time
    where bucket.bucket_lane = p_lane
      and bucket.shard_id = p_shard;

    return pg_catalog.jsonb_build_object(
      'version', 1,
      'allowed', false,
      'retryAfter', least(greatest(retry_after, 1), 60)
    );
  end if;

  update gymapp_private.garmin_gateway_preauth_buckets as bucket
  set tokens = global_available - 1,
      refilled_at = request_time
  where bucket.bucket_lane = 'global'
    and bucket.shard_id = p_shard;
  update gymapp_private.garmin_gateway_preauth_buckets as bucket
  set tokens = lane_available - 1,
      refilled_at = request_time
  where bucket.bucket_lane = p_lane
    and bucket.shard_id = p_shard;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'allowed', true,
    'retryAfter', 0
  );
end
$function$;

revoke all on function gymapp_private.consume_garmin_gateway_preauth_budget(
  text,
  integer
) from public, anon, authenticated, service_role;

create or replace function public.garmin_gateway_preauth_debit(
  p_lane text,
  p_shard integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'Garmin gateway budget access is denied.';
  end if;
  return gymapp_private.consume_garmin_gateway_preauth_budget(
    p_lane,
    p_shard
  );
end
$function$;

revoke all on function public.garmin_gateway_preauth_debit(text, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.garmin_gateway_preauth_debit(text, integer)
  to service_role;

comment on function public.garmin_gateway_preauth_debit(text, integer) is
  'Service-only fixed-cardinality global-plus-lane debit performed before Garmin JWT or signed-capability verification.';

do $verify$
declare
  limiter_source text;
begin
  select procedure.prosrc into strict limiter_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'gymapp_private.consume_garmin_gateway_preauth_budget(text,integer)'
  );

  if (
       select pg_catalog.count(*)
       from gymapp_private.garmin_gateway_preauth_buckets
     ) <> 192
     or exists (
       select 1
       from gymapp_private.garmin_gateway_preauth_buckets as bucket
       group by bucket.bucket_lane
       having pg_catalog.count(*) <> 64
     )
     or pg_catalog.strpos(pg_catalog.lower(limiter_source), 'insert into') <> 0
     or pg_catalog.strpos(pg_catalog.lower(limiter_source), 'for update') = 0
     or not (
       select relation.relrowsecurity and relation.relforcerowsecurity
       from pg_catalog.pg_class as relation
       where relation.oid =
         'gymapp_private.garmin_gateway_preauth_buckets'::regclass
     )
     or pg_catalog.has_table_privilege(
       'service_role',
       'gymapp_private.garmin_gateway_preauth_buckets',
       'SELECT'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.garmin_gateway_preauth_debit(text,integer)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.garmin_gateway_preauth_debit(text,integer)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.garmin_gateway_preauth_debit(text,integer)',
       'EXECUTE'
     ) then
    raise exception 'GymApp Garmin gateway pre-auth budget verification failed.';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
