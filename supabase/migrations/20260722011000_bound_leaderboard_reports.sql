begin;

-- Keep the trigger replacement and its supporting index atomic. A regular
-- index build blocks writes after it acquires its table lock, so bound both the
-- acquisition wait and total build time. Deploy this migration during a
-- reviewed low-traffic window; if either limit is exceeded PostgreSQL rolls the
-- transaction back for a later retry instead of extending the write outage.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
declare
  missing_columns text;
begin
  if pg_catalog.to_regclass('public.leaderboard_reports') is null
     or pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regprocedure('public.prepare_leaderboard_report()') is null
     or pg_catalog.to_regprocedure('public.safe_leaderboard_display_name(text)') is null then
    raise exception 'GymApp leaderboard report bounding prerequisites are missing';
  end if;

  select pg_catalog.string_agg(required.column_name, ', ' order by required.column_name)
    into missing_columns
  from (
    values
      ('reporter_user_id'),
      ('reported_profile_id'),
      ('reported_display_name'),
      ('reason'),
      ('status'),
      ('created_at')
  ) as required(column_name)
  where not exists (
    select 1
    from information_schema.columns as column_definition
    where column_definition.table_schema = 'public'
      and column_definition.table_name = 'leaderboard_reports'
      and column_definition.column_name = required.column_name
  );

  if missing_columns is not null then
    raise exception
      'Cannot bound leaderboard reports; missing columns: %',
      missing_columns;
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger as report_trigger
    join pg_catalog.pg_proc as routine
      on routine.oid = report_trigger.tgfoid
    join pg_catalog.pg_namespace as routine_schema
      on routine_schema.oid = routine.pronamespace
    where report_trigger.tgrelid = 'public.leaderboard_reports'::pg_catalog.regclass
      and report_trigger.tgname = 'leaderboard_reports_prepare_insert'
      and not report_trigger.tgisinternal
      and report_trigger.tgenabled <> 'D'
      and routine_schema.nspname = 'public'
      and routine.proname = 'prepare_leaderboard_report'
  ) then
    raise exception 'Leaderboard report preparation trigger is missing or disabled';
  end if;
end
$preflight$;

-- Existing rows are retained exactly as they are. This partial index keeps the
-- post-lock pending lookup bounded even if the legacy queue already contains
-- several snapshots for the same reporter, target, and reason.
create index leaderboard_reports_pending_reporter_target_reason_idx
  on public.leaderboard_reports (
    reporter_user_id,
    reported_profile_id,
    reason
  )
  where status = 'pending';

create or replace function public.prepare_leaderboard_report()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  target_user_id uuid;
  target_display_name text;
begin
  caller_user_id := auth.uid();
  if caller_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required to report a leaderboard profile.';
  end if;

  if new.reason is null
     or new.reason not in (
       'inappropriate_name',
       'hate_or_harassment',
       'impersonation',
       'spam_or_scam',
       'personal_information',
       'other'
     ) then
    raise exception using
      errcode = '23514',
      message = 'Leaderboard report reason is invalid.';
  end if;

  -- Serialize every admission from this authenticated reporter before doing
  -- any target-dependent work. A transaction may insert several rows in any
  -- target order; one reporter-wide, transaction-scoped lock is re-entrant for
  -- that whole batch, so reversed batches cannot form an A->B / B->A lock
  -- cycle. Different reporters retain independent lock domains (apart from a
  -- harmless hash collision, which only adds serialization).
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_user_id::text, 719924)
  );

  select
    profile.user_id,
    coalesce(
      public.safe_leaderboard_display_name(profile.display_name::text),
      'GymApp user'
    )
  into target_user_id, target_display_name
  from public.profiles as profile
  where profile.public_id = new.reported_profile_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'The reported leaderboard profile does not exist.';
  end if;

  if target_user_id = caller_user_id then
    raise exception using
      errcode = '23514',
      message = 'A profile cannot report itself.';
  end if;

  -- One pending row per fixed reason gives a hard six-row bound for this
  -- reporter/target pair. A trusted moderator may resolve a row, after which a
  -- later changed display name can legitimately be reported under that reason.
  if exists (
    select 1
    from public.leaderboard_reports as report
    where report.reporter_user_id = caller_user_id
      and report.reported_profile_id = new.reported_profile_id
      and report.reason = new.reason
      and report.status = 'pending'
  ) then
    raise exception using
      errcode = '23505',
      message = 'Duplicate pending leaderboard report.';
  end if;

  new.id := 'r_' || replace(pg_catalog.gen_random_uuid()::text, '-', '');
  new.reporter_user_id := caller_user_id;
  new.reported_display_name := target_display_name;
  new.status := 'pending';
  new.created_at := pg_catalog.clock_timestamp();
  return new;
