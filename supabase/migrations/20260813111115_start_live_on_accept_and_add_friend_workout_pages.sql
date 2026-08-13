begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regprocedure(
       'public.social_respond_live_workout_invite(uuid,uuid,text,text,bigint,uuid)'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.live_workout_store_receipt(text,uuid,uuid,jsonb,jsonb)'
     ) is null
     or pg_catalog.to_regprocedure('extensions.digest(bytea,text)') is null
     or pg_catalog.to_regclass('gymapp_private.live_workout_progress') is null
     or pg_catalog.to_regclass('gymapp_private.social_activity_projection') is null then
    raise exception 'GymApp social/live prerequisites are missing.';
  end if;
end
$preflight$;

-- Detailed exercises, weights, and repetitions are a separate disclosure from
-- the legacy five summaries. Existing accounts and clients remain summary-only
-- until the owner explicitly opts in with a new client.
alter table gymapp_private.social_settings
  add column if not exists share_workout_details boolean not null default false;

create or replace function public.social_workout_detail_privacy()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  settings_row record;
begin
  caller_user_id := gymapp_private.social_require_caller('update_privacy');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);
  select settings.share_workout_details, settings.revision
  into strict settings_row
  from gymapp_private.social_settings as settings
  where settings.user_id = caller_user_id;
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'shareWorkoutDetails', settings_row.share_workout_details,
    'settingsRevision', settings_row.revision
  );
end
$function$;

create or replace function public.social_update_workout_detail_privacy(
  p_share_workout_details boolean,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  settings_row record;
begin
  caller_user_id := gymapp_private.social_require_caller('update_privacy');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);
  if p_share_workout_details is null
     or p_expected_revision is null
     or p_expected_revision not between 1 and 2147483647 then
    raise exception using errcode = '22023', message = 'Workout detail privacy update is invalid.';
  end if;

  select settings.* into strict settings_row
  from gymapp_private.social_settings as settings
  where settings.user_id = caller_user_id
  for update;
  if settings_row.share_workout_details = p_share_workout_details
     and settings_row.revision in (p_expected_revision, p_expected_revision + 1) then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'shareWorkoutDetails', settings_row.share_workout_details,
      'settingsRevision', settings_row.revision
    );
  end if;
  if settings_row.revision <> p_expected_revision
     or settings_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Social privacy settings changed.';
  end if;

  update gymapp_private.social_settings as settings
  set share_workout_details = p_share_workout_details,
      revision = settings.revision + 1,
      updated_at = pg_catalog.clock_timestamp()
  where settings.user_id = caller_user_id
  returning settings.* into strict settings_row;
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'shareWorkoutDetails', settings_row.share_workout_details,
    'settingsRevision', settings_row.revision
  );
end
$function$;

revoke all on function public.social_workout_detail_privacy()
  from public, anon, authenticated, service_role;
revoke all on function public.social_update_workout_detail_privacy(boolean, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.social_workout_detail_privacy() to authenticated;
grant execute on function public.social_update_workout_detail_privacy(boolean, bigint)
  to authenticated;

create or replace function public.social_friend_workout_detail_capability(
  p_profile_id text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  target_user_id uuid;
  capability_available boolean;
begin
  caller_user_id := gymapp_private.social_require_caller('friend_details');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);
  if p_profile_id is null or p_profile_id !~ '^p_[0-9a-f]{32}$' then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  select profile.user_id into target_user_id
  from public.profiles as profile
  where profile.public_id = p_profile_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  perform gymapp_private.social_lock_pair(caller_user_id, target_user_id);
  if not gymapp_private.social_pair_is_accepted(caller_user_id, target_user_id) then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  select settings.share_recent_workouts and settings.share_workout_details
  into strict capability_available
  from gymapp_private.social_settings as settings
  where settings.user_id = target_user_id
  for share;
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'available', capability_available
  );
end
$function$;

revoke all on function public.social_friend_workout_detail_capability(text)
  from public, anon, authenticated, service_role;
grant execute on function public.social_friend_workout_detail_capability(text)
  to authenticated;

