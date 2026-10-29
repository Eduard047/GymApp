-- Synthetic fixtures and every write are rolled back, including on failure.
begin;

select plan(22);

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create temporary table report_session_fixture (
  name text primary key,
  user_id uuid not null default pg_catalog.gen_random_uuid(),
  session_id uuid not null default pg_catalog.gen_random_uuid(),
  public_id text
) on commit drop;
insert into report_session_fixture (name) values ('reporter'), ('target');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select '00000000-0000-0000-0000-000000000000', user_id,
  'authenticated', 'authenticated', user_id::text || '@example.invalid', '',
  pg_catalog.clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb, pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
from report_session_fixture;

insert into public.profiles (user_id, display_name)
select user_id, 'Session test ' || name from report_session_fixture
on conflict (user_id) do nothing;
update report_session_fixture as fixture
set public_id = profile.public_id
from public.profiles as profile where profile.user_id = fixture.user_id;

insert into auth.sessions (id, user_id, not_after, created_at, updated_at)
select session_id, user_id, pg_catalog.clock_timestamp() + interval '1 hour',
  pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
from report_session_fixture;
grant select on report_session_fixture to authenticated, service_role;

create function pg_temp.report_claims(session_value text)
returns void language plpgsql as $test$
declare reporter uuid;
begin
  select user_id into strict reporter from report_session_fixture where name = 'reporter';
  perform pg_catalog.set_config('request.jwt.claim.sub', reporter::text, true);
  perform pg_catalog.set_config('request.jwt.claims', pg_catalog.jsonb_build_object(
    'sub', reporter::text, 'role', 'authenticated', 'session_id', session_value
  )::text, true);
end
$test$;

grant execute on function pg_temp.report_claims(text) to authenticated, service_role;

-- An ordinary session succeeds and still cannot forge server-owned fields.
select pg_temp.report_claims((select session_id::text from report_session_fixture where name = 'reporter'));
set local role authenticated;
select lives_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason) values (%L, 'spam_or_scam')$q$,
    public_id
  ),
  'Ordinary session can report another profile'
) from report_session_fixture where name = 'target';
select throws_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason) values (%L, 'spam_or_scam')$q$,
    public_id
  ),
  '23505', null,
  'Duplicate report is rejected'
) from report_session_fixture where name = 'target';
select throws_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason) values (%L, 'other')$q$,
    public_id
  ),
  '23514', null,
  'Reporting your own profile is rejected'
) from report_session_fixture where name = 'reporter';
select throws_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason) values (%L, 'invalid_reason')$q$,
    public_id
  ),
  '23514', null,
  'Invalid reason is rejected'
) from report_session_fixture where name = 'target';
select throws_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason, reporter_user_id)
       select %L, 'other', user_id from report_session_fixture where name = 'target'$q$,
    public_id
  ),
  '42501', null,
  'Authenticated caller cannot set a server-owned field'
) from report_session_fixture where name = 'target';
reset role;

-- The JWT remains present while its exact session is deleted.
delete from auth.sessions where id = (select session_id from report_session_fixture where name = 'reporter');
set local role authenticated;
select throws_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason) values (%L, 'other')$q$,
    public_id
  ),
  '42501', null,
  'Deleted session is rejected'
) from report_session_fixture where name = 'target';
-- Rejection must precede target lookup, so an unknown target also yields 42501.
select throws_ok(
  $q$insert into public.leaderboard_reports (reported_profile_id, reason)
     values ('p_00000000000000000000000000000000', 'other')$q$,
  '42501', null,
  'Deleted session is rejected before target lookup (unknown target)'
);
reset role;

-- A bypass-RLS role cannot evade the trigger's exact-session check.
set local role service_role;
select throws_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason) values (%L, 'other')$q$,
    public_id
  ),
  '42501', null,
  'service_role cannot evade the exact-session check'
) from report_session_fixture where name = 'target';
reset role;

-- An existing but expired session fails through the same INSERT path.
insert into auth.sessions (id, user_id, not_after, created_at, updated_at)
select session_id, user_id, pg_catalog.clock_timestamp() - interval '1 minute',
  pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
from report_session_fixture where name = 'reporter';
set local role authenticated;
select throws_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason) values (%L, 'other')$q$,
    public_id
  ),
  '42501', null,
  'Expired session is rejected'
) from report_session_fixture where name = 'target';
reset role;

-- A live session belonging to another account is not interchangeable.
select pg_temp.report_claims((select session_id::text from report_session_fixture where name = 'target'));
set local role authenticated;
select throws_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason) values (%L, 'other')$q$,
    public_id
  ),
  '42501', null,
  'Another account''s live session is rejected'
) from report_session_fixture where name = 'target';
select pg_temp.report_claims(null);
select throws_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason) values (%L, 'other')$q$,
    public_id
  ),
  '42501', null,
  'Missing session claim is rejected'
) from report_session_fixture where name = 'target';
select pg_temp.report_claims('malformed-session');
select throws_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason) values (%L, 'other')$q$,
    public_id
  ),
  '42501', null,
  'Malformed session claim is rejected'
) from report_session_fixture where name = 'target';
select pg_temp.report_claims(pg_catalog.gen_random_uuid()::text);
select throws_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason) values (%L, 'other')$q$,
    public_id
  ),
  '42501', null,
  'Unknown session claim is rejected'
) from report_session_fixture where name = 'target';
reset role;

-- A live session without a fixed not_after remains supported.
update auth.sessions set not_after = null
where id = (select session_id from report_session_fixture where name = 'reporter');
select pg_temp.report_claims((select session_id::text from report_session_fixture where name = 'reporter'));
set local role authenticated;
select lives_ok(
  format(
    $q$insert into public.leaderboard_reports (reported_profile_id, reason) values (%L, 'other')$q$,
    public_id
  ),
  'Live session without a fixed not_after can still report'
) from report_session_fixture where name = 'target';
reset role;

-- Authentication and column grants remain the only client admission route.
set local role anon;
select throws_ok(
  $q$insert into public.leaderboard_reports (reported_profile_id, reason)
     values ('p_00000000000000000000000000000000', 'other')$q$,
  '42501', null,
  'Anonymous caller cannot insert a report'
);
reset role;

select is(
  (select count(*)::integer from public.leaderboard_reports
   where reporter_user_id = (select user_id from report_session_fixture where name = 'reporter')),
  2,
  'Denied requests did not change report rows'
);
select ok(
  not exists (
    select 1 from public.leaderboard_reports
    where reporter_user_id = (select user_id from report_session_fixture where name = 'reporter')
      and (status <> 'pending' or reported_display_name <> 'Session test target')
  ),
  'Server-owned report fields were not changed'
);
select ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.leaderboard_reports', 'SELECT'),
  'authenticated has no SELECT on leaderboard_reports'
);
select ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.leaderboard_reports', 'UPDATE'),
  'authenticated has no UPDATE on leaderboard_reports'
);
select ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.leaderboard_reports', 'DELETE'),
  'authenticated has no DELETE on leaderboard_reports'
);
select ok(
  not pg_catalog.has_function_privilege('authenticated', 'public.prepare_leaderboard_report()', 'EXECUTE'),
  'authenticated cannot execute prepare_leaderboard_report()'
);
select ok(
  not pg_catalog.has_function_privilege('anon', 'public.prepare_leaderboard_report()', 'EXECUTE'),
  'anon cannot execute prepare_leaderboard_report()'
);

select * from finish();
rollback;
