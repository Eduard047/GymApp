-- Synthetic fixtures and every write are rolled back, including on failure.
begin;
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

create function pg_temp.report_denied(target_id text, reason_value text, expected_state text)
returns void language plpgsql as $test$
begin
  begin
    insert into public.leaderboard_reports (reported_profile_id, reason)
    values (target_id, reason_value);
  exception when others then
    if sqlstate = expected_state then return; end if;
    raise;
  end;
  raise exception 'Report insertion unexpectedly succeeded; expected %', expected_state;
end
$test$;

grant execute on function pg_temp.report_claims(text) to authenticated, service_role;
grant execute on function pg_temp.report_denied(text, text, text) to authenticated, service_role;

-- An ordinary session succeeds and still cannot forge server-owned fields.
select pg_temp.report_claims((select session_id::text from report_session_fixture where name = 'reporter'));
set local role authenticated;
insert into public.leaderboard_reports (reported_profile_id, reason)
select public_id, 'spam_or_scam' from report_session_fixture where name = 'target';
select pg_temp.report_denied(public_id, 'spam_or_scam', '23505')
from report_session_fixture where name = 'target';
select pg_temp.report_denied(public_id, 'other', '23514')
from report_session_fixture where name = 'reporter';
select pg_temp.report_denied(public_id, 'invalid_reason', '23514')
from report_session_fixture where name = 'target';
do $test$
begin
  begin
    insert into public.leaderboard_reports (reported_profile_id, reason, reporter_user_id)
    select public_id, 'other', user_id from report_session_fixture where name = 'target';
    raise exception 'Authenticated caller set a server-owned field.';
  exception when insufficient_privilege then null;
  end;
end
$test$;
reset role;

-- The JWT remains present while its exact session is deleted.
delete from auth.sessions where id = (select session_id from report_session_fixture where name = 'reporter');
set local role authenticated;
select pg_temp.report_denied(public_id, 'other', '42501')
from report_session_fixture where name = 'target';
-- Rejection must precede target lookup, so an unknown target also yields 42501.
select pg_temp.report_denied('p_00000000000000000000000000000000', 'other', '42501');
reset role;

-- A bypass-RLS role cannot evade the trigger's exact-session check.
set local role service_role;
select pg_temp.report_denied(public_id, 'other', '42501')
from report_session_fixture where name = 'target';
reset role;

-- An existing but expired session fails through the same INSERT path.
insert into auth.sessions (id, user_id, not_after, created_at, updated_at)
select session_id, user_id, pg_catalog.clock_timestamp() - interval '1 minute',
  pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
from report_session_fixture where name = 'reporter';
set local role authenticated;
select pg_temp.report_denied(public_id, 'other', '42501')
from report_session_fixture where name = 'target';
reset role;

-- A live session belonging to another account is not interchangeable.
select pg_temp.report_claims((select session_id::text from report_session_fixture where name = 'target'));
set local role authenticated;
select pg_temp.report_denied(public_id, 'other', '42501')
from report_session_fixture where name = 'target';
select pg_temp.report_claims(null);
select pg_temp.report_denied(public_id, 'other', '42501')
from report_session_fixture where name = 'target';
select pg_temp.report_claims('malformed-session');
select pg_temp.report_denied(public_id, 'other', '42501')
from report_session_fixture where name = 'target';
select pg_temp.report_claims(pg_catalog.gen_random_uuid()::text);
select pg_temp.report_denied(public_id, 'other', '42501')
from report_session_fixture where name = 'target';
reset role;

-- A live session without a fixed not_after remains supported.
update auth.sessions set not_after = null
where id = (select session_id from report_session_fixture where name = 'reporter');
select pg_temp.report_claims((select session_id::text from report_session_fixture where name = 'reporter'));
set local role authenticated;
insert into public.leaderboard_reports (reported_profile_id, reason)
select public_id, 'other' from report_session_fixture where name = 'target';
reset role;

-- Authentication and column grants remain the only client admission route.
set local role anon;
do $test$
begin
  begin
    insert into public.leaderboard_reports (reported_profile_id, reason)
    values ('p_00000000000000000000000000000000', 'other');
    raise exception 'Anonymous caller inserted a report.';
  exception when insufficient_privilege then null;
  end;
end
$test$;
reset role;

do $test$
declare report_count integer;
begin
  select count(*) into report_count from public.leaderboard_reports
  where reporter_user_id = (select user_id from report_session_fixture where name = 'reporter');
  if report_count <> 2 then raise exception 'Denied requests changed report rows: %', report_count; end if;
  if exists (
    select 1 from public.leaderboard_reports
    where reporter_user_id = (select user_id from report_session_fixture where name = 'reporter')
      and (status <> 'pending' or reported_display_name <> 'Session test target')
  ) then raise exception 'Server-owned report fields changed.'; end if;
  if pg_catalog.has_table_privilege('authenticated', 'public.leaderboard_reports', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.leaderboard_reports', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.leaderboard_reports', 'DELETE')
     or pg_catalog.has_function_privilege('authenticated', 'public.prepare_leaderboard_report()', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'public.prepare_leaderboard_report()', 'EXECUTE') then
    raise exception 'Report permissions were widened.';
  end if;
end
$test$;

select 'leaderboard_report_session: passed' as result;
rollback;
