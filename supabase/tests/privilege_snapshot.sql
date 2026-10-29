-- Privilege snapshot: exact, hardcoded catalog state of every grant a client
-- role (anon, authenticated, PUBLIC) or service_role holds on the app schemas.
-- Pure catalog assertions, no fixtures. Any ADDED or REMOVED privilege fails.
--
-- When a migration intentionally changes grants (new RPC, new table, revoked
-- column, new service function), update the matching VALUES list below in the
-- same change, and review the diff as a security review of the grant itself.
--
-- Complements remaining_supabase_boundaries.sql (default-privilege probes,
-- specific private tables) and security_scan_followup_boundaries.sql (specific
-- functions): this file pins the whole surface instead of individual objects.
--
-- Notes on the recorded state (PG 17):
-- * authenticated holds INSERT/SELECT/UPDATE plus MAINTAIN on profiles and
--   user_states. MAINTAIN is the PG 17 privilege for VACUUM/ANALYZE/REINDEX/
--   CLUSTER/LOCK; information_schema does not list it, so the table snapshot
--   reads pg_class.relacl through aclexplode().
-- * gymapp_private is closed to client roles except two RLS predicate
--   functions that policies call by OID; they are listed explicitly below.
begin;

select plan(16);

-- Function EXECUTE grants, one row per (function, grantee). A NULL proacl is
-- not "no grant": it means the default ACL, which gives PUBLIC EXECUTE, so
-- acldefault() is substituted and such a function would surface as PUBLIC.
-- The signature is built from catalog type names so it does not depend on the
-- session search_path.
create temp view gymapp_fn_exec as
select
  p.oid as fn_oid,
  n.nspname::text as schema_name,
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

-- ---------------------------------------------------------------------------
-- A. public tables and views: privileges for anon, authenticated, PUBLIC
-- ---------------------------------------------------------------------------
select set_eq(
  $q$
    select
      class_row.relname::text,
      (case acl.grantee
         when 0 then 'PUBLIC'
         else pg_catalog.pg_get_userbyid(acl.grantee)
       end)::text,
      acl.privilege_type::text
    from pg_catalog.pg_class as class_row
    join pg_catalog.pg_namespace as ns on ns.oid = class_row.relnamespace
    cross join lateral pg_catalog.aclexplode(class_row.relacl) as acl
    where ns.nspname = 'public'
      and class_row.relkind in ('r', 'p', 'v', 'm', 'f', 'S')
      and (acl.grantee = 0
           or pg_catalog.pg_get_userbyid(acl.grantee)
              in ('anon', 'authenticated'))
  $q$,
  $q$
    values
      ('exercise_catalog', 'anon', 'SELECT'),
      ('exercise_catalog', 'authenticated', 'SELECT'),
      ('garmin_plans', 'authenticated', 'SELECT'),
      ('leaderboard_public', 'authenticated', 'SELECT'),
      ('profiles', 'authenticated', 'INSERT'),
      ('profiles', 'authenticated', 'MAINTAIN'),
      ('profiles', 'authenticated', 'SELECT'),
      ('profiles', 'authenticated', 'UPDATE'),
      ('user_states', 'authenticated', 'INSERT'),
      ('user_states', 'authenticated', 'MAINTAIN'),
      ('user_states', 'authenticated', 'SELECT'),
      ('user_states', 'authenticated', 'UPDATE')
  $q$,
  'public relation privileges for anon/authenticated/PUBLIC match the snapshot'
);

select is_empty(
  $q$
    select class_row.relname
    from pg_catalog.pg_class as class_row
    join pg_catalog.pg_namespace as ns on ns.oid = class_row.relnamespace
    cross join lateral pg_catalog.aclexplode(class_row.relacl) as acl
    where ns.nspname = 'public'
      and acl.is_grantable
      and (acl.grantee = 0
           or pg_catalog.pg_get_userbyid(acl.grantee)
              in ('anon', 'authenticated'))
  $q$,
  'client roles hold no WITH GRANT OPTION on any public relation'
);

