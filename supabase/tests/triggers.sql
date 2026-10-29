begin;

select plan(55);

-- Fixture: X, Y and Z hold live Auth sessions. The profiles, devices, plans and
-- rooms are created below, mostly as the table owner with cleared claims so the
-- "no caller" server paths run, and then exercised as the authenticated client.
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
)
select
  '00000000-0000-0000-0000-000000000000',
  ('c8000000-0000-4000-8000-00000000000' || n)::uuid,
  'authenticated', 'authenticated',
  'trigger-' || n || '@example.invalid', '',
  pg_catalog.clock_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
  pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
from pg_catalog.generate_series(1, 3) as n;

insert into auth.sessions (id, user_id, not_after, created_at, updated_at)
select
  ('c8100000-0000-4000-8000-00000000000' || n)::uuid,
  ('c8000000-0000-4000-8000-00000000000' || n)::uuid,
  pg_catalog.clock_timestamp() + interval '1 day',
  pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
from pg_catalog.generate_series(1, 3) as n;

-- Switches the request identity. A NULL user clears it (internal/server path).
create function pg_temp.act_as(p_user uuid, p_session uuid)
returns void
language sql
as $$
  select pg_catalog.set_config(
    'request.jwt.claim.sub', coalesce(p_user::text, ''), true
  ), pg_catalog.set_config(
    'request.jwt.claims',
    case when p_user is null then ''
    else pg_catalog.jsonb_build_object(
      'sub', p_user, 'role', 'authenticated', 'session_id', p_session
    )::text end,
    true
  )
$$;
grant execute on function pg_temp.act_as(uuid, uuid) to authenticated, anon;

create temporary table state_revisions (
  step integer primary key,
  updated_at timestamptz not null
) on commit drop;
grant all on state_revisions to authenticated;

-- ---------------------------------------------------------------------------
-- Inventory: every non-internal trigger on a public table plus auth.users.
-- A new trigger must come with a behavioural test in this file.
-- ---------------------------------------------------------------------------
select is(
  (select array_agg(
            namespace.nspname || '.' || class.relname || '.' || trigger.tgname
            order by namespace.nspname, class.relname, trigger.tgname)
   from pg_catalog.pg_trigger as trigger
   join pg_catalog.pg_class as class on class.oid = trigger.tgrelid
   join pg_catalog.pg_namespace as namespace on namespace.oid = class.relnamespace
   where not trigger.tgisinternal
     and (namespace.nspname = 'public'
          or (namespace.nspname = 'auth' and class.relname = 'users'))),
  array[
    'auth.users.auth_users_close_live_workouts',
    'public.garmin_devices.garmin_devices_handle_revocation',
    'public.garmin_plans.garmin_plans_security_guard',
    'public.leaderboard_reports.leaderboard_reports_prepare_insert',
    'public.profiles.profiles_canonical_progression_guard',
    'public.profiles.profiles_public_fields_guard',
    'public.user_states.user_states_projection_revision_only',
    'public.user_states.user_states_refresh_profile_progression',
    'public.user_states.user_states_refresh_social_activity',
    'public.user_states.user_states_server_revision',
    'public.user_states.user_states_social_activity_revision_only',
    'public.user_states.user_states_validate_load_profiles',
    'public.user_states.user_states_validate_storage_budget'
  ],
  'the reviewed trigger set on public tables and auth.users is exactly this one'
);
select is(
  (select pg_catalog.count(*)
   from pg_catalog.pg_trigger as trigger
   join pg_catalog.pg_class as class on class.oid = trigger.tgrelid
   join pg_catalog.pg_namespace as namespace on namespace.oid = class.relnamespace
   where not trigger.tgisinternal
     and (namespace.nspname = 'public'
          or (namespace.nspname = 'auth' and class.relname = 'users'))
     and trigger.tgenabled <> 'O'),
  0::bigint,
  'every reviewed trigger is enabled for ordinary sessions'
);

-- ===========================================================================
-- profiles: enforce_profile_public_fields + guard_profile_progression
-- ===========================================================================
set local role authenticated;
select pg_temp.act_as(
  'c8000000-0000-4000-8000-000000000002',
  'c8100000-0000-4000-8000-000000000002'
);

