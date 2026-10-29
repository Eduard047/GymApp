begin;

select plan(98);

-- Fixtures: users A and B with live Auth sessions. All device tokens below are
-- synthetic 64-hex strings that exist only inside this rolled-back transaction.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    'a3000000-0000-4000-8000-000000000001',
    'authenticated', 'authenticated', 'garmin-owner-a@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a3000000-0000-4000-8000-000000000002',
    'authenticated', 'authenticated', 'garmin-owner-b@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

insert into auth.sessions (id, user_id, not_after, created_at, updated_at) values
  (
    'b3000000-0000-4000-8000-000000000001',
    'a3000000-0000-4000-8000-000000000001',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'b3000000-0000-4000-8000-000000000002',
    'a3000000-0000-4000-8000-000000000002',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

-- Shared scratch rows (plan ids/revisions) readable by every test role.
create temporary table ctx (
  key text primary key,
  id uuid,
  revision bigint
) on commit drop;
grant select on ctx to public;

-- Devices: dA1 (A, main), dA2 (A, revocation target), dB1 (B).
set local role authenticated;
set local request.jwt.claim.sub = 'a3000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000001"}';
select is(
  public.garmin_create_device_idempotent(
    'c3000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('1', 64),
    'Owner A watch one'
  ) ->> 'status',
  'created',
  'A creates device dA1'
);
select is(
  public.garmin_create_device_idempotent(
    'c3000000-0000-4000-8000-000000000002',
    'd3000000-0000-4000-8000-000000000002',
    pg_catalog.repeat('2', 64),
    'Owner A watch two'
  ) ->> 'status',
  'created',
  'A creates device dA2'
);

set local request.jwt.claim.sub = 'a3000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000002"}';
select is(
  public.garmin_create_device_idempotent(
    'c3000000-0000-4000-8000-000000000003',
    'd3000000-0000-4000-8000-000000000003',
    pg_catalog.repeat('3', 64),
    'Owner B watch'
  ) ->> 'status',
  'created',
  'B creates device dB1'
);

-- garmin_list_devices -------------------------------------------------------
select is(
  (select pg_catalog.array_agg(item.value ->> 'id' order by item.value ->> 'id')
   from pg_catalog.jsonb_array_elements(
     public.garmin_list_devices() -> 'devices'
   ) as item(value)),
  array['d3000000-0000-4000-8000-000000000003'],
  'B lists exactly its own device and none of A''s'
);

set local request.jwt.claim.sub = 'a3000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000001"}';
select is(
  (select pg_catalog.array_agg(item.value ->> 'id' order by item.value ->> 'id')
   from pg_catalog.jsonb_array_elements(
     public.garmin_list_devices() -> 'devices'
   ) as item(value)),
  array[
    'd3000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000002'
  ],
  'A lists exactly A''s two devices and not B''s'
);
select ok(
  not exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      public.garmin_list_devices() -> 'devices'
    ) as item(value)
    where item.value ? 'device_token' or item.value ? 'user_id'
  ),
  'the device list never exposes the token hash or the owner id'
);

