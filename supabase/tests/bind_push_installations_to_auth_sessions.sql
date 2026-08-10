begin;

select plan(24);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    'a1000000-0000-4000-8000-000000000001',
    'authenticated', 'authenticated', 'push-session-a@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a1000000-0000-4000-8000-000000000002',
    'authenticated', 'authenticated', 'push-session-b@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a1000000-0000-4000-8000-000000000003',
    'authenticated', 'authenticated', 'push-session-expired@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a1000000-0000-4000-8000-000000000004',
    'authenticated', 'authenticated', 'push-session-missing@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

insert into auth.sessions (id, user_id, not_after, created_at, updated_at) values
  (
    'b1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'b1000000-0000-4000-8000-000000000002',
    'a1000000-0000-4000-8000-000000000001',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'b1000000-0000-4000-8000-000000000003',
    'a1000000-0000-4000-8000-000000000002',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'b1000000-0000-4000-8000-000000000004',
    'a1000000-0000-4000-8000-000000000003',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

create temporary table push_session_registration_results (
  case_name text primary key,
  payload jsonb not null
) on commit drop;

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b1000000-0000-4000-8000-000000000001"}';
insert into push_session_registration_results values (
  'session-a1',
  public.notification_register_installation(
    'c1000000-0000-4000-8000-000000000001',
    'android', 'fcm', 'production',
    'SessionBoundProviderToken_00000000000000000000000001',
    null, null, 'en', '1.0.0'
  )
);

select is(
  (select auth_session_id
   from gymapp_private.notification_installations
   where user_id = 'a1000000-0000-4000-8000-000000000001'
     and installation_id = 'c1000000-0000-4000-8000-000000000001'),
  'b1000000-0000-4000-8000-000000000001'::uuid,
  'registration persists the exact JWT session id'
);
select is(
  (select (payload ->> 'registrationRevision')::bigint
   from push_session_registration_results where case_name = 'session-a1'),
  1::bigint,
  'first registration starts at revision one'
);

insert into push_session_registration_results values (
  'session-a1-repeat',
  public.notification_register_installation(
    'c1000000-0000-4000-8000-000000000001',
    'android', 'fcm', 'production',
    'SessionBoundProviderToken_00000000000000000000000001',
    null, null, 'en', '1.0.0'
  )
);
select is(
  (select payload ->> 'bindingId' from push_session_registration_results
   where case_name = 'session-a1-repeat'),
  (select payload ->> 'bindingId' from push_session_registration_results
   where case_name = 'session-a1'),
  'an idempotent registration in the same session preserves binding'
);
select is(
  (select (payload ->> 'registrationRevision')::bigint
   from push_session_registration_results where case_name = 'session-a1-repeat'),
  1::bigint,
  'an idempotent registration in the same session preserves revision'
);

set local request.jwt.claims =
  '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b1000000-0000-4000-8000-000000000002"}';
insert into push_session_registration_results values (
  'session-a2',
  public.notification_register_installation(
    'c1000000-0000-4000-8000-000000000001',
    'android', 'fcm', 'production',
    'SessionBoundProviderToken_00000000000000000000000001',
    null, null, 'en', '1.0.0'
  )
);

select is(
  (select auth_session_id
   from gymapp_private.notification_installations
   where user_id = 'a1000000-0000-4000-8000-000000000001'
     and installation_id = 'c1000000-0000-4000-8000-000000000001'),
  'b1000000-0000-4000-8000-000000000002'::uuid,
  're-login rebinds the address to the new exact session'
);
select isnt(
  (select payload ->> 'bindingId' from push_session_registration_results
   where case_name = 'session-a2'),
  (select payload ->> 'bindingId' from push_session_registration_results
   where case_name = 'session-a1'),
  're-login rotates the opaque binding id'
);
select is(
  (select (payload ->> 'registrationRevision')::bigint
   from push_session_registration_results where case_name = 'session-a2'),
  2::bigint,
  're-login advances the registration revision exactly once'
);

select lives_ok(
  $$
    select gymapp_private.enqueue_push_notification(
      'a1000000-0000-4000-8000-000000000001',
      'friend_request_received',
      'f_session_bound',
      1,
      'session_bound_claim_1',
      'friend_request',
      'normal',
      pg_catalog.clock_timestamp() + interval '1 day'
    )
  $$,
  'a current session-bound installation accepts an opaque outbox intent'
);

create temporary table push_session_claim on commit drop as
select * from public.push_claim_deliveries(
  'd1000000-0000-4000-8000-000000000001',
  1,
  60
);
select is(
  (select pg_catalog.count(*) from push_session_claim),
  1::bigint,
  'claim returns a delivery only while its exact session remains current'
);

set local request.jwt.claims = '{"role":"service_role"}';
select ok(
  public.push_delivery_is_current(
    (select delivery_id from push_session_claim),
    (select lease_token from push_session_claim)
  ),
  'the final pre-send check accepts the current exact session'
);

delete from auth.sessions
where id = 'b1000000-0000-4000-8000-000000000002';

select ok(
  (select revoked_at is not null
      and auth_session_id is null
      and provider_token is null
      and binding_id::text <> (
        select payload ->> 'bindingId' from push_session_registration_results
        where case_name = 'session-a2'
      )
   from gymapp_private.notification_installations
   where user_id = 'a1000000-0000-4000-8000-000000000001'
     and installation_id = 'c1000000-0000-4000-8000-000000000001'),
  'session deletion immediately revokes, scrubs, and rotates its installation'
);
select ok(
  not public.push_delivery_is_current(
    (select delivery_id from push_session_claim),
    (select lease_token from push_session_claim)
  ),
  'the final pre-send check fails closed after exact-session deletion'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"a1000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"b1000000-0000-4000-8000-000000000003"}';
insert into push_session_registration_results values (
  'account-b',
  public.notification_register_installation(
    'c1000000-0000-4000-8000-000000000001',
    'android', 'fcm', 'production',
    'SessionBoundProviderToken_00000000000000000000000001',
    null, null, 'en', '1.0.0'
  )
);
select ok(
  (select user_id = 'a1000000-0000-4000-8000-000000000002'
      and auth_session_id = 'b1000000-0000-4000-8000-000000000003'
      and revoked_at is null
   from gymapp_private.notification_installations
   where installation_id = 'c1000000-0000-4000-8000-000000000001'
     and revoked_at is null),
  'account rebind exposes one active row bound to the new owner session'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.notification_installations
   where user_id = 'a1000000-0000-4000-8000-000000000001'
     and installation_id = 'c1000000-0000-4000-8000-000000000001'
     and provider_token is not null),
  0::bigint,
  'the previous account retains no provider material'
);

insert into auth.sessions (id, user_id, not_after, created_at, updated_at) values (
  'b1000000-0000-4000-8000-000000000005',
  'a1000000-0000-4000-8000-000000000001',
  pg_catalog.clock_timestamp() + interval '1 day',
  pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
);
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"b1000000-0000-4000-8000-000000000005"}';
insert into push_session_registration_results values (
  'token-rebind-a',
  public.notification_register_installation(
    'c1000000-0000-4000-8000-000000000005',
    'android', 'fcm', 'production',
    'SessionBoundProviderToken_00000000000000000000000001',
    null, null, 'en', '1.0.0'
  )
);
select ok(
  (select revoked_at is not null
      and provider_token is null
      and auth_session_id is null
   from gymapp_private.notification_installations
   where user_id = 'a1000000-0000-4000-8000-000000000002'
     and installation_id = 'c1000000-0000-4000-8000-000000000001'),
  'provider-token rebind scrubs and unbinds the stale owner row'
);
select ok(
  (select revoked_at is null
      and auth_session_id = 'b1000000-0000-4000-8000-000000000005'
   from gymapp_private.notification_installations
   where user_id = 'a1000000-0000-4000-8000-000000000001'
     and installation_id = 'c1000000-0000-4000-8000-000000000005'),
  'provider-token rebind activates only the current owner session'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000004';
set local request.jwt.claims =
  '{"sub":"a1000000-0000-4000-8000-000000000004","role":"authenticated","session_id":"b1000000-0000-4000-8000-000000000099"}';
select throws_ok(
  $$
    select public.notification_register_installation(
      'c1000000-0000-4000-8000-000000000099',
      'android', 'fcm', 'production',
      'MissingSessionProviderToken_000000000000000000000001',
      null, null, 'en', '1.0.0'
    )
  $$,
  '42501',
  'A current authenticated session is required.',
  'a JWT whose exact session row is missing cannot register'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.notification_rate_limits
   where user_id = 'a1000000-0000-4000-8000-000000000004'),
  0::bigint,
  'missing-session rejection happens before a rate-limit debit'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000003';
set local request.jwt.claims =
  '{"sub":"a1000000-0000-4000-8000-000000000003","role":"authenticated","session_id":"b1000000-0000-4000-8000-000000000004"}';
insert into push_session_registration_results values (
  'expiring-session',
  public.notification_register_installation(
    'c1000000-0000-4000-8000-000000000004',
    'android', 'fcm', 'production',
    'ExpiringSessionProviderToken_0000000000000000000001',
    null, null, 'en', '1.0.0'
  )
);

select lives_ok(
  $$
    select gymapp_private.enqueue_push_notification(
      'a1000000-0000-4000-8000-000000000003',
      'friend_request_received',
      'f_expired_session',
      1,
      'expired_session_claim_1',
      'friend_request',
      'normal',
      pg_catalog.clock_timestamp() + interval '1 day'
    )
  $$,
  'an intent is queued before the bound session expires'
);
update auth.sessions
set not_after = pg_catalog.clock_timestamp() - interval '1 minute'
where id = 'b1000000-0000-4000-8000-000000000004';

create temporary table expired_session_claim on commit drop as
select * from public.push_claim_deliveries(
  'd1000000-0000-4000-8000-000000000004',
  10,
  60
);
select is(
  (select pg_catalog.count(*) from expired_session_claim),
  0::bigint,
  'claim returns no provider material after the exact session expires'
);
select ok(
  (select revoked_at is not null
      and provider_token is null
      and auth_session_id is null
   from gymapp_private.notification_installations
   where user_id = 'a1000000-0000-4000-8000-000000000003'
     and installation_id = 'c1000000-0000-4000-8000-000000000004'),
  'claim scrubs the expired-session registration in its bounded batch'
);
select is(
  (select error_code
   from gymapp_private.push_outbox_deliveries as delivery
   join gymapp_private.push_outbox as outbox on outbox.id = delivery.outbox_id
   where outbox.dedupe_key = 'expired_session_claim_1'),
  'registration_revoked',
  'expired-session delivery is terminally invalidated without provider send'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'gymapp_private.notification_register_installation_storage_v1(uuid,text,text,text,text,text,text,text,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot bypass the session-binding wrapper'
);
select ok(
  not pg_catalog.has_function_privilege(
    'service_role',
    'gymapp_private.push_claim_deliveries_storage_v1(uuid,integer,integer)',
    'EXECUTE'
  ),
  'the dispatcher cannot bypass the session-filtering claim wrapper'
);

select * from finish();

rollback;