-- The client tries to choose its public id, progression and revision stamps.
insert into public.profiles (
  user_id, display_name, public_id, xp, level, workouts,
  progression_version, updated_at
) values (
  'c8000000-0000-4000-8000-000000000002',
  'Trigger Y', 'p_forged', 99999, 50, 900, 7, '2000-01-01'
);

select ok(
  (select profile.public_id ~ '^p_[0-9a-f]{32}$'
     and profile.public_id <> 'p_forged'
   from public.profiles as profile
   where profile.user_id = 'c8000000-0000-4000-8000-000000000002'),
  'insert replaces a client-chosen public_id with a server-generated one'
);
select is(
  (select row(profile.xp, profile.level, profile.workouts,
                         profile.progression_version)::text
   from public.profiles as profile
   where profile.user_id = 'c8000000-0000-4000-8000-000000000002'),
  '(0,1,0,1)',
  'insert ignores forged xp, level, workouts and progression_version'
);
select ok(
  (select profile.updated_at > pg_catalog.clock_timestamp() - interval '1 minute'
   from public.profiles as profile
   where profile.user_id = 'c8000000-0000-4000-8000-000000000002'),
  'insert replaces a forged profile updated_at with the server time'
);

update public.profiles
set xp = 5, level = 9, workouts = 77, progression_version = 3;
select is(
  (select row(profile.xp, profile.level, profile.workouts,
                         profile.progression_version)::text
   from public.profiles as profile
   where profile.user_id = 'c8000000-0000-4000-8000-000000000002'),
  '(0,1,0,1)',
  'update cannot write xp, level, workouts or progression_version'
);
select throws_ok(
  $$update public.profiles set public_id = 'p_00000000000000000000000000000000'$$,
  '23514',
  'Profile public_id is immutable.',
  'update cannot change the public_id'
);
select throws_ok(
  $$update public.profiles set display_name = 'mail me@example.com'$$,
  '23514',
  'Display name violates the leaderboard safety policy.',
  'update rejects a display name carrying contact data'
);
update public.profiles set display_name = '  New   Name ';
select is(
  (select profile.display_name
   from public.profiles as profile
   where profile.user_id = 'c8000000-0000-4000-8000-000000000002'),
  'New Name',
  'an allowed display name update is stored in normalized form'
);
select throws_ok(
  $$update public.profiles
    set user_id = 'c8000000-0000-4000-8000-000000000001'$$,
  '42501',
  'A profile can only derive progression for its owner.',
  'update cannot move the profile to another owner'
);
select throws_ok(
  $$insert into public.profiles (user_id, display_name)
    values ('c8000000-0000-4000-8000-000000000001', 'Not Mine')$$,
  '42501',
  'A profile can only derive progression for its owner.',
  'insert cannot create a profile for another account'
);

-- ===========================================================================
-- user_states: set_user_state_server_revision, validators, projections
-- ===========================================================================
insert into public.user_states (user_id, state, updated_at)
values (
  'c8000000-0000-4000-8000-000000000002', '{}'::jsonb, '2000-01-01'
);
insert into state_revisions
select 1, state_row.updated_at
from public.user_states as state_row
where state_row.user_id = 'c8000000-0000-4000-8000-000000000002';
select ok(
  (select revision.updated_at > pg_catalog.clock_timestamp() - interval '1 minute'
   from state_revisions as revision where revision.step = 1),
  'insert replaces a forged past revision with the server time'
);

with changed as (
  update public.user_states
  set updated_at = '2100-01-01', state = '{"note":"one"}'::jsonb
  returning updated_at
)
insert into state_revisions select 2, changed.updated_at from changed;
select ok(
  (select revision.updated_at < pg_catalog.clock_timestamp() + interval '1 minute'
     and revision.updated_at > (select first_revision.updated_at
                                from state_revisions as first_revision
                                where first_revision.step = 1)
   from state_revisions as revision where revision.step = 2),
  'update cannot forge a future revision and still advances it'
);

with changed as (
  update public.user_states
  set updated_at = '1999-01-01', state = '{"note":"two"}'::jsonb
  returning updated_at
)
insert into state_revisions select 3, changed.updated_at from changed;
select ok(
  (select revision.updated_at > (select previous.updated_at
                                 from state_revisions as previous
                                 where previous.step = 2)
   from state_revisions as revision where revision.step = 3),
  'update cannot rewind the revision to a past value'
);

