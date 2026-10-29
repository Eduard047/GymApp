begin;

select plan(32);

-- Synthetic accounts exercise auth.uid(), current-session binding, both push
-- token buckets, and the real security-definer RPCs. The outer transaction is
-- rolled back so no fixture survives the test.
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
) values
  (
    '00000000-0000-0000-0000-000000000000',
    'e1000000-0000-4000-8000-000000000001',
    'authenticated', 'authenticated', 'push-rate-register@example.invalid', '',
    pg_catalog.clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'e1000000-0000-4000-8000-000000000002',
    'authenticated', 'authenticated', 'push-rate-revoke@example.invalid', '',
    pg_catalog.clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'e1000000-0000-4000-8000-000000000003',
    'authenticated', 'authenticated', 'push-rate-limit@example.invalid', '',
    pg_catalog.clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'e1000000-0000-4000-8000-000000000004',
    'authenticated', 'authenticated', 'push-rate-foreign@example.invalid', '',
    pg_catalog.clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'e1000000-0000-4000-8000-000000000005',
    'authenticated', 'authenticated', 'push-rate-no-session@example.invalid', '',
    pg_catalog.clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'e1000000-0000-4000-8000-000000000006',
    'authenticated', 'authenticated', 'push-rate-internal@example.invalid', '',
    pg_catalog.clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'e1000000-0000-4000-8000-000000000007',
    'authenticated', 'authenticated', 'push-rate-takeover@example.invalid', '',
    pg_catalog.clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'e1000000-0000-4000-8000-000000000008',
    'authenticated', 'authenticated', 'push-rate-malformed@example.invalid', '',
    pg_catalog.clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'e1000000-0000-4000-8000-000000000009',
    'authenticated', 'authenticated', 'push-rate-drain@example.invalid', '',
    pg_catalog.clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb, '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

insert into auth.sessions (id, user_id, created_at, updated_at) values
  (
    'f1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000001',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'f1000000-0000-4000-8000-000000000002',
    'e1000000-0000-4000-8000-000000000002',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'f1000000-0000-4000-8000-000000000003',
    'e1000000-0000-4000-8000-000000000003',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'f1000000-0000-4000-8000-000000000004',
    'e1000000-0000-4000-8000-000000000004',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'f1000000-0000-4000-8000-000000000006',
    'e1000000-0000-4000-8000-000000000006',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  
  ),
  (
    'f1000000-0000-4000-8000-000000000007',
    'e1000000-0000-4000-8000-000000000007',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'f1000000-0000-4000-8000-000000000008',
    'e1000000-0000-4000-8000-000000000008',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'f1000000-0000-4000-8000-000000000009',
    'e1000000-0000-4000-8000-000000000009',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

create temporary table notification_domain_error_results (
  case_name text primary key,
  payload jsonb not null,
  response_status text
) on commit drop;

set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"e1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"f1000000-0000-4000-8000-000000000001"}';
insert into notification_domain_error_results (case_name, payload)
values (
  'register-22023',
  public.notification_register_installation(
    null, 'android', 'fcm', 'production', pg_catalog.repeat('A', 32),
    null, null, 'en', '1.0.0'
  )
);
update notification_domain_error_results
set response_status = pg_catalog.current_setting('response.status', true)
where case_name = 'register-22023';

select is(
  (select payload::text from notification_domain_error_results where case_name = 'register-22023'),
  '{"code":"22023","hint":null,"details":null,"message":"Notification registration is invalid."}'::jsonb::text,
  'malformed registration preserves the legacy 22023 body'
);
select is(
  (select response_status from notification_domain_error_results where case_name = 'register-22023'),
  '400',
  'malformed registration preserves HTTP 400'
);
select is(
  (select tokens from gymapp_private.notification_rate_limits
    where user_id = 'e1000000-0000-4000-8000-000000000001' and bucket_action = 'register'),
  29::numeric,
  'malformed registration keeps exactly one debit'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.notification_installations
    where user_id = 'e1000000-0000-4000-8000-000000000001'),
  0::bigint,
  'malformed registration creates no installation'
);

set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"e1000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"f1000000-0000-4000-8000-000000000002"}';
insert into notification_domain_error_results (case_name, payload)
values ('revoke-22023', public.notification_revoke_installation(null));
update notification_domain_error_results
set response_status = pg_catalog.current_setting('response.status', true)
where case_name = 'revoke-22023';

select is(
  (select payload::text from notification_domain_error_results where case_name = 'revoke-22023'),
  '{"code":"22023","hint":null,"details":null,"message":"Notification revocation is invalid."}'::jsonb::text,
  'malformed revocation preserves the legacy 22023 body'
);
select is(
  (select response_status from notification_domain_error_results where case_name = 'revoke-22023'),
  '400',
  'malformed revocation preserves HTTP 400'
);
select is(
  (select tokens from gymapp_private.notification_rate_limits
    where user_id = 'e1000000-0000-4000-8000-000000000002' and bucket_action = 'revoke'),
  59::numeric,
  'malformed revocation keeps exactly one debit'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.notification_installations
    where user_id = 'e1000000-0000-4000-8000-000000000002'),
  0::bigint,
  'malformed revocation mutates no installation'
);

