begin;

-- Harden the existing production schema after leaderboard_public is installed.
-- This migration intentionally preserves all rows. It removes legacy cross-user
-- read paths, normalizes client policies/grants, and makes the cloud-state
-- revision server-owned so older clients cannot bypass optimistic concurrency.
do $preflight$
declare
  missing_objects text;
begin
  select string_agg(required.object_name, ', ' order by required.object_name)
    into missing_objects
  from (
    values
      ('public.profiles'),
      ('public.user_states'),
      ('public.garmin_devices'),
      ('public.garmin_plans'),
      ('public.leaderboard_public'),
      ('public.leaderboard_reports'),
      ('public.leaderboard_blocked_terms')
  ) as required(object_name)
  where to_regclass(required.object_name) is null;

  if missing_objects is not null then
    raise exception 'Cannot harden GymApp schema; missing objects: %', missing_objects;
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_states'
      and column_name = 'updated_at'
      and data_type = 'timestamp with time zone'
  ) then
    raise exception 'public.user_states.updated_at timestamptz is required';
  end if;
end
$preflight$;

-- The old owner-view bypassed the base-table RLS and exposed unfiltered names.
-- No released GymApp client queries this view; fail rather than cascading if an
-- unknown production dependency appears.
do $legacy_leaderboard$
declare
  object_kind "char";
begin
  if to_regclass('public.leaderboard') is not null then
    select relkind
      into object_kind
    from pg_catalog.pg_class
    where oid = 'public.leaderboard'::regclass;

    if object_kind <> 'v' then
      raise exception 'public.leaderboard exists but is not a regular view';
    end if;

    execute 'revoke all privileges on table public.leaderboard from public, anon, authenticated';
    execute 'drop view public.leaderboard';
  end if;
end
$legacy_leaderboard$;

-- The UUID-free leaderboard view is now the only cross-user read surface.
-- Legacy Android builds can still read and upsert their own profile, but their
-- old direct-table leaderboard temporarily contains only the current user.
alter table public.profiles enable row level security;

drop policy if exists "Leaderboard is public" on public.profiles;
drop policy if exists "profiles are public readable" on public.profiles;
drop policy if exists "Users can read own profile" on public.profiles;
drop policy if exists "users can read own profile" on public.profiles;
drop policy if exists "Users can insert own profile" on public.profiles;
drop policy if exists "users can insert own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "users can update own profile" on public.profiles;

create policy "Users can read own profile"
on public.profiles
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can insert own profile"
on public.profiles
for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy "Users can update own profile"
on public.profiles
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Cloud state uses the same own-row access model. The production schema had two
-- duplicate policy sets, including policies targeting PUBLIC rather than the
-- authenticated role explicitly.
alter table public.user_states enable row level security;

drop policy if exists "Users can read own state" on public.user_states;
drop policy if exists "users can read own state" on public.user_states;
drop policy if exists "Users can write own state" on public.user_states;
drop policy if exists "users can insert own state" on public.user_states;
drop policy if exists "Users can insert own state" on public.user_states;
drop policy if exists "Users can update own state" on public.user_states;
drop policy if exists "users can update own state" on public.user_states;

create policy "Users can read own state"
on public.user_states
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can insert own state"
on public.user_states
for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy "Users can update own state"
on public.user_states
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Garmin clients create and maintain only rows belonging to the signed-in user.
-- The token-based plan fetch remains isolated inside its reviewed SECURITY
-- DEFINER RPC below.
alter table public.garmin_devices enable row level security;

drop policy if exists "Users can read own Garmin devices" on public.garmin_devices;
drop policy if exists "Users can insert own Garmin devices" on public.garmin_devices;
drop policy if exists "Users can update own Garmin devices" on public.garmin_devices;

create policy "Users can read own Garmin devices"
on public.garmin_devices
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can insert own Garmin devices"
on public.garmin_devices
for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy "Users can update own Garmin devices"
on public.garmin_devices
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

alter table public.garmin_plans enable row level security;

drop policy if exists "Users can read own Garmin plans" on public.garmin_plans;
drop policy if exists "Users can insert own Garmin plans" on public.garmin_plans;
drop policy if exists "Users can update own Garmin plans" on public.garmin_plans;