-- garmin_enqueue_plan -------------------------------------------------------
select is(
  public.garmin_enqueue_plan(
    'd3000000-0000-4000-8000-000000000001',
    '{"source":"test","version":1,"title":"Plan one","note":"","createdAt":"2026-01-01T00:00:00Z","startedAt":"2026-01-01T00:00:00Z","exercises":[{"name":"Squat","sets":[{"weight":100,"reps":5}]}]}'::jsonb,
    'e3000000-0000-4000-8000-000000000001'
  ) ->> 'status',
  'queued',
  'A enqueues a plan to its own device dA1'
);
reset role;
insert into ctx
select 'p1', plan.id, plan.plan_revision
from public.garmin_plans as plan
where plan.client_request_id = 'e3000000-0000-4000-8000-000000000001';
select ok(
  (select plan.status = 'pending'
     and plan.user_id = 'a3000000-0000-4000-8000-000000000001'
     and plan.device_id = 'd3000000-0000-4000-8000-000000000001'
   from public.garmin_plans as plan
   where plan.id = (select id from ctx where key = 'p1')),
  'the queued plan is pending and bound to owner A and device dA1'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a3000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000002"}';
select is(
  public.garmin_enqueue_plan(
    'd3000000-0000-4000-8000-000000000001',
    '{"source":"test","version":1,"title":"Intrusion","note":"","createdAt":"2026-01-01T00:00:00Z","startedAt":"2026-01-01T00:00:00Z","exercises":[{"name":"Squat","sets":[{"weight":100,"reps":5}]}]}'::jsonb,
    'e3000000-0000-4000-8000-000000000002'
  ),
  '{"error":"Device not found"}'::jsonb,
  'B cannot enqueue a plan to A''s device'
);
select is(
  public.garmin_enqueue_plan(
    'd3000000-0000-4000-8000-000000000099',
    '{"source":"test","version":1,"title":"Intrusion","note":"","createdAt":"2026-01-01T00:00:00Z","startedAt":"2026-01-01T00:00:00Z","exercises":[{"name":"Squat","sets":[{"weight":100,"reps":5}]}]}'::jsonb,
    'e3000000-0000-4000-8000-000000000003'
  ),
  '{"error":"Device not found"}'::jsonb,
  'enqueue to a nonexistent device returns the identical response'
);
select is(
  public.garmin_enqueue_plan(
    'd3000000-0000-4000-8000-000000000001',
    '{"source":"test","version":1,"title":"Plan one","note":"","createdAt":"2026-01-01T00:00:00Z","startedAt":"2026-01-01T00:00:00Z","exercises":[{"name":"Squat","sets":[{"weight":100,"reps":5}]}]}'::jsonb,
    'e3000000-0000-4000-8000-000000000001'
  ),
  '{"error":"Device not found"}'::jsonb,
  'B replaying A''s client request id against A''s device learns nothing (request ids are owner-scoped)'
);
reset role;
select is(
  (select pg_catalog.count(*) from public.garmin_plans
   where user_id = 'a3000000-0000-4000-8000-000000000002'),
  0::bigint,
  'rejected cross-user enqueues leave no plan row for B'
);
select is(
  (select pg_catalog.count(*) from public.garmin_plans
   where device_id = 'd3000000-0000-4000-8000-000000000001'),
  1::bigint,
  'dA1 still holds exactly A''s one plan after the cross-user enqueues'
);

-- Wrong-token watch calls (service_role) -------------------------------------
set local role service_role;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"service_role"}';
select is(
  public.garmin_quarantine_pending_plan(
    pg_catalog.repeat('3', 64),
    (select id from ctx where key = 'p1'),
    (select revision from ctx where key = 'p1'),
    'foreign token must not quarantine'
  ),
  '{"status":"conflict"}'::jsonb,
  'B''s device token cannot quarantine A''s plan'
);
select is(
  public.garmin_quarantine_pending_plan(
    pg_catalog.repeat('9', 64),
    (select id from ctx where key = 'p1'),
    (select revision from ctx where key = 'p1'),
    'unknown token must not quarantine'
  ),
  '{"error":"Invalid device"}'::jsonb,
  'an unknown token cannot quarantine anything'
);
select is(
  public.garmin_quarantine_pending_plan(
    'not-a-token',
    (select id from ctx where key = 'p1'),
    (select revision from ctx where key = 'p1'),
    'malformed token must not quarantine'
  ),
  '{"error":"Invalid device"}'::jsonb,
  'a malformed token cannot quarantine anything'
);
select is(
  public.garmin_ack_plan(
    pg_catalog.repeat('3', 64),
    (select id from ctx where key = 'p1'),
    (select revision from ctx where key = 'p1')
  ),
  '{"status":"conflict"}'::jsonb,
  'B''s device token cannot acknowledge A''s plan'
);
select is(
  public.garmin_fetch_pending_plan(pg_catalog.repeat('3', 64)),
  '{"status":"empty"}'::jsonb,
  'B''s device token fetches nothing from A''s queue'
);
reset role;
select is(
  (select plan.status from public.garmin_plans as plan
   where plan.id = (select id from ctx where key = 'p1')),
  'pending',
  'A''s plan is still pending after every wrong-token attempt'
);

