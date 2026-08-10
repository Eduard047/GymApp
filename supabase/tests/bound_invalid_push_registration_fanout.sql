begin;

select plan(8);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  'e1000000-0000-4000-8000-000000000007',
  'authenticated', 'authenticated', 'push-bounded-fanout@example.invalid', '',
  pg_catalog.clock_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}',
  pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
);

insert into auth.sessions (id, user_id, created_at, updated_at) values (
  'f1000000-0000-4000-8000-000000000007',
  'e1000000-0000-4000-8000-000000000007',
  pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
);

insert into gymapp_private.notification_installations (
  id, user_id, installation_id, binding_id, auth_session_id,
  platform, provider, environment, provider_token, token_fingerprint
) values (
  'e2000000-0000-4000-8000-000000000007',
  'e1000000-0000-4000-8000-000000000007',
  'e3000000-0000-4000-8000-000000000007',
  'a1000000-0000-4000-8000-000000000007',
  'f1000000-0000-4000-8000-000000000007',
  'android', 'fcm', 'production',
  'BoundedFanoutProviderToken_00000000000000000000001',
  pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to('bounded-fanout-token', 'UTF8'), 'sha256'),
    'hex'
  )
);

insert into gymapp_private.push_outbox (
  recipient_user_id, event_type, object_id, object_revision,
  dedupe_key, collapse_key, priority, expires_at
)
select
  'e1000000-0000-4000-8000-000000000007',
  'friend_request_received',
  'f_' || pg_catalog.md5('bounded-fanout-' || series::text),
  series,
  'bounded_fanout_' || series::text,
  'friend_request',
  'normal',
  pg_catalog.clock_timestamp() + interval '1 day'
from pg_catalog.generate_series(1, 501) as series;

insert into gymapp_private.push_outbox_deliveries (
  id, outbox_id, installation_id, installation_revision, status,
  attempt_count, next_attempt_at, lease_owner, lease_token, lease_expires_at
)
select
  case when outbox.object_revision = 1
    then 'd1000000-0000-4000-8000-000000000001'::uuid
    else pg_catalog.gen_random_uuid()
  end,
  outbox.id,
  'e2000000-0000-4000-8000-000000000007',
  1,
  case when outbox.object_revision = 1 then 'processing' else 'pending' end,
  case when outbox.object_revision = 1 then 1 else 0 end,
  pg_catalog.clock_timestamp(),
  case when outbox.object_revision = 1
    then 'd2000000-0000-4000-8000-000000000001'::uuid
    else null
  end,
  case when outbox.object_revision = 1
    then 'd3000000-0000-4000-8000-000000000001'::uuid
    else null
  end,
  case when outbox.object_revision = 1
    then pg_catalog.clock_timestamp() + interval '5 minutes'
    else null
  end
from gymapp_private.push_outbox as outbox
where outbox.recipient_user_id = 'e1000000-0000-4000-8000-000000000007';

-- A terminal historical row for the same installation must not enter the
-- invalid-registration reconciliation set.
with historical_outbox as (
  insert into gymapp_private.push_outbox (
    recipient_user_id, event_type, object_id, object_revision,
    dedupe_key, collapse_key, priority, status, completion_reason,
    expires_at, completed_at
  ) values (
    'e1000000-0000-4000-8000-000000000007',
    'friend_request_received',
    'f_ffffffffffffffffffffffffffffffff',
    777,
    'bounded_fanout_historical',
    'friend_request',
    'normal',
    'complete',
    'delivered',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp()
  ) returning id
)
insert into gymapp_private.push_outbox_deliveries (
  outbox_id, installation_id, installation_revision, status,
  attempt_count, provider_status, delivered_at
)
select
  historical_outbox.id,
  'e2000000-0000-4000-8000-000000000007',
  1,
  'delivered',
  1,
  200,
  pg_catalog.clock_timestamp()
from historical_outbox;

select is(
  public.push_mark_retry(
    'd1000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000001',
    'fcm_unregistered',
    404,
    null,
    true,
    false
  ),
  true,
  'the leased invalid-registration result is accepted'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.push_outbox_deliveries
   where installation_id = 'e2000000-0000-4000-8000-000000000007'
     and status = 'invalid'),
  500::bigint,
  'one invalid-registration call changes at most 500 current deliveries'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.push_outbox_deliveries
   where installation_id = 'e2000000-0000-4000-8000-000000000007'
     and status = 'pending'),
  1::bigint,
  'the bounded remainder stays pending for the ordinary claim sweep'
);
select ok(
  (select revoked_at is not null
      and provider_token is null
      and binding_id <> 'a1000000-0000-4000-8000-000000000007'
   from gymapp_private.notification_installations
   where id = 'e2000000-0000-4000-8000-000000000007'),
  'invalid registration scrubs the address and rotates the opaque binding'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.push_outbox_deliveries
   where installation_id = 'e2000000-0000-4000-8000-000000000007'
     and status = 'delivered'),
  1::bigint,
  'the historical delivered row is untouched by bounded reconciliation'
);

create temporary table bounded_push_claim_result on commit drop as
select * from public.push_claim_deliveries(
  'd4000000-0000-4000-8000-000000000001',
  1,
  15
);

select is(
  (select pg_catalog.count(*) from bounded_push_claim_result),
  0::bigint,
  'the revoked installation yields no new provider delivery'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.push_outbox_deliveries
   where installation_id = 'e2000000-0000-4000-8000-000000000007'
     and status = 'invalid'),
  501::bigint,
  'the ordinary claim sweep safely invalidates the bounded remainder'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.push_outbox_deliveries
   where installation_id = 'e2000000-0000-4000-8000-000000000007'
     and status = 'delivered'),
  1::bigint,
  'the claim sweep also preserves the historical terminal delivery'
);

select * from finish();

rollback;
