begin;

select plan(18);

-- Synthetic Auth rows make social_require_caller exercise the real auth.uid(),
-- signed-session binding, token bucket, and security-definer RPC path. The
-- surrounding transaction is rolled back so the test never retains fixtures.
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
    'd1000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'social-rate-22023@example.invalid',
    '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    pg_catalog.clock_timestamp(),
    pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'd1000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'social-rate-p0002@example.invalid',
    '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    pg_catalog.clock_timestamp(),
    pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'd1000000-0000-4000-8000-000000000003',
    'authenticated',
    'authenticated',
    'social-rate-p0001@example.invalid',
    '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    pg_catalog.clock_timestamp(),
    pg_catalog.clock_timestamp()
  );

insert into auth.sessions (id, user_id, created_at, updated_at) values
  (
    'd2000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    pg_catalog.clock_timestamp(),
    pg_catalog.clock_timestamp()
  ),
  (
    'd2000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000002',
    pg_catalog.clock_timestamp(),
    pg_catalog.clock_timestamp()
  ),
  (
    'd2000000-0000-4000-8000-000000000003',
    'd1000000-0000-4000-8000-000000000003',
    pg_catalog.clock_timestamp(),
    pg_catalog.clock_timestamp()
  );

create temporary table social_domain_error_results (
  case_name text primary key,
  payload jsonb not null,
  response_status text
) on commit drop;

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"d1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"d2000000-0000-4000-8000-000000000001"}';
insert into social_domain_error_results (case_name, payload)
values (
  '22023',
  public.social_update_privacy(null, true, true, true, 1)
);
update social_domain_error_results
set response_status = pg_catalog.current_setting('response.status', true)
where case_name = '22023';

select is(
  (select payload->>'code' from social_domain_error_results where case_name = '22023'),
  '22023',
  'invalid privacy input preserves SQLSTATE 22023'
);
select is(
  (select payload->>'message' from social_domain_error_results where case_name = '22023'),
  'Social privacy update is invalid.',
  'invalid privacy input preserves the legacy error message'
);
select is(
  (select response_status from social_domain_error_results where case_name = '22023'),
  '400',
  'SQLSTATE 22023 preserves the legacy HTTP 400 status'
);
select is(
  (select tokens from gymapp_private.social_rate_limits
    where user_id = 'd1000000-0000-4000-8000-000000000001'
      and bucket_action = 'update_privacy'),
  19::numeric,
  'the 22023 response keeps exactly one committed token debit'
);
select is(
  (select pg_catalog.count(*) from public.profiles
    where user_id = 'd1000000-0000-4000-8000-000000000001'),
  0::bigint,
  'profile initialization rolls back with the 22023 business subtransaction'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.social_settings
    where user_id = 'd1000000-0000-4000-8000-000000000001'),
  0::bigint,
  'privacy initialization rolls back with the 22023 business subtransaction'
);

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"d1000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"d2000000-0000-4000-8000-000000000002"}';
insert into social_domain_error_results (case_name, payload)
values ('P0002', public.social_block_profile('malformed-profile-id'));
update social_domain_error_results
set response_status = pg_catalog.current_setting('response.status', true)
where case_name = 'P0002';

select is(
  (select payload->>'code' from social_domain_error_results where case_name = 'P0002'),
  'P0002',
  'unavailable profile preserves SQLSTATE P0002'
);
select is(
  (select payload->>'message' from social_domain_error_results where case_name = 'P0002'),
  'Social resource unavailable.',
  'unavailable profile preserves the legacy generic message'
);
select is(
  (select response_status from social_domain_error_results where case_name = 'P0002'),
  '500',
  'SQLSTATE P0002 preserves the legacy PostgREST HTTP 500 status'
);
select is(
  (select tokens from gymapp_private.social_rate_limits
    where user_id = 'd1000000-0000-4000-8000-000000000002'
      and bucket_action = 'block_profile'),
  29::numeric,
  'the P0002 response keeps exactly one committed token debit'
);
select is(
  (select pg_catalog.count(*) from public.profiles
    where user_id = 'd1000000-0000-4000-8000-000000000002'),
  0::bigint,
  'profile initialization rolls back with the P0002 business subtransaction'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.social_settings
    where user_id = 'd1000000-0000-4000-8000-000000000002'),
  0::bigint,
  'privacy initialization rolls back with the P0002 business subtransaction'
);

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000003';
set local request.jwt.claims =
  '{"sub":"d1000000-0000-4000-8000-000000000003","role":"authenticated","session_id":"d2000000-0000-4000-8000-000000000003"}';
insert into social_domain_error_results (case_name, payload)
values (
  'P0001',
  public.social_update_privacy(true, true, true, true, 2)
);
update social_domain_error_results
set response_status = pg_catalog.current_setting('response.status', true)
where case_name = 'P0001';

select is(
  (select payload->>'code' from social_domain_error_results where case_name = 'P0001'),
  'P0001',
  'stale privacy CAS preserves SQLSTATE P0001'
);
select is(
  (select payload->>'message' from social_domain_error_results where case_name = 'P0001'),
  'Social privacy settings changed.',
  'stale privacy CAS preserves the legacy conflict message'
);
select is(
  (select response_status from social_domain_error_results where case_name = 'P0001'),
  '400',
  'SQLSTATE P0001 preserves the legacy HTTP 400 status'
);
select is(
  (select tokens from gymapp_private.social_rate_limits
    where user_id = 'd1000000-0000-4000-8000-000000000003'
      and bucket_action = 'update_privacy'),
  19::numeric,
  'the P0001 response keeps exactly one committed token debit'
);
select is(
  (select pg_catalog.count(*) from public.profiles
    where user_id = 'd1000000-0000-4000-8000-000000000003'),
  0::bigint,
  'profile initialization rolls back with the P0001 business subtransaction'
);
select is(
  (select pg_catalog.count(*) from gymapp_private.social_settings
    where user_id = 'd1000000-0000-4000-8000-000000000003'),
  0::bigint,
  'privacy initialization rolls back with the P0001 business subtransaction'
);

select * from finish();

rollback;
