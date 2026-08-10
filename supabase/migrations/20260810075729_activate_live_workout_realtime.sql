begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

-- Realtime owns its schema. Since Realtime v2.112.7, custom DDL there is
-- forbidden except RLS policy management on realtime.messages. All helper
-- functions and triggers therefore remain in gymapp_private.
do $preflight$
declare
  authenticated_role_oid oid;
begin
  if pg_catalog.to_regclass('realtime.messages') is null
     or pg_catalog.to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null
     or pg_catalog.to_regclass('gymapp_private.live_workout_rooms') is null
     or pg_catalog.to_regclass('gymapp_private.live_workout_members') is null then
    raise exception 'GymApp live-workout Realtime prerequisites are missing.';
  end if;
  select role.oid into strict authenticated_role_oid
  from pg_catalog.pg_roles as role
  where role.rolname = 'authenticated';
  if exists (
    select 1
    from pg_catalog.pg_policy as policy
    where policy.polrelid = 'realtime.messages'::pg_catalog.regclass
      and policy.polcmd in ('r', '*')
      and (
        policy.polroles = array[0::oid]
        or authenticated_role_oid = any(policy.polroles)
      )
  ) then
    raise exception 'Competing authenticated Realtime SELECT policies must be removed before live-workout activation.';
  end if;
end
$preflight$;

-- A signed but administratively revoked JWT is not enough: bind every channel
-- authorization/re-authorization to the exact session_id that still exists in
-- auth.sessions. Supabase Realtime caches channel authorization, so an already
-- subscribed connection can still receive an opaque invalidation hint until
-- it disconnects or presents a refreshed JWT. Authoritative polls and every
-- live RPC independently recheck the current session and return no room data.
create or replace function gymapp_private.realtime_has_current_auth_session()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and gymapp_private.has_current_auth_session((select auth.uid()))
$function$;

revoke all on function gymapp_private.realtime_has_current_auth_session()
  from public, anon, authenticated, service_role;
grant execute on function gymapp_private.realtime_has_current_auth_session()
  to authenticated;

create policy gymapp_live_broadcast_personal_read
on realtime.messages
for select
to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and (select gymapp_private.realtime_has_current_auth_session())
  and (select realtime.topic()) = 'gymapp:user:' || (select auth.uid())::text
);

create or replace function gymapp_private.broadcast_live_workout_room(
  p_room_id text,
  p_kind text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_revision bigint;
  recipient record;
begin
  if p_room_id is null
     or p_room_id !~ '^lr_[0-9a-f]{32}$'
     or p_kind not in (
       'invite', 'joined', 'started', 'progress',
       'participant_finished', 'room_closed'
     ) then
    raise exception using errcode = '22023', message = 'Live workout Broadcast is invalid.';
  end if;

  select room.revision into room_revision
  from gymapp_private.live_workout_rooms as room
  where room.id = p_room_id;
  if not found then
    return;
  end if;

  for recipient in
    select member.user_id
    from gymapp_private.live_workout_members as member
    where member.room_id = p_room_id
    order by member.user_id
  loop
    perform realtime.send(
      pg_catalog.jsonb_build_object(
        'version', 1,
        'kind', p_kind,
        'roomId', p_room_id,
        'roomRevision', room_revision
      ),
      'gymapp_live_changed',
      'gymapp:user:' || recipient.user_id::text,
      true
    );
  end loop;
end
$function$;

revoke all on function gymapp_private.broadcast_live_workout_room(text, text)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.broadcast_live_workout_room_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  event_kind text;
begin
  event_kind := case
    when new.status = 'ready' and old.status = 'waiting' then 'joined'
    when new.status = 'active' and old.status = 'ready' then 'started'
    when new.status in ('completed', 'cancelled', 'expired') then 'room_closed'
    else 'progress'
  end;
  perform gymapp_private.broadcast_live_workout_room(new.id, event_kind);
  return new;
end
$function$;

revoke all on function gymapp_private.broadcast_live_workout_room_change()
  from public, anon, authenticated, service_role;

create trigger live_workout_rooms_broadcast_change
after update on gymapp_private.live_workout_rooms
for each row
when (old.revision is distinct from new.revision)
execute function gymapp_private.broadcast_live_workout_room_change();

create or replace function gymapp_private.broadcast_live_workout_member_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  event_kind text;
begin
  if tg_op = 'INSERT' then
    if new.role <> 'participant' or new.state <> 'invited' then
      return new;
    end if;
    event_kind := 'invite';
  elsif old.state = 'invited' and new.state = 'joined' then
    event_kind := 'joined';
  elsif old.state = 'joined' and new.state = 'finished' then
    event_kind := 'participant_finished';
  elsif new.state in ('left', 'revoked') then
    event_kind := 'room_closed';
  else
    return new;
  end if;

  perform gymapp_private.broadcast_live_workout_room(new.room_id, event_kind);
  return new;
end
$function$;

revoke all on function gymapp_private.broadcast_live_workout_member_change()
  from public, anon, authenticated, service_role;

create trigger live_workout_members_broadcast_change
after insert or update on gymapp_private.live_workout_members
for each row execute function gymapp_private.broadcast_live_workout_member_change();

do $verify$
declare
  authenticated_role_oid oid;
begin
  select role.oid into strict authenticated_role_oid
  from pg_catalog.pg_roles as role
  where role.rolname = 'authenticated';

  if not exists (
    select 1
    from pg_catalog.pg_policy as policy
    where policy.polrelid = 'realtime.messages'::pg_catalog.regclass
      and policy.polname = 'gymapp_live_broadcast_personal_read'
      and policy.polcmd = 'r'
      and authenticated_role_oid = any(policy.polroles)
  ) then
    raise exception 'GymApp personal Realtime read policy was not installed.';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_policy as policy
    where policy.polrelid = 'realtime.messages'::pg_catalog.regclass
      and policy.polcmd in ('r', '*')
      and (
        policy.polroles = array[0::oid]
        or authenticated_role_oid = any(policy.polroles)
      )
  ) <> 1 then
    raise exception 'GymApp personal Realtime read policy is not the sole authenticated SELECT boundary.';
  end if;

  -- Live clients never send Broadcast. Refuse activation if another policy
  -- would let authenticated/PUBLIC insert and spoof a progress or lifecycle
  -- invalidation on this project.
  if exists (
    select 1
    from pg_catalog.pg_policy as policy
    where policy.polrelid = 'realtime.messages'::pg_catalog.regclass
      and policy.polcmd in ('a', '*')
      and (
        policy.polroles = array[0::oid]
        or authenticated_role_oid = any(policy.polroles)
      )
  ) then
    raise exception 'Authenticated Realtime Broadcast INSERT policy must be removed before live-workout activation.';
  end if;

  if pg_catalog.has_function_privilege(
       'authenticated',
       'gymapp_private.broadcast_live_workout_room(text,text)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'gymapp_private.realtime_has_current_auth_session()',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'gymapp_private.realtime_has_current_auth_session()',
       'EXECUTE'
     ) then
    raise exception 'Live-workout Broadcast helper is directly callable.';
  end if;
end
$verify$;

commit;
