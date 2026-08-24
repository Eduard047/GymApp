begin;

select plan(56);

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
    'e5000000-0000-4000-8000-000000000001',
    'authenticated', 'authenticated', 'leaderboard-live-a@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'e5000000-0000-4000-8000-000000000002',
    'authenticated', 'authenticated', 'leaderboard-live-b@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'e5000000-0000-4000-8000-000000000003',
    'authenticated', 'authenticated', 'leaderboard-expired@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

insert into auth.sessions (id, user_id, not_after, created_at, updated_at) values
  (
    'e6000000-0000-4000-8000-000000000001',
    'e5000000-0000-4000-8000-000000000001',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'e6000000-0000-4000-8000-000000000002',
    'e5000000-0000-4000-8000-000000000002',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'e6000000-0000-4000-8000-000000000003',
    'e5000000-0000-4000-8000-000000000003',
    pg_catalog.clock_timestamp() - interval '1 second',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

insert into public.profiles (
  user_id, public_id, display_name, xp, level, workouts,
  progression_version, updated_at
) values
  (
    'e5000000-0000-4000-8000-000000000001',
    'p_50000000000000000000000000000001',
    'Live owner A', 120, 2, 3, 1, pg_catalog.clock_timestamp()
  ),
  (
    'e5000000-0000-4000-8000-000000000002',
    'p_50000000000000000000000000000002',
    'Live owner B', 220, 3, 4, 1, pg_catalog.clock_timestamp()
  ),
  (
    'e5000000-0000-4000-8000-000000000003',
    'p_50000000000000000000000000000003',
    'Expired owner', 320, 4, 5, 1, pg_catalog.clock_timestamp()
  );

select ok(
  (select class_row.relrowsecurity
   from pg_catalog.pg_class as class_row
   where class_row.oid =
     'gymapp_private.user_state_quarantine'::pg_catalog.regclass),
  'quarantine has RLS enabled'
);
select ok(
  (select class_row.relforcerowsecurity
   from pg_catalog.pg_class as class_row
   where class_row.oid =
     'gymapp_private.user_state_quarantine'::pg_catalog.regclass),
  'quarantine forces RLS for non-bypass owners'
);
select is(
  (select pg_catalog.count(*)
   from pg_catalog.pg_policy as policy_row
   where policy_row.polrelid =
     'gymapp_private.user_state_quarantine'::pg_catalog.regclass),
  0::bigint,
  'quarantine has no client policy'
);
select ok(
  not has_table_privilege(
    'anon', 'gymapp_private.user_state_quarantine',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
  ),
  'anon has no quarantine privilege'
);
select ok(
  not has_table_privilege(
    'authenticated', 'gymapp_private.user_state_quarantine',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
  ),
  'authenticated has no quarantine privilege'
);
select ok(
  not has_table_privilege(
    'service_role', 'gymapp_private.user_state_quarantine',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
  ),
  'service_role has no quarantine privilege'
);

select ok(
  (select class_row.relrowsecurity
   from pg_catalog.pg_class as class_row
   where class_row.oid =
     'gymapp_private.user_state_progression'::pg_catalog.regclass),
  'progression cache has RLS enabled'
);
select ok(
  (select class_row.relforcerowsecurity
   from pg_catalog.pg_class as class_row
   where class_row.oid =
     'gymapp_private.user_state_progression'::pg_catalog.regclass),
  'progression cache forces RLS for non-bypass owners'
);
select is(
  (select pg_catalog.count(*)
   from pg_catalog.pg_policy as policy_row
   where policy_row.polrelid =
     'gymapp_private.user_state_progression'::pg_catalog.regclass),
  0::bigint,
  'progression cache has no client policy'
);
select ok(
  not has_table_privilege(
    'anon', 'gymapp_private.user_state_progression',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
  ),
  'anon has no progression-cache privilege'
);
select ok(
  not has_table_privilege(
    'authenticated', 'gymapp_private.user_state_progression',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
  ),
  'authenticated has no progression-cache privilege'
);
select ok(
  not has_table_privilege(
    'service_role', 'gymapp_private.user_state_progression',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
  ),
  'service_role has no progression-cache privilege'
);

select ok(
  pg_catalog.to_regprocedure('public.leaderboard_public_rows()') is not null,
  'leaderboard compatibility function exists'
);
select ok(
  (select procedure_row.prosecdef
   from pg_catalog.pg_proc as procedure_row
   where procedure_row.oid =
     'public.leaderboard_public_rows()'::pg_catalog.regprocedure),
  'leaderboard compatibility function is SECURITY DEFINER'
);
select is(
  (select procedure_row.provolatile::text
   from pg_catalog.pg_proc as procedure_row
   where procedure_row.oid =
     'public.leaderboard_public_rows()'::pg_catalog.regprocedure),
  'v'::text,
  'leaderboard compatibility function is VOLATILE for the session lock'
);
select ok(
  (select 'search_path=""' = any(procedure_row.proconfig)
   from pg_catalog.pg_proc as procedure_row
   where procedure_row.oid =
     'public.leaderboard_public_rows()'::pg_catalog.regprocedure),
  'leaderboard compatibility function has an empty search_path'
);
select ok(
  (select pg_catalog.pg_get_functiondef(procedure_row.oid)
            like '%gymapp_private.current_auth_session_is_live()%'
   from pg_catalog.pg_proc as procedure_row
   where procedure_row.oid =
     'public.leaderboard_public_rows()'::pg_catalog.regprocedure),
  'leaderboard compatibility function checks the exact live Auth session'
);
select ok(
  not has_function_privilege(
    'anon', 'public.leaderboard_public_rows()', 'EXECUTE'
  ),
  'anon cannot execute the leaderboard compatibility function'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.leaderboard_public_rows()', 'EXECUTE'
  ),
  'authenticated retains the compatibility RPC grant'
);
select ok(
  has_function_privilege(
    'service_role', 'public.leaderboard_public_rows()', 'EXECUTE'
  ),
  'service_role retains the compatibility RPC grant'
);
select ok(
  not has_table_privilege('anon', 'public.leaderboard_public', 'SELECT'),
  'anon cannot select the leaderboard compatibility view'
);
select ok(
  has_table_privilege('authenticated', 'public.leaderboard_public', 'SELECT'),
  'authenticated retains the compatibility view grant'
);

