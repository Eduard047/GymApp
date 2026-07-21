begin;

do $preflight$
begin
  if pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regclass('public.leaderboard_public') is null
     or pg_catalog.to_regclass('gymapp_private.user_state_quarantine') is null
     or pg_catalog.to_regprocedure('public.safe_leaderboard_display_name(text)') is null then
    raise exception 'GymApp leaderboard hardening prerequisites are missing';
  end if;
end
$preflight$;

-- Workout history in public.user_states is a private synchronization snapshot
-- authored by the account's clients. Shape validation and canonical XP math do
-- not prove that those workouts happened, so it must not drive a cross-account
-- ranking. Keep the existing API contract available to every released client,
-- but return only the caller's own row until GymApp has a trusted, append-only
-- workout receipt source. This removes the public integrity sink without
-- deleting or rewriting anyone's private workout history.
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
stable
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
  where profile.user_id = (select auth.uid())
    and not exists (
      select 1
      from gymapp_private.user_state_quarantine as quarantine
      where quarantine.user_id = profile.user_id
    )
$function$;

comment on function public.leaderboard_public_rows() is
  'Owner-only compatibility projection. Cross-account ranking stays disabled until progression comes from a trusted append-only receipt source rather than client-authored user_states.';

revoke all on function public.leaderboard_public_rows()
  from public, anon, authenticated;
grant execute on function public.leaderboard_public_rows()
  to authenticated, service_role;

-- The wrapper view keeps its existing six-field response shape and grants, so
-- Android, iOS, and PWA releases fail safe without a coordinated client rollout.
revoke all on table public.leaderboard_public
  from public, anon, authenticated;
grant select on table public.leaderboard_public
  to authenticated, service_role;

do $verify$
begin
  if exists (select 1 from public.leaderboard_public_rows()) then
    raise exception 'The owner-only leaderboard returned rows without an authenticated owner';
  end if;
  if has_function_privilege('anon', 'public.leaderboard_public_rows()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.leaderboard_public_rows()', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.leaderboard_public_rows()', 'EXECUTE')
     or has_table_privilege('anon', 'public.leaderboard_public', 'SELECT')
     or not has_table_privilege('authenticated', 'public.leaderboard_public', 'SELECT')
     or not has_table_privilege('service_role', 'public.leaderboard_public', 'SELECT') then
    raise exception 'GymApp owner-only leaderboard grants are not least privilege';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