-- ---------------------------------------------------------------------------
-- B. public columns: effective privileges for anon, authenticated, PUBLIC
--    (table-level grants expand to every column; column-level grants add to it)
-- ---------------------------------------------------------------------------
select set_eq(
  $q$
    select
      column_row.table_name::text,
      column_row.column_name::text,
      column_row.grantee::text,
      column_row.privilege_type::text
    from information_schema.column_privileges as column_row
    where column_row.table_schema = 'public'
      and column_row.grantee in ('anon', 'authenticated', 'PUBLIC')
  $q$,
  $q$
    values
      ('exercise_catalog', 'display_order', 'anon', 'SELECT'),
      ('exercise_catalog', 'display_order', 'authenticated', 'SELECT'),
      ('exercise_catalog', 'key', 'anon', 'SELECT'),
      ('exercise_catalog', 'key', 'authenticated', 'SELECT'),
      ('exercise_catalog', 'muscle_ids', 'anon', 'SELECT'),
      ('exercise_catalog', 'muscle_ids', 'authenticated', 'SELECT'),
      ('exercise_catalog', 'name_en', 'anon', 'SELECT'),
      ('exercise_catalog', 'name_en', 'authenticated', 'SELECT'),
      ('exercise_catalog', 'name_uk', 'anon', 'SELECT'),
      ('exercise_catalog', 'name_uk', 'authenticated', 'SELECT'),
      ('garmin_plans', 'client_request_id', 'authenticated', 'SELECT'),
      ('garmin_plans', 'completed_at', 'authenticated', 'SELECT'),
      ('garmin_plans', 'created_at', 'authenticated', 'SELECT'),
      ('garmin_plans', 'device_id', 'authenticated', 'INSERT'),
      ('garmin_plans', 'device_id', 'authenticated', 'SELECT'),
      ('garmin_plans', 'downloaded_at', 'authenticated', 'SELECT'),
      ('garmin_plans', 'id', 'authenticated', 'SELECT'),
      ('garmin_plans', 'plan', 'authenticated', 'INSERT'),
      ('garmin_plans', 'plan', 'authenticated', 'SELECT'),
      ('garmin_plans', 'plan_revision', 'authenticated', 'SELECT'),
      ('garmin_plans', 'result', 'authenticated', 'SELECT'),
      ('garmin_plans', 'status', 'authenticated', 'INSERT'),
      ('garmin_plans', 'status', 'authenticated', 'SELECT'),
      ('garmin_plans', 'user_id', 'authenticated', 'INSERT'),
      ('garmin_plans', 'user_id', 'authenticated', 'SELECT'),
      ('garmin_plans', 'validation_error', 'authenticated', 'SELECT'),
      ('leaderboard_public', 'display_name', 'authenticated', 'SELECT'),
      ('leaderboard_public', 'is_current_user', 'authenticated', 'SELECT'),
      ('leaderboard_public', 'level', 'authenticated', 'SELECT'),
      ('leaderboard_public', 'profile_id', 'authenticated', 'SELECT'),
      ('leaderboard_public', 'workouts', 'authenticated', 'SELECT'),
      ('leaderboard_public', 'xp', 'authenticated', 'SELECT'),
      ('leaderboard_reports', 'reason', 'authenticated', 'INSERT'),
      ('leaderboard_reports', 'reported_profile_id', 'authenticated', 'INSERT'),
      ('profiles', 'display_name', 'authenticated', 'INSERT'),
      ('profiles', 'display_name', 'authenticated', 'SELECT'),
      ('profiles', 'display_name', 'authenticated', 'UPDATE'),
      ('profiles', 'level', 'authenticated', 'INSERT'),
      ('profiles', 'level', 'authenticated', 'SELECT'),
      ('profiles', 'level', 'authenticated', 'UPDATE'),
      ('profiles', 'progression_version', 'authenticated', 'INSERT'),
      ('profiles', 'progression_version', 'authenticated', 'SELECT'),
      ('profiles', 'progression_version', 'authenticated', 'UPDATE'),
      ('profiles', 'public_id', 'authenticated', 'INSERT'),
      ('profiles', 'public_id', 'authenticated', 'SELECT'),
      ('profiles', 'public_id', 'authenticated', 'UPDATE'),
      ('profiles', 'updated_at', 'authenticated', 'INSERT'),
      ('profiles', 'updated_at', 'authenticated', 'SELECT'),
      ('profiles', 'updated_at', 'authenticated', 'UPDATE'),
      ('profiles', 'user_id', 'authenticated', 'INSERT'),
      ('profiles', 'user_id', 'authenticated', 'SELECT'),
      ('profiles', 'user_id', 'authenticated', 'UPDATE'),
      ('profiles', 'workouts', 'authenticated', 'INSERT'),
      ('profiles', 'workouts', 'authenticated', 'SELECT'),
      ('profiles', 'workouts', 'authenticated', 'UPDATE'),
      ('profiles', 'xp', 'authenticated', 'INSERT'),
      ('profiles', 'xp', 'authenticated', 'SELECT'),
      ('profiles', 'xp', 'authenticated', 'UPDATE'),
      ('user_states', 'state', 'authenticated', 'INSERT'),
      ('user_states', 'state', 'authenticated', 'SELECT'),
      ('user_states', 'state', 'authenticated', 'UPDATE'),
      ('user_states', 'updated_at', 'authenticated', 'INSERT'),
      ('user_states', 'updated_at', 'authenticated', 'SELECT'),
      ('user_states', 'updated_at', 'authenticated', 'UPDATE'),
      ('user_states', 'user_id', 'authenticated', 'INSERT'),
      ('user_states', 'user_id', 'authenticated', 'SELECT'),
      ('user_states', 'user_id', 'authenticated', 'UPDATE')
  $q$,
  'public column privileges for anon/authenticated/PUBLIC match the snapshot'
);

