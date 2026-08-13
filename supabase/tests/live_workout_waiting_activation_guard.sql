begin;

select plan(4);

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
    'd3000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'live-guard-valid@example.invalid',
    '',
    '2026-08-13 10:00:00+00',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    '2026-08-13 10:00:00+00',
    '2026-08-13 10:00:00+00'
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'd3000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'live-guard-invalid@example.invalid',
    '',
    '2026-08-13 10:00:00+00',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    '2026-08-13 10:00:00+00',
    '2026-08-13 10:00:00+00'
  );

insert into gymapp_private.live_workout_rooms (
  id,
  owner_user_id,
  client_request_id,
  status,
  plan,
  summary,
  revision,
  created_at,
  invite_expires_at,
  last_activity_at,
  updated_at
) values
  (
    'lr_d3000000000040008000000000000001',
    'd3000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000011',
    'waiting',
    '{"version":1,"exercises":[]}'::jsonb,
    '{}'::jsonb,
    1,
    '2026-08-13 10:00:00+00',
    '2026-08-20 10:00:00+00',
    '2026-08-13 10:00:00+00',
    '2026-08-13 10:00:00+00'
  ),
  (
    'lr_d3000000000040008000000000000002',
    'd3000000-0000-4000-8000-000000000002',
    'd3000000-0000-4000-8000-000000000012',
    'waiting',
    '{"version":1,"exercises":[]}'::jsonb,
    '{}'::jsonb,
    1,
    '2026-08-13 10:00:00+00',
    '2026-08-20 10:00:00+00',
    '2026-08-13 10:00:00+00',
    '2026-08-13 10:00:00+00'
  );

select lives_ok(
  $test$
    update gymapp_private.live_workout_rooms
    set status = 'active',
        revision = 2,
        started_at = '2026-08-13 10:01:00+00',
        active_expires_at = '2026-08-14 10:01:00+00',
        last_activity_at = '2026-08-13 10:01:00+00',
        updated_at = '2026-08-13 10:01:00+00'
    where id = 'lr_d3000000000040008000000000000001'
  $test$,
  'waiting room can transition directly to invariant-safe active state'
);

select is(
  (select status from gymapp_private.live_workout_rooms
    where id = 'lr_d3000000000040008000000000000001'),
  'active',
  'successful direct activation is committed inside the test transaction'
);

select is(
  (select active_expires_at - started_at from gymapp_private.live_workout_rooms
    where id = 'lr_d3000000000040008000000000000001'),
  interval '24 hours',
  'direct activation keeps the exact 24-hour active lifetime'
);

select throws_ok(
  $test$
    update gymapp_private.live_workout_rooms
    set status = 'active',
        revision = 2,
        started_at = '2026-08-13 10:01:00+00',
        active_expires_at = '2026-08-14 10:02:00+00',
        last_activity_at = '2026-08-13 10:01:00+00',
        updated_at = '2026-08-13 10:01:00+00'
    where id = 'lr_d3000000000040008000000000000002'
  $test$,
  '42501',
  'Live workout room transition is invalid.',
  'waiting-to-active rejects an expiry that is not exactly started_at plus 24 hours'
);

select * from finish();

rollback;