-- The 54000 cap is reached by a caller that already holds twelve active
-- installations and registers a fresh, unowned installation id.
insert into gymapp_private.notification_installations (
  user_id, installation_id, auth_session_id, platform, provider, environment,
  provider_token, token_fingerprint
)
select
  'e1000000-0000-4000-8000-000000000003',
  pg_catalog.gen_random_uuid(),
  'f1000000-0000-4000-8000-000000000003',
  'android', 'fcm', 'production',
  'LimitCallerToken_' || pg_catalog.lpad(series::text, 32, '0'),
  pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to('limit-caller-' || series::text, 'UTF8'), 'sha256'),
    'hex'
  )
from pg_catalog.generate_series(1, 12) as series;

set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000003';
set local request.jwt.claims =
  '{"sub":"e1000000-0000-4000-8000-000000000003","role":"authenticated","session_id":"f1000000-0000-4000-8000-000000000003"}';
insert into notification_domain_error_results (case_name, payload)
values (
  'register-54000',
  public.notification_register_installation(
    'e3000000-0000-4000-8000-000000000098',
    'android', 'fcm', 'production',
    'NewOwnerProviderToken_00000000000000000000000000001',
    null, null, 'en', '1.0.0'
  )
);
update notification_domain_error_results
set response_status = pg_catalog.current_setting('response.status', true)
where case_name = 'register-54000';

select is(
  (select payload::text from notification_domain_error_results where case_name = 'register-54000'),
  '{"code":"54000","hint":null,"details":null,"message":"Notification installation limit exceeded."}'::jsonb::text,
  'installation cap preserves the legacy 54000 body'
);
select is(
  (select response_status from notification_domain_error_results where case_name = 'register-54000'),
  '500',
  'installation cap preserves HTTP 500'
);
select is(
  (select tokens from gymapp_private.notification_rate_limits
    where user_id = 'e1000000-0000-4000-8000-000000000003' and bucket_action = 'register'),
  29::numeric,
  'installation cap keeps exactly one debit'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.notification_installations
    where user_id = 'e1000000-0000-4000-8000-000000000003' and revoked_at is null),
  12::bigint,
  'the caller retains exactly the original active installations'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.notification_installations
    where user_id = 'e1000000-0000-4000-8000-000000000003'
      and installation_id = 'e3000000-0000-4000-8000-000000000098'),
  0::bigint,
  'the capped registration inserts no caller binding'
);

-- Taking over a foreign installation id without proving possession of its
-- provider address is rejected by the ownership wrapper before the worker
-- runs. The rejection must still return the legacy body and persist one debit.
insert into gymapp_private.notification_installations (
  user_id, installation_id, auth_session_id, platform, provider, environment,
  provider_token, token_fingerprint
) values (
  'e1000000-0000-4000-8000-000000000004',
  'e3000000-0000-4000-8000-000000000099',
  'f1000000-0000-4000-8000-000000000004',
  'android', 'fcm', 'production',
  'ForeignProviderToken_000000000000000000000000000001',
  pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to('foreign-limit-binding', 'UTF8'), 'sha256'),
    'hex'
  )
);

set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000007';
set local request.jwt.claims =
  '{"sub":"e1000000-0000-4000-8000-000000000007","role":"authenticated","session_id":"f1000000-0000-4000-8000-000000000007"}';
insert into notification_domain_error_results (case_name, payload)
values (
  'register-takeover-22023',
  public.notification_register_installation(
    'e3000000-0000-4000-8000-000000000099',
    'android', 'fcm', 'production',
    'NewOwnerProviderToken_00000000000000000000000000001',
    null, null, 'en', '1.0.0'
  )
);
update notification_domain_error_results
set response_status = pg_catalog.current_setting('response.status', true)
where case_name = 'register-takeover-22023';

select is(
  (select payload::text from notification_domain_error_results where case_name = 'register-takeover-22023'),
  '{"code":"22023","hint":null,"details":null,"message":"Notification registration is invalid."}'::jsonb::text,
  'foreign installation takeover without the address returns the legacy 22023 body'
);
select is(
  (select response_status from notification_domain_error_results where case_name = 'register-takeover-22023'),
  '400',
  'foreign installation takeover returns HTTP 400'
);
select is(
  (select tokens from gymapp_private.notification_rate_limits
    where user_id = 'e1000000-0000-4000-8000-000000000007' and bucket_action = 'register'),
  29::numeric,
  'foreign installation takeover keeps exactly one debit'
);
select ok(
  (select revoked_at is null
      and provider_token = 'ForeignProviderToken_000000000000000000000000000001'
    from gymapp_private.notification_installations
    where user_id = 'e1000000-0000-4000-8000-000000000004'
      and installation_id = 'e3000000-0000-4000-8000-000000000099'),
  'the rejected takeover leaves the foreign binding unchanged'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.notification_installations
    where user_id = 'e1000000-0000-4000-8000-000000000007'),
  0::bigint,
  'the rejected takeover creates no caller binding'
);