-- ---------------------------------------------------------------------------
-- C. public functions: EXECUTE for authenticated, anon, PUBLIC
-- ---------------------------------------------------------------------------
select set_eq(
  $q$
    select exec_row.signature, exec_row.grantee
    from gymapp_fn_exec as exec_row
    where exec_row.schema_name = 'public'
      and exec_row.grantee = 'authenticated'
  $q$,
  $q$
    values
      ('public.commit_account_deletion_operation(text)', 'authenticated'),
      ('public.consume_account_deletion_grant(text)', 'authenticated'),
      ('public.garmin_create_device(text)', 'authenticated'),
      ('public.garmin_create_device_idempotent(uuid,uuid,text,text)', 'authenticated'),
      ('public.garmin_enqueue_plan(uuid,jsonb,uuid)', 'authenticated'),
      ('public.garmin_list_devices()', 'authenticated'),
      ('public.garmin_read_activity_only_workouts()', 'authenticated'),
      ('public.garmin_revoke_device(uuid)', 'authenticated'),
      ('public.garmin_rotate_device_token(uuid,text,bigint)', 'authenticated'),
      ('public.garmin_sync_activity_only_workouts(bigint,uuid,jsonb)', 'authenticated'),
      ('public.leaderboard_public_rows()', 'authenticated'),
      ('public.notification_register_installation(uuid,text,text,text,text,text,text,text,text)', 'authenticated'),
      ('public.notification_revoke_installation(uuid)', 'authenticated'),
      ('public.prepare_account_deletion()', 'authenticated'),
      ('public.require_live_session_for_account_deletion()', 'authenticated'),
      ('public.social_block_profile(text)', 'authenticated'),
      ('public.social_cancel_friend_request(text,bigint)', 'authenticated'),
      ('public.social_cancel_workout_invite(text,bigint)', 'authenticated'),
      ('public.social_dashboard()', 'authenticated'),
      ('public.social_friend_details(text)', 'authenticated'),
      ('public.social_friend_workout_detail_capability(text)', 'authenticated'),
      ('public.social_friend_workout_page(text,text,timestamp with time zone,integer)', 'authenticated'),
      ('public.social_my_friend_code()', 'authenticated'),
      ('public.social_remove_friend(text,bigint)', 'authenticated'),
      ('public.social_respond_friend_request(text,text,bigint)', 'authenticated'),
      ('public.social_respond_workout_invite(text,text,bigint)', 'authenticated'),
      ('public.social_send_friend_request(text)', 'authenticated'),
      ('public.social_send_workout_invite(text,uuid,jsonb)', 'authenticated'),
      ('public.social_sync_workout_durations(jsonb)', 'authenticated'),
      ('public.social_unblock_profile(text)', 'authenticated'),
      ('public.social_update_privacy(boolean,boolean,boolean,boolean,bigint)', 'authenticated'),
      ('public.social_update_workout_detail_privacy(boolean,bigint)', 'authenticated'),
      ('public.social_workout_detail_privacy()', 'authenticated'),
      ('public.social_workout_inbox()', 'authenticated'),
      ('public.social_workout_inbox_page(timestamp with time zone,text,boolean,integer)', 'authenticated'),
      ('public.social_workout_invite_plan(text,bigint)', 'authenticated')
  $q$,
  'authenticated EXECUTE on public functions matches the snapshot'
);