set local role service_role;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"service_role"}';
select is(
  public.garmin_fetch_pending_plan(pg_catalog.repeat('1', 64)) ->> 'planId',
  (select id::text from ctx where key = 'p1'),
  'A''s own device token fetches A''s plan'
);

-- garmin_rotate_device_token ---------------------------------------------------
reset role;
create temporary table hashes (key text primary key, token_hash text, revision bigint)
  on commit drop;
insert into hashes
select 'dA1_before', device.device_token, device.token_revision
from public.garmin_devices as device
where device.id = 'd3000000-0000-4000-8000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub = 'a3000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000002"}';
select is(
  public.garmin_rotate_device_token(
    'd3000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('4', 64),
    1
  ),
  '{"error":"Device not found"}'::jsonb,
  'B rotating A''s device gets the generic not-found response'
);
select is(
  public.garmin_rotate_device_token(
    'd3000000-0000-4000-8000-000000000099',
    pg_catalog.repeat('4', 64),
    1
  ),
  '{"error":"Device not found"}'::jsonb,
  'rotating a nonexistent device returns the identical response (no existence oracle)'
);
reset role;
select ok(
  (select device.device_token = (select token_hash from hashes where key = 'dA1_before')
     and device.token_revision = (select revision from hashes where key = 'dA1_before')
   from public.garmin_devices as device
   where device.id = 'd3000000-0000-4000-8000-000000000001'),
  'A''s token hash and revision are unchanged after B''s rotation attempt'
);
set local role service_role;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"service_role"}';
select is(
  public.garmin_fetch_pending_plan(pg_catalog.repeat('1', 64)) ->> 'status',
  'candidate',
  'A''s original token still works after B''s rotation attempt'
);
select is(
  public.garmin_fetch_pending_plan(pg_catalog.repeat('4', 64)),
  '{"error":"Invalid device"}'::jsonb,
  'the replacement token B chose does not authenticate anything'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a3000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000001"}';
select is(
  public.garmin_rotate_device_token(
    'd3000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('4', 64),
    1
  ) #>> '{device,token_revision}',
  '2',
  'A rotates its own device and the revision advances to 2'
);
select is(
  public.garmin_rotate_device_token(
    'd3000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('4', 64),
    1
  ) ->> 'status',
  'already_rotated',
  'an exact retry of the committed rotation is an idempotent replay'
);
select is(
  public.garmin_rotate_device_token(
    'd3000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('5', 64),
    1
  ) ->> 'status',
  'conflict',
  'a stale expected revision with a different secret is a conflict'
);
reset role;
select is(
  (select device.device_token from public.garmin_devices as device
   where device.id = 'd3000000-0000-4000-8000-000000000001'),
  gymapp_private.garmin_device_token_hash(pg_catalog.repeat('4', 64)),
  'the stored hash is the hash of the replacement token and the stale attempt did not win'
);

set local role service_role;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"service_role"}';
select is(
  public.garmin_fetch_pending_plan(pg_catalog.repeat('1', 64)),
  '{"error":"Invalid device"}'::jsonb,
  'the old token can no longer fetch after rotation'
);
select is(
  public.garmin_ack_plan(
    pg_catalog.repeat('1', 64),
    (select id from ctx where key = 'p1'),
    (select revision from ctx where key = 'p1')
  ),
  '{"error":"Invalid device"}'::jsonb,
  'the old token can no longer acknowledge after rotation'
);
select is(
  public.garmin_quarantine_pending_plan(
    pg_catalog.repeat('1', 64),
    (select id from ctx where key = 'p1'),
    (select revision from ctx where key = 'p1'),
    'old token must not quarantine'
  ),
  '{"error":"Invalid device"}'::jsonb,
  'the old token can no longer quarantine after rotation'
);
select is(
  public.garmin_record_capability_use(pg_catalog.repeat('1', 64), 3::smallint),
  false,
  'the old token can no longer record capability use after rotation'
);
select is(
  public.garmin_fetch_pending_plan(pg_catalog.repeat('4', 64)) ->> 'planId',
  (select id::text from ctx where key = 'p1'),
  'the new token fetches the pending plan'
);

