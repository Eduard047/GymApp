begin;

create or replace function gymapp_private.guard_live_workout_room()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if new.id is distinct from old.id
     or new.owner_user_id is distinct from old.owner_user_id
     or new.client_request_id is distinct from old.client_request_id
     or new.created_at is distinct from old.created_at
     or new.invite_expires_at is distinct from old.invite_expires_at then
    raise exception using errcode = '42501', message = 'Live workout room identity is immutable.';
  end if;

  if new.plan is distinct from old.plan
     or new.summary is distinct from old.summary then
    if not (
      old.payload_purged_at is null
      and new.payload_purged_at is not null
      and new.plan is null
      and new.summary is null
      and new.status in ('completed', 'cancelled', 'expired')
    ) then
      raise exception using errcode = '42501', message = 'Live workout plan is immutable.';
    end if;
  end if;

  if new.revision <> old.revision + 1 then
    raise exception using errcode = '40001', message = 'Live workout room revision must advance exactly once.';
  end if;
  if new.last_activity_at < old.last_activity_at
     or new.updated_at < old.updated_at then
    raise exception using errcode = '22023', message = 'Live workout room time cannot move backwards.';
  end if;

  if not (
    new.status = old.status
    or (old.status = 'waiting' and new.status in ('ready', 'cancelled', 'expired'))
    or (
      old.status = 'waiting'
      and new.status = 'active'
      and old.started_at is null
      and old.active_expires_at is null
      and old.ended_at is null
      and old.close_reason is null
      and new.started_at is not null
      and new.active_expires_at = new.started_at + interval '24 hours'
      and new.ended_at is null
      and new.close_reason is null
    )
    or (old.status = 'ready' and new.status in ('active', 'cancelled', 'expired'))
    or (old.status = 'active' and new.status in ('completed', 'cancelled', 'expired'))
  ) then
    raise exception using errcode = '42501', message = 'Live workout room transition is invalid.';
  end if;
  return new;
end
$function$;

revoke all on function gymapp_private.guard_live_workout_room()
  from public, anon, authenticated, service_role;

commit;
