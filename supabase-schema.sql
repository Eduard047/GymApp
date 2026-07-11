-- RETIRED: do not use this former monolithic snapshot.
--
-- GymApp production is migration-managed. The old snapshot could recreate a
-- permissive cross-user profiles policy, the legacy owner-view leaderboard, and
-- anonymous Garmin table grants after the privacy hardening migrations.
--
-- Apply every ordered file in supabase/migrations instead. This fail-closed stub
-- intentionally makes accidental SQL Editor execution non-destructive.

do $retired_schema$
begin
  raise exception using
    errcode = 'P0001',
    message = 'supabase-schema.sql is retired; apply the ordered supabase/migrations files instead';
end
$retired_schema$;