-- A malformed provider address for a valid installation id is also rejected by
-- the wrapper before the worker and must be debited once.
set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000008';
set local request.jwt.claims =
  '{"sub":"e1000000-0000-4000-8000-000000000008","role":"authenticated","session_id":"f1000000-0000-4000-8000-000000000008"}';
insert into notification_domain_error_results (case_name, payload)
values (
  'register-malformed-token',
  public.notification_register_installation(
    'e3000000-0000-4000-8000-000000000008',
    'android', 'fcm', 'production', 'short token',
    null, null, 'en', '1.0.0'
  )
);
update notification_domain_error_results
set response_status = pg_catalog.current_setting('response.status', true)
where case_name = 'register-malformed-token';

select is(
  (select payload::text from notification_domain_error_results where case_name = 'register-malformed-token'),
  '{"code":"22023","hint":null,"details":null,"message":"Notification registration is invalid."}'::jsonb::text,
  'malformed provider address returns the legacy 22023 body'
);
select is(
  (select response_status from notification_domain_error_results where case_name = 'register-malformed-token'),
  '400',
  'malformed provider address returns HTTP 400'
);
select is(
  (select tokens from gymapp_private.notification_rate_limits
    where user_id = 'e1000000-0000-4000-8000-000000000008' and bucket_action = 'register'),
  29::numeric,
  'malformed provider address keeps exactly one debit'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.notification_installations
    where user_id = 'e1000000-0000-4000-8000-000000000008'),
  0::bigint,
  'malformed provider address creates no installation'
);

-- Repeated rejected registrations drain the same bucket and are then limited
-- exactly like valid ones.
set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000009';
set local request.jwt.claims =
  '{"sub":"e1000000-0000-4000-8000-000000000009","role":"authenticated","session_id":"f1000000-0000-4000-8000-000000000009"}';
do $drain$
begin
  for attempt in 1..30 loop
    perform public.notification_register_installation(
      'e3000000-0000-4000-8000-000000000009',
      'android', 'fcm', 'production', 'short token',
      null, null, 'en', '1.0.0'
    );
  end loop;
end
$drain$;
select ok(
  (select tokens < 1
    from gymapp_private.notification_rate_limits
    where user_id = 'e1000000-0000-4000-8000-000000000009' and bucket_action = 'register'),
  'thirty rejected registrations drain the register bucket'
);
select throws_ok(
  $$
    select public.notification_register_installation(
      'e3000000-0000-4000-8000-000000000009',
      'android', 'fcm', 'production', 'short token',
      null, null, 'en', '1.0.0'
    )
  $$,
  'P0001',
  'Notification request rate limit exceeded.',
  'an empty bucket rate-limits further rejected registrations'
);

set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000005';
set local request.jwt.claims =
  '{"sub":"e1000000-0000-4000-8000-000000000005","role":"authenticated","session_id":"f1000000-0000-4000-8000-000000000005"}';
select throws_ok(
  $$ select public.notification_revoke_installation('e3000000-0000-4000-8000-000000000005') $$,
  '42501',
  'A current authenticated session is required.',
  'missing Auth session still raises 42501'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.notification_rate_limits
    where user_id = 'e1000000-0000-4000-8000-000000000005'),
  0::bigint,
  'missing Auth session is rejected before any debit'
);

create function pg_temp.notification_test_internal_failure()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception using errcode = 'XX000', message = 'synthetic notification storage failure';
end
$function$;

create trigger notification_test_internal_failure
before insert on gymapp_private.notification_installations
for each row execute function pg_temp.notification_test_internal_failure();

set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000006';
set local request.jwt.claims =
  '{"sub":"e1000000-0000-4000-8000-000000000006","role":"authenticated","session_id":"f1000000-0000-4000-8000-000000000006"}';
select throws_ok(
  $$
    select public.notification_register_installation(
      'e3000000-0000-4000-8000-000000000006',
      'android', 'fcm', 'production',
      'InternalFailureToken_00000000000000000000000000001',
      null, null, 'en', '1.0.0'
    )
  $$,
  'XX000',
  'synthetic notification storage failure',
  'unexpected storage errors still raise'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.notification_rate_limits
    where user_id = 'e1000000-0000-4000-8000-000000000006'),
  0::bigint,
  'an unexpected error rolls its tentative debit back'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.notification_installations
    where user_id = 'e1000000-0000-4000-8000-000000000006'),
  0::bigint,
  'an unexpected error commits no installation'
);

drop trigger notification_test_internal_failure
  on gymapp_private.notification_installations;

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'gymapp_private.notification_domain_error_response(text,text,text,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot call the private response helper'
);
select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.notification_register_installation(uuid,text,text,text,text,text,text,text,text)',
    'EXECUTE'
  ),
  'authenticated registration execute grant is preserved'
);
select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.notification_revoke_installation(uuid)',
    'EXECUTE'
  ),
  'authenticated revocation execute grant is preserved'
);

select * from finish();

rollback;