end
$function$;

comment on function public.prepare_leaderboard_report() is
  'Serializes each authenticated reporter, rejects self-reports, snapshots the filtered target name, and admits at most one pending row per reporter, target, and fixed reason.';

-- The function remains a trigger-only privileged boundary. Reassert the
-- original direct-execution restriction after replacing its body.
revoke all on function public.prepare_leaderboard_report()
  from public, anon, authenticated;

do $verify$
begin
  if pg_catalog.to_regclass(
      'public.leaderboard_reports_pending_reporter_target_reason_idx'
    ) is null then
    raise exception 'Leaderboard pending-report lookup index is missing';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as relation_schema
      on relation_schema.oid = relation.relnamespace
    where relation_schema.nspname = 'public'
      and relation.relname = 'leaderboard_reports'
      and relation.relkind = 'r'
      and relation.relrowsecurity
  ) then
    raise exception 'Leaderboard report RLS is not enabled';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_policies as policy
    where policy.schemaname = 'public'
      and policy.tablename = 'leaderboard_reports'
      and policy.policyname = 'authenticated users can submit leaderboard reports'
      and policy.cmd = 'INSERT'
      and policy.roles = array['authenticated']::name[]
  ) then
    raise exception 'Leaderboard report insert policy changed unexpectedly';
  end if;

  if pg_catalog.has_function_privilege(
      'anon',
      'public.prepare_leaderboard_report()',
      'EXECUTE'
    )
    or pg_catalog.has_function_privilege(
      'authenticated',
      'public.prepare_leaderboard_report()',
      'EXECUTE'
    ) then
    raise exception 'Leaderboard report trigger function is client-executable';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.leaderboard_reports', 'SELECT')
    or pg_catalog.has_table_privilege('anon', 'public.leaderboard_reports', 'INSERT')
    or pg_catalog.has_table_privilege('anon', 'public.leaderboard_reports', 'UPDATE')
    or pg_catalog.has_table_privilege('anon', 'public.leaderboard_reports', 'DELETE')
    or pg_catalog.has_any_column_privilege('anon', 'public.leaderboard_reports', 'SELECT')
    or pg_catalog.has_any_column_privilege('anon', 'public.leaderboard_reports', 'INSERT')
    or pg_catalog.has_any_column_privilege('anon', 'public.leaderboard_reports', 'UPDATE') then
    raise exception 'Anonymous leaderboard report privileges changed unexpectedly';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.leaderboard_reports', 'SELECT')
    or pg_catalog.has_table_privilege('authenticated', 'public.leaderboard_reports', 'INSERT')
    or pg_catalog.has_table_privilege('authenticated', 'public.leaderboard_reports', 'UPDATE')
    or pg_catalog.has_table_privilege('authenticated', 'public.leaderboard_reports', 'DELETE')
    or pg_catalog.has_any_column_privilege(
      'authenticated',
      'public.leaderboard_reports',
      'SELECT'
    )
    or pg_catalog.has_any_column_privilege(
      'authenticated',
      'public.leaderboard_reports',
      'UPDATE'
    )
    or not pg_catalog.has_column_privilege(
      'authenticated',
      'public.leaderboard_reports',
      'reported_profile_id',
      'INSERT'
    )
    or not pg_catalog.has_column_privilege(
      'authenticated',
      'public.leaderboard_reports',
      'reason',
      'INSERT'
    )
    or pg_catalog.has_column_privilege(
      'authenticated',
      'public.leaderboard_reports',
      'reporter_user_id',
      'INSERT'
    )
    or pg_catalog.has_column_privilege(
      'authenticated',
      'public.leaderboard_reports',
      'reported_display_name',
      'INSERT'
    )
    or pg_catalog.has_column_privilege(
      'authenticated',
      'public.leaderboard_reports',
      'status',
      'INSERT'
    ) then
    raise exception 'Authenticated leaderboard report privileges changed unexpectedly';
  end if;

  if not pg_catalog.has_table_privilege(
      'service_role',
      'public.leaderboard_reports',
      'SELECT'
    )
    or not pg_catalog.has_table_privilege(
      'service_role',
      'public.leaderboard_reports',
      'INSERT'
    )
    or not pg_catalog.has_table_privilege(
      'service_role',
      'public.leaderboard_reports',
      'UPDATE'
    )
    or not pg_catalog.has_table_privilege(
      'service_role',
      'public.leaderboard_reports',
      'DELETE'
    ) then
    raise exception 'Trusted moderation privileges changed unexpectedly';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