select is_empty(
  $q$
    select exec_row.signature
    from gymapp_fn_exec as exec_row
    where exec_row.schema_name = 'public'
      and exec_row.grantee = 'anon'
  $q$,
  'anon has EXECUTE on no public function'
);

select is_empty(
  $q$
    select exec_row.signature
    from gymapp_fn_exec as exec_row
    where exec_row.schema_name = 'public'
      and exec_row.grantee = 'PUBLIC'
  $q$,
  'PUBLIC has EXECUTE on no public function'
);

select is_empty(
  $q$
    select p.oid::pg_catalog.regprocedure
    from pg_catalog.pg_proc as p
    where p.pronamespace = 'public'::pg_catalog.regnamespace
      and p.proacl is null
  $q$,
  'no public function relies on the implicit default ACL (PUBLIC EXECUTE)'
);

-- ---------------------------------------------------------------------------
-- D. public functions: EXECUTE for service_role
-- ---------------------------------------------------------------------------
select set_eq(
  $q$
    select exec_row.signature, exec_row.grantee
    from gymapp_fn_exec as exec_row
    where exec_row.schema_name = 'public'
      and exec_row.grantee = 'service_role'
  $q$,
  $q$
    values
      ('public.edge_preauth_debit(text,text)', 'service_role'),
      ('public.enforce_profile_public_fields()', 'service_role'),
      ('public.garmin_ack_plan(text,uuid,bigint)', 'service_role'),
      ('public.garmin_fetch_pending_plan(text)', 'service_role'),
      ('public.garmin_gateway_preauth_debit(text,integer)', 'service_role'),
      ('public.garmin_quarantine_pending_plan(text,uuid,bigint,text)', 'service_role'),
      ('public.garmin_record_capability_use(text,smallint)', 'service_role'),
      ('public.leaderboard_public_rows()', 'service_role'),
      ('public.prepare_leaderboard_report()', 'service_role'),
      ('public.push_authorize_delivery_send(uuid,uuid)', 'service_role'),
      ('public.push_claim_deliveries(uuid,integer,integer)', 'service_role'),
      ('public.push_delivery_is_current(uuid,uuid)', 'service_role'),
      ('public.push_mark_delivered(uuid,uuid,integer)', 'service_role'),
      ('public.push_mark_retry(uuid,uuid,text,integer,integer,boolean,boolean)', 'service_role'),
      ('public.rls_auto_enable()', 'service_role'),
      ('public.safe_leaderboard_display_name(text)', 'service_role'),
      ('public.set_user_state_server_revision()', 'service_role'),
      ('public.social_apply_live_workout_operation(uuid,uuid,text,uuid,bigint,jsonb)', 'service_role'),
      ('public.social_cancel_live_workout(uuid,uuid,text,uuid,bigint)', 'service_role'),
      ('public.social_finish_live_workout(uuid,uuid,text,uuid,bigint)', 'service_role'),
      ('public.social_gateway_perimeter_debit(uuid,uuid)', 'service_role'),
      ('public.social_leave_live_workout(uuid,uuid,text,uuid,bigint)', 'service_role'),
      ('public.social_live_gateway_debit(uuid,uuid,text)', 'service_role'),
      ('public.social_live_workout_inbox(uuid,uuid)', 'service_role'),
      ('public.social_live_workout_snapshot(uuid,uuid,text)', 'service_role'),
      ('public.social_respond_live_workout_invite(uuid,uuid,text,text,bigint,uuid)', 'service_role'),
      ('public.social_send_live_workout_invite(uuid,uuid,text,uuid,jsonb)', 'service_role'),
      ('public.social_start_live_workout(uuid,uuid,text,bigint,uuid)', 'service_role')
  $q$,
  'service_role EXECUTE on public functions matches the snapshot'
);

-- ---------------------------------------------------------------------------
-- E. gymapp_private: closed to anon, authenticated, PUBLIC
-- ---------------------------------------------------------------------------
select is_empty(
  $q$
    select acl.privilege_type
    from pg_catalog.pg_namespace as ns
    cross join lateral pg_catalog.aclexplode(ns.nspacl) as acl
    where ns.nspname = 'gymapp_private'
      and (acl.grantee = 0
           or pg_catalog.pg_get_userbyid(acl.grantee)
              in ('anon', 'authenticated'))
  $q$,
  'schema gymapp_private grants nothing to anon, authenticated, or PUBLIC'
);