with changed as (
  update public.user_states
  set state = state
  returning updated_at
)
insert into state_revisions select 4, changed.updated_at from changed;
select ok(
  (select revision.updated_at > (select previous.updated_at
                                 from state_revisions as previous
                                 where previous.step = 3)
   from state_revisions as revision where revision.step = 4),
  'a no-op update still strictly advances the revision'
);
select ok(
  (select pg_catalog.bool_and(revision.updated_at > revision.previous_at)
   from (
     select current_row.updated_at,
            pg_catalog.lag(current_row.updated_at)
              over (order by current_row.step) as previous_at
     from state_revisions as current_row
   ) as revision
   where revision.previous_at is not null),
  'the server revision is strictly increasing across every write'
);

select throws_ok(
  $$update public.user_states
    set user_id = 'c8000000-0000-4000-8000-000000000001'$$,
  '22023',
  'GymApp cloud state owner is immutable.',
  'a cloud state cannot be reassigned to another account'
);
select throws_ok(
  $$update public.user_states
    set state = '{"owner":{"userId":"c8000000-0000-4000-8000-000000000001"}}'::jsonb$$,
  '42501',
  'GymApp cloud state owner does not match its authenticated row.',
  'a state naming another owner is rejected'
);
select throws_ok(
  $$update public.user_states
    set state = '{"exercises":[{"name":"x","loadProfile":{"direction":"sideways","allowedWeightsKg":[1]}}]}'::jsonb$$,
  '22023',
  'GymApp exercise load profile is invalid.',
  'a malformed exercise load profile is rejected'
);
select throws_ok(
  $$update public.user_states
    set state = pg_catalog.jsonb_build_object(
      'note', pg_catalog.repeat('9', 1030)::numeric
    )$$,
  '54000',
  'GymApp cloud state contains an oversized JSON number.',
  'the storage budget rejects an oversized JSON number'
);
select is(
  (select state_row.state
   from public.user_states as state_row
   where state_row.user_id = 'c8000000-0000-4000-8000-000000000002'),
  '{"note":"two"}'::jsonb,
  'rejected state writes leave the stored state unchanged'
);

-- A real workout drives the canonical progression and the social projection.
update public.user_states
set state = '{"sessions":[{"date":1767261600000,"exercises":[{"name":"Squat","sets":[{"weight":100,"reps":5}]}]}]}'::jsonb;
select is(
  (select row(profile.xp, profile.level, profile.workouts)::text
   from public.profiles as profile
   where profile.user_id = 'c8000000-0000-4000-8000-000000000002'),
  '(120,1,1)',
  'saving a workout derives the profile progression from the stored state'
);
update public.profiles set xp = 99999, level = 50, workouts = 900;
select is(
  (select row(profile.xp, profile.level, profile.workouts)::text
   from public.profiles as profile
   where profile.user_id = 'c8000000-0000-4000-8000-000000000002'),
  '(120,1,1)',
  'a client update cannot overwrite the derived progression'
);

-- A state write that leaves the state unchanged only moves the revision stamp.
update public.user_states set state = state;

reset role;
select pg_temp.act_as(null, null);

select is(
  (select row(projection.xp, projection.level, projection.workouts)::text
   from gymapp_private.user_state_progression as projection
   where projection.user_id = 'c8000000-0000-4000-8000-000000000002'),
  '(120,1,1)',
  'the private progression cache matches the derived values'
);
select is(
  (select pg_catalog.count(*)
   from public.user_states as state_row
   join gymapp_private.user_state_progression as projection
     on projection.user_id = state_row.user_id
    and projection.source_revision = state_row.updated_at
   join gymapp_private.social_activity_projection as social
     on social.user_id = state_row.user_id
    and social.source_revision = state_row.updated_at
   where state_row.user_id = 'c8000000-0000-4000-8000-000000000002'),
  1::bigint,
  'a revision-only write advances both projection source revisions in step'
);
select is(
  (select pg_catalog.jsonb_array_length(social.recent_workouts)::text || ':' ||
          (social.exercise_records -> 0 ->> 'name')
   from gymapp_private.social_activity_projection as social
   where social.user_id = 'c8000000-0000-4000-8000-000000000002'),
  '1:Squat',
  'the social activity projection is derived from the stored workout'
);