create or replace function gymapp_private.broadcast_social_settings_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  recipient_user_id uuid;
begin
  if old.revision is not distinct from new.revision then
    return new;
  end if;
  for recipient_user_id in
    select new.user_id
    union
    select case when friendship.user_low_id = new.user_id
      then friendship.user_high_id else friendship.user_low_id end
    from gymapp_private.friendships as friendship
    where friendship.status = 'accepted'
      and new.user_id in (friendship.user_low_id, friendship.user_high_id)
    order by 1
  loop
    perform realtime.send(
      pg_catalog.jsonb_build_object(
        'version', 1,
        'kind', 'privacy_changed'
      ),
      'gymapp_social_changed',
      'gymapp:user:' || recipient_user_id::text,
      true
    );
  end loop;
  return new;
end
$function$;

revoke all on function gymapp_private.broadcast_social_settings_change()
  from public, anon, authenticated, service_role;
drop trigger if exists social_settings_broadcast_privacy_change
  on gymapp_private.social_settings;
drop trigger if exists social_settings_broadcast_detail_privacy
  on gymapp_private.social_settings;
create trigger social_settings_broadcast_privacy_change
after update
on gymapp_private.social_settings
for each row
execute function gymapp_private.broadcast_social_settings_change();

-- A peer can remove the relationship while the other client is displaying an
-- exact workout. Send the same opaque invalidation to both accounts whenever
-- relationship authorization changes; clients must refetch rather than infer
-- the new state from the event.
create or replace function gymapp_private.broadcast_social_relationship_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  recipient_user_id uuid;
begin
  if old.status is not distinct from new.status then
    return new;
  end if;
  foreach recipient_user_id in array array[new.user_low_id, new.user_high_id]
  loop
    perform realtime.send(
      pg_catalog.jsonb_build_object(
        'version', 1,
        'kind', 'privacy_changed'
      ),
      'gymapp_social_changed',
      'gymapp:user:' || recipient_user_id::text,
      true
    );
  end loop;
  return new;
end
$function$;

revoke all on function gymapp_private.broadcast_social_relationship_change()
  from public, anon, authenticated, service_role;
drop trigger if exists friendships_broadcast_social_change
  on gymapp_private.friendships;
create trigger friendships_broadcast_social_change
after update of status
on gymapp_private.friendships
for each row
when (old.status is distinct from new.status)
execute function gymapp_private.broadcast_social_relationship_change();

