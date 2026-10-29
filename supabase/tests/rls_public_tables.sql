begin;

select plan(79);

-- Fixture: user A and user B hold live auth sessions; user C holds an expired
-- one. Everything below runs as the real client roles (anon, authenticated),
-- so the table grants, column grants, and RLS policies are exercised exactly
-- as PostgREST would exercise them.
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
    'f1000000-0000-4000-8000-000000000001',
    'authenticated', 'authenticated', 'rls-public-a@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'f1000000-0000-4000-8000-000000000002',
    'authenticated', 'authenticated', 'rls-public-b@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'f1000000-0000-4000-8000-000000000003',
    'authenticated', 'authenticated', 'rls-public-c@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

insert into auth.sessions (id, user_id, not_after, created_at, updated_at) values
  (
    'f2000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000001',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'f2000000-0000-4000-8000-000000000002',
    'f1000000-0000-4000-8000-000000000002',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'f2000000-0000-4000-8000-000000000003',
    'f1000000-0000-4000-8000-000000000003',
    pg_catalog.clock_timestamp() - interval '1 second',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

-- garmin_devices has no client privileges, so devices are fixture rows.
insert into public.garmin_devices (
  id, user_id, device_token, display_name, binding_version, token_revision
) values
  (
    'f3000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000001',
    pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to('rls-public-a', 'UTF8')), 'hex'),
    'RLS watch A', 2, 1
  ),
  (
    'f3000000-0000-4000-8000-000000000002',
    'f1000000-0000-4000-8000-000000000002',
    pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to('rls-public-b', 'UTF8')), 'hex'),
    'RLS watch B', 2, 1
  );

-- User C exists only to prove an expired session reads nothing.
insert into public.profiles (user_id, display_name)
values ('f1000000-0000-4000-8000-000000000003', 'Cara Lifter');
insert into public.user_states (user_id)
values ('f1000000-0000-4000-8000-000000000003');

select pg_catalog.set_config(
  'test.plan',
  '{"source":"gymapp","version":1,"title":"RLS plan","note":"","createdAt":"2026-01-01T00:00:00Z","startedAt":"2026-01-01T00:00:00Z","exercises":[{"name":"Squat","sets":[{"weight":50,"reps":5}]}]}',
  true
);