delete from public.user_states
where user_id = 'c8000000-0000-4000-8000-000000000002';
select is(
  (select row(profile.xp, profile.level, profile.workouts)::text
   from public.profiles as profile
   where profile.user_id = 'c8000000-0000-4000-8000-000000000002'),
  '(0,1,0)',
  'deleting the cloud state resets the profile progression'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.user_state_progression
   where user_id = 'c8000000-0000-4000-8000-000000000002')
  + (select pg_catalog.count(*)
     from gymapp_private.social_activity_projection
     where user_id = 'c8000000-0000-4000-8000-000000000002'),
  0::bigint,
  'deleting the cloud state removes both private projections'
);

-- ===========================================================================
-- leaderboard_reports: prepare_leaderboard_report
-- ===========================================================================
insert into public.profiles (user_id, display_name) values
  ('c8000000-0000-4000-8000-000000000001', 'Reporter X'),
  ('c8000000-0000-4000-8000-000000000003', 'Target Z');

-- Clients can read only their own profile, so the reporter learns the target
-- public id out of band (the leaderboard); model that with a helper table.
create temporary table report_target (public_id text primary key)
  on commit drop;
grant select on report_target to authenticated;
insert into report_target
select profile.public_id
from public.profiles as profile
where profile.user_id = 'c8000000-0000-4000-8000-000000000003';

set local role authenticated;
select pg_temp.act_as(
  'c8000000-0000-4000-8000-000000000001',
  'c8100000-0000-4000-8000-000000000001'
);
insert into public.leaderboard_reports (reported_profile_id, reason)
select target.public_id, 'impersonation' from report_target as target;

select throws_ok(
  $$insert into public.leaderboard_reports (
      reporter_user_id, reported_profile_id, reason
    ) values (
      'c8000000-0000-4000-8000-000000000002', 'p_x', 'other'
    )$$,
  '42501',
  null,
  'clients have no INSERT privilege on reporter_user_id'
);
select throws_ok(
  $$insert into public.leaderboard_reports (
      reported_profile_id, reason, status
    ) values ('p_x', 'other', 'actioned')$$,
  '42501',
  null,
  'clients have no INSERT privilege on status'
);
select throws_ok(
  $$insert into public.leaderboard_reports (reported_profile_id, reason)
    select target.public_id, 'impersonation' from report_target as target$$,
  '23505',
  'Duplicate pending leaderboard report.',
  'a duplicate pending report for the same reason is rejected'
);
select throws_ok(
  $$insert into public.leaderboard_reports (reported_profile_id, reason)
    select target.public_id, 'rude' from report_target as target$$,
  '23514',
  'Leaderboard report reason is invalid.',
  'an unknown report reason is rejected'
);
select throws_ok(
  $$insert into public.leaderboard_reports (reported_profile_id, reason)
    values ('p_00000000000000000000000000000000', 'other')$$,
  '23503',
  'The reported leaderboard profile does not exist.',
  'a report against an unknown profile is rejected'
);
select throws_ok(
  $$insert into public.leaderboard_reports (reported_profile_id, reason)
    select profile.public_id, 'other'
    from public.profiles as profile
    where profile.user_id = 'c8000000-0000-4000-8000-000000000001'$$,
  '23514',
  'A profile cannot report itself.',
  'a self-report is rejected'
);

-- Column privileges are not the only barrier: with them bypassed (table owner)
-- the trigger itself still forces every server-owned column.
reset role;
select pg_temp.act_as(
  'c8000000-0000-4000-8000-000000000001',
  'c8100000-0000-4000-8000-000000000001'
);
insert into public.leaderboard_reports (
  id, reporter_user_id, reported_profile_id, reported_display_name,
  reason, status, created_at
)
select
  'r_ffffffffffffffffffffffffffffffff',
  'c8000000-0000-4000-8000-000000000002',
  profile.public_id,
  'Forged name',
  'spam_or_scam',
  'actioned',
  '2000-01-01'
from public.profiles as profile
where profile.user_id = 'c8000000-0000-4000-8000-000000000003';