create policy "Users can read own Garmin plans"
on public.garmin_plans
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can insert own Garmin plans"
on public.garmin_plans
for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy "Users can update own Garmin plans"
on public.garmin_plans
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Make updated_at authoritative on the server. Android upserts omit updated_at;
-- without this trigger an iOS conditional PATCH could overwrite a newer Android
-- state while still matching the stale revision.
create or replace function public.set_user_state_server_revision()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT' then
    new.updated_at := pg_catalog.clock_timestamp();
  else
    new.updated_at := pg_catalog.greatest(
      pg_catalog.clock_timestamp(),
      old.updated_at + interval '1 microsecond'
    );
  end if;
  return new;
end
$function$;

comment on function public.set_user_state_server_revision() is
  'Owns the user_states optimistic-concurrency revision on the database server.';

revoke all on function public.set_user_state_server_revision()
  from public, anon, authenticated;

drop trigger if exists user_states_server_revision on public.user_states;
create trigger user_states_server_revision
before insert or update on public.user_states
for each row
execute function public.set_user_state_server_revision();

-- Remove broad legacy table and column grants, then grant only operations used
-- by authenticated clients. Account deletion remains a privileged server action.
revoke all privileges on table
  public.profiles,
  public.user_states,
  public.garmin_devices,
  public.garmin_plans
from public, anon;

revoke delete, truncate, references, trigger on table
  public.profiles,
  public.user_states,
  public.garmin_devices,
  public.garmin_plans
from authenticated;

do $column_revoke$
declare
  column_grant record;
  grantee_sql text;
begin
  for column_grant in
    select distinct table_name, grantee, privilege_type, column_name
    from information_schema.column_privileges
    where table_schema = 'public'
      and table_name in ('profiles', 'user_states', 'garmin_devices', 'garmin_plans')
      and grantee in ('PUBLIC', 'anon', 'authenticated')
      and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'REFERENCES')
  loop
    grantee_sql := case
      when column_grant.grantee = 'PUBLIC' then 'PUBLIC'
      else format('%I', column_grant.grantee)
    end;
    execute format(
      'revoke %s (%I) on table public.%I from %s',
      column_grant.privilege_type,
      column_grant.column_name,
      column_grant.table_name,
      grantee_sql
    );
  end loop;
end
$column_revoke$;

grant select, insert, update on table
  public.profiles,
  public.user_states,
  public.garmin_devices,
  public.garmin_plans
to authenticated;

-- Keep the unauthenticated Garmin bridge working only through its opaque
-- 256-bit device token. Signed-in apps do not need direct RPC execution.
alter function public.garmin_fetch_pending_plan(text)
  set search_path = '';
revoke all on function public.garmin_fetch_pending_plan(text)
  from public, anon, authenticated;
grant execute on function public.garmin_fetch_pending_plan(text)
  to anon, service_role;

-- Event-trigger functions are internal DDL hooks, never client RPC endpoints.
revoke all on function public.rls_auto_enable()
  from public, anon, authenticated;

-- Cover every foreign key used during account cascades and plan lookup.
create index if not exists garmin_devices_user_id_idx
  on public.garmin_devices (user_id);
create index if not exists garmin_plans_user_id_idx
  on public.garmin_plans (user_id);
create index if not exists garmin_plans_device_id_idx
  on public.garmin_plans (device_id);

-- Effective privilege checks include grants inherited through group roles.
do $grant_audit$
declare
  target_table text;
  qualified_table text;
