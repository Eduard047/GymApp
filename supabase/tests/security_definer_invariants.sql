-- SECURITY DEFINER invariants for the schemas the app owns (public and
-- gymapp_private). Pure catalog assertions, no fixtures.
--
-- A SECURITY DEFINER function runs with its owner's rights, so it must pin its
-- search_path, must never be callable by anon/PUBLIC, and must be owned by the
-- migration role rather than a client role. Trigger functions and the service
-- and core workers must stay unreachable from client roles.
--
-- Complements privilege_snapshot.sql (exact grant lists) with rules that hold
-- for every current and future function, so a new function that breaks them
-- fails here even before anyone updates a snapshot.
--
-- Hardcoded lists below (the rls_auto_enable exception, the *_core names, the
-- service-only functions) must be updated in the same change that intentionally
-- adds, renames, or re-grants such a function.
begin;

select plan(12);

-- One row per SECURITY DEFINER function with its search_path settings.
create temp view gymapp_secdef as
select
  p.oid as fn_oid,
  (n.nspname || '.' || p.proname || '('
    || pg_catalog.array_to_string(
         p.proargtypes::pg_catalog.oid[]::pg_catalog.regtype[], ',')
    || ')')::text as signature,
  pg_catalog.pg_get_userbyid(p.proowner)::text as owner_name,
  config.search_path_settings,
  coalesce(
    pg_catalog.array_length(config.search_path_settings, 1), 0
  ) as search_path_count,
  config.search_path_settings[1] as search_path_setting
from pg_catalog.pg_proc as p
join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
cross join lateral (
  select array(
    select setting.entry
    from pg_catalog.unnest(p.proconfig) as setting(entry)
    where setting.entry like 'search_path=%'
  ) as search_path_settings
) as config
where n.nspname in ('public', 'gymapp_private')
  and p.prosecdef;

-- Function EXECUTE grants, one row per (function, grantee). A NULL proacl is
-- the default ACL, which grants PUBLIC EXECUTE, so acldefault() is substituted.
create temp view gymapp_fn_exec as
select
  p.oid as fn_oid,
  (n.nspname || '.' || p.proname || '('
    || pg_catalog.array_to_string(
         p.proargtypes::pg_catalog.oid[]::pg_catalog.regtype[], ',')
    || ')')::text as signature,
  (case acl.grantee
     when 0 then 'PUBLIC'
     else pg_catalog.pg_get_userbyid(acl.grantee)
   end)::text as grantee
from pg_catalog.pg_proc as p
join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
cross join lateral pg_catalog.aclexplode(
  coalesce(p.proacl, pg_catalog.acldefault('f'::"char", p.proowner))
) as acl
where n.nspname in ('public', 'gymapp_private')
  and acl.privilege_type = 'EXECUTE';

-- public functions that only service_role may execute (Edge Functions and the
-- push/edge/gateway workers, the trigger functions, and the realtime workers).
-- leaderboard_public_rows() is deliberately absent: authenticated also runs it.
create temp table gymapp_service_only_functions (signature text primary key);
insert into gymapp_service_only_functions (signature) values
  ('public.edge_preauth_debit(text,text)'),
  ('public.enforce_profile_public_fields()'),
  ('public.garmin_ack_plan(text,uuid,bigint)'),
  ('public.garmin_fetch_pending_plan(text)'),
  ('public.garmin_gateway_preauth_debit(text,integer)'),
  ('public.garmin_quarantine_pending_plan(text,uuid,bigint,text)'),
  ('public.garmin_record_capability_use(text,smallint)'),
  ('public.prepare_leaderboard_report()'),
  ('public.push_authorize_delivery_send(uuid,uuid)'),
  ('public.push_claim_deliveries(uuid,integer,integer)'),
  ('public.push_delivery_is_current(uuid,uuid)'),
  ('public.push_mark_delivered(uuid,uuid,integer)'),
  ('public.push_mark_retry(uuid,uuid,text,integer,integer,boolean,boolean)'),
  ('public.rls_auto_enable()'),
  ('public.safe_leaderboard_display_name(text)'),
  ('public.set_user_state_server_revision()'),
  ('public.social_apply_live_workout_operation(uuid,uuid,text,uuid,bigint,jsonb)'),
  ('public.social_cancel_live_workout(uuid,uuid,text,uuid,bigint)'),
  ('public.social_finish_live_workout(uuid,uuid,text,uuid,bigint)'),
  ('public.social_gateway_perimeter_debit(uuid,uuid)'),
  ('public.social_leave_live_workout(uuid,uuid,text,uuid,bigint)'),
  ('public.social_live_gateway_debit(uuid,uuid,text)'),
  ('public.social_live_workout_inbox(uuid,uuid)'),
  ('public.social_live_workout_snapshot(uuid,uuid,text)'),
  ('public.social_respond_live_workout_invite(uuid,uuid,text,text,bigint,uuid)'),
  ('public.social_send_live_workout_invite(uuid,uuid,text,uuid,jsonb)'),
  ('public.social_start_live_workout(uuid,uuid,text,bigint,uuid)');

-- ---------------------------------------------------------------------------
-- A. search_path is pinned on every SECURITY DEFINER function
-- ---------------------------------------------------------------------------
select isnt_empty(
  $q$ select signature from gymapp_secdef $q$,
  'catalog scan finds SECURITY DEFINER functions in public and gymapp_private'
);