select is(
  (select row(
            report.reporter_user_id, report.status,
            report.reported_display_name)::text
   from public.leaderboard_reports as report
   where report.reason = 'spam_or_scam'
     and report.reporter_user_id in (
       'c8000000-0000-4000-8000-000000000001',
       'c8000000-0000-4000-8000-000000000002'
     )),
  '(c8000000-0000-4000-8000-000000000001,pending,"Target Z")',
  'the trigger forces reporter, pending status and the stored target name'
);
select ok(
  (select report.id ~ '^r_[0-9a-f]{32}$'
     and report.id <> 'r_ffffffffffffffffffffffffffffffff'
     and report.created_at > pg_catalog.clock_timestamp() - interval '1 minute'
   from public.leaderboard_reports as report
   where report.reason = 'spam_or_scam'
     and report.reporter_user_id = 'c8000000-0000-4000-8000-000000000001'),
  'the trigger replaces a forged id and created_at'
);
select is(
  (select pg_catalog.count(*)
   from public.leaderboard_reports as report
   where report.reporter_user_id = 'c8000000-0000-4000-8000-000000000002'),
  0::bigint,
  'no report is attributed to the forged reporter'
);
select pg_temp.act_as(null, null);
select throws_ok(
  $$insert into public.leaderboard_reports (reported_profile_id, reason)
    select profile.public_id, 'other'
    from public.profiles as profile
    where profile.user_id = 'c8000000-0000-4000-8000-000000000003'$$,
  '42501',
  'Authentication is required to report a leaderboard profile.',
  'a report without an authenticated caller is rejected'
);

-- ===========================================================================
-- garmin_devices revocation + garmin_plans guard
-- ===========================================================================
insert into public.garmin_devices (
  id, user_id, device_token, display_name, binding_version, token_revision
) values
  ('c8200000-0000-4000-8000-000000000001',
   'c8000000-0000-4000-8000-000000000001',
   pg_catalog.repeat('a', 64), 'Watch X1', 2, 1),
  ('c8200000-0000-4000-8000-000000000002',
   'c8000000-0000-4000-8000-000000000001',
   pg_catalog.repeat('b', 64), 'Watch X2', 2, 1),
  ('c8200000-0000-4000-8000-000000000003',
   'c8000000-0000-4000-8000-000000000002',
   pg_catalog.repeat('c', 64), 'Watch Y1', 2, 1);

-- Distinct payloads give each plan its own derived request key.
insert into public.garmin_plans (user_id, device_id, plan)
select
  device.user_id,
  device.id,
  pg_catalog.jsonb_build_object(
    'source', 'test', 'version', 1, 'title', 'Plan ' || label.name,
    'note', '', 'createdAt', '2026-01-01T00:00:00Z',
    'startedAt', '2026-01-01T00:00:00Z',
    'exercises', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'name', 'Squat',
      'sets', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'weight', 100, 'reps', 5))))
  )
from (values
  ('x1-a', 'c8200000-0000-4000-8000-000000000001'::uuid),
  ('x1-b', 'c8200000-0000-4000-8000-000000000001'::uuid),
  ('x1-c', 'c8200000-0000-4000-8000-000000000001'::uuid),
  ('x2-a', 'c8200000-0000-4000-8000-000000000002'::uuid),
  ('y1-a', 'c8200000-0000-4000-8000-000000000003'::uuid)
) as label(name, device_id)
join public.garmin_devices as device on device.id = label.device_id;

-- One X1 plan was already delivered to the watch before the revocation.
update public.garmin_plans
set status = 'downloaded', downloaded_at = pg_catalog.clock_timestamp()
where plan ->> 'title' = 'Plan x1-c';

insert into gymapp_private.garmin_device_rate_limits (
  device_id, bucket_action, tokens, refilled_at
) values
  ('c8200000-0000-4000-8000-000000000001', 'fetch_plan', 1,
   pg_catalog.clock_timestamp()),
  ('c8200000-0000-4000-8000-000000000002', 'fetch_plan', 1,
   pg_catalog.clock_timestamp());

select is(
  (select pg_catalog.count(*)
   from public.garmin_plans as plan
   where plan.user_id in (
       'c8000000-0000-4000-8000-000000000001',
       'c8000000-0000-4000-8000-000000000002'
     ) and plan.status = 'pending'
     and plan.plan_revision >= 1 and plan.client_request_id is not null),
  4::bigint,
  'plan insert stores pending plans with a server revision and request key'
);

