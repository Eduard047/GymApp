begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
declare
  postgres_role_oid oid := pg_catalog.to_regrole('postgres');
  client_role_oids oid[] := array[
    pg_catalog.to_regrole('anon'),
    pg_catalog.to_regrole('authenticated'),
    pg_catalog.to_regrole('service_role')
  ];
begin
  if current_user <> 'postgres' then
    raise exception 'GymApp default-privilege hardening must run as postgres.';
  end if;

  if postgres_role_oid is null
     or pg_catalog.array_position(client_role_oids, null) is not null
     or pg_catalog.to_regnamespace('extensions') is null
     or pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regclass('public.leaderboard_public') is null
     or pg_catalog.to_regclass('gymapp_private.user_state_quarantine') is null
     or pg_catalog.to_regclass('gymapp_private.user_state_progression') is null
     or pg_catalog.to_regprocedure('public.leaderboard_public_rows()') is null
     or pg_catalog.to_regprocedure(
       'public.safe_leaderboard_display_name(text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.current_auth_session_is_live()'
     ) is null then
    raise exception 'GymApp remaining-boundary hardening prerequisites are missing.';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_class as class_row
    where class_row.oid in (
      'public.profiles'::pg_catalog.regclass,
      'public.leaderboard_public'::pg_catalog.regclass,
      'gymapp_private.user_state_quarantine'::pg_catalog.regclass,
      'gymapp_private.user_state_progression'::pg_catalog.regclass
    )
      and class_row.relowner <> postgres_role_oid
  ) or exists (
    select 1
    from pg_catalog.pg_proc as procedure_row
    where procedure_row.oid in (
      'public.leaderboard_public_rows()'::pg_catalog.regprocedure,
      'public.safe_leaderboard_display_name(text)'::pg_catalog.regprocedure,
      'gymapp_private.current_auth_session_is_live()'::pg_catalog.regprocedure
    )
      and procedure_row.proowner <> postgres_role_oid
  ) then
    raise exception 'GymApp boundary objects have an unexpected owner.';
  end if;

  -- These two server-owned tables have never had client policies. Refuse to
  -- erase an environment-specific policy silently; an operator must inspect
  -- such drift before this migration can continue.
  if exists (
    select 1
    from pg_catalog.pg_policy as policy_row
    where policy_row.polrelid in (
      'gymapp_private.user_state_quarantine'::pg_catalog.regclass,
      'gymapp_private.user_state_progression'::pg_catalog.regclass
    )
  ) then
    raise exception 'Unexpected client policy exists on a private projection table.';
  end if;

  -- A schema-specific REVOKE cannot subtract a global table/sequence default.
  -- Production has no such grants; abort on drift instead of claiming a scoped
  -- hardening that would be ineffective.
  if exists (
    select 1
    from pg_catalog.pg_default_acl as default_acl
    cross join lateral pg_catalog.aclexplode(default_acl.defaclacl) as privilege
    where default_acl.defaclrole = postgres_role_oid
      and default_acl.defaclnamespace = 0
      and default_acl.defaclobjtype in ('r', 'S')
      and (
        privilege.grantee = 0
        or privilege.grantee = any (client_role_oids)
      )
  ) then
    raise exception 'Unexpected global postgres table or sequence defaults require operator review.';
  end if;

  -- Removing PostgreSQL's built-in PUBLIC EXECUTE must be global. The only
  -- current non-system postgres-owned functions outside the two GymApp schemas
  -- are extension helpers, whose future compatibility is restored explicitly
  -- below. Abort if a new platform/application owner boundary has appeared.
  if exists (
    select 1
    from pg_catalog.pg_proc as procedure_row
    join pg_catalog.pg_namespace as namespace_row
      on namespace_row.oid = procedure_row.pronamespace
    where procedure_row.proowner = postgres_role_oid
      and namespace_row.nspname not in (
        'public',
        'gymapp_private',
        'extensions',
        'information_schema'
      )
      and namespace_row.nspname !~ '^pg_'
  ) then
    raise exception 'Unexpected postgres-owned function schema requires default-ACL review.';
  end if;
end
$preflight$;

-- These are internal caches used only by owner-controlled SECURITY DEFINER
-- functions. RLS + FORCE RLS with no policies provides defense in depth even
-- if a later migration accidentally grants schema/table access to a client.
alter table gymapp_private.user_state_quarantine
  enable row level security;
alter table gymapp_private.user_state_quarantine
  force row level security;
alter table gymapp_private.user_state_progression
  enable row level security;
alter table gymapp_private.user_state_progression
  force row level security;

revoke all privileges on table gymapp_private.user_state_quarantine
  from public, anon, authenticated, service_role;
revoke all privileges on table gymapp_private.user_state_progression
  from public, anon, authenticated, service_role;

-- The leaderboard is intentionally owner-only while progression remains based
-- on client-authored state. Bind that compatibility projection to the exact
-- current Auth session as well as auth.uid(), so a deleted/revoked or expired
-- access JWT returns no rows. VOLATILE is required because the live-session
-- helper takes a key-share lock to serialize reads with session deletion.
create or replace function public.leaderboard_public_rows()
returns table (
  profile_id text,
  display_name text,
  xp bigint,
  level bigint,
  workouts bigint,
  is_current_user boolean
)
language sql
volatile
security definer
set search_path = ''
as $function$
  select
    profile.public_id::text,
    coalesce(
      public.safe_leaderboard_display_name(profile.display_name::text),
      'GymApp user'
    )::text,
    greatest(coalesce(profile.xp, 0), 0)::bigint,
    greatest(coalesce(profile.level, 1), 1)::bigint,
    greatest(coalesce(profile.workouts, 0), 0)::bigint,
    true
  from public.profiles as profile
  where (select gymapp_private.current_auth_session_is_live())
    and profile.user_id = (select auth.uid())
    and not exists (
      select 1
      from gymapp_private.user_state_quarantine as quarantine
      where quarantine.user_id = profile.user_id
    )