-- garmin_record_capability_use (service_role, token-bound) ----------------------
select is(
  public.garmin_record_capability_use(pg_catalog.repeat('4', 64), 3::smallint),
  true,
  'the current token records a v3 capability observation'
);
select is(
  public.garmin_record_capability_use(pg_catalog.repeat('4', 64), 3::smallint),
  false,
  'a second observation inside the one-hour window is not recorded again'
);
select is(
  public.garmin_record_capability_use(pg_catalog.repeat('4', 64), 4::smallint),
  false,
  'an unsupported capability version is rejected'
);
select is(
  public.garmin_record_capability_use(pg_catalog.repeat('9', 64), 3::smallint),
  false,
  'an unknown token records nothing'
);
select is(
  public.garmin_record_capability_use('not-a-token', 2::smallint),
  false,
  'a malformed token records nothing'
);
reset role;
select ok(
  (select device.v3_capability_last_seen_at is not null
     and device.legacy_capability_last_seen_at is null
   from public.garmin_devices as device
   where device.id = 'd3000000-0000-4000-8000-000000000001')
  and not exists (
    select 1 from public.garmin_devices as device
    where device.id <> 'd3000000-0000-4000-8000-000000000001'
      and (
        device.v3_capability_last_seen_at is not null
        or device.legacy_capability_last_seen_at is not null
      )
      and device.user_id in (
        'a3000000-0000-4000-8000-000000000001',
        'a3000000-0000-4000-8000-000000000002'
      )
  ),
  'only the token-bound device row (v3 column) was touched by capability recording'
);

-- Quarantine and acknowledgement through the intended token ---------------------
set local role service_role;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"service_role"}';
select is(
  public.garmin_quarantine_pending_plan(
    pg_catalog.repeat('4', 64),
    (select id from ctx where key = 'p1'),
    (select revision from ctx where key = 'p1'),
    'contract drift detected'
  ),
  '{"status":"quarantined"}'::jsonb,
  'the owning device''s current token quarantines its pending plan'
);
reset role;
select ok(
  (select plan.status = 'invalid'
     and plan.validation_error = 'contract drift detected'
   from public.garmin_plans as plan
   where plan.id = (select id from ctx where key = 'p1')),
  'the quarantined plan is invalid with the supplied reason'
);
set local role service_role;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"service_role"}';
select is(
  public.garmin_quarantine_pending_plan(
    pg_catalog.repeat('4', 64),
    (select id from ctx where key = 'p1'),
    (select revision from ctx where key = 'p1'),
    'second attempt'
  ),
  '{"status":"conflict"}'::jsonb,
  'a plan that is no longer pending cannot be quarantined again'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = 'a3000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000001"}';
select is(
  public.garmin_enqueue_plan(
    'd3000000-0000-4000-8000-000000000001',
    '{"source":"test","version":1,"title":"Plan three","note":"","createdAt":"2026-01-02T00:00:00Z","startedAt":"2026-01-02T00:00:00Z","exercises":[{"name":"Bench","sets":[{"weight":60,"reps":8}]}]}'::jsonb,
    'e3000000-0000-4000-8000-000000000004'
  ) ->> 'status',
  'queued',
  'A enqueues a second plan to dA1 after the first was quarantined'
);
reset role;
insert into ctx
select 'p3', plan.id, plan.plan_revision
from public.garmin_plans as plan
where plan.client_request_id = 'e3000000-0000-4000-8000-000000000004';
set local role service_role;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"service_role"}';
select is(
  public.garmin_ack_plan(
    pg_catalog.repeat('4', 64),
    (select id from ctx where key = 'p3'),
    (select revision from ctx where key = 'p3')
  ) ->> 'status',
  'acknowledged',
  'the owning device''s current token acknowledges its plan'
);
reset role;
select ok(
  (select plan.status = 'downloaded' and plan.downloaded_at is not null
   from public.garmin_plans as plan
   where plan.id = (select id from ctx where key = 'p3')),
  'the acknowledged plan is marked downloaded'
);

