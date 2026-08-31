begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
begin
  if pg_catalog.to_regprocedure('gymapp_private.current_auth_session_is_live()') is null
     or pg_catalog.to_regprocedure('public.prepare_leaderboard_report()') is null
     or not exists (
       select 1 from pg_catalog.pg_policies
       where schemaname = 'public' and tablename = 'leaderboard_reports'
         and policyname = 'authenticated users can submit leaderboard reports'
         and cmd = 'INSERT'
     ) then
    raise exception 'Leaderboard report session prerequisites are missing.';
  end if;
end
$preflight$;

-- Authenticate the exact live session before any target-dependent work.
-- The existing predicate locks writable sessions against concurrent revocation.
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
  if caller_user_id is null
     or not gymapp_private.current_auth_session_is_live() then
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
  'Requires an exact live Auth session, serializes each reporter, and preserves bounded pending reports and server-owned fields.';

revoke all on function public.prepare_leaderboard_report()
  from public, anon, authenticated;

-- Keep the existing INSERT role, owner check, and column-level grants.
-- The trigger also enforces the session check for callers that bypass RLS.
alter policy "authenticated users can submit leaderboard reports"
  on public.leaderboard_reports
  with check (
    reporter_user_id = (select auth.uid())
    and (select gymapp_private.current_auth_session_is_live())
  );

notify pgrst, 'reload schema';

commit;
