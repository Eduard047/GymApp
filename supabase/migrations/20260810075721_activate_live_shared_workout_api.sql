begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

-- New live-workout endpoints are intentionally not user-token RPCs. A
-- user-authenticated Edge gateway verifies the bearer, extracts its signed
-- session_id, commits a separate perimeter debit, and then invokes these
-- service-role-only functions with the exact user/session pair.
do $preflight$
begin
  if pg_catalog.to_regclass('gymapp_private.live_workout_rooms') is null
     or pg_catalog.to_regclass('gymapp_private.live_workout_members') is null
     or pg_catalog.to_regclass('gymapp_private.live_workout_progress') is null
     or pg_catalog.to_regclass('gymapp_private.live_workout_operation_receipts') is null
     or pg_catalog.to_regprocedure('gymapp_private.validate_live_workout_plan(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_pair_is_accepted(uuid,uuid)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_lock_pair(uuid,uuid)') is null then
    raise exception 'GymApp live-workout storage prerequisites are missing.';
  end if;
end
$preflight$;

create or replace function gymapp_private.live_gateway_require_session(
  p_caller_user_id uuid,
  p_session_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if p_caller_user_id is null
     or p_session_id is null
     or not exists (
       select 1
       from auth.sessions as session
       where session.id = p_session_id
         and session.user_id = p_caller_user_id
     ) then
    raise exception using errcode = '42501', message = 'A current authenticated session is required.';
  end if;
end
$function$;

revoke all on function gymapp_private.live_gateway_require_session(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.live_workout_receipt_replay(
  p_room_id text,
  p_user_id uuid,
  p_client_operation_id uuid,
  p_request jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  receipt_row record;
begin
  select receipt.request, receipt.result
  into receipt_row
  from gymapp_private.live_workout_operation_receipts as receipt
  where receipt.room_id = p_room_id
    and receipt.user_id = p_user_id
    and receipt.client_operation_id = p_client_operation_id;

  if not found then
    return null;
  end if;
  if receipt_row.request is distinct from p_request then
    raise exception using errcode = '22023', message = 'Client operation id was reused with a different request.';
  end if;
  return receipt_row.result;
end
$function$;

revoke all on function gymapp_private.live_workout_receipt_replay(text, uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.live_workout_store_receipt(
  p_room_id text,
  p_user_id uuid,
  p_client_operation_id uuid,
  p_request jsonb,
  p_result jsonb
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  receipt_count integer;
begin
  select pg_catalog.count(*)::integer
  into receipt_count
  from gymapp_private.live_workout_operation_receipts as receipt
  where receipt.room_id = p_room_id
    and receipt.user_id = p_user_id;
  if receipt_count >= 512 then
    raise exception using errcode = 'P0001', message = 'Live workout operation receipt limit reached.';
  end if;
  insert into gymapp_private.live_workout_operation_receipts (
    room_id, user_id, client_operation_id, request, result
  ) values (
    p_room_id, p_user_id, p_client_operation_id, p_request, p_result
  );
end
$function$;

revoke all on function gymapp_private.live_workout_store_receipt(text, uuid, uuid, jsonb, jsonb)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.live_workout_lock_pair_for_room(
  p_room_id text,
  p_caller_user_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  peer_user_id uuid;
begin
  select peer.user_id
  into peer_user_id
  from gymapp_private.live_workout_members as caller
  join gymapp_private.live_workout_members as peer
    on peer.room_id = caller.room_id
   and peer.user_id <> caller.user_id
  where caller.room_id = p_room_id
    and caller.user_id = p_caller_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  perform gymapp_private.social_lock_pair(p_caller_user_id, peer_user_id);
  return peer_user_id;
end
$function$;

revoke all on function gymapp_private.live_workout_lock_pair_for_room(text, uuid)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.close_live_workout_rooms_for_pair(
  p_first_user_id uuid,
  p_second_user_id uuid,
  p_reason text
)
returns integer
language plpgsql
volatile
strict
security definer
set search_path = ''
as $function$
declare
  room_row record;
  close_time timestamptz := pg_catalog.clock_timestamp();
  closed_count integer := 0;
begin
  if p_first_user_id = p_second_user_id
     or p_reason not in ('friend_removed', 'blocked', 'account_deleted') then
    raise exception using errcode = '22023', message = 'Live workout pair closure is invalid.';
  end if;

  for room_row in
    select room.id
    from gymapp_private.live_workout_rooms as room
    where room.status in ('waiting', 'ready', 'active')
      and exists (
        select 1
        from gymapp_private.live_workout_members as first_member
        where first_member.room_id = room.id
          and first_member.user_id = p_first_user_id
      )
      and exists (
        select 1
        from gymapp_private.live_workout_members as second_member
        where second_member.room_id = room.id
          and second_member.user_id = p_second_user_id
      )
    order by room.id
    for update of room
  loop
    update gymapp_private.live_workout_rooms as room
    set status = 'cancelled',
        close_reason = p_reason,
        revision = room.revision + 1,
        ended_at = close_time,
        last_activity_at = greatest(room.last_activity_at, close_time),
        updated_at = close_time
    where room.id = room_row.id;

    update gymapp_private.live_workout_members as member
    set state = 'revoked',
        revision = member.revision + 1,
        departed_at = close_time,
        updated_at = close_time
    where member.room_id = room_row.id
      and member.state in ('invited', 'joined');
    closed_count := closed_count + 1;
  end loop;
  return closed_count;
end
$function$;

revoke all on function gymapp_private.close_live_workout_rooms_for_pair(uuid, uuid, text)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.cleanup_live_workouts(
  p_limit integer default 100
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  cleanup_time timestamptz := pg_catalog.clock_timestamp();
  room_row record;
  expired_count integer := 0;
  purged_count integer := 0;
  deleted_count integer := 0;
begin
  if p_limit is null or p_limit not between 1 and 500 then
    raise exception using errcode = '22023', message = 'Live workout cleanup limit is invalid.';
  end if;

  for room_row in
    select room.id
    from gymapp_private.live_workout_rooms as room
    where (
      room.status in ('waiting', 'ready')
      and room.invite_expires_at <= cleanup_time
    ) or (
      room.status = 'active'
      and room.active_expires_at <= cleanup_time
    )
    order by case when room.status = 'active'
      then room.active_expires_at else room.invite_expires_at end, room.id
    limit p_limit
    for update of room skip locked
  loop
    update gymapp_private.live_workout_rooms as room
    set status = 'expired',
        close_reason = 'expired',
        revision = room.revision + 1,
        ended_at = cleanup_time,
        last_activity_at = greatest(room.last_activity_at, cleanup_time),
        updated_at = cleanup_time
    where room.id = room_row.id;
    update gymapp_private.live_workout_members as member
    set state = 'revoked',
        revision = member.revision + 1,
        departed_at = cleanup_time,
        updated_at = cleanup_time
    where member.room_id = room_row.id
      and member.state in ('invited', 'joined');
    expired_count := expired_count + 1;
  end loop;

  for room_row in
    select room.id
    from gymapp_private.live_workout_rooms as room
    where room.plan is not null
      and (
        (room.status = 'completed' and room.ended_at <= cleanup_time - interval '30 days')
        or (
          room.status in ('cancelled', 'expired')
          and room.ended_at <= cleanup_time - interval '24 hours'
        )
      )
    order by room.ended_at, room.id
    limit p_limit
    for update of room skip locked
  loop
    delete from gymapp_private.live_workout_operation_receipts as receipt
    where receipt.room_id = room_row.id;
    delete from gymapp_private.live_workout_progress as progress
    where progress.room_id = room_row.id;
    update gymapp_private.live_workout_rooms as room
    set plan = null,
        summary = null,
        payload_purged_at = cleanup_time,
        revision = room.revision + 1,
        updated_at = cleanup_time
    where room.id = room_row.id;
    purged_count := purged_count + 1;
  end loop;

  with delete_candidates as (
    select room.id
    from gymapp_private.live_workout_rooms as room
    where room.status in ('completed', 'cancelled', 'expired')
      and room.ended_at <= cleanup_time - interval '31 days'
    order by room.ended_at, room.id
    limit p_limit
    for update skip locked
  ), deleted as (
    delete from gymapp_private.live_workout_rooms as room
    using delete_candidates as candidate
    where room.id = candidate.id
    returning room.id
  )
  select pg_catalog.count(*)::integer into deleted_count from deleted;

  return pg_catalog.jsonb_build_object(
    'expired', expired_count,
    'purged', purged_count,
    'deleted', deleted_count
  );
end
$function$;

revoke all on function gymapp_private.cleanup_live_workouts(integer)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.live_workout_snapshot_for(
  p_caller_user_id uuid,
  p_room_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  room_row record;
  peer_user_id uuid;
  participants_json jsonb;
begin
  select room.*
  into room_row
  from gymapp_private.live_workout_rooms as room
  where room.id = p_room_id
    and room.plan is not null
    and exists (
      select 1
      from gymapp_private.live_workout_members as member
      where member.room_id = room.id
        and member.user_id = p_caller_user_id
    );
  if not found then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;

  select member.user_id
  into peer_user_id
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
    and member.user_id <> p_caller_user_id;
  if not found
     or not gymapp_private.social_pair_is_accepted(p_caller_user_id, peer_user_id) then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;

  select pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'isSelf', member.user_id = p_caller_user_id,
      'profile', pg_catalog.jsonb_build_object(
        'profileId', profile.public_id,
        'displayName', gymapp_private.social_safe_display_name(profile.display_name)
      ),
      'role', member.role,
      'state', member.state,
      'membershipRevision', member.revision,
      'joinedAt', member.joined_at,
      'finishedAt', member.finished_at,
      'departedAt', member.departed_at,
      'progress', case when progress.room_id is null then null else
        progress.payload || pg_catalog.jsonb_build_object('revision', progress.revision)
      end
    ) order by case when member.role = 'owner' then 0 else 1 end
  )
  into participants_json
  from gymapp_private.live_workout_members as member
  join public.profiles as profile on profile.user_id = member.user_id
  left join gymapp_private.live_workout_progress as progress
    on progress.room_id = member.room_id
   and progress.user_id = member.user_id
  where member.room_id = p_room_id;

  if participants_json is null
     or pg_catalog.jsonb_array_length(participants_json) <> 2 then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'room', pg_catalog.jsonb_build_object(
      'roomId', room_row.id,
      'status', room_row.status,
      'roomRevision', room_row.revision,
      'closeReason', room_row.close_reason,
      'createdAt', room_row.created_at,
      'inviteExpiresAt', room_row.invite_expires_at,
      'startedAt', room_row.started_at,
      'activeExpiresAt', room_row.active_expires_at,
      'endedAt', room_row.ended_at,
      'summary', room_row.summary
    ),
    'plan', room_row.plan,
    'participants', participants_json
  );
end
$function$;

revoke all on function gymapp_private.live_workout_snapshot_for(uuid, text)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.friendship_close_live_workouts()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform gymapp_private.close_live_workout_rooms_for_pair(
    new.user_low_id, new.user_high_id, 'friend_removed'
  );
  return new;
end
$function$;

revoke all on function gymapp_private.friendship_close_live_workouts()
  from public, anon, authenticated, service_role;

create trigger friendships_close_live_workouts
after update of status on gymapp_private.friendships
for each row
when (old.status = 'accepted' and new.status <> 'accepted')
execute function gymapp_private.friendship_close_live_workouts();

create or replace function gymapp_private.block_close_live_workouts()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform gymapp_private.close_live_workout_rooms_for_pair(
    new.blocker_user_id, new.blocked_user_id, 'blocked'
  );
  return new;
end
$function$;

revoke all on function gymapp_private.block_close_live_workouts()
  from public, anon, authenticated, service_role;

create trigger friend_blocks_close_live_workouts
after insert on gymapp_private.friend_blocks
for each row execute function gymapp_private.block_close_live_workouts();

create or replace function gymapp_private.auth_user_close_live_workouts()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_row record;
  peer_user_id uuid;
begin
  for room_row in
    select room.id
    from gymapp_private.live_workout_rooms as room
    join gymapp_private.live_workout_members as member
      on member.room_id = room.id
     and member.user_id = old.id
    where room.status in ('waiting', 'ready', 'active')
    order by room.id
    for update of room
  loop
    select member.user_id into peer_user_id
    from gymapp_private.live_workout_members as member
    where member.room_id = room_row.id
      and member.user_id <> old.id;
    if found then
      perform gymapp_private.close_live_workout_rooms_for_pair(
        old.id, peer_user_id, 'account_deleted'
      );
    end if;
  end loop;
  return old;
end
$function$;

revoke all on function gymapp_private.auth_user_close_live_workouts()
  from public, anon, authenticated, service_role;

create trigger auth_users_close_live_workouts
before delete on auth.users
for each row execute function gymapp_private.auth_user_close_live_workouts();

create or replace function public.social_live_workout_inbox(
  p_caller_user_id uuid,
  p_session_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  invitations_json jsonb;
  rooms_json jsonb;
  read_time timestamptz := pg_catalog.clock_timestamp();
begin
  perform gymapp_private.live_gateway_require_session(p_caller_user_id, p_session_id);

  with invitations as (
    select
      room.id,
      room.status,
      room.revision,
      room.created_at,
      room.invite_expires_at,
      room.summary,
      profile.public_id,
      gymapp_private.social_safe_display_name(profile.display_name) as display_name
    from gymapp_private.live_workout_members as caller
    join gymapp_private.live_workout_rooms as room on room.id = caller.room_id
    join gymapp_private.live_workout_members as owner_member
      on owner_member.room_id = room.id
     and owner_member.role = 'owner'
    join public.profiles as profile on profile.user_id = owner_member.user_id
    where caller.user_id = p_caller_user_id
      and caller.role = 'participant'
      and caller.state = 'invited'
      and room.status = 'waiting'
      and room.invite_expires_at > read_time
      and gymapp_private.social_pair_is_accepted(
        p_caller_user_id, owner_member.user_id
      )
    order by room.created_at desc, room.id desc
    limit 25
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'roomId', invitation.id,
      'status', invitation.status,
      'roomRevision', invitation.revision,
      'createdAt', invitation.created_at,
      'inviteExpiresAt', invitation.invite_expires_at,
      'summary', invitation.summary,
      'owner', pg_catalog.jsonb_build_object(
        'profileId', invitation.public_id,
        'displayName', invitation.display_name
      )
    ) order by invitation.created_at desc, invitation.id desc
  ), '[]'::jsonb)
  into invitations_json
  from invitations as invitation;

  with open_rooms as (
    select
      room.id,
      room.status,
      room.revision as room_revision,
      room.created_at,
      room.started_at,
      room.active_expires_at,
      room.summary,
      caller.role,
      caller.state,
      caller.revision as membership_revision,
      peer.user_id as peer_user_id,
      profile.public_id,
      gymapp_private.social_safe_display_name(profile.display_name) as display_name
    from gymapp_private.live_workout_members as caller
    join gymapp_private.live_workout_rooms as room on room.id = caller.room_id
    join gymapp_private.live_workout_members as peer
      on peer.room_id = room.id
     and peer.user_id <> caller.user_id
    join public.profiles as profile on profile.user_id = peer.user_id
    where caller.user_id = p_caller_user_id
      and caller.state in ('joined', 'finished')
      and room.status in ('waiting', 'ready', 'active')
      and case when room.status = 'active'
        then room.active_expires_at > read_time
        else room.invite_expires_at > read_time end
      and gymapp_private.social_pair_is_accepted(
        p_caller_user_id, peer.user_id
      )
    order by room.updated_at desc, room.id desc
    limit 5
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'roomId', open_room.id,
      'status', open_room.status,
      'roomRevision', open_room.room_revision,
      'role', open_room.role,
      'memberState', open_room.state,
      'membershipRevision', open_room.membership_revision,
      'createdAt', open_room.created_at,
      'startedAt', open_room.started_at,
      'activeExpiresAt', open_room.active_expires_at,
      'summary', open_room.summary,
      'peer', pg_catalog.jsonb_build_object(
        'profileId', open_room.public_id,
        'displayName', open_room.display_name
      )
    ) order by open_room.created_at desc, open_room.id desc
  ), '[]'::jsonb)
  into rooms_json
  from open_rooms as open_room;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'invitations', invitations_json,
    'rooms', rooms_json
  );
end
$function$;

create or replace function public.social_send_live_workout_invite(
  p_caller_user_id uuid,
  p_session_id uuid,
  p_profile_id text,
  p_client_request_id uuid,
  p_workout jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  target_user_id uuid;
  live_plan jsonb;
  summary_json jsonb;
  room_row record;
  existing_target_user_id uuid;
  pending_inbound_count integer;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  perform gymapp_private.live_gateway_require_session(p_caller_user_id, p_session_id);
  if p_profile_id is null
     or p_profile_id !~ '^p_[0-9a-f]{32}$'
     or p_client_request_id is null
     or p_workout is null then
    raise exception using errcode = '22023', message = 'Live workout invitation is invalid.';
  end if;
  live_plan := gymapp_private.validate_live_workout_plan(p_workout);
  summary_json := gymapp_private.social_workout_summary(live_plan);

  if not exists (
    select 1 from public.profiles as profile
    where profile.user_id = p_caller_user_id
  ) then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  select profile.user_id into target_user_id
  from public.profiles as profile
  where profile.public_id = p_profile_id;
  if not found or target_user_id = p_caller_user_id then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'result', 'submitted_or_unavailable',
      'roomId', null,
      'status', null,
      'roomRevision', null
    );
  end if;

  perform gymapp_private.social_lock_pair(p_caller_user_id, target_user_id);
  if not gymapp_private.social_pair_is_accepted(
    p_caller_user_id, target_user_id
  ) then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'result', 'submitted_or_unavailable',
      'roomId', null,
      'status', null,
      'roomRevision', null
    );
  end if;

  select room.*,
         participant.user_id as participant_user_id
  into room_row
  from gymapp_private.live_workout_rooms as room
  join gymapp_private.live_workout_members as participant
    on participant.room_id = room.id
   and participant.role = 'participant'
  where room.owner_user_id = p_caller_user_id
    and room.client_request_id = p_client_request_id
  for update of room;
  if found then
    existing_target_user_id := room_row.participant_user_id;
    if existing_target_user_id <> target_user_id
       or room_row.plan is distinct from live_plan then
      raise exception using errcode = '22023', message = 'Client request id was reused with different invite data.';
    end if;
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'result', 'submitted',
      'roomId', room_row.id,
      'status', room_row.status,
      'roomRevision', room_row.revision
    );
  end if;

  if exists (
    select 1
    from gymapp_private.live_workout_members as member
    join gymapp_private.live_workout_rooms as open_room
      on open_room.id = member.room_id
    where member.user_id = p_caller_user_id
      and member.state in ('joined', 'finished')
      and open_room.status in ('waiting', 'ready', 'active')
  ) then
    raise exception using errcode = 'P0001', message = 'User already has an open live workout.';
  end if;

  select pg_catalog.count(*)::integer
  into pending_inbound_count
  from gymapp_private.live_workout_members as member
  join gymapp_private.live_workout_rooms as pending_room
    on pending_room.id = member.room_id
  where member.user_id = target_user_id
    and member.state = 'invited'
    and pending_room.status = 'waiting'
    and pending_room.invite_expires_at > mutation_time;
  if pending_inbound_count >= 25 then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'result', 'submitted_or_unavailable',
      'roomId', null,
      'status', null,
      'roomRevision', null
    );
  end if;

  insert into gymapp_private.live_workout_rooms (
    owner_user_id,
    client_request_id,
    status,
    plan,
    summary,
    created_at,
    invite_expires_at,
    last_activity_at,
    updated_at
  ) values (
    p_caller_user_id,
    p_client_request_id,
    'waiting',
    live_plan,
    summary_json,
    mutation_time,
    mutation_time + interval '7 days',
    mutation_time,
    mutation_time
  ) returning * into strict room_row;

  insert into gymapp_private.live_workout_members (
    room_id, user_id, role, state, invited_at, joined_at, updated_at
  ) values
    (
      room_row.id, p_caller_user_id, 'owner', 'joined',
      mutation_time, mutation_time, mutation_time
    ),
    (
      room_row.id, target_user_id, 'participant', 'invited',
      mutation_time, null, mutation_time
    );

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'result', 'submitted',
    'roomId', room_row.id,
    'status', room_row.status,
    'roomRevision', room_row.revision
  );