-- garmin_revoke_device -----------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = 'a3000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000001"}';
select is(
  public.garmin_enqueue_plan(
    'd3000000-0000-4000-8000-000000000002',
    '{"source":"test","version":1,"title":"Plan four","note":"","createdAt":"2026-01-03T00:00:00Z","startedAt":"2026-01-03T00:00:00Z","exercises":[{"name":"Row","sets":[{"weight":50,"reps":10}]}]}'::jsonb,
    'e3000000-0000-4000-8000-000000000005'
  ) ->> 'status',
  'queued',
  'A enqueues a plan to dA2 ahead of its revocation'
);
reset role;
insert into ctx
select 'p4', plan.id, plan.plan_revision
from public.garmin_plans as plan
where plan.client_request_id = 'e3000000-0000-4000-8000-000000000005';
set local role service_role;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"service_role"}';
select is(
  public.garmin_fetch_pending_plan(pg_catalog.repeat('2', 64)) ->> 'planId',
  (select id::text from ctx where key = 'p4'),
  'dA2''s token fetches its pending plan before revocation'
);
reset role;
select ok(
  (select pg_catalog.count(*) > 0
   from gymapp_private.garmin_device_rate_limits
   where device_id = 'd3000000-0000-4000-8000-000000000002'),
  'dA2 has rate-limit buckets before revocation'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a3000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000002"}';
select is(
  public.garmin_revoke_device('d3000000-0000-4000-8000-000000000002'),
  '{"error":"Device not found"}'::jsonb,
  'B cannot revoke A''s device (generic not-found)'
);
select is(
  public.garmin_revoke_device('d3000000-0000-4000-8000-000000000099'),
  '{"error":"Device not found"}'::jsonb,
  'revoking a nonexistent device returns the identical response (no existence oracle)'
);
reset role;
select ok(
  (select device.revoked_at is null
   from public.garmin_devices as device
   where device.id = 'd3000000-0000-4000-8000-000000000002')
  and (select plan.status = 'pending'
       from public.garmin_plans as plan
       where plan.id = (select id from ctx where key = 'p4')),
  'A''s device stays active and its plan stays pending after B''s revoke attempt'
);
set local role service_role;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"service_role"}';
select is(
  public.garmin_fetch_pending_plan(pg_catalog.repeat('2', 64)) ->> 'status',
  'candidate',
  'dA2''s token still works after B''s revoke attempt'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a3000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000001"}';
select is(
  public.garmin_revoke_device('d3000000-0000-4000-8000-000000000002'),
  '{"status":"revoked"}'::jsonb,
  'A revokes its own device dA2'
);
select is(
  public.garmin_revoke_device('d3000000-0000-4000-8000-000000000002'),
  '{"status":"already_revoked"}'::jsonb,
  'a second revoke is an idempotent already_revoked'
);
reset role;
select ok(
  (select device.revoked_at is not null
   from public.garmin_devices as device
   where device.id = 'd3000000-0000-4000-8000-000000000002'),
  'revoked_at is stamped on dA2'
);
select ok(
  (select plan.status = 'invalid'
     and plan.validation_error =
       'Garmin device was revoked before this plan was delivered.'
   from public.garmin_plans as plan
   where plan.id = (select id from ctx where key = 'p4')),
  'revocation marks the undelivered plan invalid with the revocation reason'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.garmin_device_rate_limits
   where device_id = 'd3000000-0000-4000-8000-000000000002'),
  0::bigint,
  'revocation deletes the device''s rate-limit buckets'
);
select ok(
  (select device.revoked_at is null
   from public.garmin_devices as device
   where device.id = 'd3000000-0000-4000-8000-000000000001')
  and (select plan.status = 'downloaded'
       from public.garmin_plans as plan
       where plan.id = (select id from ctx where key = 'p3'))
  and (select plan.status = 'invalid'
          and plan.validation_error = 'contract drift detected'
       from public.garmin_plans as plan
       where plan.id = (select id from ctx where key = 'p1')),
  'revoking dA2 leaves dA1 active and its plans untouched'
);