begin
  foreach target_table in array array[
    'profiles',
    'user_states',
    'garmin_devices',
    'garmin_plans'
  ]
  loop
    qualified_table := format('public.%I', target_table);

    if has_table_privilege('anon', qualified_table, 'SELECT')
      or has_table_privilege('anon', qualified_table, 'INSERT')
      or has_table_privilege('anon', qualified_table, 'UPDATE')
      or has_table_privilege('anon', qualified_table, 'DELETE')
      or has_table_privilege('anon', qualified_table, 'TRUNCATE')
      or has_table_privilege('anon', qualified_table, 'REFERENCES')
      or has_table_privilege('anon', qualified_table, 'TRIGGER')
      or has_any_column_privilege('anon', qualified_table, 'SELECT')
      or has_any_column_privilege('anon', qualified_table, 'INSERT')
      or has_any_column_privilege('anon', qualified_table, 'UPDATE')
      or has_any_column_privilege('anon', qualified_table, 'REFERENCES') then
      raise exception
        'anon retains an effective privilege on % through a legacy or inherited grant',
        qualified_table;
    end if;

    if not has_table_privilege('authenticated', qualified_table, 'SELECT')
      or not has_table_privilege('authenticated', qualified_table, 'INSERT')
      or not has_table_privilege('authenticated', qualified_table, 'UPDATE')
      or has_table_privilege('authenticated', qualified_table, 'DELETE')
      or has_table_privilege('authenticated', qualified_table, 'TRUNCATE')
      or has_table_privilege('authenticated', qualified_table, 'REFERENCES')
      or has_table_privilege('authenticated', qualified_table, 'TRIGGER')
      or has_any_column_privilege('authenticated', qualified_table, 'REFERENCES') then
      raise exception
        'authenticated privileges are incorrect on %', qualified_table;
    end if;
  end loop;

  if has_function_privilege(
      'authenticated',
      'public.garmin_fetch_pending_plan(text)',
      'EXECUTE'
    )
    or not has_function_privilege(
      'anon',
      'public.garmin_fetch_pending_plan(text)',
      'EXECUTE'
    ) then
    raise exception 'Garmin fetch RPC execution grants are incorrect';
  end if;

  if has_function_privilege('anon', 'public.rls_auto_enable()', 'EXECUTE')
    or has_function_privilege(
      'authenticated',
      'public.rls_auto_enable()',
      'EXECUTE'
    ) then
    raise exception 'rls_auto_enable remains client-executable';
  end if;
end
$grant_audit$;

-- Fail closed if any legacy or unexpected policy survived.
do $policy_audit$
declare
  policy_errors text;
begin
  with expected(table_name, policy_name, command_name) as (
    values
      ('profiles', 'Users can read own profile', 'SELECT'),
      ('profiles', 'Users can insert own profile', 'INSERT'),
      ('profiles', 'Users can update own profile', 'UPDATE'),
      ('user_states', 'Users can read own state', 'SELECT'),
      ('user_states', 'Users can insert own state', 'INSERT'),
      ('user_states', 'Users can update own state', 'UPDATE'),
      ('garmin_devices', 'Users can read own Garmin devices', 'SELECT'),
      ('garmin_devices', 'Users can insert own Garmin devices', 'INSERT'),
      ('garmin_devices', 'Users can update own Garmin devices', 'UPDATE'),
      ('garmin_plans', 'Users can read own Garmin plans', 'SELECT'),
      ('garmin_plans', 'Users can insert own Garmin plans', 'INSERT'),
      ('garmin_plans', 'Users can update own Garmin plans', 'UPDATE')
  ),
  problems as (
    select
      expected.table_name || ':' || expected.policy_name || ':missing-or-wrong' as problem
    from expected
    left join pg_catalog.pg_policies policy
      on policy.schemaname = 'public'
      and policy.tablename = expected.table_name
      and policy.policyname = expected.policy_name
    where policy.policyname is null
      or policy.cmd <> expected.command_name
      or policy.roles <> array['authenticated']::name[]

    union all

    select
      policy.tablename || ':' || policy.policyname || ':unexpected'
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename in (
        'profiles',
        'user_states',
        'garmin_devices',
        'garmin_plans'
      )
      and not exists (
        select 1
        from expected
        where expected.table_name = policy.tablename
          and expected.policy_name = policy.policyname
      )
  )
  select string_agg(problem, ', ' order by problem)
    into policy_errors
  from problems;

  if policy_errors is not null then
    raise exception 'Unexpected GymApp policies: %', policy_errors;
  end if;

  if to_regclass('public.leaderboard') is not null then
    raise exception 'Legacy public.leaderboard view was not removed';
  end if;
end
$policy_audit$;

notify pgrst, 'reload schema';

commit;