end
$function$;

create or replace function public.social_respond_live_workout_invite(
  p_caller_user_id uuid,
  p_session_id uuid,
  p_room_id text,
  p_decision text,
  p_expected_room_revision bigint,
  p_client_operation_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  peer_user_id uuid;
  room_row record;
  caller_member record;
  request_json jsonb;
  result_json jsonb;
  replayed_result jsonb;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  perform gymapp_private.live_gateway_require_session(p_caller_user_id, p_session_id);
  if p_room_id is null or p_room_id !~ '^lr_[0-9a-f]{32}$'
     or p_decision is null or p_decision not in ('accept', 'decline')
     or p_expected_room_revision is null
     or p_expected_room_revision not between 1 and 2147483647
     or p_client_operation_id is null then
    raise exception using errcode = '22023', message = 'Live workout invitation response is invalid.';
  end if;
  request_json := pg_catalog.jsonb_build_object(
    'kind', 'respond_invite',
    'decision', p_decision,
    'expectedRoomRevision', p_expected_room_revision
  );

  peer_user_id := gymapp_private.live_workout_lock_pair_for_room(
    p_room_id, p_caller_user_id
  );
  select room.* into strict room_row
  from gymapp_private.live_workout_rooms as room
  where room.id = p_room_id
  for update;
  perform 1
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
  order by member.user_id
  for update;
  select member.* into strict caller_member
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
    and member.user_id = p_caller_user_id;

  if not gymapp_private.social_pair_is_accepted(p_caller_user_id, peer_user_id) then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  replayed_result := gymapp_private.live_workout_receipt_replay(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json
  );
  if replayed_result is not null then
    return replayed_result;
  end if;

  if room_row.status = 'waiting'
     and room_row.invite_expires_at <= mutation_time then
    update gymapp_private.live_workout_rooms as room
    set status = 'expired', close_reason = 'expired',
        revision = room.revision + 1, ended_at = mutation_time,
        last_activity_at = greatest(room.last_activity_at, mutation_time),
        updated_at = mutation_time
    where room.id = p_room_id
    returning * into strict room_row;
    update gymapp_private.live_workout_members as member
    set state = 'revoked', revision = member.revision + 1,
        departed_at = mutation_time, updated_at = mutation_time
    where member.room_id = p_room_id
      and member.state in ('invited', 'joined');
    result_json := pg_catalog.jsonb_build_object(
      'version', 1, 'result', 'closed', 'roomId', room_row.id,
      'status', room_row.status, 'roomRevision', room_row.revision,
      'endedAt', room_row.ended_at
    );
    perform gymapp_private.live_workout_store_receipt(
      p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
    );
    return result_json;
  end if;

  if room_row.status <> 'waiting'
     or caller_member.role <> 'participant'
     or caller_member.state <> 'invited' then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  if room_row.revision <> p_expected_room_revision
     or room_row.revision >= 2147483647
     or caller_member.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Live workout changed.';
  end if;

  if p_decision = 'accept' then
    if exists (
      select 1
      from gymapp_private.live_workout_members as member
      join gymapp_private.live_workout_rooms as open_room
        on open_room.id = member.room_id
      where member.user_id = p_caller_user_id
        and member.room_id <> p_room_id
        and member.state in ('joined', 'finished')
        and open_room.status in ('waiting', 'ready', 'active')
    ) then
      raise exception using errcode = 'P0001', message = 'User already has an open live workout.';
    end if;

    update gymapp_private.live_workout_members as member
    set state = 'joined', revision = member.revision + 1,
        joined_at = mutation_time, updated_at = mutation_time
    where member.room_id = p_room_id
      and member.user_id = p_caller_user_id
    returning * into strict caller_member;
    update gymapp_private.live_workout_rooms as room
    set status = 'ready', revision = room.revision + 1,
        last_activity_at = greatest(room.last_activity_at, mutation_time),
        updated_at = mutation_time
    where room.id = p_room_id
    returning * into strict room_row;
    result_json := pg_catalog.jsonb_build_object(
      'version', 1, 'result', 'joined', 'roomId', room_row.id,
      'status', room_row.status, 'roomRevision', room_row.revision,
      'membershipRevision', caller_member.revision
    );
  else
    update gymapp_private.live_workout_rooms as room
    set status = 'cancelled', close_reason = 'declined',
        revision = room.revision + 1, ended_at = mutation_time,
        last_activity_at = greatest(room.last_activity_at, mutation_time),
        updated_at = mutation_time
    where room.id = p_room_id
    returning * into strict room_row;
    update gymapp_private.live_workout_members as member
    set state = 'revoked', revision = member.revision + 1,
        departed_at = mutation_time, updated_at = mutation_time
    where member.room_id = p_room_id
      and member.state in ('invited', 'joined');
    select member.* into strict caller_member
    from gymapp_private.live_workout_members as member
    where member.room_id = p_room_id
      and member.user_id = p_caller_user_id;
    result_json := pg_catalog.jsonb_build_object(
      'version', 1, 'result', 'declined', 'roomId', room_row.id,
      'status', room_row.status, 'roomRevision', room_row.revision,
      'membershipRevision', caller_member.revision,
      'endedAt', room_row.ended_at
    );
  end if;

  perform gymapp_private.live_workout_store_receipt(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
  );
  return result_json;
end
$function$;

create or replace function public.social_start_live_workout(
  p_caller_user_id uuid,
  p_session_id uuid,
  p_room_id text,
  p_expected_room_revision bigint,
  p_client_operation_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  peer_user_id uuid;
  room_row record;
  caller_member record;
  request_json jsonb;
  result_json jsonb;
  replayed_result jsonb;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  perform gymapp_private.live_gateway_require_session(p_caller_user_id, p_session_id);
  if p_room_id is null or p_room_id !~ '^lr_[0-9a-f]{32}$'
     or p_expected_room_revision is null
     or p_expected_room_revision not between 1 and 2147483647
     or p_client_operation_id is null then
    raise exception using errcode = '22023', message = 'Live workout start is invalid.';
  end if;
  request_json := pg_catalog.jsonb_build_object(
    'kind', 'start', 'expectedRoomRevision', p_expected_room_revision
  );

  peer_user_id := gymapp_private.live_workout_lock_pair_for_room(
    p_room_id, p_caller_user_id
  );
  select room.* into strict room_row
  from gymapp_private.live_workout_rooms as room
  where room.id = p_room_id
  for update;
  perform 1
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
  order by member.user_id
  for update;
  select member.* into strict caller_member
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
    and member.user_id = p_caller_user_id;

  if not gymapp_private.social_pair_is_accepted(p_caller_user_id, peer_user_id) then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  replayed_result := gymapp_private.live_workout_receipt_replay(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json
  );
  if replayed_result is not null then
    return replayed_result;
  end if;

  if room_row.status = 'ready'
     and room_row.invite_expires_at <= mutation_time then
    update gymapp_private.live_workout_rooms as room
    set status = 'expired', close_reason = 'expired',
        revision = room.revision + 1, ended_at = mutation_time,
        last_activity_at = greatest(room.last_activity_at, mutation_time),
        updated_at = mutation_time
    where room.id = p_room_id
    returning * into strict room_row;
    update gymapp_private.live_workout_members as member
    set state = 'revoked', revision = member.revision + 1,
        departed_at = mutation_time, updated_at = mutation_time
    where member.room_id = p_room_id
      and member.state = 'joined';
    result_json := pg_catalog.jsonb_build_object(
      'version', 1, 'result', 'closed', 'roomId', room_row.id,
      'status', room_row.status, 'roomRevision', room_row.revision,
      'endedAt', room_row.ended_at
    );
    perform gymapp_private.live_workout_store_receipt(
      p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
    );
    return result_json;
  end if;

  if room_row.status <> 'ready'
     or caller_member.role <> 'owner'
     or caller_member.state <> 'joined'
     or exists (
       select 1
       from gymapp_private.live_workout_members as member
       where member.room_id = p_room_id
         and member.state <> 'joined'
     ) then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  if room_row.revision <> p_expected_room_revision
     or room_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Live workout changed.';
  end if;
  if exists (
    select 1
    from gymapp_private.live_workout_members as member
    join gymapp_private.live_workout_rooms as open_room
      on open_room.id = member.room_id
    where member.user_id in (p_caller_user_id, peer_user_id)
      and member.room_id <> p_room_id
      and member.state in ('joined', 'finished')
      and open_room.status in ('waiting', 'ready', 'active')
  ) then
    raise exception using errcode = 'P0001', message = 'A participant already has another open live workout.';
  end if;

  update gymapp_private.live_workout_rooms as room
  set status = 'active', revision = room.revision + 1,
      started_at = mutation_time,
      active_expires_at = mutation_time + interval '24 hours',
      last_activity_at = greatest(room.last_activity_at, mutation_time),
      updated_at = mutation_time
  where room.id = p_room_id
  returning * into strict room_row;

  insert into gymapp_private.live_workout_progress (
    room_id, user_id, updated_at
  )
  select p_room_id, member.user_id, mutation_time
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
  order by member.user_id;

  result_json := pg_catalog.jsonb_build_object(
    'version', 1, 'result', 'started', 'roomId', room_row.id,
    'status', room_row.status, 'roomRevision', room_row.revision,
    'startedAt', room_row.started_at,
    'activeExpiresAt', room_row.active_expires_at,
    'myProgressRevision', 1
  );
  perform gymapp_private.live_workout_store_receipt(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
  );
  return result_json;
end
$function$;

create or replace function public.social_live_workout_snapshot(
  p_caller_user_id uuid,
  p_session_id uuid,
  p_room_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  perform gymapp_private.live_gateway_require_session(p_caller_user_id, p_session_id);
  if p_room_id is null or p_room_id !~ '^lr_[0-9a-f]{32}$' then
    raise exception using errcode = '22023', message = 'Live workout snapshot request is invalid.';
  end if;
  return gymapp_private.live_workout_snapshot_for(p_caller_user_id, p_room_id);
end
$function$;

create or replace function public.social_apply_live_workout_operation(
  p_caller_user_id uuid,
  p_session_id uuid,
  p_room_id text,
  p_client_operation_id uuid,
  p_expected_progress_revision bigint,
  p_operation jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  peer_user_id uuid;
  room_row record;
  caller_member record;
  progress_row record;
  request_json jsonb;
  result_json jsonb;
  replayed_result jsonb;
  operation_kind text;
  set_id text;
  weight_value numeric;
  reps_value numeric;
  completed_sets jsonb;
  previous_set_id text;
  completion_time timestamptz;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  perform gymapp_private.live_gateway_require_session(p_caller_user_id, p_session_id);
  if p_room_id is null or p_room_id !~ '^lr_[0-9a-f]{32}$'
     or p_client_operation_id is null
     or p_expected_progress_revision is null
     or p_expected_progress_revision not between 1 and 2147483647
     or p_operation is null
     or pg_catalog.jsonb_typeof(p_operation) is distinct from 'object'
     or pg_catalog.pg_column_size(p_operation) > 4096
     or pg_catalog.jsonb_typeof(p_operation->'kind') is distinct from 'string'
     or pg_catalog.jsonb_typeof(p_operation->'setId') is distinct from 'string' then
    raise exception using errcode = '22023', message = 'Live workout operation is invalid.';
  end if;
  operation_kind := p_operation->>'kind';
  set_id := p_operation->>'setId';
  if set_id !~ '^s_[0-9]{2}_[0-9]{2}$'
     or operation_kind not in ('complete_set', 'undo_set') then
    raise exception using errcode = '22023', message = 'Live workout operation is invalid.';
  end if;

  if operation_kind = 'complete_set' then
    if (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_operation)) <> 4
       or not (p_operation ? 'weight')
       or not (p_operation ? 'reps')
       or pg_catalog.jsonb_typeof(p_operation->'weight') is distinct from 'number'
       or pg_catalog.jsonb_typeof(p_operation->'reps') is distinct from 'number' then
      raise exception using errcode = '22023', message = 'Live workout completion is invalid.';
    end if;
    weight_value := (p_operation->>'weight')::numeric;
    reps_value := (p_operation->>'reps')::numeric;
    if weight_value not between 0 and 1000000
       or reps_value not between 1 and 10000
       or reps_value <> pg_catalog.trunc(reps_value) then
      raise exception using errcode = '22023', message = 'Live workout completion values are invalid.';
    end if;
  elsif (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_operation)) <> 2 then
    raise exception using errcode = '22023', message = 'Live workout undo is invalid.';
  end if;

  request_json := pg_catalog.jsonb_build_object(
    'kind', 'apply',
    'expectedProgressRevision', p_expected_progress_revision,
    'operation', p_operation
  );
  peer_user_id := gymapp_private.live_workout_lock_pair_for_room(
    p_room_id, p_caller_user_id
  );
  select room.* into strict room_row
  from gymapp_private.live_workout_rooms as room
  where room.id = p_room_id
  for update;
  perform 1
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
  order by member.user_id
  for update;
  select member.* into strict caller_member
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
    and member.user_id = p_caller_user_id;
  select progress.* into strict progress_row
  from gymapp_private.live_workout_progress as progress
  where progress.room_id = p_room_id
    and progress.user_id = p_caller_user_id
  for update;

  if not gymapp_private.social_pair_is_accepted(p_caller_user_id, peer_user_id) then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  replayed_result := gymapp_private.live_workout_receipt_replay(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json
  );
  if replayed_result is not null then
    return replayed_result;
  end if;

  if room_row.status = 'active'
     and room_row.active_expires_at <= mutation_time then
    update gymapp_private.live_workout_rooms as room
    set status = 'expired', close_reason = 'expired',
        revision = room.revision + 1, ended_at = mutation_time,
        last_activity_at = greatest(room.last_activity_at, mutation_time),
        updated_at = mutation_time
    where room.id = p_room_id
    returning * into strict room_row;
    update gymapp_private.live_workout_members as member
    set state = 'revoked', revision = member.revision + 1,
        departed_at = mutation_time, updated_at = mutation_time
    where member.room_id = p_room_id
      and member.state = 'joined';
    result_json := pg_catalog.jsonb_build_object(
      'version', 1, 'result', 'closed', 'roomId', room_row.id,
      'status', room_row.status, 'roomRevision', room_row.revision,
      'endedAt', room_row.ended_at
    );
    perform gymapp_private.live_workout_store_receipt(
      p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
    );
    return result_json;
  end if;

  if room_row.status <> 'active'
     or caller_member.state <> 'joined'
     or progress_row.payload->>'finishedAt' is not null then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  if progress_row.revision <> p_expected_progress_revision
     or progress_row.revision >= 2147483647
     or room_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Live workout progress changed.';
  end if;
  if not exists (
    select 1
    from pg_catalog.jsonb_array_elements(room_row.plan->'exercises') as exercise(value)
    cross join lateral pg_catalog.jsonb_array_elements(exercise.value->'sets') as set_item(value)
    where set_item.value->>'setId' = set_id
  ) then
    raise exception using errcode = '22023', message = 'Live workout set is invalid.';
  end if;

  if operation_kind = 'complete_set' then
    if exists (
      select 1
      from pg_catalog.jsonb_array_elements(progress_row.payload->'completedSets') as completed(value)
      where completed.value->>'setId' = set_id
    ) then
      raise exception using errcode = 'P0001', message = 'Live workout set was already completed.';
    end if;
    if pg_catalog.jsonb_array_length(progress_row.payload->'completedSets') >= 120 then
      raise exception using errcode = 'P0001', message = 'Live workout progress is full.';
    end if;
    completion_time := mutation_time;
    completed_sets := progress_row.payload->'completedSets'
      || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'setId', set_id,
        'weight', case when weight_value = 0 then 0 else weight_value end,
        'reps', reps_value::integer,
        'completedAt', completion_time
      ));
  else
    if progress_row.payload->>'undoableSetId' is distinct from set_id then
      raise exception using errcode = 'P0001', message = 'Only the latest own set can be undone.';
    end if;
    select coalesce(
      pg_catalog.jsonb_agg(completed.value order by completed.ordinality),
      '[]'::jsonb
    )
    into completed_sets
    from pg_catalog.jsonb_array_elements(progress_row.payload->'completedSets')
      with ordinality as completed(value, ordinality)
    where completed.ordinality < pg_catalog.jsonb_array_length(
      progress_row.payload->'completedSets'
    );
    if pg_catalog.jsonb_array_length(completed_sets) > 0 then
      previous_set_id := completed_sets -> -1 ->> 'setId';
    end if;
  end if;

  update gymapp_private.live_workout_progress as progress
  set payload = pg_catalog.jsonb_build_object(
        'version', 1,
        'completedSets', completed_sets,
        'undoableSetId', case when operation_kind = 'complete_set'
          then set_id else previous_set_id end,
        'finishedAt', null
      ),
      revision = progress.revision + 1,
      updated_at = mutation_time
  where progress.room_id = p_room_id
    and progress.user_id = p_caller_user_id
  returning * into strict progress_row;

  update gymapp_private.live_workout_rooms as room
  set revision = room.revision + 1,
      last_activity_at = greatest(room.last_activity_at, mutation_time),
      updated_at = mutation_time
  where room.id = p_room_id
  returning * into strict room_row;

  result_json := pg_catalog.jsonb_build_object(
    'version', 1, 'result', 'applied', 'roomId', room_row.id,
    'roomRevision', room_row.revision,
    'progressRevision', progress_row.revision,
    'kind', operation_kind,
    'setId', set_id,
    'completedAt', completion_time
  );
  perform gymapp_private.live_workout_store_receipt(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
  );
  return result_json;