select ok(
  not pg_catalog.has_schema_privilege('anon', 'gymapp_private', 'USAGE,CREATE')
  and not pg_catalog.has_schema_privilege(
    'authenticated', 'gymapp_private', 'USAGE,CREATE'
  ),
  'anon and authenticated have no USAGE or CREATE on gymapp_private'
);

select is_empty(
  $q$
    select class_row.relname
    from pg_catalog.pg_class as class_row
    cross join lateral pg_catalog.aclexplode(class_row.relacl) as acl
    where class_row.relnamespace = 'gymapp_private'::pg_catalog.regnamespace
      and (acl.grantee = 0
           or pg_catalog.pg_get_userbyid(acl.grantee)
              in ('anon', 'authenticated'))
  $q$,
  'no gymapp_private relation (table, sequence, view) grants to client roles'
);

select is_empty(
  $q$
    select class_row.relname || '.' || attr.attname
    from pg_catalog.pg_attribute as attr
    join pg_catalog.pg_class as class_row on class_row.oid = attr.attrelid
    cross join lateral pg_catalog.aclexplode(attr.attacl) as acl
    where class_row.relnamespace = 'gymapp_private'::pg_catalog.regnamespace
      and (acl.grantee = 0
           or pg_catalog.pg_get_userbyid(acl.grantee)
              in ('anon', 'authenticated'))
  $q$,
  'no gymapp_private column carries a column-level grant to client roles'
);

-- The only client-executable gymapp_private functions are the two session
-- predicates that RLS policies call (reached through stored policy OIDs, not
-- through schema lookup). anon and PUBLIC must never appear here.
select set_eq(
  $q$
    select exec_row.signature, exec_row.grantee
    from gymapp_fn_exec as exec_row
    where exec_row.schema_name = 'gymapp_private'
      and exec_row.grantee in ('anon', 'authenticated', 'PUBLIC')
  $q$,
  $q$
    values
      ('gymapp_private.current_auth_session_is_live()', 'authenticated'),
      ('gymapp_private.realtime_has_current_auth_session()', 'authenticated')
  $q$,
  'gymapp_private functions executable by clients are exactly the RLS predicates'
);

-- ---------------------------------------------------------------------------
-- F. row level security on every table in public and gymapp_private
-- ---------------------------------------------------------------------------
select is_empty(
  $q$
    select ns.nspname || '.' || class_row.relname
    from pg_catalog.pg_class as class_row
    join pg_catalog.pg_namespace as ns on ns.oid = class_row.relnamespace
    where ns.nspname in ('public', 'gymapp_private')
      and class_row.relkind in ('r', 'p')
      and not class_row.relrowsecurity
  $q$,
  'every table in public and gymapp_private has row level security enabled'
);

-- Guards the check above against passing vacuously and pins the inventory:
-- adding a table means updating this count (and giving it RLS).
select set_eq(
  $q$
    select ns.nspname::text, pg_catalog.count(*)::text
    from pg_catalog.pg_class as class_row
    join pg_catalog.pg_namespace as ns on ns.oid = class_row.relnamespace
    where ns.nspname in ('public', 'gymapp_private')
      and class_row.relkind in ('r', 'p')
    group by ns.nspname
  $q$,
  $q$
    values
      ('public', '7'),
      ('gymapp_private', '28')
  $q$,
  'table inventory is 7 in public and 28 in gymapp_private'
);

-- relforcerowsecurity is the actual state, not a requirement for every table:
-- no public table forces RLS; these private tables do (owner is subject too).
select set_eq(
  $q$
    select ns.nspname::text, class_row.relname::text
    from pg_catalog.pg_class as class_row
    join pg_catalog.pg_namespace as ns on ns.oid = class_row.relnamespace
    where ns.nspname in ('public', 'gymapp_private')
      and class_row.relkind in ('r', 'p')
      and class_row.relforcerowsecurity
  $q$,
  $q$
    values
      ('gymapp_private', 'account_deletion_operations'),
      ('gymapp_private', 'activity_only_workout_sync_states'),
      ('gymapp_private', 'activity_only_workouts'),
      ('gymapp_private', 'garmin_gateway_preauth_buckets'),
      ('gymapp_private', 'social_friend_codes'),
      ('gymapp_private', 'user_state_progression'),
      ('gymapp_private', 'user_state_quarantine')
  $q$,
  'tables with FORCE ROW LEVEL SECURITY match the snapshot'
);

select * from finish();

rollback;
