begin;

select plan(40);

select has_function(
  'public',
  'garmin_create_device_idempotent',
  array['uuid', 'uuid', 'text', 'text'],
  'idempotent Garmin creator exists with the reviewed typed contract'
);
select ok(
  (select procedure.prosecdef
   from pg_catalog.pg_proc as procedure
   where procedure.oid =
     'public.garmin_create_device_idempotent(uuid,uuid,text,text)'::regprocedure),
  'idempotent Garmin creator is security definer'
);
select ok(
  (select 'search_path=""' = any(procedure.proconfig)
   from pg_catalog.pg_proc as procedure
   where procedure.oid =
     'public.garmin_create_device_idempotent(uuid,uuid,text,text)'::regprocedure),
  'idempotent Garmin creator has an empty fixed search_path'
);
select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.garmin_create_device_idempotent(uuid,uuid,text,text)',
    'EXECUTE'
  ),
  'anonymous clients cannot execute the idempotent creator'
);
select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.garmin_create_device_idempotent(uuid,uuid,text,text)',
    'EXECUTE'
  ),
  'authenticated clients can execute only the owner-bound creator'
);
select ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.garmin_devices', 'SELECT'
  ),
  'authenticated clients cannot read internal replay metadata directly'
);
select ok(
  (select index_definition.indexdef like
     '%UNIQUE INDEX garmin_devices_creation_request_id_unique%'
     and index_definition.indexdef like
       '%WHERE (creation_request_id IS NOT NULL)%'
   from pg_catalog.pg_indexes as index_definition
   where index_definition.schemaname = 'public'
     and index_definition.indexname =
       'garmin_devices_creation_request_id_unique'),
  'a global partial unique index serializes non-null creation request IDs'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'public.garmin_create_device_idempotent(uuid,uuid,text,text)'::regprocedure
  ) like '%pg_advisory_xact_lock%719924%',
  'creator takes the global request-ID advisory lock'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'public.garmin_create_device_idempotent(uuid,uuid,text,text)'::regprocedure
  ) like '%pg_advisory_xact_lock%719922%',
  'creator shares the legacy per-owner advisory lock'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'gymapp_private.has_current_auth_session(uuid)'::regprocedure
  ) like '%session.not_after > pg_catalog.clock_timestamp()%'
  and (
    select procedure.provolatile = 'v'
    from pg_catalog.pg_proc as procedure
    where procedure.oid =
      'gymapp_private.has_current_auth_session(uuid)'::regprocedure
  ),
  'the shared owner boundary rejects expired exact Auth sessions'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    'a2000000-0000-4000-8000-000000000001',
    'authenticated', 'authenticated', 'garmin-create-a@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a2000000-0000-4000-8000-000000000002',
    'authenticated', 'authenticated', 'garmin-create-b@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a2000000-0000-4000-8000-000000000003',
    'authenticated', 'authenticated', 'garmin-create-expired@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a2000000-0000-4000-8000-000000000004',
    'authenticated', 'authenticated', 'garmin-create-recent@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