-- X revokes the first watch through the public RPC as the authenticated owner.
set local role authenticated;
select pg_temp.act_as(
  'c8000000-0000-4000-8000-000000000001',
  'c8100000-0000-4000-8000-000000000001'
);
select is(
  public.garmin_revoke_device('c8200000-0000-4000-8000-000000000001') ->> 'status',
  'revoked',
  'the owner can revoke their own watch'
);
reset role;
select pg_temp.act_as(null, null);

select is(
  (select pg_catalog.count(*)
   from public.garmin_plans as plan
   where plan.device_id = 'c8200000-0000-4000-8000-000000000001'
     and plan.status = 'invalid'
     and plan.validation_error =
       'Garmin device was revoked before this plan was delivered.'),
  2::bigint,
  'revocation retires every pending plan of that watch with the reviewed message'
);
select is(
  (select plan.status
   from public.garmin_plans as plan
   where plan.plan ->> 'title' = 'Plan x1-c'),
  'downloaded',
  'revocation leaves an already delivered plan alone'
);
select is(
  (select pg_catalog.string_agg(plan.status, ',' order by plan.plan ->> 'title')
   from public.garmin_plans as plan
   where plan.plan ->> 'title' in ('Plan x2-a', 'Plan y1-a')),
  'pending,pending',
  'revocation leaves other watches and other accounts pending'
);
select is(
  (select pg_catalog.string_agg(
            limits.device_id::text, ',' order by limits.device_id)
   from gymapp_private.garmin_device_rate_limits as limits
   where limits.device_id in (
     'c8200000-0000-4000-8000-000000000001',
     'c8200000-0000-4000-8000-000000000002')),
  'c8200000-0000-4000-8000-000000000002',
  'revocation clears only that watch''s rate-limit buckets'
);

-- guard_garmin_plan, with the request identity of the owner.
select pg_temp.act_as(
  'c8000000-0000-4000-8000-000000000001',
  'c8100000-0000-4000-8000-000000000001'
);
select throws_ok(
  $$update public.garmin_plans set status = 'completed'
    where plan ->> 'title' = 'Plan x2-a'$$,
  '42501',
  'Garmin delivery state is server-controlled.',
  'a client-identity update cannot move delivery state'
);
select throws_ok(
  $$update public.garmin_plans
    set plan = pg_catalog.jsonb_set(plan, '{title}', '"Edited"')
    where plan ->> 'title' = 'Plan x2-a'$$,
  '22023',
  'Garmin plan identity and payload are immutable.',
  'a stored plan payload is immutable'
);
select throws_ok(
  $$insert into public.garmin_plans (user_id, device_id, plan)
    values (
      'c8000000-0000-4000-8000-000000000002',
      'c8200000-0000-4000-8000-000000000003',
      '{}'::jsonb
    )$$,
  '42501',
  'A Garmin plan can only belong to its authenticated owner.',
  'a plan cannot be inserted for another account'
);
select throws_ok(
  $$insert into public.garmin_plans (user_id, device_id, plan)
    values (
      'c8000000-0000-4000-8000-000000000001',
      'c8200000-0000-4000-8000-000000000002',
      '{}'::jsonb
    )$$,
  '22023',
  'Plan source is invalid.',
  'an invalid plan payload is rejected with its validation message'
);
select throws_ok(
  $$insert into public.garmin_plans (user_id, device_id, plan)
    select device.user_id, device.id, '{"source":"test"}'::jsonb
    from public.garmin_devices as device
    where device.id = 'c8200000-0000-4000-8000-000000000001'$$,
  '22023',
  null,
  'a plan payload is validated before the revoked-device binding check'
);
select throws_ok(
  $$insert into public.garmin_plans (user_id, device_id, plan)
    values (
      'c8000000-0000-4000-8000-000000000001',
      'c8200000-0000-4000-8000-000000000001',
      '{"source":"test","version":1,"title":"Late","note":"","createdAt":"2026-01-01T00:00:00Z","startedAt":"2026-01-01T00:00:00Z","exercises":[{"name":"Squat","sets":[{"weight":100,"reps":5}]}]}'::jsonb
    )$$,
  '42501',
  'Garmin plan device binding is invalid.',
  'a new plan cannot target a revoked watch'
);

