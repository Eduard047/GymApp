-- Retired before production deployment.
--
-- The current Garmin bridge fetches plans through the narrowly scoped
-- garmin_fetch_pending_plan RPC. Direct anonymous table grants would conflict
-- with the later production privacy hardening. Keep this historical version as a
-- safe revoke so a migration push cannot restore those grants.

revoke select on table public.garmin_devices from anon;
revoke select, update on table public.garmin_plans from anon;