set local role service_role;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"service_role"}';
select is(
  public.garmin_fetch_pending_plan(pg_catalog.repeat('2', 64)),
  '{"error":"Invalid device"}'::jsonb,
  'the revoked device token can no longer fetch'
);
select is(
  public.garmin_ack_plan(
    pg_catalog.repeat('2', 64),
    (select id from ctx where key = 'p4'),
    (select revision from ctx where key = 'p4')
  ),
  '{"error":"Invalid device"}'::jsonb,
  'the revoked device token can no longer acknowledge'
);
select is(
  public.garmin_quarantine_pending_plan(
    pg_catalog.repeat('2', 64),
    (select id from ctx where key = 'p4'),
    (select revision from ctx where key = 'p4'),
    'revoked token must not quarantine'
  ),
  '{"error":"Invalid device"}'::jsonb,
  'the revoked device token can no longer quarantine'
);
select is(
  public.garmin_record_capability_use(pg_catalog.repeat('2', 64), 2::smallint),
  false,
  'the revoked device token can no longer record capability use'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a3000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000001"}';
select is(
  public.garmin_enqueue_plan(
    'd3000000-0000-4000-8000-000000000002',
    '{"source":"test","version":1,"title":"After revoke","note":"","createdAt":"2026-01-04T00:00:00Z","startedAt":"2026-01-04T00:00:00Z","exercises":[{"name":"Row","sets":[{"weight":50,"reps":10}]}]}'::jsonb,
    'e3000000-0000-4000-8000-000000000006'
  ),
  '{"error":"Device not found"}'::jsonb,
  'A cannot enqueue to its own revoked device'
);
select is(
  public.garmin_rotate_device_token(
    'd3000000-0000-4000-8000-000000000002',
    pg_catalog.repeat('6', 64),
    1
  ),
  '{"error":"Device not found"}'::jsonb,
  'A cannot rotate the token of its own revoked device'
);
select is(
  (select pg_catalog.array_agg(item.value ->> 'id')
   from pg_catalog.jsonb_array_elements(
     public.garmin_list_devices() -> 'devices'
   ) as item(value)),
  array['d3000000-0000-4000-8000-000000000001'],
  'the device list omits the revoked device'
);

-- Mismatched session: A's subject with B's live session id ------------------------
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000002"}';
select is(
  public.garmin_list_devices(),
  '{"error":"Unauthorized"}'::jsonb,
  'a session that belongs to another user cannot list devices'
);
select is(
  public.garmin_rotate_device_token(
    'd3000000-0000-4000-8000-000000000001',
    pg_catalog.repeat('7', 64),
    2
  ),
  '{"error":"Unauthorized"}'::jsonb,
  'a session that belongs to another user cannot rotate a token'
);
select is(
  public.garmin_revoke_device('d3000000-0000-4000-8000-000000000001'),
  '{"error":"Unauthorized"}'::jsonb,
  'a session that belongs to another user cannot revoke a device'
);
select is(
  public.garmin_enqueue_plan(
    'd3000000-0000-4000-8000-000000000001',
    '{"source":"test","version":1,"title":"Bad session","note":"","createdAt":"2026-01-05T00:00:00Z","startedAt":"2026-01-05T00:00:00Z","exercises":[{"name":"Row","sets":[{"weight":50,"reps":10}]}]}'::jsonb,
    'e3000000-0000-4000-8000-000000000007'
  ),
  '{"error":"Unauthorized"}'::jsonb,
  'a session that belongs to another user cannot enqueue a plan'
);
reset role;
select ok(
  (select device.revoked_at is null and device.token_revision = 2
   from public.garmin_devices as device
   where device.id = 'd3000000-0000-4000-8000-000000000001')
  and not exists (
    select 1 from public.garmin_plans as plan
    where plan.client_request_id = 'e3000000-0000-4000-8000-000000000007'
  ),
  'the mismatched-session attempts changed no device or plan state'
);

-- Role boundaries: owner RPCs are authenticated-only, watch RPCs service-only -------
set local role authenticated;
set local request.jwt.claim.sub = 'a3000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a3000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b3000000-0000-4000-8000-000000000001"}';
select throws_ok(
  format('select public.garmin_fetch_pending_plan(%L)', pg_catalog.repeat('4', 64)),
  '42501', null,
  'an authenticated owner cannot call the watch fetch RPC with its own token'
);
select throws_ok(
  format('select public.garmin_ack_plan(%L, %L, 1)', pg_catalog.repeat('4', 64),
    'd3000000-0000-4000-8000-000000000001'),
  '42501', null,
  'an authenticated owner cannot call the watch acknowledgement RPC'
);
select throws_ok(
  format('select public.garmin_quarantine_pending_plan(%L, %L, 1, %L)',
    pg_catalog.repeat('4', 64), 'd3000000-0000-4000-8000-000000000001', 'x'),
  '42501', null,
  'an authenticated owner cannot call the watch quarantine RPC'
);
select throws_ok(
  format('select public.garmin_record_capability_use(%L, 3::smallint)',
    pg_catalog.repeat('4', 64)),
  '42501', null,
  'an authenticated owner cannot call the capability recording RPC'
);
select throws_ok(
  'select public.garmin_gateway_preauth_debit(''fetch'', 0)',
  '42501', null,
  'an authenticated owner cannot call the gateway pre-auth debit RPC'
);

set local role service_role;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"service_role"}';
select throws_ok(
  'select public.garmin_list_devices()',
  '42501', null,
  'service_role cannot call the owner device list RPC'
);
select throws_ok(
  'select public.garmin_revoke_device(''d3000000-0000-4000-8000-000000000001'')',
  '42501', null,
  'service_role cannot call the owner revoke RPC'
);
select throws_ok(
  format('select public.garmin_rotate_device_token(%L, %L, 2)',
    'd3000000-0000-4000-8000-000000000001', pg_catalog.repeat('8', 64)),
  '42501', null,
  'service_role cannot call the owner rotate RPC'
);
select throws_ok(
  format('select public.garmin_enqueue_plan(%L, %L::jsonb, %L)',
    'd3000000-0000-4000-8000-000000000001', '{}',
    'e3000000-0000-4000-8000-000000000008'),
  '42501', null,
  'service_role cannot call the owner enqueue RPC'
);