set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{}';
select is(
  (select pg_catalog.count(*) from public.leaderboard_public_rows()),
  0::bigint,
  'missing JWT claims fail closed without exposing a row'
);

set local request.jwt.claim.sub = 'e5000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{"sub":"e5000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e6000000-0000-4000-8000-000000000001"}';
select is(
  (select pg_catalog.count(*) from public.leaderboard_public_rows()),
  1::bigint,
  'the exact live session receives one owner row'
);
select is(
  (select profile_id from public.leaderboard_public_rows()),
  (select profile.public_id::text
   from public.profiles as profile
   where profile.user_id = 'e5000000-0000-4000-8000-000000000001'),
  'the exact live session cannot receive another owner profile'
);
select ok(
  (select is_current_user from public.leaderboard_public_rows()),
  'the compatibility response keeps its current-user field'
);

set local request.jwt.claims =
  '{"sub":"e5000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e6000000-0000-4000-8000-000000000002"}';
select is(
  (select pg_catalog.count(*) from public.leaderboard_public_rows()),
  0::bigint,
  'a session owned by another account fails closed'
);

set local request.jwt.claims =
  '{"sub":"e5000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(
  (select pg_catalog.count(*) from public.leaderboard_public_rows()),
  0::bigint,
  'a JWT without session_id fails closed'
);

set local request.jwt.claims =
  '{"sub":"e5000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"not-a-uuid"}';
select is(
  (select pg_catalog.count(*) from public.leaderboard_public_rows()),
  0::bigint,
  'a malformed session_id fails closed'
);

set local request.jwt.claim.sub = 'e5000000-0000-4000-8000-000000000003';
set local request.jwt.claims =
  '{"sub":"e5000000-0000-4000-8000-000000000003","role":"authenticated","session_id":"e6000000-0000-4000-8000-000000000003"}';
select is(
  (select pg_catalog.count(*) from public.leaderboard_public_rows()),
  0::bigint,
  'an expired exact Auth session fails closed'
);

set local request.jwt.claim.sub = 'e5000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{"sub":"e5000000-0000-4000-8000-000000000002","role":"authenticated","session_id":"e6000000-0000-4000-8000-000000000002"}';
select is(
  (select pg_catalog.count(*) from public.leaderboard_public_rows()),
  1::bigint,
  'a second exact live session works before revocation'
);
delete from auth.sessions
where id = 'e6000000-0000-4000-8000-000000000002';
select is(
  (select pg_catalog.count(*) from public.leaderboard_public_rows()),
  0::bigint,
  'deleting the exact Auth session immediately revokes leaderboard reads'
);

create table public.gymapp_default_acl_table_probe (id bigint);
create table gymapp_private.gymapp_default_acl_table_probe (id bigint);
alter table gymapp_private.gymapp_default_acl_table_probe
  enable row level security;
alter table gymapp_private.gymapp_default_acl_table_probe
  force row level security;
create sequence public.gymapp_default_acl_sequence_probe;
create sequence gymapp_private.gymapp_default_acl_sequence_probe;
create function public.gymapp_default_acl_function_probe()
returns integer
language sql
as $function$ select 1 $function$;
create function gymapp_private.gymapp_default_acl_function_probe()
returns integer
language sql
as $function$ select 1 $function$;
create function extensions.gymapp_default_acl_function_probe()
returns integer
language sql
as $function$ select 1 $function$;