-- Accepting is the single start gesture. The participant membership, room
-- lifecycle, and both empty progress rows commit in one transaction. The
-- response deliberately retains legacy status="ready" so already released
-- clients accept the exact-key response and then discover the authoritative
-- active snapshot through their existing refresh path.
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
  inserted_progress_count integer := 0;
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
      from gymapp_private.live_workout_progress as progress
      where progress.room_id = p_room_id
    ) then
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
      raise exception using errcode = 'P0001', message = 'A participant already has an open live workout.';
    end if;

    update gymapp_private.live_workout_members as member
    set state = 'joined', revision = member.revision + 1,
        joined_at = mutation_time, updated_at = mutation_time
    where member.room_id = p_room_id
      and member.user_id = p_caller_user_id
    returning * into strict caller_member;

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
      and member.state = 'joined'
    order by member.user_id;
    get diagnostics inserted_progress_count = row_count;
    if inserted_progress_count <> 2 then
      raise exception using errcode = 'P0001', message = 'Live workout changed.';
    end if;

    result_json := pg_catalog.jsonb_build_object(
      'version', 1, 'result', 'joined', 'roomId', room_row.id,
      'status', 'ready', 'roomRevision', room_row.revision,
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

revoke all on function public.social_respond_live_workout_invite(
  uuid, uuid, text, text, bigint, uuid
) from public, anon, authenticated;
grant execute on function public.social_respond_live_workout_invite(
  uuid, uuid, text, text, bigint, uuid
) to service_role;

-- The direct waiting -> active transition is one canonical lifecycle event.
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
    when new.status = 'active' and old.status in ('waiting', 'ready') then 'started'
    when new.status in ('completed', 'cancelled', 'expired') then 'room_closed'
    else 'progress'
  end;
  perform gymapp_private.broadcast_live_workout_room(new.id, event_kind);
  return new;
end
$function$;

revoke all on function gymapp_private.broadcast_live_workout_room_change()
  from public, anon, authenticated, service_role;

-- Push is also an invalidator. Notify both accounts with the canonical active
-- room target; clients still fetch the account-bound snapshot before opening.
create or replace function gymapp_private.enqueue_live_workout_room_push()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  recipient record;
  finished_member record;
begin
  if old.status = 'waiting' and new.status = 'ready' then
    perform gymapp_private.enqueue_push_notification(
      new.owner_user_id,
      'live_invite_accepted',
      new.id,
      new.revision,
      'live_invite_accepted:' || new.id || ':' || new.revision::text,
      'live_workout',
      'high',
      pg_catalog.clock_timestamp() + interval '1 day'
    );
  elsif old.status in ('waiting', 'ready') and new.status = 'active' then
    for recipient in
      select member.user_id
      from gymapp_private.live_workout_members as member
      where member.room_id = new.id
      order by member.user_id
    loop
      perform gymapp_private.enqueue_push_notification(
        recipient.user_id,
        'live_room_started',
        new.id,
        new.revision,
        'live_room_started:' || new.id || ':' || new.revision::text,
        'live_workout',
        'high',
        pg_catalog.clock_timestamp() + interval '1 day'
      );
    end loop;
  end if;

  if old.status = 'active' and new.status in ('active', 'completed') then
    for finished_member in
      select member.user_id
      from gymapp_private.live_workout_members as member
      where member.room_id = new.id
        and member.state = 'finished'
        and member.updated_at = new.updated_at
      order by member.user_id
    loop
      for recipient in
        select member.user_id
        from gymapp_private.live_workout_members as member
        where member.room_id = new.id
          and member.user_id <> finished_member.user_id
        order by member.user_id
      loop
        perform gymapp_private.enqueue_push_notification(
          recipient.user_id,
          'live_participant_finished',
          new.id,
          new.revision,
          'live_participant_finished:' || new.id || ':' || new.revision::text,
          'live_workout',
          'high',
          pg_catalog.clock_timestamp() + interval '1 day'
        );
      end loop;
    end loop;
  end if;

  if old.status in ('waiting', 'ready', 'active')
     and new.status in ('completed', 'cancelled', 'expired') then
    for recipient in
      select member.user_id
      from gymapp_private.live_workout_members as member
      where member.room_id = new.id
      order by member.user_id
    loop
      perform gymapp_private.enqueue_push_notification(
        recipient.user_id,
        'live_room_closed',
        new.id,
        new.revision,
        'live_room_closed:' || new.id || ':' || new.revision::text,
        'live_workout',
        'high',
        pg_catalog.clock_timestamp() + interval '1 day'
      );
    end loop;
  end if;
  return new;
end
$function$;

revoke all on function gymapp_private.enqueue_live_workout_room_push()
  from public, anon, authenticated, service_role;

-- Older projections deliberately tolerated up to 24 hours of device clock
-- skew. Friend activity is a completed-history surface. Recompute its bounded
-- view from the current validated state after removing only future sessions;
-- this fixes existing projections at read time without an unbounded backfill.
create or replace function gymapp_private.social_friend_activity_from_state(p_state jsonb)
returns table (recent_workouts jsonb, exercise_records jsonb)
language plpgsql
volatile
strict
security invoker
set search_path = ''
as $function$
declare
  filtered_state jsonb;
begin
  perform gymapp_private.validate_user_state(p_state);
  filtered_state := pg_catalog.jsonb_set(
    p_state,
    '{sessions}',
    coalesce((
      select pg_catalog.jsonb_agg(session.value order by session.ordinality)
      from pg_catalog.jsonb_array_elements(
        case when pg_catalog.jsonb_typeof(p_state->'sessions') = 'array'
          then p_state->'sessions' else '[]'::jsonb end
      ) with ordinality as session(value, ordinality)
      where coalesce(session.value->>'date', session.value->>'startedAt')::numeric <=
        (extract(epoch from pg_catalog.clock_timestamp()) * 1000)::numeric
    ), '[]'::jsonb),
    false
  );
  return query
  select activity.recent_workouts, activity.exercise_records
  from gymapp_private.social_activity_from_state(filtered_state) as activity;
end
$function$;

revoke all on function gymapp_private.social_friend_activity_from_state(jsonb)
  from public, anon, authenticated, service_role;

-- All newly-written projections use the strict completed-history boundary.
-- Existing current rows need no table-wide rewrite: social_friend_details below
-- detects the legacy future-session case and recomputes that one bounded read.
create or replace function gymapp_private.refresh_social_activity_projection()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  owner_user_id uuid;
  activity record;
begin
  owner_user_id := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
  if tg_op = 'UPDATE' and old.user_id is distinct from new.user_id then
    raise exception using errcode = '22023', message = 'GymApp cloud state owner is immutable.';
  end if;
  if auth.uid() is not null and auth.uid() <> owner_user_id then
    raise exception using errcode = '42501', message = 'Cloud state can only refresh its owner social projection.';
  end if;
  if tg_op = 'DELETE' then
    delete from gymapp_private.social_activity_projection as projection
    where projection.user_id = owner_user_id;
    return old;
  end if;
  if tg_op = 'UPDATE'
     and old.user_id is not distinct from new.user_id
     and old.state is not distinct from new.state then
    return new;
  end if;
  select * into strict activity
  from gymapp_private.social_friend_activity_from_state(new.state);
  insert into gymapp_private.social_activity_projection (
    user_id, source_revision, recent_workouts, exercise_records, projected_at
  ) values (
    new.user_id, new.updated_at, activity.recent_workouts,
    activity.exercise_records, pg_catalog.clock_timestamp()
  )
  on conflict (user_id) do update
  set source_revision = excluded.source_revision,
      recent_workouts = excluded.recent_workouts,
      exercise_records = excluded.exercise_records,
      projected_at = excluded.projected_at;
  return new;
end
$function$;

revoke all on function gymapp_private.refresh_social_activity_projection()
  from public, anon, authenticated, service_role;

create or replace function public.social_friend_details(p_profile_id text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  target_user_id uuid;
  target_profile record;
  target_settings record;
  state_value jsonb;
  state_revision timestamptz;
  progression_xp integer;
  progression_level integer;
  progression_workouts integer;
  activity_recent_workouts jsonb := '[]'::jsonb;
  activity_exercise_records jsonb := '[]'::jsonb;
  is_current boolean := false;
  filtered_activity record;
  has_future_session boolean := false;
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  caller_user_id := gymapp_private.social_require_caller('friend_details');

  begin
    perform gymapp_private.social_ensure_account_rows(caller_user_id);

    if p_profile_id is null or p_profile_id !~ '^p_[0-9a-f]{32}$' then
      raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
    end if;
    select profile.user_id,
           profile.public_id,
           gymapp_private.social_safe_display_name(profile.display_name) as display_name
    into target_profile
    from public.profiles as profile
    where profile.public_id = p_profile_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
    end if;
    target_user_id := target_profile.user_id;
    perform gymapp_private.social_lock_pair(caller_user_id, target_user_id);
    if not gymapp_private.social_pair_is_accepted(caller_user_id, target_user_id) then
      raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
    end if;

    select settings.share_progress,
           settings.share_recent_workouts,
           settings.share_records
    into strict target_settings
    from gymapp_private.social_settings as settings
    where settings.user_id = target_user_id
    for share;

    select state.state, state.updated_at,
           progression_row.xp, progression_row.level, progression_row.workouts,
           activity_row.recent_workouts, activity_row.exercise_records,
           quarantine.user_id is null
             and progression_row.source_revision = state.updated_at
             and activity_row.source_revision = state.updated_at
    into state_value, state_revision,
         progression_xp, progression_level, progression_workouts,
         activity_recent_workouts, activity_exercise_records, is_current
    from public.user_states as state
    join gymapp_private.user_state_progression as progression_row
      on progression_row.user_id = state.user_id
    join gymapp_private.social_activity_projection as activity_row
      on activity_row.user_id = state.user_id
    left join gymapp_private.user_state_quarantine as quarantine
      on quarantine.user_id = state.user_id
    where state.user_id = target_user_id;

    if not found then
      state_revision := null;
      is_current := false;
    elsif is_current then
      select exists (
        select 1
        from pg_catalog.jsonb_array_elements(
          case when pg_catalog.jsonb_typeof(state_value->'sessions') = 'array'
            then state_value->'sessions' else '[]'::jsonb end
        ) as session(value)
        where coalesce(session.value->>'date', session.value->>'startedAt')::numeric >
          (extract(epoch from pg_catalog.clock_timestamp()) * 1000)::numeric
      ) into has_future_session;
      if has_future_session then
        select * into strict filtered_activity
        from gymapp_private.social_friend_activity_from_state(state_value);
        activity_recent_workouts := filtered_activity.recent_workouts;
        activity_exercise_records := filtered_activity.exercise_records;
      end if;
    end if;

    return pg_catalog.jsonb_build_object(
      'version', 1,
      'friend', pg_catalog.jsonb_build_object(
        'profileId', target_profile.public_id,
        'displayName', target_profile.display_name,
        'xp', case when target_settings.share_progress and is_current then progression_xp else null end,
        'level', case when target_settings.share_progress and is_current then progression_level else null end,
        'workouts', case when target_settings.share_progress and is_current then progression_workouts else null end,
        'progressShared', target_settings.share_progress,
        'statsAvailable', target_settings.share_progress and is_current,
        'progressUpdatedAt', case when target_settings.share_progress and is_current
          then state_revision else null end
      ),
      'sharing', pg_catalog.jsonb_build_object(
        'progress', target_settings.share_progress,
        'recentWorkouts', target_settings.share_recent_workouts,
        'records', target_settings.share_records
      ),
      'activityUpdatedAt', case
        when is_current
          and (target_settings.share_recent_workouts or target_settings.share_records)
          then state_revision else null end,
      'recentWorkouts', case
        when is_current and target_settings.share_recent_workouts
          then activity_recent_workouts else '[]'::jsonb end,
      'exerciseRecords', case
        when is_current and target_settings.share_records
          then activity_exercise_records else '[]'::jsonb end,
      'integrity', 'self_reported'
    );
  exception
    when sqlstate '22023' or sqlstate 'P0001' or sqlstate 'P0002' then
      get stacked diagnostics
        domain_error_code = returned_sqlstate,
        domain_error_message = message_text,
        domain_error_detail = pg_exception_detail,
        domain_error_hint = pg_exception_hint;
      return gymapp_private.social_domain_error_response(
        domain_error_code,
        domain_error_message,
        domain_error_detail,
        domain_error_hint
      );
  end;
end
$function$;

revoke all on function public.social_friend_details(text)
  from public, anon, authenticated, service_role;
grant execute on function public.social_friend_details(text) to authenticated;

-- A bounded, revision-fenced page contains enough data to render the same
-- read-only workout detail as local history without exposing notes or raw state.
create or replace function public.social_friend_workout_page(
  p_profile_id text,
  p_cursor text default null,
  p_expected_activity_revision timestamptz default null,
  p_limit integer default 5
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  target_user_id uuid;
  target_profile record;
  target_settings record;
  state_value jsonb;
  activity_revision timestamptz;
  items_json jsonb := '[]'::jsonb;
  next_cursor text;
begin
  caller_user_id := gymapp_private.social_require_caller('friend_details');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);

  if p_profile_id is null or p_profile_id !~ '^p_[0-9a-f]{32}$'
     or p_limit is distinct from 5
     or p_cursor is not null then
    raise exception using errcode = '22023', message = 'Friend workout page request is invalid.';
  end if;

  select profile.user_id,
         profile.public_id,
         gymapp_private.social_safe_display_name(profile.display_name) as display_name
  into target_profile
  from public.profiles as profile
  where profile.public_id = p_profile_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  target_user_id := target_profile.user_id;
  perform gymapp_private.social_lock_pair(caller_user_id, target_user_id);
  if not gymapp_private.social_pair_is_accepted(caller_user_id, target_user_id) then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;

  select settings.share_recent_workouts, settings.share_workout_details
  into strict target_settings
  from gymapp_private.social_settings as settings
  where settings.user_id = target_user_id
  for share;
  if not target_settings.share_recent_workouts
     or not target_settings.share_workout_details then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;

  select state.state, state.updated_at
  into state_value, activity_revision
  from public.user_states as state
  join gymapp_private.social_activity_projection as projection
    on projection.user_id = state.user_id
   and projection.source_revision = state.updated_at
  left join gymapp_private.user_state_quarantine as quarantine
    on quarantine.user_id = state.user_id
  where state.user_id = target_user_id
    and quarantine.user_id is null;

  if not found then
    if p_expected_activity_revision is not null then
      raise exception using errcode = 'P0001', message = 'Friend workout activity changed.';
    end if;
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'friend', pg_catalog.jsonb_build_object(
        'profileId', target_profile.public_id,
        'displayName', target_profile.display_name
      ),
      'activityRevision', null,
      'items', '[]'::jsonb,
      'nextCursor', null,
      'integrity', 'self_reported'
    );
  end if;
  if p_expected_activity_revision is not null
     and p_expected_activity_revision is distinct from activity_revision then
    raise exception using errcode = 'P0001', message = 'Friend workout activity changed.';
  end if;
  perform gymapp_private.validate_user_state(state_value);

  with raw_sessions as (
    select
      session.ordinality::bigint as session_number,
      session.value as session_value,
      coalesce(session.value->>'date', session.value->>'startedAt')::numeric as workout_millis
    from pg_catalog.jsonb_array_elements(
      case when pg_catalog.jsonb_typeof(state_value->'sessions') = 'array'
        then state_value->'sessions' else '[]'::jsonb end
    ) with ordinality as session(value, ordinality)
  ),
  recent_sessions as (
    select session.*
    from raw_sessions as session
    where session.workout_millis <= (
      extract(epoch from pg_catalog.clock_timestamp()) * 1000
    )::numeric
      and (
        exists (
          select 1
          from pg_catalog.jsonb_array_elements(
            case when pg_catalog.jsonb_typeof(session.session_value->'sets') = 'array'
              then session.session_value->'sets' else '[]'::jsonb end
          ) as flat_set(value)
        )
        or exists (
          select 1
          from pg_catalog.jsonb_array_elements(
            case when pg_catalog.jsonb_typeof(session.session_value->'exercises') = 'array'
              then session.session_value->'exercises' else '[]'::jsonb end
          ) as exercise(value)
          cross join lateral pg_catalog.jsonb_array_elements(
            case when pg_catalog.jsonb_typeof(exercise.value->'sets') = 'array'
              then exercise.value->'sets' else '[]'::jsonb end
          ) as nested_set(value)
        )
      )
    order by session.workout_millis desc, session.session_number desc
    limit 5
  ),
  eligible_sessions as (
    select session.*
    from recent_sessions as session
    order by session.workout_millis desc, session.session_number desc
    limit 5
  ),
  page_sessions as (
    select *, pg_catalog.row_number() over (
      order by workout_millis desc, session_number desc
    ) as page_position
    from eligible_sessions
  ),
  native_sets as (
    select
      session.session_number,
      session.workout_millis,
      session.page_position,
      exercise.ordinality::bigint as exercise_order,
      set_item.ordinality::bigint as set_order,
      pg_catalog.btrim(exercise.value->>'name') as exercise_name,
      case
        when pg_catalog.jsonb_typeof(exercise.value->'catalogKey') = 'string'
         and exercise.value->>'catalogKey' ~ '^[a-z0-9_]{1,64}$'
          then exercise.value->>'catalogKey'
        else null
      end as catalog_key,
      (set_item.value->>'weight')::numeric as weight_value,
      (set_item.value->>'reps')::integer as reps_value
    from page_sessions as session
    cross join lateral pg_catalog.jsonb_array_elements(
      case when pg_catalog.jsonb_typeof(session.session_value->'exercises') = 'array'
        then session.session_value->'exercises' else '[]'::jsonb end
    ) with ordinality as exercise(value, ordinality)
    cross join lateral pg_catalog.jsonb_array_elements(
      case when pg_catalog.jsonb_typeof(exercise.value->'sets') = 'array'
        then exercise.value->'sets' else '[]'::jsonb end
    ) with ordinality as set_item(value, ordinality)
    where session.page_position <= p_limit
      and not (
        pg_catalog.jsonb_typeof(session.session_value->'sets') is not distinct from 'array'
        and pg_catalog.jsonb_array_length(session.session_value->'sets') > 0
      )
      and gymapp_private.social_name_is_safe(pg_catalog.btrim(exercise.value->>'name'))
  ),
  flat_sets as (
    select
      session.session_number,
      session.workout_millis,
      session.page_position,
      set_item.ordinality::bigint as exercise_order,
      set_item.ordinality::bigint as set_order,
      pg_catalog.btrim(coalesce(
        set_item.value->>'exerciseName', set_item.value->>'name'
      )) as exercise_name,
      case
        when pg_catalog.jsonb_typeof(set_item.value->'catalogKey') = 'string'
         and set_item.value->>'catalogKey' ~ '^[a-z0-9_]{1,64}$'
          then set_item.value->>'catalogKey'
        else null
      end as catalog_key,
      (set_item.value->>'weight')::numeric as weight_value,
      (set_item.value->>'reps')::integer as reps_value
    from page_sessions as session
    cross join lateral pg_catalog.jsonb_array_elements(
      case when pg_catalog.jsonb_typeof(session.session_value->'sets') = 'array'
        then session.session_value->'sets' else '[]'::jsonb end
    ) with ordinality as set_item(value, ordinality)
    where session.page_position <= p_limit
      and pg_catalog.jsonb_typeof(session.session_value->'sets') = 'array'
      and pg_catalog.jsonb_array_length(session.session_value->'sets') > 0
      and gymapp_private.social_name_is_safe(pg_catalog.btrim(coalesce(
        set_item.value->>'exerciseName', set_item.value->>'name'
      )))
  ),
  identified_sets as (
    select set_row.*,
      case when set_row.catalog_key is not null
        then 'catalog:' || set_row.catalog_key
        else 'name:' || gymapp_private.social_normalize_name(set_row.exercise_name)
      end as exercise_identity
    from (
      select * from native_sets
      union all
      select * from flat_sets
    ) as set_row
  ),
  sets_with_exercise_order as (
    select set_row.*,
      pg_catalog.min(set_row.exercise_order) over (
        partition by set_row.session_number, set_row.exercise_identity
      ) as first_exercise_order
    from identified_sets as set_row
  ),
  ranked_sets as (
    select set_row.*,
      pg_catalog.row_number() over (
        partition by set_row.session_number
        order by set_row.exercise_order, set_row.set_order, set_row.exercise_identity
      ) as workout_set_position,
      pg_catalog.row_number() over (
        partition by set_row.session_number, set_row.exercise_identity
        order by set_row.exercise_order, set_row.set_order
      ) as exercise_set_position,
      pg_catalog.dense_rank() over (
        partition by set_row.session_number
        order by set_row.first_exercise_order, set_row.exercise_identity
      ) as exercise_position
    from sets_with_exercise_order as set_row
  ),
  exercise_rows as (
    select
      set_row.session_number,
      set_row.exercise_identity,
      pg_catalog.min(set_row.exercise_order) as exercise_order,
      pg_catalog.min(set_row.exercise_name) as exercise_name,
      pg_catalog.max(set_row.catalog_key) as catalog_key,
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'weightKg', set_row.weight_value,
          'reps', set_row.reps_value
        ) order by set_row.set_order
      ) as sets_json
    from ranked_sets as set_row
    where set_row.workout_set_position <= 100
      and set_row.exercise_set_position <= 20
      and set_row.exercise_position <= 20
    group by set_row.session_number, set_row.exercise_identity
  ),
  workout_rollups as (
    select
      set_row.session_number,
      pg_catalog.count(*)::integer as set_count,
      pg_catalog.count(distinct set_row.exercise_identity)::integer as exercise_count,
      pg_catalog.bool_or(
        set_row.workout_set_position > 100
        or set_row.exercise_set_position > 20
        or set_row.exercise_position > 20
      ) as truncated
    from ranked_sets as set_row
    group by set_row.session_number
  ),
  workout_exercises as (
    select exercise.session_number,
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'catalogKey', exercise.catalog_key,
          'name', exercise.exercise_name,
          'sets', exercise.sets_json
        ) order by exercise.exercise_order, exercise.exercise_identity
      ) as exercises_json
    from exercise_rows as exercise
    group by exercise.session_number
  ),
  page_items as (
    select
      session.page_position,
      session.workout_millis,
      session.session_number,
      pg_catalog.jsonb_build_object(
        'workoutId', 'fw_' || pg_catalog.substr(
          pg_catalog.encode(
            extensions.digest(
              pg_catalog.convert_to(
                target_profile.public_id || ':' || session.workout_millis::text || ':' ||
                  session.session_number::text || ':' || activity_revision::text,
                'UTF8'
              ),
              'sha256'
            ),
            'hex'
          ),
          1,
          32
        ),
        'startedAt', pg_catalog.to_timestamp(
          (session.workout_millis / 1000)::double precision
        ),
        'workoutDay', ((pg_catalog.to_timestamp(
          (session.workout_millis / 1000)::double precision
        ) at time zone 'UTC')::date)::text,
        'exerciseCount', rollup.exercise_count,
        'setCount', rollup.set_count,
        'truncated', coalesce(rollup.truncated, false),
        'exercises', coalesce(exercises.exercises_json, '[]'::jsonb)
      ) as item_json
    from page_sessions as session
    join workout_rollups as rollup on rollup.session_number = session.session_number
    join workout_exercises as exercises on exercises.session_number = session.session_number
    where session.page_position <= p_limit
  )
  select
    coalesce(pg_catalog.jsonb_agg(
      item.item_json order by item.page_position
    ), '[]'::jsonb),
    null::text
  into items_json, next_cursor
  from page_items as item;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'friend', pg_catalog.jsonb_build_object(
      'profileId', target_profile.public_id,
      'displayName', target_profile.display_name
    ),
    'activityRevision', activity_revision,
    'items', items_json,
    'nextCursor', next_cursor,
    'integrity', 'self_reported'
  );
end
$function$;

revoke all on function public.social_friend_workout_page(
  text, text, timestamptz, integer
) from public, anon, authenticated, service_role;
grant execute on function public.social_friend_workout_page(
  text, text, timestamptz, integer
) to authenticated;

comment on function public.social_friend_workout_page(text, text, timestamptz, integer) is
  'Accepted-friend-only, privacy-checked, revision-fenced detail for exactly the same latest five workouts covered by share_recent_workouts. Cursor requests and non-five limits fail closed. Notes and raw state never leave the server; each item is capped at 20 exercises and 100 sets.';

do $verify$
begin
  if pg_catalog.has_function_privilege(
       'anon',
       'public.social_friend_workout_page(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.social_friend_workout_page(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.social_workout_detail_privacy()',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.social_workout_detail_privacy()',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.social_update_workout_detail_privacy(boolean,bigint)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.social_friend_workout_detail_capability(text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.social_friend_workout_detail_capability(text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.social_update_workout_detail_privacy(boolean,bigint)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.social_respond_live_workout_invite(uuid,uuid,text,text,bigint,uuid)',
       'EXECUTE'
     ) then
    raise exception 'GymApp social/live grants are invalid.';
  end if;
end
$verify$;

commit;