-- Anonymous callers: every garmin_* public function is closed ---------------------
set local role anon;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok(
  'select public.garmin_list_devices()', '42501', null,
  'anon cannot call garmin_list_devices'
);
select throws_ok(
  'select public.garmin_create_device(''x'')', '42501', null,
  'anon cannot call garmin_create_device'
);
select throws_ok(
  format('select public.garmin_create_device_idempotent(%L, %L, %L, ''x'')',
    'c3000000-0000-4000-8000-000000000009',
    'd3000000-0000-4000-8000-000000000009', pg_catalog.repeat('a', 64)),
  '42501', null,
  'anon cannot call garmin_create_device_idempotent'
);
select throws_ok(
  format('select public.garmin_enqueue_plan(%L, ''{}''::jsonb, %L)',
    'd3000000-0000-4000-8000-000000000001',
    'e3000000-0000-4000-8000-000000000009'),
  '42501', null,
  'anon cannot call garmin_enqueue_plan'
);
select throws_ok(
  format('select public.garmin_rotate_device_token(%L, %L, 1)',
    'd3000000-0000-4000-8000-000000000001', pg_catalog.repeat('8', 64)),
  '42501', null,
  'anon cannot call garmin_rotate_device_token'
);
select throws_ok(
  'select public.garmin_revoke_device(''d3000000-0000-4000-8000-000000000001'')',
  '42501', null,
  'anon cannot call garmin_revoke_device'
);
select throws_ok(
  'select public.garmin_revoke_device_core(''d3000000-0000-4000-8000-000000000001'')',
  '42501', null,
  'anon cannot call garmin_revoke_device_core'
);
select throws_ok(
  format('select public.garmin_fetch_pending_plan(%L)', pg_catalog.repeat('4', 64)),
  '42501', null,
  'anon cannot call garmin_fetch_pending_plan'
);
select throws_ok(
  format('select public.garmin_fetch_pending_plan_core(%L)', pg_catalog.repeat('4', 64)),
  '42501', null,
  'anon cannot call garmin_fetch_pending_plan_core'
);
select throws_ok(
  format('select public.garmin_ack_plan(%L, %L, 1)', pg_catalog.repeat('4', 64),
    'd3000000-0000-4000-8000-000000000001'),
  '42501', null,
  'anon cannot call garmin_ack_plan'
);
select throws_ok(
  format('select public.garmin_ack_plan_core(%L, %L, 1)', pg_catalog.repeat('4', 64),
    'd3000000-0000-4000-8000-000000000001'),
  '42501', null,
  'anon cannot call garmin_ack_plan_core'
);
select throws_ok(
  format('select public.garmin_quarantine_pending_plan(%L, %L, 1, ''x'')',
    pg_catalog.repeat('4', 64), 'd3000000-0000-4000-8000-000000000001'),
  '42501', null,
  'anon cannot call garmin_quarantine_pending_plan'
);
select throws_ok(
  format('select public.garmin_quarantine_pending_plan_core(%L, %L, 1, ''x'')',
    pg_catalog.repeat('4', 64), 'd3000000-0000-4000-8000-000000000001'),
  '42501', null,
  'anon cannot call garmin_quarantine_pending_plan_core'
);
select throws_ok(
  format('select public.garmin_record_capability_use(%L, 3::smallint)',
    pg_catalog.repeat('4', 64)),
  '42501', null,
  'anon cannot call garmin_record_capability_use'
);
select throws_ok(
  'select public.garmin_gateway_preauth_debit(''fetch'', 0)', '42501', null,
  'anon cannot call garmin_gateway_preauth_debit'
);
select throws_ok(
  'select public.garmin_read_activity_only_workouts()', '42501', null,
  'anon cannot call garmin_read_activity_only_workouts'
);
select throws_ok(
  format('select public.garmin_sync_activity_only_workouts(0, %L, ''[]''::jsonb)',
    'e3000000-0000-4000-8000-000000000010'),
  '42501', null,
  'anon cannot call garmin_sync_activity_only_workouts'
);
select throws_ok(
  'select public.garmin_create_device_core(''x'')', '42501', null,
  'anon cannot call garmin_create_device_core'
);

reset role;
select * from finish();
rollback;