$function$;

comment on function public.leaderboard_public_rows() is
  'Live-session-bound owner-only compatibility projection. Cross-account ranking stays disabled until progression comes from a trusted append-only receipt source.';

revoke all privileges on function public.leaderboard_public_rows()
  from public, anon, authenticated, service_role;
grant execute on function public.leaderboard_public_rows()
  to authenticated, service_role;

-- Supabase projects historically auto-granted new public objects to API roles.
-- Keep future GymApp objects deny-by-default; every supported API endpoint must
-- opt in with an explicit GRANT in the same migration as its authorization.
alter default privileges for role postgres in schema public
  revoke all privileges on tables
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema gymapp_private
  revoke all privileges on tables
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all privileges on sequences
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema gymapp_private
  revoke all privileges on sequences
  from public, anon, authenticated, service_role;

-- PostgreSQL's built-in function default is EXECUTE for PUBLIC and cannot be
-- subtracted by an IN SCHEMA revoke. Remove it globally for postgres, clear any
-- schema-specific API grants in GymApp schemas, then preserve the prior default
-- for the only audited non-app boundary owned by postgres: extensions.
alter default privileges for role postgres
  revoke all privileges on functions
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all privileges on functions
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema gymapp_private
  revoke all privileges on functions
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema extensions
  grant execute on functions to public;

do $verify$
declare
  postgres_role_oid oid := pg_catalog.to_regrole('postgres');
  client_role_oids oid[] := array[
    pg_catalog.to_regrole('anon'),
    pg_catalog.to_regrole('authenticated'),
    pg_catalog.to_regrole('service_role')
  ];
  public_schema_oid oid := pg_catalog.to_regnamespace('public');
  private_schema_oid oid := pg_catalog.to_regnamespace('gymapp_private');
  extensions_schema_oid oid := pg_catalog.to_regnamespace('extensions');
begin
  if exists (
    select 1
    from pg_catalog.pg_class as class_row
    where class_row.oid in (
      'gymapp_private.user_state_quarantine'::pg_catalog.regclass,
      'gymapp_private.user_state_progression'::pg_catalog.regclass
    )
      and (
        not class_row.relrowsecurity
        or not class_row.relforcerowsecurity
      )
  ) or exists (
    select 1
    from pg_catalog.pg_policy as policy_row
    where policy_row.polrelid in (
      'gymapp_private.user_state_quarantine'::pg_catalog.regclass,
      'gymapp_private.user_state_progression'::pg_catalog.regclass
    )
  ) then
    raise exception 'Private projection RLS is not fail closed.';
  end if;

  if has_table_privilege(
       'anon',
       'gymapp_private.user_state_quarantine',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
     )
     or has_table_privilege(
       'authenticated',
       'gymapp_private.user_state_quarantine',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
     )
     or has_table_privilege(
       'service_role',
       'gymapp_private.user_state_quarantine',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
     )
     or has_table_privilege(
       'anon',
       'gymapp_private.user_state_progression',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
     )
     or has_table_privilege(
       'authenticated',
       'gymapp_private.user_state_progression',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
     )
     or has_table_privilege(
       'service_role',
       'gymapp_private.user_state_progression',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
     ) then
    raise exception 'Private projection tables remain client-accessible.';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as procedure_row
    where procedure_row.oid =
      'public.leaderboard_public_rows()'::pg_catalog.regprocedure
      and (
        not procedure_row.prosecdef
        or procedure_row.provolatile <> 'v'
        or not (
          coalesce(procedure_row.proconfig, array[]::text[])
          @> array['search_path=""']::text[]
        )
        or pg_catalog.pg_get_functiondef(procedure_row.oid)
          not like '%gymapp_private.current_auth_session_is_live()%'
      )
  )
     or has_function_privilege(
       'anon', 'public.leaderboard_public_rows()', 'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated', 'public.leaderboard_public_rows()', 'EXECUTE'
     )
     or not has_function_privilege(
       'service_role', 'public.leaderboard_public_rows()', 'EXECUTE'
     ) then
    raise exception 'Leaderboard live-session boundary is incomplete.';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_default_acl as default_acl
    where default_acl.defaclrole = postgres_role_oid
      and default_acl.defaclnamespace = 0
      and default_acl.defaclobjtype = 'f'
  ) or exists (
    select 1
    from pg_catalog.pg_default_acl as default_acl
    cross join lateral pg_catalog.aclexplode(default_acl.defaclacl) as privilege
    where default_acl.defaclrole = postgres_role_oid
      and (
        (
          default_acl.defaclnamespace = 0
          and default_acl.defaclobjtype = 'f'
        )
        or (
          default_acl.defaclnamespace in (
            public_schema_oid,
            private_schema_oid
          )
          and default_acl.defaclobjtype in ('r', 'S', 'f')
        )
      )
      and (
        privilege.grantee = 0
        or privilege.grantee = any (client_role_oids)
      )
  ) then
    raise exception 'GymApp future object defaults remain client-accessible.';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_default_acl as default_acl
    cross join lateral pg_catalog.aclexplode(default_acl.defaclacl) as privilege
    where default_acl.defaclrole = postgres_role_oid
      and default_acl.defaclnamespace = extensions_schema_oid
      and default_acl.defaclobjtype = 'f'
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception 'Future extension function compatibility was not preserved.';
  end if;

  if exists (select 1 from public.leaderboard_public_rows()) then
    raise exception 'Leaderboard returned rows without a live authenticated session.';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
