create or replace function public.garmin_fetch_pending_plan(p_device_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  found_device public.garmin_devices%rowtype;
  found_plan public.garmin_plans%rowtype;
begin
  select *
  into found_device
  from public.garmin_devices
  where device_token = p_device_token
    and revoked_at is null
  limit 1;

  if not found then
    return jsonb_build_object('error', 'Invalid device');
  end if;

  update public.garmin_devices
  set last_seen_at = now()
  where id = found_device.id;

  select *
  into found_plan
  from public.garmin_plans
  where user_id = found_device.user_id
    and status = 'pending'
  order by created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('status', 'empty');
  end if;

  update public.garmin_plans
  set
    status = 'downloaded',
    device_id = found_device.id,
    downloaded_at = now()
  where id = found_plan.id;

  return jsonb_build_object(
    'status', 'ok',
    'planId', found_plan.id,
    'plan', found_plan.plan
  );
end;
$$;

revoke all on function public.garmin_fetch_pending_plan(text) from public;
grant execute on function public.garmin_fetch_pending_plan(text) to anon, authenticated;