-- ---------------------------------------------------------------------------
-- anon: no client privileges on private tables; catalog is read-only.
-- ---------------------------------------------------------------------------
set local role anon;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok(
  $$select user_id from public.profiles$$,
  '42501', null, 'anon cannot select profiles'
);
select throws_ok(
  $$insert into public.profiles (user_id, display_name)
    values ('f1000000-0000-4000-8000-000000000001', 'Anon Intruder')$$,
  '42501', null, 'anon cannot insert profiles'
);
select throws_ok(
  $$update public.profiles set display_name = 'Anon Intruder'$$,
  '42501', null, 'anon cannot update profiles'
);
select throws_ok(
  $$delete from public.profiles$$,
  '42501', null, 'anon cannot delete profiles'
);
select throws_ok(
  $$select user_id from public.user_states$$,
  '42501', null, 'anon cannot select user_states'
);
select throws_ok(
  $$insert into public.user_states (user_id)
    values ('f1000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'anon cannot insert user_states'
);
select throws_ok(
  $$update public.user_states set state = '{}'::jsonb$$,
  '42501', null, 'anon cannot update user_states'
);
select throws_ok(
  $$select id from public.garmin_plans$$,
  '42501', null, 'anon cannot select garmin_plans'
);
select throws_ok(
  $$insert into public.garmin_plans (user_id, device_id, status, plan)
    values ('f1000000-0000-4000-8000-000000000001',
            'f3000000-0000-4000-8000-000000000001',
            'pending', current_setting('test.plan')::jsonb)$$,
  '42501', null, 'anon cannot insert garmin_plans'
);
select throws_ok(
  $$select id from public.leaderboard_reports$$,
  '42501', null, 'anon cannot select leaderboard_reports'
);
select throws_ok(
  $$insert into public.leaderboard_reports (reported_profile_id, reason)
    values ('p_00000000000000000000000000000000', 'other')$$,
  '42501', null, 'anon cannot insert leaderboard_reports'
);
select throws_ok(
  $$select id from public.garmin_devices$$,
  '42501', null, 'anon cannot select garmin_devices'
);
select throws_ok(
  $$insert into public.garmin_devices (user_id, device_token)
    values ('f1000000-0000-4000-8000-000000000001', 'anon-token')$$,
  '42501', null, 'anon cannot insert garmin_devices'
);
select throws_ok(
  $$select term from public.leaderboard_blocked_terms$$,
  '42501', null, 'anon cannot select leaderboard_blocked_terms'
);
select throws_ok(
  $$select profile_id from public.leaderboard_public$$,
  '42501', null, 'anon cannot select the leaderboard_public view'
);
select isnt_empty(
  $$select key from public.exercise_catalog$$,
  'anon can select exercise_catalog'
);
select throws_ok(
  $$insert into public.exercise_catalog (key, name_en, name_uk, muscle_ids, display_order)
    values ('rls_anon_probe', 'Probe', 'Probe', array[]::text[], 9999)$$,
  '42501', null, 'anon cannot insert exercise_catalog'
);
select throws_ok(
  $$update public.exercise_catalog set name_en = 'Hacked'$$,
  '42501', null, 'anon cannot update exercise_catalog'
);
select throws_ok(
  $$delete from public.exercise_catalog$$,
  '42501', null, 'anon cannot delete exercise_catalog'
);

-- ---------------------------------------------------------------------------
-- User A: owner access to own rows.
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = 'f1000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"f2000000-0000-4000-8000-000000000001"}';

select lives_ok(
  $$insert into public.profiles (user_id, display_name)
    values ('f1000000-0000-4000-8000-000000000001', 'Alice Lifter')$$,
  'A can insert own profile'
);
select lives_ok(
  $$insert into public.user_states (user_id)
    values ('f1000000-0000-4000-8000-000000000001')$$,
  'A can insert own user_states row'
);
select is(
  (select pg_catalog.count(*) from public.profiles
   where user_id = 'f1000000-0000-4000-8000-000000000001'),
  1::bigint,
  'A can select own profile'
);
select is(
  (select pg_catalog.count(*) from public.user_states
   where user_id = 'f1000000-0000-4000-8000-000000000001'),
  1::bigint,
  'A can select own user_states row'
);
select lives_ok(
  $t$do $d$
  declare affected integer;
  begin
    update public.profiles set display_name = 'Alice Renamed'
    where user_id = 'f1000000-0000-4000-8000-000000000001';
    get diagnostics affected = row_count;
    if affected <> 1 then
      raise exception 'expected 1 updated profile row, got %', affected;
    end if;
  end
  $d$$t$,
  'A can update own profile (1 row affected)'
);
select lives_ok(
  $t$do $d$
  declare affected integer;
  begin
    update public.user_states set state = '{"marker":"v2"}'::jsonb
    where user_id = 'f1000000-0000-4000-8000-000000000001';
    get diagnostics affected = row_count;
    if affected <> 1 then
      raise exception 'expected 1 updated user_states row, got %', affected;
    end if;
  end
  $d$$t$,
  'A can update own user_states row (1 row affected)'
);
select is(
  (select display_name from public.profiles
   where user_id = 'f1000000-0000-4000-8000-000000000001'),
  'Alice Renamed',
  'A reads back the updated profile name'
);
select is(
  (select state ->> 'marker' from public.user_states
   where user_id = 'f1000000-0000-4000-8000-000000000001'),
  'v2',
  'A reads back the updated user_states payload'
);

select lives_ok(
  $$insert into public.garmin_plans (user_id, device_id, status, plan)
    values ('f1000000-0000-4000-8000-000000000001',
            'f3000000-0000-4000-8000-000000000001',
            'pending', current_setting('test.plan')::jsonb)$$,
  'A can insert a garmin_plans row through the four granted columns'
);
select is(
  (select pg_catalog.count(*) from public.garmin_plans
   where user_id = 'f1000000-0000-4000-8000-000000000001'),
  1::bigint,
  'A can select own garmin_plans row'
);
select throws_ok(
  $$insert into public.garmin_plans (user_id, device_id, status, plan, client_request_id)
    values ('f1000000-0000-4000-8000-000000000001',
            'f3000000-0000-4000-8000-000000000001',
            'pending', current_setting('test.plan')::jsonb,
            'f4000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'A cannot insert garmin_plans.client_request_id (column not granted)'
);
select throws_ok(
  $$insert into public.garmin_plans (user_id, device_id, status, plan, result)
    values ('f1000000-0000-4000-8000-000000000001',
            'f3000000-0000-4000-8000-000000000001',
            'pending', current_setting('test.plan')::jsonb, '{}'::jsonb)$$,
  '42501', null, 'A cannot insert garmin_plans.result (column not granted)'
);
select throws_ok(
  $$update public.garmin_plans set status = 'completed'
    where user_id = 'f1000000-0000-4000-8000-000000000001'$$,
  '42501', null, 'A cannot update garmin_plans (no UPDATE privilege)'
);
select throws_ok(
  $$delete from public.garmin_plans
    where user_id = 'f1000000-0000-4000-8000-000000000001'$$,
  '42501', null, 'A cannot delete garmin_plans (no DELETE privilege)'
);
select throws_ok(
  $$select id from public.garmin_devices$$,
  '42501', null, 'A cannot select garmin_devices directly (RPC only)'
);
select throws_ok(
  $$insert into public.garmin_devices (user_id, device_token)
    values ('f1000000-0000-4000-8000-000000000001', 'direct-token')$$,
  '42501', null, 'A cannot insert garmin_devices directly (RPC only)'
);

-- ---------------------------------------------------------------------------
-- User B: creates own rows, then probes A's data.
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = 'f1000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"f1000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"f2000000-0000-4000-8000-000000000002"}';

select lives_ok(
  $$insert into public.profiles (user_id, display_name)
    values ('f1000000-0000-4000-8000-000000000002', 'Bob Lifter')$$,
  'B can insert own profile'
);
select lives_ok(
  $$insert into public.user_states (user_id)
    values ('f1000000-0000-4000-8000-000000000002')$$,
  'B can insert own user_states row'
);
select is(
  (select pg_catalog.count(*) from public.profiles),
  1::bigint,
  'B sees only its own profile row'
);
select is(
  (select pg_catalog.count(*) from public.profiles
   where user_id = 'f1000000-0000-4000-8000-000000000001'),
  0::bigint,
  'B sees 0 of A profile rows'
);
select is(
  (select pg_catalog.count(*) from public.user_states),
  1::bigint,
  'B sees only its own user_states row'
);
select is(
  (select pg_catalog.count(*) from public.user_states
   where user_id = 'f1000000-0000-4000-8000-000000000001'),
  0::bigint,
  'B sees 0 of A user_states rows'
);
select lives_ok(
  $t$do $d$
  declare affected integer;
  begin
    update public.profiles set display_name = 'Hacked By Bob'
    where user_id = 'f1000000-0000-4000-8000-000000000001';
    get diagnostics affected = row_count;
    if affected <> 0 then
      raise exception 'expected 0 updated profile rows, got %', affected;
    end if;
  end
  $d$$t$,
  'B updating A profile affects 0 rows'
);
select lives_ok(
  $t$do $d$
  declare affected integer;
  begin
    update public.user_states set state = '{"marker":"hacked"}'::jsonb
    where user_id = 'f1000000-0000-4000-8000-000000000001';
    get diagnostics affected = row_count;
    if affected <> 0 then
      raise exception 'expected 0 updated user_states rows, got %', affected;
    end if;
  end
  $d$$t$,
  'B updating A user_states row affects 0 rows'
);
select throws_ok(
  $$insert into public.profiles (user_id, display_name)
    values ('f1000000-0000-4000-8000-000000000001', 'Bob As Alice')$$,
  '42501', null, 'B cannot insert a profile for A (RLS violation)'
);
select throws_ok(
  $$insert into public.user_states (user_id)
    values ('f1000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'B cannot insert a user_states row for A (RLS violation)'
);
select throws_ok(
  $$delete from public.profiles
    where user_id = 'f1000000-0000-4000-8000-000000000002'$$,
  '42501', null, 'B cannot delete even its own profile (no DELETE privilege)'
);
select throws_ok(
  $$delete from public.user_states
    where user_id = 'f1000000-0000-4000-8000-000000000002'$$,
  '42501', null, 'B cannot delete even its own user_states row (no DELETE privilege)'
);
select is(
  (select pg_catalog.count(*) from public.garmin_plans),
  0::bigint,
  'B sees 0 garmin_plans rows (A plan is hidden)'
);
select throws_ok(
  $$insert into public.garmin_plans (user_id, device_id, status, plan)
    values ('f1000000-0000-4000-8000-000000000001',
            'f3000000-0000-4000-8000-000000000001',
            'pending', current_setting('test.plan')::jsonb)$$,
  '42501', null, 'B cannot insert a garmin_plans row for A'
);
select throws_ok(
  $$insert into public.garmin_plans (user_id, device_id, status, plan)
    values ('f1000000-0000-4000-8000-000000000002',
            'f3000000-0000-4000-8000-000000000001',
            'pending', current_setting('test.plan')::jsonb)$$,
  '42501', null, 'B cannot attach its own garmin_plans row to A device'
);
select throws_ok(
  $$update public.garmin_plans set status = 'completed'
    where user_id = 'f1000000-0000-4000-8000-000000000001'$$,
  '42501', null, 'B cannot update garmin_plans (no UPDATE privilege)'
);
select throws_ok(
  $$select id from public.garmin_devices$$,
  '42501', null, 'B cannot select garmin_devices directly (RPC only)'
);
select throws_ok(
  $$insert into public.garmin_devices (user_id, device_token)
    values ('f1000000-0000-4000-8000-000000000002', 'direct-token')$$,
  '42501', null, 'B cannot insert garmin_devices directly (RPC only)'
);

-- Back to the table owner: A rows must be exactly as A left them, and B public
-- id is captured for the report and leaderboard checks.
reset role;

select is(
  (select display_name from public.profiles
   where user_id = 'f1000000-0000-4000-8000-000000000001'),
  'Alice Renamed',
  'A profile name is untouched by B writes'
);
select is(
  (select state ->> 'marker' from public.user_states
   where user_id = 'f1000000-0000-4000-8000-000000000001'),
  'v2',
  'A user_states payload is untouched by B writes'
);
select pg_catalog.set_config(
  'test.b_public_id',
  (select public_id from public.profiles
   where user_id = 'f1000000-0000-4000-8000-000000000002'),
  true
);
select pg_catalog.set_config(
  'test.a_public_id',
  (select public_id from public.profiles
   where user_id = 'f1000000-0000-4000-8000-000000000001'),
  true
);

-- ---------------------------------------------------------------------------
-- leaderboard_reports: insert-only through two granted columns, never readable.
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = 'f1000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"f2000000-0000-4000-8000-000000000001"}';

select lives_ok(
  $$insert into public.leaderboard_reports (reported_profile_id, reason)
    values (current_setting('test.b_public_id'), 'spam_or_scam')$$,
  'A can insert a leaderboard report through the granted columns'
);
select throws_ok(
  $$insert into public.leaderboard_reports (reported_profile_id, reason, reporter_user_id)
    values (current_setting('test.b_public_id'), 'other',
            'f1000000-0000-4000-8000-000000000002')$$,
  '42501', null, 'A cannot insert leaderboard_reports.reporter_user_id (column not granted)'
);
select throws_ok(
  $$insert into public.leaderboard_reports (reported_profile_id, reason, status)
    values (current_setting('test.b_public_id'), 'other', 'actioned')$$,
  '42501', null, 'A cannot insert leaderboard_reports.status (column not granted)'
);
select throws_ok(
  $$select id from public.leaderboard_reports$$,
  '42501', null, 'A cannot read leaderboard_reports (no SELECT privilege)'
);

-- ---------------------------------------------------------------------------
-- leaderboard_public view: caller sees only their own current row.
-- ---------------------------------------------------------------------------
select is(
  (select pg_catalog.count(*) from public.leaderboard_public),
  1::bigint,
  'A sees exactly one leaderboard_public row'
);
select is(
  (select profile_id from public.leaderboard_public),
  current_setting('test.a_public_id'),
  'A leaderboard_public row is A own profile'
);
select is(
  (select is_current_user from public.leaderboard_public),
  true,
  'A leaderboard_public row is flagged as the current user'
);
select is(
  (select pg_catalog.count(*) from public.leaderboard_public
   where profile_id = current_setting('test.b_public_id')),
  0::bigint,
  'A leaderboard_public does not expose B profile'
);

set local request.jwt.claim.sub = 'f1000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"f1000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"f2000000-0000-4000-8000-000000000002"}';

select throws_ok(
  $$select id from public.leaderboard_reports$$,
  '42501', null, 'B cannot read the report filed against B (no SELECT privilege)'
);
select is(
  (select pg_catalog.count(*) from public.leaderboard_public),
  1::bigint,
  'B sees exactly one leaderboard_public row'
);
select is(
  (select pg_catalog.count(*) from public.leaderboard_public
   where profile_id = current_setting('test.a_public_id')),
  0::bigint,
  'B leaderboard_public does not expose A profile'
);

-- Quarantined users are hidden even from themselves.
reset role;
insert into gymapp_private.user_state_quarantine (user_id, validation_error)
values ('f1000000-0000-4000-8000-000000000002', 'rls fixture quarantine');

select is(
  (select pg_catalog.count(*) from public.leaderboard_reports
   where reporter_user_id = 'f1000000-0000-4000-8000-000000000001'
     and reported_profile_id = current_setting('test.b_public_id')
     and status = 'pending'),
  1::bigint,
  'the stored report belongs to A, targets B, and is pending'
);

set local role authenticated;
set local request.jwt.claim.sub = 'f1000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"f1000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"f2000000-0000-4000-8000-000000000002"}';

select is(
  (select pg_catalog.count(*) from public.leaderboard_public),
  0::bigint,
  'a quarantined profile is hidden from leaderboard_public'
);

reset role;

select columns_are(
  'public', 'leaderboard_public',
  array['profile_id', 'display_name', 'xp', 'level', 'workouts', 'is_current_user'],
  'leaderboard_public exposes exactly the public columns'
);
select ok(
  (select reloptions @> array['security_invoker=true', 'security_barrier=true']
   from pg_catalog.pg_class
   where oid = 'public.leaderboard_public'::pg_catalog.regclass),
  'leaderboard_public is a security_invoker, security_barrier view'
);

-- ---------------------------------------------------------------------------
-- exercise_catalog (read-only) and leaderboard_blocked_terms (no access).
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = 'f1000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"f2000000-0000-4000-8000-000000000001"}';

select isnt_empty(
  $$select key from public.exercise_catalog$$,
  'authenticated can select exercise_catalog'
);
select throws_ok(
  $$insert into public.exercise_catalog (key, name_en, name_uk, muscle_ids, display_order)
    values ('rls_auth_probe', 'Probe', 'Probe', array[]::text[], 9999)$$,
  '42501', null, 'authenticated cannot insert exercise_catalog'
);
select throws_ok(
  $$update public.exercise_catalog set name_en = 'Hacked'$$,
  '42501', null, 'authenticated cannot update exercise_catalog'
);
select throws_ok(
  $$delete from public.exercise_catalog$$,
  '42501', null, 'authenticated cannot delete exercise_catalog'
);
select throws_ok(
  $$select term from public.leaderboard_blocked_terms$$,
  '42501', null, 'authenticated cannot select leaderboard_blocked_terms'
);

-- ---------------------------------------------------------------------------
-- Expired session: owner policies fail closed.
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = 'f1000000-0000-4000-8000-000000000003';
set local request.jwt.claims =
  '{"sub":"f1000000-0000-4000-8000-000000000003","role":"authenticated","session_id":"f2000000-0000-4000-8000-000000000003"}';

select is(
  (select pg_catalog.count(*) from public.profiles),
  0::bigint,
  'an expired session reads no profile rows'
);
select is(
  (select pg_catalog.count(*) from public.user_states),
  0::bigint,
  'an expired session reads no user_states rows'
);
select throws_ok(
  $$insert into public.profiles (user_id, display_name)
    values ('f1000000-0000-4000-8000-000000000003', 'Cara Again')$$,
  '42501', null, 'an expired session cannot insert a profile'
);
select is(
  (select pg_catalog.count(*) from public.leaderboard_public),
  0::bigint,
  'an expired session reads no leaderboard_public rows'
);

select * from finish();
rollback;