select is_empty(
  $q$
    select signature
    from gymapp_secdef
    where search_path_count <> 1
  $q$,
  'every SECURITY DEFINER function sets search_path exactly once'
);

-- Allowed values: the empty search_path, plus the one listed pg_catalog-only
-- exception below. Anything else (public, extensions, $user, mixed) fails.
select is_empty(
  $q$
    select signature, search_path_setting
    from gymapp_secdef
    where search_path_setting <> 'search_path=""'
      and not (signature = 'public.rls_auto_enable()'
               and search_path_setting = 'search_path=pg_catalog')
  $q$,
  'SECURITY DEFINER search_path is empty, or the declared pg_catalog exception'
);

select set_eq(
  $q$
    select signature, search_path_setting
    from gymapp_secdef
    where search_path_setting <> 'search_path=""'
  $q$,
  $q$
    values ('public.rls_auto_enable()', 'search_path=pg_catalog')
  $q$,
  'rls_auto_enable is the only SECURITY DEFINER function without an empty search_path'
);

-- ---------------------------------------------------------------------------
-- B. SECURITY DEFINER functions are never callable by anon or PUBLIC
-- ---------------------------------------------------------------------------
select is_empty(
  $q$
    select secdef.signature, exec_row.grantee
    from gymapp_secdef as secdef
    join gymapp_fn_exec as exec_row on exec_row.fn_oid = secdef.fn_oid
    where exec_row.grantee in ('anon', 'PUBLIC')
  $q$,
  'no SECURITY DEFINER function is executable by anon or PUBLIC'
);

-- ---------------------------------------------------------------------------
-- C. core workers and service-only functions stay away from client roles
-- ---------------------------------------------------------------------------
select set_eq(
  $q$
    select (n.nspname || '.' || p.proname || '('
      || pg_catalog.array_to_string(
           p.proargtypes::pg_catalog.oid[]::pg_catalog.regtype[], ',')
      || ')')::text
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname in ('public', 'gymapp_private')
      and p.proname like '%\_core' escape '\'
  $q$,
  $q$
    values
      ('public.garmin_ack_plan_core(text,uuid,bigint)'),
      ('public.garmin_create_device_core(text)'),
      ('public.garmin_fetch_pending_plan_core(text)'),
      ('public.garmin_quarantine_pending_plan_core(text,uuid,bigint,text)'),
      ('public.garmin_revoke_device_core(uuid)')
  $q$,
  'the *_core worker functions match the snapshot'
);

select is_empty(
  $q$
    select exec_row.signature, exec_row.grantee
    from gymapp_fn_exec as exec_row
    join pg_catalog.pg_proc as p on p.oid = exec_row.fn_oid
    where p.proname like '%\_core' escape '\'
      and exec_row.grantee in ('anon', 'authenticated', 'PUBLIC')
  $q$,
  'no *_core function is executable by anon, authenticated, or PUBLIC'
);

select set_eq(
  $q$
    select exec_row.signature
    from gymapp_fn_exec as exec_row
    join gymapp_service_only_functions as listed
      on listed.signature = exec_row.signature
    where exec_row.grantee = 'service_role'
  $q$,
  $q$ select signature from gymapp_service_only_functions $q$,
  'every listed service-only function exists and service_role can execute it'
);

select is_empty(
  $q$
    select exec_row.signature, exec_row.grantee
    from gymapp_fn_exec as exec_row
    join gymapp_service_only_functions as listed
      on listed.signature = exec_row.signature
    where exec_row.grantee in ('anon', 'authenticated', 'PUBLIC')
  $q$,
  'no service-only function is executable by anon, authenticated, or PUBLIC'
);

-- ---------------------------------------------------------------------------
-- D. owner of every SECURITY DEFINER function is the migration role
-- ---------------------------------------------------------------------------
select set_eq(
  $q$ select distinct owner_name from gymapp_secdef $q$,
  $q$ values ('postgres') $q$,
  'every SECURITY DEFINER function is owned by postgres, never a client role'
);

-- ---------------------------------------------------------------------------
-- E. trigger functions are not callable by client roles
-- ---------------------------------------------------------------------------
select isnt_empty(
  $q$
    select p.oid
    from pg_catalog.pg_proc as p
    where p.pronamespace in (
        'public'::pg_catalog.regnamespace,
        'gymapp_private'::pg_catalog.regnamespace
      )
      and p.prorettype in (
        'trigger'::pg_catalog.regtype,
        'event_trigger'::pg_catalog.regtype
      )
  $q$,
  'catalog scan finds trigger functions in public and gymapp_private'
);

select is_empty(
  $q$
    select exec_row.signature, exec_row.grantee
    from gymapp_fn_exec as exec_row
    join pg_catalog.pg_proc as p on p.oid = exec_row.fn_oid
    where p.prorettype in (
        'trigger'::pg_catalog.regtype,
        'event_trigger'::pg_catalog.regtype
      )
      and exec_row.grantee in ('anon', 'authenticated', 'PUBLIC')
  $q$,
  'no trigger function is executable by anon, authenticated, or PUBLIC'
);

select * from finish();

rollback;