select ok(
  (select class_row.relrowsecurity
   from pg_catalog.pg_class as class_row
   where class_row.oid =
     'public.gymapp_default_acl_table_probe'::pg_catalog.regclass),
  'the existing public-table DDL guard still enables RLS'
);
select ok(
  not has_table_privilege(
    'anon', 'public.gymapp_default_acl_table_probe',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
  ),
  'future public tables grant nothing to anon'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.gymapp_default_acl_table_probe',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
  ),
  'future public tables grant nothing to authenticated'
);
select ok(
  not has_table_privilege(
    'service_role', 'public.gymapp_default_acl_table_probe',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
  ),
  'future public tables grant nothing to service_role'
);
select ok(
  not has_table_privilege(
    'anon', 'gymapp_private.gymapp_default_acl_table_probe',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
  ),
  'future private tables grant nothing to anon'
);
select ok(
  not has_table_privilege(
    'authenticated', 'gymapp_private.gymapp_default_acl_table_probe',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
  ),
  'future private tables grant nothing to authenticated'
);
select ok(
  not has_table_privilege(
    'service_role', 'gymapp_private.gymapp_default_acl_table_probe',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
  ),
  'future private tables grant nothing to service_role'
);
select ok(
  not has_sequence_privilege(
    'anon', 'public.gymapp_default_acl_sequence_probe', 'USAGE,SELECT,UPDATE'
  ),
  'future public sequences grant nothing to anon'
);
select ok(
  not has_sequence_privilege(
    'authenticated', 'public.gymapp_default_acl_sequence_probe',
    'USAGE,SELECT,UPDATE'
  ),
  'future public sequences grant nothing to authenticated'
);
select ok(
  not has_sequence_privilege(
    'service_role', 'public.gymapp_default_acl_sequence_probe',
    'USAGE,SELECT,UPDATE'
  ),
  'future public sequences grant nothing to service_role'
);
select ok(
  not has_sequence_privilege(
    'anon', 'gymapp_private.gymapp_default_acl_sequence_probe',
    'USAGE,SELECT,UPDATE'
  ),
  'future private sequences grant nothing to anon'
);
select ok(
  not has_sequence_privilege(
    'authenticated', 'gymapp_private.gymapp_default_acl_sequence_probe',
    'USAGE,SELECT,UPDATE'
  ),
  'future private sequences grant nothing to authenticated'
);
select ok(
  not has_sequence_privilege(
    'service_role', 'gymapp_private.gymapp_default_acl_sequence_probe',
    'USAGE,SELECT,UPDATE'
  ),
  'future private sequences grant nothing to service_role'
);
select ok(
  not has_function_privilege(
    'public', 'public.gymapp_default_acl_function_probe()', 'EXECUTE'
  ),
  'future public functions are not executable by PUBLIC'
);
select ok(
  not has_function_privilege(
    'anon', 'public.gymapp_default_acl_function_probe()', 'EXECUTE'
  ),
  'future public functions are not executable by anon'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.gymapp_default_acl_function_probe()', 'EXECUTE'
  ),
  'future public functions are not executable by authenticated'
);
select ok(
  not has_function_privilege(
    'service_role', 'public.gymapp_default_acl_function_probe()', 'EXECUTE'
  ),
  'future public functions are not executable by service_role'
);
select ok(
  not has_function_privilege(
    'public', 'gymapp_private.gymapp_default_acl_function_probe()', 'EXECUTE'
  ),
  'future private functions are not executable by PUBLIC'
);
select ok(
  not has_function_privilege(
    'anon', 'gymapp_private.gymapp_default_acl_function_probe()', 'EXECUTE'
  ),
  'future private functions are not executable by anon'
);
select ok(
  not has_function_privilege(
    'authenticated', 'gymapp_private.gymapp_default_acl_function_probe()',
    'EXECUTE'
  ),
  'future private functions are not executable by authenticated'
);
select ok(
  not has_function_privilege(
    'service_role', 'gymapp_private.gymapp_default_acl_function_probe()',
    'EXECUTE'
  ),
  'future private functions are not executable by service_role'
);
select ok(
  has_function_privilege(
    'public', 'extensions.gymapp_default_acl_function_probe()', 'EXECUTE'
  ),
  'future extension functions preserve the pre-hardening PUBLIC default'
);
select ok(
  has_function_privilege(
    'anon', 'extensions.gymapp_default_acl_function_probe()', 'EXECUTE'
  ),
  'extension compatibility remains inherited by client roles'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.leaderboard_public_rows()', 'EXECUTE'
  ),
  'deny-by-default does not remove an explicit supported RPC grant'
);

select * from finish();

rollback;