insert into auth.sessions (id, user_id, not_after, created_at, updated_at) values
  (
    'b2000000-0000-4000-8000-000000000001',
    'a2000000-0000-4000-8000-000000000001',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'b2000000-0000-4000-8000-000000000002',
    'a2000000-0000-4000-8000-000000000002',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'b2000000-0000-4000-8000-000000000003',
    'a2000000-0000-4000-8000-000000000003',
    pg_catalog.clock_timestamp() - interval '1 minute',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'b2000000-0000-4000-8000-000000000004',
    'a2000000-0000-4000-8000-000000000004',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

create temporary table garmin_create_results (
  case_name text primary key,
  payload jsonb not null
) on commit drop;

set local request.jwt.claim.sub = 'a2000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a2000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b2000000-0000-4000-8000-000000000001"}';
insert into garmin_create_results values (
  'created',
  public.garmin_create_device_idempotent(
    '11000000-0000-4000-8000-000000000001',
    '21000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('a', 64),
    'Test Watch'
  )
);
create temporary table garmin_created_snapshot on commit drop as
select device.*
from public.garmin_devices as device
where device.creation_request_id =
  '11000000-0000-4000-8000-000000000001';

select is(
  (select payload ->> 'status' from garmin_create_results where case_name = 'created'),
  'created',
  'first owner request creates the requested device'
);
select is(
  (select payload #>> '{device,device_token}'
   from garmin_create_results where case_name = 'created'),
  pg_catalog.repeat('a', 64),
  'first response returns the caller-generated one-time token exactly'
);
select is(
  (select pg_catalog.count(*) from public.garmin_devices
   where creation_request_id = '11000000-0000-4000-8000-000000000001'),
  1::bigint,
  'first request inserts exactly one row'
);
select is(
  (select device_token from public.garmin_devices
   where creation_request_id = '11000000-0000-4000-8000-000000000001'),
  gymapp_private.garmin_device_token_hash(pg_catalog.repeat('a', 64)),
  'database stores only the established SHA-256 token hash'
);
select is(
  (select creation_request_id from public.garmin_devices
   where id = '21000000-0000-4000-8000-000000000001'),
  '11000000-0000-4000-8000-000000000001'::uuid,
  'database binds the stable request ID to the requested device ID'
);

insert into garmin_create_results values (
  'replay',
  public.garmin_create_device_idempotent(
    '11000000-0000-4000-8000-000000000001',
    '21000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('a', 64),
    'Test Watch'
  )
);
select is(
  (select payload ->> 'status' from garmin_create_results where case_name = 'replay'),
  'already_created',
  'an exact duplicate deterministically replays instead of inserting'
);
select is(
  (select payload -> 'device' from garmin_create_results where case_name = 'replay'),
  (select payload -> 'device' from garmin_create_results where case_name = 'created'),
  'exact replay returns the original device and one-time token payload'
);
select ok(
  (select current_device.created_at = snapshot.created_at
      and current_device.last_seen_at is not distinct from snapshot.last_seen_at
      and current_device.revoked_at is not distinct from snapshot.revoked_at
      and current_device.token_revision = snapshot.token_revision
      and current_device.device_token = snapshot.device_token
   from public.garmin_devices as current_device
   join garmin_created_snapshot as snapshot using (id)),
  'exact replay does not update timestamps, revision, revocation, or token hash'
);
select is(
  (select pg_catalog.count(*) from public.garmin_devices
   where creation_request_id = '11000000-0000-4000-8000-000000000001'),
  1::bigint,
  'duplicate and concurrent-equivalent calls converge on one unique row'
);

select is(
  public.garmin_create_device_idempotent(
    '11000000-0000-4000-8000-000000000001',
    '21000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('b', 64),
    'Test Watch'
  ) ->> 'status',
  'conflict',
  'same request ID with a changed token is rejected'
);
select is(
  public.garmin_create_device_idempotent(
    '11000000-0000-4000-8000-000000000001',
    '21000000-0000-4000-8000-000000000099',
    pg_catalog.repeat('a', 64),
    'Test Watch'
  ) ->> 'status',
  'conflict',
  'same request ID with a changed device ID is rejected'
);
select is(
  public.garmin_create_device_idempotent(
    '11000000-0000-4000-8000-000000000001',
    '21000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('a', 64),
    'Changed Watch'
  ) ->> 'status',
  'conflict',
  'same request ID with a changed display payload is rejected'
);
select is(
  (select pg_catalog.count(*) from public.garmin_devices
   where user_id = 'a2000000-0000-4000-8000-000000000001'),
  1::bigint,
  'changed-payload replays have no insertion side effects'
);

set local request.jwt.claim.sub = 'a2000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"a2000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"b2000000-0000-4000-8000-000000000002"}';
select is(
  public.garmin_create_device_idempotent(
    '11000000-0000-4000-8000-000000000001',
    '21000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('a', 64),
    'Test Watch'
  ) ->> 'status',
  'conflict',
  'another owner cannot replay the global request ID'
);
select is(
  (select pg_catalog.count(*) from public.garmin_devices
   where user_id = 'a2000000-0000-4000-8000-000000000002'),
  0::bigint,
  'wrong-owner replay has no row side effects'
);

set local request.jwt.claim.sub = 'a2000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a2000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b2000000-0000-4000-8000-000000000001"}';
update public.garmin_devices
set revoked_at = pg_catalog.clock_timestamp()
where creation_request_id = '11000000-0000-4000-8000-000000000001';
select is(
  public.garmin_create_device_idempotent(
    '11000000-0000-4000-8000-000000000001',
    '21000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('a', 64),
    'Test Watch'
  ) ->> 'status',
  'conflict',
  'a revoked request cannot replay or resurrect the device'
);
select ok(
  (select revoked_at is not null and token_revision = 1
   from public.garmin_devices
   where creation_request_id = '11000000-0000-4000-8000-000000000001'),
  'revoked replay leaves revocation and revision unchanged'
);

select is(
  public.garmin_create_device_idempotent(
    '12000000-0000-3000-8000-000000000001',
    '22000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('c', 64),
    'Malformed Watch'
  ) ->> 'error',
  'Invalid device creation request',
  'non-v4 request IDs are rejected before insertion'
);
select is(
  public.garmin_create_device_idempotent(
    '12000000-0000-4000-8000-000000000001',
    '22000000-0000-4000-8000-000000000001',
    'NOT-A-DEVICE-TOKEN',
    'Malformed Watch'
  ) ->> 'error',
  'Invalid device creation request',
  'malformed raw tokens are rejected before hashing/insertion'
);
select is(
  (select pg_catalog.count(*) from public.garmin_devices
   where id = '22000000-0000-4000-8000-000000000001'),
  0::bigint,
  'malformed requests have no device-row side effects'
);

set local request.jwt.claim.sub = 'a2000000-0000-4000-8000-000000000003';
set local request.jwt.claims =
  '{"sub":"a2000000-0000-4000-8000-000000000003","role":"authenticated","session_id":"b2000000-0000-4000-8000-000000000003"}';
select is(
  public.garmin_create_device_idempotent(
    '13000000-0000-4000-8000-000000000001',
    '23000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('d', 64),
    'Expired Watch'
  ) ->> 'error',
  'Unauthorized',
  'an expired exact Auth session is rejected'
);
select is(
  (select pg_catalog.count(*) from public.garmin_devices
   where user_id = 'a2000000-0000-4000-8000-000000000003'),
  0::bigint,
  'expired-session rejection has no device-row side effects'
);

set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"anon"}';
select is(
  public.garmin_create_device_idempotent(
    '14000000-0000-4000-8000-000000000001',
    '24000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('e', 64),
    'Anonymous Watch'
  ) ->> 'error',
  'Unauthorized',
  'anonymous invocation is rejected by the server boundary'
);
select is(
  (select pg_catalog.count(*) from public.garmin_devices
   where creation_request_id = '14000000-0000-4000-8000-000000000001'),
  0::bigint,
  'anonymous rejection has no device-row side effects'
);

