grant usage on schema public to anon, authenticated;

grant select, insert, update on table public.garmin_devices to authenticated;
grant select, insert, update on table public.garmin_plans to authenticated;

grant select on table public.garmin_devices to anon;
grant select, update on table public.garmin_plans to anon;