end
$function$;

create or replace function public.social_finish_live_workout(
  p_caller_user_id uuid,
  p_session_id uuid,
  p_room_id text,
  p_client_operation_id uuid,
  p_expected_progress_revision bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  peer_user_id uuid;
  room_row record;
  caller_member record;
  progress_row record;
  request_json jsonb;
  result_json jsonb;
  replayed_result jsonb;
  all_finished boolean;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  perform gymapp_private.live_gateway_require_session(p_caller_user_id, p_session_id);
  if p_room_id is null or p_room_id !~ '^lr_[0-9a-f]{32}$'
     or p_client_operation_id is null
     or p_expected_progress_revision is null
     or p_expected_progress_revision not between 1 and 2147483647 then
    raise exception using errcode = '22023', message = 'Live workout finish is invalid.';
  end if;
  request_json := pg_catalog.jsonb_build_object(
    'kind', 'finish', 'expectedProgressRevision', p_expected_progress_revision
  );
  peer_user_id := gymapp_private.live_workout_lock_pair_for_room(
    p_room_id, p_caller_user_id
  );
  select room.* into strict room_row
  from gymapp_private.live_workout_rooms as room
  where room.id = p_room_id
  for update;
  perform 1
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
  order by member.user_id
  for update;
  select member.* into strict caller_member
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
    and member.user_id = p_caller_user_id;
  select progress.* into strict progress_row
  from gymapp_private.live_workout_progress as progress
  where progress.room_id = p_room_id
    and progress.user_id = p_caller_user_id
  for update;

  if not gymapp_private.social_pair_is_accepted(p_caller_user_id, peer_user_id) then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  replayed_result := gymapp_private.live_workout_receipt_replay(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json
  );
  if replayed_result is not null then
    return replayed_result;
  end if;
  if room_row.status = 'active'
     and room_row.active_expires_at <= mutation_time then
    update gymapp_private.live_workout_rooms as room
    set status = 'expired', close_reason = 'expired',
        revision = room.revision + 1, ended_at = mutation_time,
        last_activity_at = greatest(room.last_activity_at, mutation_time),
        updated_at = mutation_time
    where room.id = p_room_id
    returning * into strict room_row;
    update gymapp_private.live_workout_members as member
    set state = 'revoked', revision = member.revision + 1,
        departed_at = mutation_time, updated_at = mutation_time
    where member.room_id = p_room_id
      and member.state = 'joined';
    result_json := pg_catalog.jsonb_build_object(
      'version', 1, 'result', 'closed', 'roomId', room_row.id,
      'status', room_row.status, 'roomRevision', room_row.revision,
      'endedAt', room_row.ended_at
    );
    perform gymapp_private.live_workout_store_receipt(
      p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
    );
    return result_json;
  end if;
  if room_row.status <> 'active'
     or caller_member.state <> 'joined'
     or progress_row.payload->>'finishedAt' is not null then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  if progress_row.revision <> p_expected_progress_revision
     or progress_row.revision >= 2147483647
     or caller_member.revision >= 2147483647
     or room_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Live workout progress changed.';
  end if;

  -- Progress must finish while the caller is still joined and the room active;
  -- the storage guard intentionally rejects the reverse order.
  update gymapp_private.live_workout_progress as progress
  set payload = pg_catalog.jsonb_set(
        progress.payload, '{finishedAt}', pg_catalog.to_jsonb(mutation_time), false
      ),
      revision = progress.revision + 1,
      updated_at = mutation_time
  where progress.room_id = p_room_id
    and progress.user_id = p_caller_user_id
  returning * into strict progress_row;
  update gymapp_private.live_workout_members as member
  set state = 'finished', revision = member.revision + 1,
      finished_at = mutation_time, updated_at = mutation_time
  where member.room_id = p_room_id
    and member.user_id = p_caller_user_id
  returning * into strict caller_member;

  select pg_catalog.bool_and(member.state = 'finished')
  into all_finished
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id;
  update gymapp_private.live_workout_rooms as room
  set status = case when all_finished then 'completed' else room.status end,
      close_reason = case when all_finished then 'completed' else null end,
      revision = room.revision + 1,
      ended_at = case when all_finished then mutation_time else null end,
      last_activity_at = greatest(room.last_activity_at, mutation_time),
      updated_at = mutation_time
  where room.id = p_room_id
  returning * into strict room_row;

  result_json := pg_catalog.jsonb_build_object(
    'version', 1, 'result', 'finished', 'roomId', room_row.id,
    'status', room_row.status, 'roomRevision', room_row.revision,
    'progressRevision', progress_row.revision,
    'membershipRevision', caller_member.revision,
    'finishedAt', mutation_time
  );
  perform gymapp_private.live_workout_store_receipt(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
  );
  return result_json;
end
$function$;

create or replace function public.social_leave_live_workout(
  p_caller_user_id uuid,
  p_session_id uuid,
  p_room_id text,
  p_client_operation_id uuid,
  p_expected_membership_revision bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  peer_user_id uuid;
  room_row record;
  caller_member record;
  request_json jsonb;
  result_json jsonb;
  replayed_result jsonb;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  perform gymapp_private.live_gateway_require_session(p_caller_user_id, p_session_id);
  if p_room_id is null or p_room_id !~ '^lr_[0-9a-f]{32}$'
     or p_client_operation_id is null
     or p_expected_membership_revision is null
     or p_expected_membership_revision not between 1 and 2147483647 then
    raise exception using errcode = '22023', message = 'Live workout leave is invalid.';
  end if;
  request_json := pg_catalog.jsonb_build_object(
    'kind', 'leave', 'expectedMembershipRevision', p_expected_membership_revision
  );
  peer_user_id := gymapp_private.live_workout_lock_pair_for_room(
    p_room_id, p_caller_user_id
  );
  select room.* into strict room_row
  from gymapp_private.live_workout_rooms as room
  where room.id = p_room_id
  for update;
  perform 1
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
  order by member.user_id
  for update;
  select member.* into strict caller_member
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
    and member.user_id = p_caller_user_id;

  if not gymapp_private.social_pair_is_accepted(p_caller_user_id, peer_user_id) then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  replayed_result := gymapp_private.live_workout_receipt_replay(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json
  );
  if replayed_result is not null then
    return replayed_result;
  end if;
  if room_row.status not in ('ready', 'active')
     or caller_member.role <> 'participant'
     or caller_member.state not in ('joined', 'finished') then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  if caller_member.revision <> p_expected_membership_revision
     or caller_member.revision >= 2147483647
     or room_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Live workout membership changed.';
  end if;

  update gymapp_private.live_workout_rooms as room
  set status = 'cancelled', close_reason = 'left',
      revision = room.revision + 1, ended_at = mutation_time,
      last_activity_at = greatest(room.last_activity_at, mutation_time),
      updated_at = mutation_time
  where room.id = p_room_id
  returning * into strict room_row;
  update gymapp_private.live_workout_members as member
  set state = 'left',
      revision = member.revision + 1,
      departed_at = mutation_time,
      updated_at = mutation_time
  where member.room_id = p_room_id
    and member.user_id = p_caller_user_id
    and member.state in ('joined', 'finished');
  update gymapp_private.live_workout_members as member
  set state = 'revoked',
      revision = member.revision + 1,
      departed_at = mutation_time,
      updated_at = mutation_time
  where member.room_id = p_room_id
    and member.user_id <> p_caller_user_id
    and member.state in ('invited', 'joined');
  select member.* into strict caller_member
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
    and member.user_id = p_caller_user_id;

  result_json := pg_catalog.jsonb_build_object(
    'version', 1, 'result', 'left', 'roomId', room_row.id,
    'status', room_row.status, 'roomRevision', room_row.revision,
    'membershipRevision', caller_member.revision,
    'endedAt', room_row.ended_at
  );
  perform gymapp_private.live_workout_store_receipt(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
  );
  return result_json;
end
$function$;

create or replace function public.social_cancel_live_workout(
  p_caller_user_id uuid,
  p_session_id uuid,
  p_room_id text,
  p_client_operation_id uuid,
  p_expected_room_revision bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  peer_user_id uuid;
  room_row record;
  caller_member record;
  request_json jsonb;
  result_json jsonb;
  replayed_result jsonb;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  perform gymapp_private.live_gateway_require_session(p_caller_user_id, p_session_id);
  if p_room_id is null or p_room_id !~ '^lr_[0-9a-f]{32}$'
     or p_client_operation_id is null
     or p_expected_room_revision is null
     or p_expected_room_revision not between 1 and 2147483647 then
    raise exception using errcode = '22023', message = 'Live workout cancellation is invalid.';
  end if;
  request_json := pg_catalog.jsonb_build_object(
    'kind', 'cancel', 'expectedRoomRevision', p_expected_room_revision
  );
  peer_user_id := gymapp_private.live_workout_lock_pair_for_room(
    p_room_id, p_caller_user_id
  );
  select room.* into strict room_row
  from gymapp_private.live_workout_rooms as room
  where room.id = p_room_id
  for update;
  perform 1
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
  order by member.user_id
  for update;
  select member.* into strict caller_member
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
    and member.user_id = p_caller_user_id;

  if not gymapp_private.social_pair_is_accepted(p_caller_user_id, peer_user_id) then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  replayed_result := gymapp_private.live_workout_receipt_replay(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json
  );
  if replayed_result is not null then
    return replayed_result;
  end if;
  if room_row.status not in ('waiting', 'ready', 'active')
     or caller_member.role <> 'owner'
     or caller_member.state not in ('joined', 'finished') then
    raise exception using errcode = 'P0002', message = 'Live workout unavailable.';
  end if;
  if room_row.revision <> p_expected_room_revision
     or room_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Live workout changed.';
  end if;

  update gymapp_private.live_workout_rooms as room
  set status = 'cancelled', close_reason = 'cancelled',
      revision = room.revision + 1, ended_at = mutation_time,
      last_activity_at = greatest(room.last_activity_at, mutation_time),
      updated_at = mutation_time
  where room.id = p_room_id
  returning * into strict room_row;
  update gymapp_private.live_workout_members as member
  set state = 'revoked', revision = member.revision + 1,
      departed_at = mutation_time, updated_at = mutation_time
  where member.room_id = p_room_id
    and member.state in ('invited', 'joined');
  select member.* into strict caller_member
  from gymapp_private.live_workout_members as member
  where member.room_id = p_room_id
    and member.user_id = p_caller_user_id;

  result_json := pg_catalog.jsonb_build_object(
    'version', 1, 'result', 'cancelled', 'roomId', room_row.id,
    'status', room_row.status, 'roomRevision', room_row.revision,
    'membershipRevision', caller_member.revision,
    'endedAt', room_row.ended_at
  );
  perform gymapp_private.live_workout_store_receipt(
    p_room_id, p_caller_user_id, p_client_operation_id, request_json, result_json
  );
  return result_json;
end
$function$;

revoke all on function public.social_live_workout_inbox(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.social_send_live_workout_invite(uuid, uuid, text, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.social_respond_live_workout_invite(uuid, uuid, text, text, bigint, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.social_start_live_workout(uuid, uuid, text, bigint, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.social_live_workout_snapshot(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.social_apply_live_workout_operation(uuid, uuid, text, uuid, bigint, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.social_finish_live_workout(uuid, uuid, text, uuid, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.social_leave_live_workout(uuid, uuid, text, uuid, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.social_cancel_live_workout(uuid, uuid, text, uuid, bigint)
  from public, anon, authenticated, service_role;

grant execute on function public.social_live_workout_inbox(uuid, uuid)
  to service_role;
grant execute on function public.social_send_live_workout_invite(uuid, uuid, text, uuid, jsonb)
  to service_role;
grant execute on function public.social_respond_live_workout_invite(uuid, uuid, text, text, bigint, uuid)
  to service_role;
grant execute on function public.social_start_live_workout(uuid, uuid, text, bigint, uuid)
  to service_role;
grant execute on function public.social_live_workout_snapshot(uuid, uuid, text)
  to service_role;
grant execute on function public.social_apply_live_workout_operation(uuid, uuid, text, uuid, bigint, jsonb)
  to service_role;
grant execute on function public.social_finish_live_workout(uuid, uuid, text, uuid, bigint)
  to service_role;
grant execute on function public.social_leave_live_workout(uuid, uuid, text, uuid, bigint)
  to service_role;
grant execute on function public.social_cancel_live_workout(uuid, uuid, text, uuid, bigint)
  to service_role;

comment on function public.social_live_workout_inbox(uuid, uuid) is
  'Service-gateway-only bounded live invite/open-room index. First UUID is verified user, second is its current Auth session.';
comment on function public.social_send_live_workout_invite(uuid, uuid, text, uuid, jsonb) is
  'Service-gateway-only immutable two-person live-workout invitation.';
comment on function public.social_respond_live_workout_invite(uuid, uuid, text, text, bigint, uuid) is
  'Service-gateway-only accept-to-ready or decline transition with durable operation receipt.';
comment on function public.social_start_live_workout(uuid, uuid, text, bigint, uuid) is
  'Service-gateway-only owner start. Both joined members are checked for any other open room before active progress is created.';
comment on function public.social_live_workout_snapshot(uuid, uuid, text) is
  'Service-gateway-only durable reconnect snapshot; never returns Auth UUIDs, email, notes, or credentials.';
comment on function public.social_apply_live_workout_operation(uuid, uuid, text, uuid, bigint, jsonb) is
  'Service-gateway-only caller-owned complete/undo operation with progress CAS and idempotency receipt.';
comment on function public.social_finish_live_workout(uuid, uuid, text, uuid, bigint) is
  'Service-gateway-only caller finish. Progress is sealed before membership and room lifecycle advance.';
comment on function public.social_leave_live_workout(uuid, uuid, text, uuid, bigint) is
  'Service-gateway-only participant leave with membership CAS; the shared room closes for both users.';
comment on function public.social_cancel_live_workout(uuid, uuid, text, uuid, bigint) is
  'Service-gateway-only owner cancellation with room CAS; the shared room closes for both users.';

-- Supabase Cron is the bounded safety net for expiry and retention. Every
-- state-changing RPC also checks its target deadline before mutation, so a
-- delayed job cannot make an expired room writable again.
create extension if not exists pg_cron with schema pg_catalog;

do $schedule_cleanup$
begin
  if not exists (
    select 1
    from cron.job as job
    where job.jobname = 'gymapp-live-workout-cleanup-v1'
  ) then
    perform cron.schedule(
      'gymapp-live-workout-cleanup-v1',
      '*/5 * * * *',
      'select gymapp_private.cleanup_live_workouts(100);'
    );
  end if;
end
$schedule_cleanup$;

do $verify$
declare
  rpc_signature text;
begin
  foreach rpc_signature in array array[
    'public.social_live_workout_inbox(uuid,uuid)',
    'public.social_send_live_workout_invite(uuid,uuid,text,uuid,jsonb)',
    'public.social_respond_live_workout_invite(uuid,uuid,text,text,bigint,uuid)',
    'public.social_start_live_workout(uuid,uuid,text,bigint,uuid)',
    'public.social_live_workout_snapshot(uuid,uuid,text)',
    'public.social_apply_live_workout_operation(uuid,uuid,text,uuid,bigint,jsonb)',
    'public.social_finish_live_workout(uuid,uuid,text,uuid,bigint)',
    'public.social_leave_live_workout(uuid,uuid,text,uuid,bigint)',
    'public.social_cancel_live_workout(uuid,uuid,text,uuid,bigint)'
  ] loop
    if pg_catalog.has_function_privilege('anon', rpc_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege('authenticated', rpc_signature, 'EXECUTE')
       or not pg_catalog.has_function_privilege('service_role', rpc_signature, 'EXECUTE') then
      raise exception 'Live-workout RPC % is not exactly service-gateway-only.', rpc_signature;
    end if;
  end loop;

  if pg_catalog.has_function_privilege(
       'service_role',
       'gymapp_private.live_gateway_require_session(uuid,uuid)',
       'EXECUTE'
     )
     or not exists (
       select 1 from cron.job as job
       where job.jobname = 'gymapp-live-workout-cleanup-v1'
     ) then
    raise exception 'Live-workout private helper grants or cleanup schedule are invalid.';
  end if;
end
$verify$;

select pg_catalog.pg_notify('pgrst', 'reload schema');

commit;