insert into public.garmin_devices (
  id, user_id, device_token, display_name, binding_version, token_revision,
  created_at, revoked_at
)
select
  ('31000000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'a2000000-0000-4000-8000-000000000002'::uuid,
  pg_catalog.encode(
    pg_catalog.sha256(pg_catalog.convert_to('active-' || value, 'UTF8')),
    'hex'
  ),
  'Active ' || value,
  2,
  1,
  pg_catalog.clock_timestamp(),
  null
from pg_catalog.generate_series(1, 5) as value;
set local request.jwt.claim.sub = 'a2000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"a2000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"b2000000-0000-4000-8000-000000000002"}';
select is(
  public.garmin_create_device_idempotent(
    '15000000-0000-4000-8000-000000000001',
    '25000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('f', 64),
    'Over Active Limit'
  ) ->> 'error',
  'Device creation limit reached',
  'the existing five-active-device limit remains enforced'
);
select is(
  (select pg_catalog.count(*) from public.garmin_devices
   where user_id = 'a2000000-0000-4000-8000-000000000002'),
  5::bigint,
  'active-device limit rejection inserts nothing'
);

insert into public.garmin_devices (
  id, user_id, device_token, display_name, binding_version, token_revision,
  created_at, revoked_at
)
select
  ('32000000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'a2000000-0000-4000-8000-000000000004'::uuid,
  pg_catalog.encode(
    pg_catalog.sha256(pg_catalog.convert_to('recent-' || value, 'UTF8')),
    'hex'
  ),
  'Recent ' || value,
  2,
  1,
  pg_catalog.clock_timestamp(),
  pg_catalog.clock_timestamp()
from pg_catalog.generate_series(1, 20) as value;
set local request.jwt.claim.sub = 'a2000000-0000-4000-8000-000000000004';
set local request.jwt.claims =
  '{"sub":"a2000000-0000-4000-8000-000000000004","role":"authenticated","session_id":"b2000000-0000-4000-8000-000000000004"}';
select is(
  public.garmin_create_device_idempotent(
    '16000000-0000-4000-8000-000000000001',
    '26000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('1', 64),
    'Over Recent Limit'
  ) ->> 'error',
  'Device creation limit reached',
  'the existing 20-per-day creation limit remains enforced'
);
select is(
  (select pg_catalog.count(*) from public.garmin_devices
   where user_id = 'a2000000-0000-4000-8000-000000000004'),
  20::bigint,
  'recent-creation limit rejection inserts nothing'
);

insert into public.garmin_devices (
  id, user_id, device_token, display_name, binding_version, token_revision
) values (
  '27000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000001',
  gymapp_private.garmin_device_token_hash(pg_catalog.repeat('2', 64)),
  'Legacy Compatible Watch',
  2,
  1
);
select is(
  (select creation_request_id from public.garmin_devices
   where id = '27000000-0000-4000-8000-000000000001'),
  null::uuid,
  'legacy-created rows remain compatible with a null request ID'
);
select ok(
  pg_catalog.has_function_privilege(
    'authenticated', 'public.garmin_create_device(text)', 'EXECUTE'
  ),
  'released clients retain access to the legacy creator after migration'
);

select * from finish();

rollback;