-- A client insert cannot choose delivery state or revision.
set local role authenticated;
insert into public.garmin_plans (user_id, device_id, plan, status)
values (
  'c8000000-0000-4000-8000-000000000001',
  'c8200000-0000-4000-8000-000000000002',
  '{"source":"test","version":1,"title":"Forged status","note":"","createdAt":"2026-01-01T00:00:00Z","startedAt":"2026-01-01T00:00:00Z","exercises":[{"name":"Squat","sets":[{"weight":100,"reps":5}]}]}'::jsonb,
  'completed'
);
reset role;
select pg_temp.act_as(null, null);
select is(
  (select row(
            plan.status, plan.downloaded_at is null, plan.completed_at is null,
            plan.validation_error is null,
            plan.plan_revision = 1 + (
              select pg_catalog.max(other.plan_revision)
              from public.garmin_plans as other
              where other.user_id = plan.user_id
                and other.id <> plan.id))::text
   from public.garmin_plans as plan
   where plan.plan ->> 'title' = 'Forged status'),
  '(pending,t,t,t,t)',
  'a forged completed status is reset to pending with the next revision'
);

-- ===========================================================================
-- auth.users: auth_user_close_live_workouts
-- ===========================================================================
insert into gymapp_private.live_workout_rooms (
  id, owner_user_id, client_request_id, status, plan, summary, revision,
  created_at, invite_expires_at, last_activity_at, updated_at
) values
  (
    'lr_c8000000000040008000000000000001',
    'c8000000-0000-4000-8000-000000000002',
    'c8300000-0000-4000-8000-000000000001',
    'waiting', '{"version":1,"exercises":[]}'::jsonb, '{}'::jsonb, 1,
    '2026-10-29 10:00:00+00', '2026-11-05 10:00:00+00',
    '2026-10-29 10:00:00+00', '2026-10-29 10:00:00+00'
  ),
  (
    'lr_c8000000000040008000000000000002',
    'c8000000-0000-4000-8000-000000000003',
    'c8300000-0000-4000-8000-000000000002',
    'waiting', '{"version":1,"exercises":[]}'::jsonb, '{}'::jsonb, 1,
    '2026-10-29 10:00:00+00', '2026-11-05 10:00:00+00',
    '2026-10-29 10:00:00+00', '2026-10-29 10:00:00+00'
  );
insert into gymapp_private.live_workout_members (
  room_id, user_id, role, state, invited_at, joined_at
) values
  ('lr_c8000000000040008000000000000001',
   'c8000000-0000-4000-8000-000000000002', 'owner', 'joined',
   '2026-10-29 10:00:00+00', '2026-10-29 10:01:00+00'),
  ('lr_c8000000000040008000000000000001',
   'c8000000-0000-4000-8000-000000000001', 'participant', 'invited',
   '2026-10-29 10:00:00+00', null),
  ('lr_c8000000000040008000000000000002',
   'c8000000-0000-4000-8000-000000000003', 'owner', 'joined',
   '2026-10-29 10:00:00+00', '2026-10-29 10:01:00+00'),
  ('lr_c8000000000040008000000000000002',
   'c8000000-0000-4000-8000-000000000002', 'participant', 'invited',
   '2026-10-29 10:00:00+00', null);

delete from auth.users where id = 'c8000000-0000-4000-8000-000000000001';

select is(
  (select row(room.status, room.close_reason,
                         room.ended_at is not null)::text
   from gymapp_private.live_workout_rooms as room
   where room.id = 'lr_c8000000000040008000000000000001'),
  '(cancelled,account_deleted,t)',
  'deleting an account cancels its live workout room as account_deleted'
);
select is(
  (select member.state
   from gymapp_private.live_workout_members as member
   where member.room_id = 'lr_c8000000000040008000000000000001'
     and member.user_id = 'c8000000-0000-4000-8000-000000000002'),
  'revoked',
  'the remaining partner is released from the cancelled room'
);
select is(
  (select row(room.status, room.close_reason)::text
   from gymapp_private.live_workout_rooms as room
   where room.id = 'lr_c8000000000040008000000000000002'),
  '(waiting,)',
  'a room of an unrelated pair is not affected'
);
select is(
  (select pg_catalog.count(*)
   from auth.users
   where id in ('c8000000-0000-4000-8000-000000000002',
                'c8000000-0000-4000-8000-000000000003')),
  2::bigint,
  'only the deleted account disappears'
);

select * from finish();

rollback;
