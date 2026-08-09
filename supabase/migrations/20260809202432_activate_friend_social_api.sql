begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regclass('gymapp_private.social_settings') is null
     or pg_catalog.to_regclass('gymapp_private.friendships') is null
     or pg_catalog.to_regclass('gymapp_private.friend_blocks') is null
     or pg_catalog.to_regclass('gymapp_private.social_activity_projection') is null
     or pg_catalog.to_regclass('gymapp_private.social_workout_invites') is null
     or pg_catalog.to_regprocedure('gymapp_private.validate_social_workout(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_lock_pair(uuid,uuid)') is null then
    raise exception 'GymApp social activation prerequisites are missing.';
  end if;

  if exists (
    select 1
    from public.user_states as state
    join gymapp_private.user_state_progression as progression
      on progression.user_id = state.user_id
     and progression.source_revision = state.updated_at
    where not exists (
      select 1 from gymapp_private.user_state_quarantine as quarantine
      where quarantine.user_id = state.user_id
    )
      and not exists (
        select 1 from gymapp_private.social_activity_projection as activity
        where activity.user_id = state.user_id
          and activity.source_revision = state.updated_at
      )
  ) then
    raise exception 'GymApp social activation refused a stale projection backfill.';
  end if;
end
$preflight$;

create or replace function gymapp_private.social_purge_expired_workout_payloads(
  p_user_id uuid
)
returns void
language plpgsql
volatile
strict
security definer
set search_path = ''
as $function$
declare
  cleanup_time timestamptz := pg_catalog.clock_timestamp();
begin
  if auth.uid() is distinct from p_user_id then
    raise exception using errcode = '42501', message = 'Workout invite retention is owner-bound.';
  end if;

  with expired_candidates as (
    select invite.id
    from gymapp_private.social_workout_invites as invite
    where invite.status = 'pending'
      and invite.expires_at <= cleanup_time
      and p_user_id in (invite.sender_user_id, invite.recipient_user_id)
    order by invite.expires_at, invite.id
    limit 100
    for update skip locked
  )
  update gymapp_private.social_workout_invites as invite
  set status = 'expired',
      revision = least(invite.revision + 1, 2147483647),
      responded_at = invite.expires_at,
      updated_at = cleanup_time
  from expired_candidates as candidate
  where invite.id = candidate.id;

  -- Keep only an idempotency/status tombstone after the bounded retry window.
  -- The tombstone prevents a reused client_request_id from creating a second
  -- invitation without retaining exercises, names, weights, or repetitions.
  with purge_candidates as (
    select invite.id
    from gymapp_private.social_workout_invites as invite
    where invite.workout is not null
      and p_user_id in (invite.sender_user_id, invite.recipient_user_id)
      and (
        (invite.status = 'accepted'
          and invite.responded_at <= cleanup_time - interval '30 days')
        or (invite.status in ('declined', 'cancelled', 'expired')
          and invite.responded_at <= cleanup_time - interval '24 hours')
      )
    order by invite.responded_at, invite.id
    limit 100
    for update skip locked
  )
  update gymapp_private.social_workout_invites as invite
  set workout = null,
      summary = null,
      payload_purged_at = cleanup_time,
      updated_at = cleanup_time
  from purge_candidates as candidate
  where invite.id = candidate.id;
end
$function$;

revoke all on function gymapp_private.social_purge_expired_workout_payloads(uuid)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_require_caller(p_action text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
begin
  if caller_user_id is null
     or not gymapp_private.has_current_auth_session(caller_user_id) then
    raise exception using errcode = '42501', message = 'A live authenticated session is required.';
  end if;
  perform gymapp_private.consume_social_rate_limit(caller_user_id, p_action);
  return caller_user_id;
end
$function$;

revoke all on function gymapp_private.social_require_caller(text)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_ensure_account_rows(p_user_id uuid)
returns void
language plpgsql
volatile
strict
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is distinct from p_user_id then
    raise exception using errcode = '42501', message = 'Social account initialization is owner-bound.';
  end if;

  insert into public.profiles (
    user_id, display_name, xp, level, workouts, progression_version, updated_at
  ) values (
    p_user_id, 'GymApp user', 0, 1, 0, 1, pg_catalog.clock_timestamp()
  ) on conflict (user_id) do nothing;

  insert into gymapp_private.social_settings (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;
end
$function$;

revoke all on function gymapp_private.social_ensure_account_rows(uuid)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_pair_is_blocked(
  p_first_user_id uuid,
  p_second_user_id uuid
)
returns boolean
language sql
stable
strict
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from gymapp_private.friend_blocks as block
    where (block.blocker_user_id = p_first_user_id and block.blocked_user_id = p_second_user_id)
       or (block.blocker_user_id = p_second_user_id and block.blocked_user_id = p_first_user_id)
  )
$function$;

revoke all on function gymapp_private.social_pair_is_blocked(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_pair_is_accepted(
  p_first_user_id uuid,
  p_second_user_id uuid
)
returns boolean
language sql
stable
strict
security definer
set search_path = ''
as $function$
  select not gymapp_private.social_pair_is_blocked(p_first_user_id, p_second_user_id)
    and exists (
      select 1
      from gymapp_private.friendships as friendship
      where friendship.user_low_id = case
              when p_first_user_id::text < p_second_user_id::text
                then p_first_user_id else p_second_user_id end
        and friendship.user_high_id = case
              when p_first_user_id::text < p_second_user_id::text
                then p_second_user_id else p_first_user_id end
        and friendship.status = 'accepted'
    )
$function$;

revoke all on function gymapp_private.social_pair_is_accepted(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_cancel_pending_workout_invites(
  p_first_user_id uuid,
  p_second_user_id uuid
)
returns void
language plpgsql
volatile
strict
security definer
set search_path = ''
as $function$
declare
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  update gymapp_private.social_workout_invites as invite
  set status = case
        when invite.expires_at <= mutation_time then 'expired'
        else 'cancelled'
      end,
      revision = least(invite.revision + 1, 2147483647),
      responded_at = case
        when invite.expires_at <= mutation_time then invite.expires_at
        else mutation_time
      end,
      updated_at = mutation_time
  where invite.status = 'pending'
    and (
      (invite.sender_user_id = p_first_user_id and invite.recipient_user_id = p_second_user_id)
      or (invite.sender_user_id = p_second_user_id and invite.recipient_user_id = p_first_user_id)
    );
end
$function$;

revoke all on function gymapp_private.social_cancel_pending_workout_invites(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.social_dashboard()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  self_json jsonb;
  friends_json jsonb;
  incoming_json jsonb;
  outgoing_json jsonb;
  blocked_json jsonb;
  pending_invite_count integer;
begin
  caller_user_id := gymapp_private.social_require_caller('dashboard');
  -- Opportunistic retention runs only on read endpoints that never acquire a
  -- pair advisory lock. Mutations acquire the pair lock first and must not
  -- enter with workout-invite row locks held (that order can deadlock block or
  -- remove against another mutation for the same pair).
  perform gymapp_private.social_purge_expired_workout_payloads(caller_user_id);
  perform gymapp_private.social_ensure_account_rows(caller_user_id);

  select pg_catalog.jsonb_build_object(
    'profileId', profile.public_id,
    'friendCode', profile.public_id,
    'displayName', gymapp_private.social_safe_display_name(profile.display_name),
    'xp', case when state.user_id is not null
                    and progression.source_revision = state.updated_at
                    and activity.source_revision = state.updated_at
                    and quarantine.user_id is null
               then progression.xp else null end,
    'level', case when state.user_id is not null
                       and progression.source_revision = state.updated_at
                       and activity.source_revision = state.updated_at
                       and quarantine.user_id is null
                  then progression.level else null end,
    'workouts', case when state.user_id is not null
                          and progression.source_revision = state.updated_at
                          and activity.source_revision = state.updated_at
                          and quarantine.user_id is null
                     then progression.workouts else null end,
    'statsAvailable', state.user_id is not null
      and progression.source_revision = state.updated_at
      and activity.source_revision = state.updated_at
      and quarantine.user_id is null,
    'progressUpdatedAt', case when state.user_id is not null
                                  and progression.source_revision = state.updated_at
                                  and activity.source_revision = state.updated_at
                                  and quarantine.user_id is null
                             then state.updated_at else null end,
    'privacy', pg_catalog.jsonb_build_object(
      'allowRequests', settings.allow_requests,
      'shareProgress', settings.share_progress,
      'shareRecentWorkouts', settings.share_recent_workouts,
      'shareRecords', settings.share_records
    ),
    'settingsRevision', settings.revision
  )
  into strict self_json
  from public.profiles as profile
  join gymapp_private.social_settings as settings on settings.user_id = profile.user_id
  left join public.user_states as state on state.user_id = profile.user_id
  left join gymapp_private.user_state_progression as progression
    on progression.user_id = profile.user_id
  left join gymapp_private.social_activity_projection as activity
    on activity.user_id = profile.user_id
  left join gymapp_private.user_state_quarantine as quarantine
    on quarantine.user_id = profile.user_id
  where profile.user_id = caller_user_id;

  with accepted as (
    select
      friendship.id,
      friendship.revision,
      case when friendship.user_low_id = caller_user_id
        then friendship.user_high_id else friendship.user_low_id end as friend_user_id
    from gymapp_private.friendships as friendship
    where friendship.status = 'accepted'
      and caller_user_id in (friendship.user_low_id, friendship.user_high_id)
  ),
  visible as (
    select
      accepted.id,
      accepted.revision,
      profile.public_id,
      gymapp_private.social_safe_display_name(profile.display_name) as display_name,
      coalesce(settings.share_progress, false) as share_progress,
      state.updated_at as state_revision,
      progression.source_revision as progression_revision,
      activity.source_revision as activity_revision,
      quarantine.user_id as quarantined_user_id,
      progression.xp,
      progression.level,
      progression.workouts
    from accepted
    join public.profiles as profile on profile.user_id = accepted.friend_user_id
    left join gymapp_private.social_settings as settings on settings.user_id = accepted.friend_user_id
    left join public.user_states as state on state.user_id = accepted.friend_user_id
    left join gymapp_private.user_state_progression as progression
      on progression.user_id = accepted.friend_user_id
    left join gymapp_private.social_activity_projection as activity
      on activity.user_id = accepted.friend_user_id
    left join gymapp_private.user_state_quarantine as quarantine
      on quarantine.user_id = accepted.friend_user_id
    where not gymapp_private.social_pair_is_blocked(caller_user_id, accepted.friend_user_id)
  ),
  bounded as (
    select *
    from visible
    order by
      case when share_progress
                 and state_revision is not null
                 and progression_revision = state_revision
                 and activity_revision = state_revision
                 and quarantined_user_id is null then xp end desc nulls last,
      case when share_progress
                 and state_revision is not null
                 and progression_revision = state_revision
                 and activity_revision = state_revision
                 and quarantined_user_id is null then workouts end desc nulls last,
      pg_catalog.lower(display_name), public_id
    limit 200
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'friendshipId', bounded.id,
      'profileId', bounded.public_id,
      'displayName', bounded.display_name,
      'xp', case when bounded.share_progress
                       and bounded.state_revision is not null
                       and bounded.progression_revision = bounded.state_revision
                       and bounded.activity_revision = bounded.state_revision
                       and bounded.quarantined_user_id is null
                  then bounded.xp else null end,
      'level', case when bounded.share_progress
                          and bounded.state_revision is not null
                          and bounded.progression_revision = bounded.state_revision
                          and bounded.activity_revision = bounded.state_revision
                          and bounded.quarantined_user_id is null
                     then bounded.level else null end,
      'workouts', case when bounded.share_progress
                             and bounded.state_revision is not null
                             and bounded.progression_revision = bounded.state_revision
                             and bounded.activity_revision = bounded.state_revision
                             and bounded.quarantined_user_id is null
                        then bounded.workouts else null end,
      'progressShared', bounded.share_progress,
      'statsAvailable', bounded.share_progress
        and bounded.state_revision is not null
        and bounded.progression_revision = bounded.state_revision
        and bounded.activity_revision = bounded.state_revision
        and bounded.quarantined_user_id is null,
      'progressUpdatedAt', case when bounded.share_progress
                                     and bounded.state_revision is not null
                                     and bounded.progression_revision = bounded.state_revision
                                     and bounded.activity_revision = bounded.state_revision
                                     and bounded.quarantined_user_id is null
                                then bounded.state_revision else null end,
      'friendshipRevision', bounded.revision,
      'status', 'accepted'
    ) order by
      case when bounded.share_progress
                 and bounded.state_revision is not null
                 and bounded.progression_revision = bounded.state_revision
                 and bounded.activity_revision = bounded.state_revision
                 and bounded.quarantined_user_id is null then bounded.xp end desc nulls last,
      case when bounded.share_progress
                 and bounded.state_revision is not null
                 and bounded.progression_revision = bounded.state_revision
                 and bounded.activity_revision = bounded.state_revision
                 and bounded.quarantined_user_id is null then bounded.workouts end desc nulls last,
      pg_catalog.lower(bounded.display_name), bounded.public_id
  ), '[]'::jsonb)
  into friends_json
  from bounded;

  with requests as (
    select
      friendship.id,
      friendship.revision,
      friendship.requested_at,
      friendship.requester_user_id as peer_user_id
    from gymapp_private.friendships as friendship
    where friendship.status = 'pending'
      and friendship.requester_user_id <> caller_user_id
      and caller_user_id in (friendship.user_low_id, friendship.user_high_id)
      and not gymapp_private.social_pair_is_blocked(
        caller_user_id,
        friendship.requester_user_id
      )
    order by friendship.requested_at desc, friendship.id
    limit 100
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'friendshipId', request.id,
      'profileId', profile.public_id,
      'displayName', gymapp_private.social_safe_display_name(profile.display_name),
      'requestedAt', request.requested_at,
      'friendshipRevision', request.revision,
      'status', 'pending'
    ) order by request.requested_at desc, request.id
  ), '[]'::jsonb)
  into incoming_json
  from requests as request
  join public.profiles as profile on profile.user_id = request.peer_user_id;

  with requests as (
    select
      friendship.id,
      friendship.revision,
      friendship.requested_at,
      case when friendship.user_low_id = caller_user_id
        then friendship.user_high_id else friendship.user_low_id end as peer_user_id
    from gymapp_private.friendships as friendship
    where friendship.status = 'pending'
      and friendship.requester_user_id = caller_user_id
      and not gymapp_private.social_pair_is_blocked(
        caller_user_id,
        case when friendship.user_low_id = caller_user_id
          then friendship.user_high_id else friendship.user_low_id end
      )
    order by friendship.requested_at desc, friendship.id
    limit 25
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'friendshipId', request.id,
      'profileId', profile.public_id,
      'displayName', gymapp_private.social_safe_display_name(profile.display_name),
      'requestedAt', request.requested_at,
      'friendshipRevision', request.revision,
      'status', 'pending'
    ) order by request.requested_at desc, request.id
  ), '[]'::jsonb)
  into outgoing_json
  from requests as request
  join public.profiles as profile on profile.user_id = request.peer_user_id;

  with bounded as (
    select block.blocked_user_id, block.blocked_at
    from gymapp_private.friend_blocks as block
    where block.blocker_user_id = caller_user_id
    order by block.blocked_at desc, block.blocked_user_id
    limit 200
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'profileId', profile.public_id,
      'displayName', gymapp_private.social_safe_display_name(profile.display_name),
      'blockedAt', bounded.blocked_at
    ) order by bounded.blocked_at desc, profile.public_id
  ), '[]'::jsonb)
  into blocked_json
  from bounded
  join public.profiles as profile on profile.user_id = bounded.blocked_user_id;

  select pg_catalog.count(*)::integer
  into pending_invite_count
  from gymapp_private.social_workout_invites as invite
  where invite.recipient_user_id = caller_user_id
    and invite.status = 'pending'
    and invite.expires_at > pg_catalog.clock_timestamp()
    and gymapp_private.social_pair_is_accepted(invite.sender_user_id, caller_user_id);

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'self', self_json,
    'friends', friends_json,
    'incoming', incoming_json,
    'outgoing', outgoing_json,
    'blocked', blocked_json,
    'pendingWorkoutInviteCount', pending_invite_count
  );
end
$function$;

revoke all on function public.social_dashboard()
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
  state_revision timestamptz;
  progression_xp integer;
  progression_level integer;
  progression_workouts integer;
  activity_recent_workouts jsonb := '[]'::jsonb;
  activity_exercise_records jsonb := '[]'::jsonb;
  is_current boolean := false;
begin
  caller_user_id := gymapp_private.social_require_caller('friend_details');
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

  select
    settings.share_progress,
    settings.share_recent_workouts,
    settings.share_records
  into strict target_settings
  from gymapp_private.social_settings as settings
  where settings.user_id = target_user_id
  for share;

  select state.updated_at,
         progression_row.xp, progression_row.level, progression_row.workouts,
         activity_row.recent_workouts, activity_row.exercise_records,
         quarantine.user_id is null
           and progression_row.source_revision = state.updated_at
           and activity_row.source_revision = state.updated_at
  into state_revision,
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
      when is_current and (target_settings.share_recent_workouts or target_settings.share_records)
        then state_revision else null end,
    'recentWorkouts', case
      when is_current and target_settings.share_recent_workouts
        then activity_recent_workouts else '[]'::jsonb end,
    'exerciseRecords', case
      when is_current and target_settings.share_records
        then activity_exercise_records else '[]'::jsonb end,
    'integrity', 'self_reported'
  );
end
$function$;

revoke all on function public.social_friend_details(text)
  from public, anon, authenticated, service_role;

create or replace function public.social_send_friend_request(p_friend_code text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  target_user_id uuid;
  low_user_id uuid;
  high_user_id uuid;
  target_allows_requests boolean;
  friendship_row record;
  friendship_exists boolean := false;
  caller_accepted_count integer;
  target_accepted_count integer;
  caller_pending_count integer;
  target_pending_count integer;
  request_time timestamptz := pg_catalog.clock_timestamp();
begin
  caller_user_id := gymapp_private.social_require_caller('send_friend');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);

  if p_friend_code is null or p_friend_code !~ '^p_[0-9a-f]{32}$' then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;
  select profile.user_id into target_user_id
  from public.profiles as profile
  where profile.public_id = p_friend_code;
  if not found or target_user_id = caller_user_id then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

  perform gymapp_private.social_lock_pair(caller_user_id, target_user_id);
  if gymapp_private.social_pair_is_blocked(caller_user_id, target_user_id) then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

  insert into gymapp_private.social_settings (user_id)
  values (target_user_id)
  on conflict (user_id) do nothing;
  select settings.allow_requests into strict target_allows_requests
  from gymapp_private.social_settings as settings
  where settings.user_id = target_user_id
  for share;

  low_user_id := case when caller_user_id::text < target_user_id::text
    then caller_user_id else target_user_id end;
  high_user_id := case when caller_user_id::text < target_user_id::text
    then target_user_id else caller_user_id end;

  select friendship.* into friendship_row
  from gymapp_private.friendships as friendship
  where friendship.user_low_id = low_user_id
    and friendship.user_high_id = high_user_id
  for update;
  friendship_exists := found;

  if friendship_exists and friendship_row.status = 'accepted' then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

  if friendship_exists
     and friendship_row.status = 'pending'
     and friendship_row.requester_user_id = target_user_id then
    select pg_catalog.count(*)::integer into caller_accepted_count
    from gymapp_private.friendships as friendship
    where friendship.status = 'accepted'
      and caller_user_id in (friendship.user_low_id, friendship.user_high_id);
    select pg_catalog.count(*)::integer into target_accepted_count
    from gymapp_private.friendships as friendship
    where friendship.status = 'accepted'
      and target_user_id in (friendship.user_low_id, friendship.user_high_id);

    if caller_accepted_count < 200
       and target_accepted_count < 200
       and friendship_row.revision < 2147483647 then
      update gymapp_private.friendships as friendship
      set status = 'accepted',
          revision = friendship.revision + 1,
          responded_at = request_time,
          updated_at = request_time
      where friendship.id = friendship_row.id;
    end if;
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

  if friendship_exists and friendship_row.status = 'pending' then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;
  if not target_allows_requests then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

  select pg_catalog.count(*)::integer into caller_pending_count
  from gymapp_private.friendships as friendship
  where friendship.status = 'pending'
    and friendship.requester_user_id = caller_user_id;
  select pg_catalog.count(*)::integer into target_pending_count
  from gymapp_private.friendships as friendship
  where friendship.status = 'pending'
    and friendship.requester_user_id <> target_user_id
    and target_user_id in (friendship.user_low_id, friendship.user_high_id);
  if caller_pending_count >= 25 or target_pending_count >= 100 then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

  if friendship_exists then
    if friendship_row.revision < 2147483647 then
      update gymapp_private.friendships as friendship
      set requester_user_id = caller_user_id,
          status = 'pending',
          revision = friendship.revision + 1,
          requested_at = request_time,
          responded_at = null,
          updated_at = request_time
      where friendship.id = friendship_row.id;
    end if;
  else
    insert into gymapp_private.friendships (
      user_low_id, user_high_id, requester_user_id, status,
      revision, requested_at, responded_at, updated_at
    ) values (
      low_user_id, high_user_id, caller_user_id, 'pending',
      1, request_time, null, request_time
    );
  end if;
  return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
end
$function$;

revoke all on function public.social_send_friend_request(text)
  from public, anon, authenticated, service_role;

create or replace function public.social_respond_friend_request(
  p_friendship_id text,
  p_decision text,
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
  friendship_row record;
  desired_status text;
  caller_accepted_count integer;
  peer_accepted_count integer;
  peer_user_id uuid;
  response_time timestamptz := pg_catalog.clock_timestamp();
begin
  caller_user_id := gymapp_private.social_require_caller('respond_friend');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);
  if p_friendship_id is null or p_friendship_id !~ '^f_[0-9a-f]{32}$'
     or p_decision is null or p_decision not in ('accept', 'decline')
     or p_expected_revision is null
     or p_expected_revision not between 1 and 2147483647 then
    raise exception using errcode = '22023', message = 'Friend request response is invalid.';
  end if;
  desired_status := case when p_decision = 'accept' then 'accepted' else 'declined' end;

  select friendship.* into friendship_row
  from gymapp_private.friendships as friendship
  where friendship.id = p_friendship_id
    and caller_user_id in (friendship.user_low_id, friendship.user_high_id)
    and friendship.requester_user_id <> caller_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  perform gymapp_private.social_lock_pair(friendship_row.user_low_id, friendship_row.user_high_id);
  select friendship.* into strict friendship_row
  from gymapp_private.friendships as friendship
  where friendship.id = p_friendship_id
  for update;

  if gymapp_private.social_pair_is_blocked(friendship_row.user_low_id, friendship_row.user_high_id) then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  if friendship_row.status = desired_status
     and friendship_row.revision = p_expected_revision + 1 then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'friendshipId', friendship_row.id,
      'status', friendship_row.status,
      'friendshipRevision', friendship_row.revision
    );
  end if;
  if friendship_row.status <> 'pending'
     or friendship_row.requester_user_id = caller_user_id then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  if friendship_row.revision <> p_expected_revision
     or friendship_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Social relation changed.';
  end if;

  if desired_status = 'accepted' then
    peer_user_id := friendship_row.requester_user_id;
    select pg_catalog.count(*)::integer into caller_accepted_count
    from gymapp_private.friendships as friendship
    where friendship.status = 'accepted'
      and caller_user_id in (friendship.user_low_id, friendship.user_high_id);
    select pg_catalog.count(*)::integer into peer_accepted_count
    from gymapp_private.friendships as friendship
    where friendship.status = 'accepted'
      and peer_user_id in (friendship.user_low_id, friendship.user_high_id);
    if caller_accepted_count >= 200 or peer_accepted_count >= 200 then
      raise exception using errcode = 'P0001', message = 'Friend limit reached.';
    end if;
  end if;

  update gymapp_private.friendships as friendship
  set status = desired_status,
      revision = friendship.revision + 1,
      responded_at = response_time,
      updated_at = response_time
  where friendship.id = friendship_row.id
  returning friendship.* into strict friendship_row;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'friendshipId', friendship_row.id,
    'status', friendship_row.status,
    'friendshipRevision', friendship_row.revision
  );
end
$function$;

revoke all on function public.social_respond_friend_request(text, text, bigint)
  from public, anon, authenticated, service_role;

create or replace function public.social_cancel_friend_request(
  p_friendship_id text,
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
  friendship_row record;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  caller_user_id := gymapp_private.social_require_caller('cancel_friend');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);
  if p_friendship_id is null or p_friendship_id !~ '^f_[0-9a-f]{32}$'
     or p_expected_revision is null
     or p_expected_revision not between 1 and 2147483647 then
    raise exception using errcode = '22023', message = 'Friend request cancellation is invalid.';
  end if;
  select friendship.* into friendship_row
  from gymapp_private.friendships as friendship
  where friendship.id = p_friendship_id
    and friendship.requester_user_id = caller_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  perform gymapp_private.social_lock_pair(friendship_row.user_low_id, friendship_row.user_high_id);
  select friendship.* into strict friendship_row
  from gymapp_private.friendships as friendship
  where friendship.id = p_friendship_id
  for update;

  if friendship_row.status = 'removed'
     and friendship_row.requester_user_id = caller_user_id
     and friendship_row.revision = p_expected_revision + 1 then
    return pg_catalog.jsonb_build_object(
      'version', 1, 'friendshipId', friendship_row.id,
      'status', 'removed', 'friendshipRevision', friendship_row.revision
    );
  end if;
  if friendship_row.status <> 'pending'
     or friendship_row.requester_user_id <> caller_user_id then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  if friendship_row.revision <> p_expected_revision
     or friendship_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Social relation changed.';
  end if;

  update gymapp_private.friendships as friendship
  set status = 'removed', revision = friendship.revision + 1,
      responded_at = mutation_time, updated_at = mutation_time
  where friendship.id = friendship_row.id
  returning friendship.* into strict friendship_row;
  return pg_catalog.jsonb_build_object(
    'version', 1, 'friendshipId', friendship_row.id,
    'status', 'removed', 'friendshipRevision', friendship_row.revision
  );
end
$function$;

revoke all on function public.social_cancel_friend_request(text, bigint)
  from public, anon, authenticated, service_role;

create or replace function public.social_remove_friend(
  p_friendship_id text,
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
  friendship_row record;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  caller_user_id := gymapp_private.social_require_caller('remove_friend');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);
  if p_friendship_id is null or p_friendship_id !~ '^f_[0-9a-f]{32}$'
     or p_expected_revision is null
     or p_expected_revision not between 1 and 2147483647 then
    raise exception using errcode = '22023', message = 'Friend removal is invalid.';
  end if;
  select friendship.* into friendship_row
  from gymapp_private.friendships as friendship
  where friendship.id = p_friendship_id
    and caller_user_id in (friendship.user_low_id, friendship.user_high_id);
  if not found then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  perform gymapp_private.social_lock_pair(friendship_row.user_low_id, friendship_row.user_high_id);
  select friendship.* into strict friendship_row
  from gymapp_private.friendships as friendship
  where friendship.id = p_friendship_id
  for update;

  if friendship_row.status = 'removed'
     and friendship_row.revision = p_expected_revision + 1 then
    return pg_catalog.jsonb_build_object(
      'version', 1, 'friendshipId', friendship_row.id,
      'status', 'removed', 'friendshipRevision', friendship_row.revision
    );
  end if;
  if friendship_row.status <> 'accepted' then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  if friendship_row.revision <> p_expected_revision
     or friendship_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Social relation changed.';
  end if;

  update gymapp_private.friendships as friendship
  set status = 'removed', revision = friendship.revision + 1,
      responded_at = mutation_time, updated_at = mutation_time
  where friendship.id = friendship_row.id
  returning friendship.* into strict friendship_row;
  perform gymapp_private.social_cancel_pending_workout_invites(
    friendship_row.user_low_id, friendship_row.user_high_id
  );
  return pg_catalog.jsonb_build_object(
    'version', 1, 'friendshipId', friendship_row.id,
    'status', 'removed', 'friendshipRevision', friendship_row.revision
  );
end
$function$;

revoke all on function public.social_remove_friend(text, bigint)
  from public, anon, authenticated, service_role;

create or replace function public.social_block_profile(p_profile_id text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  target_user_id uuid;
  existing_block boolean;
  blocked_count integer;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  caller_user_id := gymapp_private.social_require_caller('block_profile');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);
  if p_profile_id is null or p_profile_id !~ '^p_[0-9a-f]{32}$' then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  select profile.user_id into target_user_id
  from public.profiles as profile
  where profile.public_id = p_profile_id;
  if not found or target_user_id = caller_user_id then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;

  perform gymapp_private.social_lock_pair(caller_user_id, target_user_id);
  select exists (
    select 1 from gymapp_private.friend_blocks as block
    where block.blocker_user_id = caller_user_id
      and block.blocked_user_id = target_user_id
  ) into existing_block;
  if not existing_block then
    select pg_catalog.count(*)::integer into blocked_count
    from gymapp_private.friend_blocks as block
    where block.blocker_user_id = caller_user_id;
    if blocked_count >= 200 then
      raise exception using errcode = 'P0001', message = 'Block limit reached.';
    end if;
  end if;
  insert into gymapp_private.friend_blocks (
    blocker_user_id, blocked_user_id, blocked_at
  ) values (
    caller_user_id, target_user_id, mutation_time
  ) on conflict (blocker_user_id, blocked_user_id) do nothing;

  update gymapp_private.friendships as friendship
  set status = 'removed',
      revision = least(friendship.revision + 1, 2147483647),
      responded_at = mutation_time,
      updated_at = mutation_time
  where friendship.user_low_id = case when caller_user_id::text < target_user_id::text
      then caller_user_id else target_user_id end
    and friendship.user_high_id = case when caller_user_id::text < target_user_id::text
      then target_user_id else caller_user_id end
    and friendship.status <> 'removed';

  perform gymapp_private.social_cancel_pending_workout_invites(
    caller_user_id, target_user_id
  );
  return pg_catalog.jsonb_build_object(
    'version', 1, 'profileId', p_profile_id, 'blocked', true
  );
end
$function$;

revoke all on function public.social_block_profile(text)
  from public, anon, authenticated, service_role;

create or replace function public.social_unblock_profile(p_profile_id text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  target_user_id uuid;
begin
  caller_user_id := gymapp_private.social_require_caller('unblock_profile');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);
  if p_profile_id is null or p_profile_id !~ '^p_[0-9a-f]{32}$' then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  select profile.user_id into target_user_id
  from public.profiles as profile
  where profile.public_id = p_profile_id;
  if not found or target_user_id = caller_user_id then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;

  perform gymapp_private.social_lock_pair(caller_user_id, target_user_id);
  delete from gymapp_private.friend_blocks as block
  where block.blocker_user_id = caller_user_id
    and block.blocked_user_id = target_user_id;
  return pg_catalog.jsonb_build_object(
    'version', 1, 'profileId', p_profile_id, 'blocked', false
  );
end
$function$;

revoke all on function public.social_unblock_profile(text)
  from public, anon, authenticated, service_role;

create or replace function public.social_update_privacy(
  p_allow_requests boolean,
  p_share_progress boolean,
  p_share_recent_workouts boolean,
  p_share_records boolean,
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
  if p_allow_requests is null
     or p_share_progress is null
     or p_share_recent_workouts is null
     or p_share_records is null
     or p_expected_revision is null
     or p_expected_revision not between 1 and 2147483647 then
    raise exception using errcode = '22023', message = 'Social privacy update is invalid.';
  end if;

  select settings.* into strict settings_row
  from gymapp_private.social_settings as settings
  where settings.user_id = caller_user_id
  for update;

  if settings_row.allow_requests = p_allow_requests
     and settings_row.share_progress = p_share_progress
     and settings_row.share_recent_workouts = p_share_recent_workouts
     and settings_row.share_records = p_share_records
     and settings_row.revision in (p_expected_revision, p_expected_revision + 1) then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'privacy', pg_catalog.jsonb_build_object(
        'allowRequests', settings_row.allow_requests,
        'shareProgress', settings_row.share_progress,
        'shareRecentWorkouts', settings_row.share_recent_workouts,
        'shareRecords', settings_row.share_records
      ),
      'settingsRevision', settings_row.revision
    );
  end if;
  if settings_row.revision <> p_expected_revision
     or settings_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Social privacy settings changed.';
  end if;

  update gymapp_private.social_settings as settings
  set allow_requests = p_allow_requests,
      share_progress = p_share_progress,
      share_recent_workouts = p_share_recent_workouts,
      share_records = p_share_records,
      revision = settings.revision + 1,
      updated_at = pg_catalog.clock_timestamp()
  where settings.user_id = caller_user_id
  returning settings.* into strict settings_row;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'privacy', pg_catalog.jsonb_build_object(
      'allowRequests', settings_row.allow_requests,
      'shareProgress', settings_row.share_progress,
      'shareRecentWorkouts', settings_row.share_recent_workouts,
      'shareRecords', settings_row.share_records
    ),
    'settingsRevision', settings_row.revision
  );
end
$function$;

revoke all on function public.social_update_privacy(boolean, boolean, boolean, boolean, bigint)
  from public, anon, authenticated, service_role;

create or replace function public.social_send_workout_invite(
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
  caller_user_id uuid;
  target_user_id uuid;
  canonical_workout jsonb;
  workout_summary jsonb;
  existing_invite_id text;
  sender_pending_count integer;
  recipient_pending_count integer;
  request_time timestamptz := pg_catalog.clock_timestamp();
begin
  caller_user_id := gymapp_private.social_require_caller('send_workout');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);
  if p_client_request_id is null
     or p_client_request_id::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;
  if p_workout is null then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;
  begin
    canonical_workout := gymapp_private.validate_social_workout(p_workout);
    workout_summary := gymapp_private.social_workout_summary(canonical_workout);
  exception
    when sqlstate '22023' or sqlstate '54000' then
      return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'gymapp-social-workout-request:' || caller_user_id::text || ':' || p_client_request_id::text,
      0
    )
  );
  select invite.id into existing_invite_id
  from gymapp_private.social_workout_invites as invite
  where invite.sender_user_id = caller_user_id
    and invite.client_request_id = p_client_request_id;
  if found then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

  if p_profile_id is null or p_profile_id !~ '^p_[0-9a-f]{32}$' then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;
  select profile.user_id into target_user_id
  from public.profiles as profile
  where profile.public_id = p_profile_id;
  if not found or target_user_id = caller_user_id then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

  perform gymapp_private.social_lock_pair(caller_user_id, target_user_id);
  if not gymapp_private.social_pair_is_accepted(caller_user_id, target_user_id) then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;
  select pg_catalog.count(*)::integer into sender_pending_count
  from gymapp_private.social_workout_invites as invite
  where invite.sender_user_id = caller_user_id
    and invite.status = 'pending'
    and invite.expires_at > request_time;
  select pg_catalog.count(*)::integer into recipient_pending_count
  from gymapp_private.social_workout_invites as invite
  where invite.recipient_user_id = target_user_id
    and invite.status = 'pending'
    and invite.expires_at > request_time;
  if sender_pending_count >= 25 or recipient_pending_count >= 25 then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

  insert into gymapp_private.social_workout_invites (
    sender_user_id, recipient_user_id, client_request_id,
    status, workout, summary, revision,
    created_at, expires_at, responded_at, updated_at
  ) values (
    caller_user_id, target_user_id, p_client_request_id,
    'pending', canonical_workout, workout_summary, 1,
    request_time, request_time + interval '7 days', null, request_time
  );
  return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
end
$function$;

revoke all on function public.social_send_workout_invite(text, uuid, jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.social_workout_inbox()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  incoming_json jsonb;
  outgoing_json jsonb;
  pending_incoming_count integer;
  read_time timestamptz := pg_catalog.clock_timestamp();
begin
  caller_user_id := gymapp_private.social_require_caller('workout_inbox');
  perform gymapp_private.social_purge_expired_workout_payloads(caller_user_id);
  perform gymapp_private.social_ensure_account_rows(caller_user_id);

  with bounded as (
    select invite.*,
      invite.status = 'pending' and invite.expires_at > read_time as active_pending,
      case when invite.status = 'pending' and invite.expires_at <= read_time
        then 'expired' else invite.status end as effective_status,
      case when invite.status = 'pending' and invite.expires_at <= read_time
        then invite.expires_at else invite.responded_at end as effective_responded_at
    from gymapp_private.social_workout_invites as invite
    where invite.recipient_user_id = caller_user_id
      and invite.workout is not null
      and (
        (invite.status = 'accepted'
          and invite.responded_at > read_time - interval '30 days')
        or (invite.status = 'pending' and invite.expires_at > read_time)
      )
      and gymapp_private.social_pair_is_accepted(invite.sender_user_id, caller_user_id)
    order by
      (invite.status = 'pending' and invite.expires_at > read_time) desc,
      invite.created_at desc, invite.id
    limit 25
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'inviteId', bounded.id,
      'profileId', profile.public_id,
      'displayName', gymapp_private.social_safe_display_name(profile.display_name),
      'status', bounded.effective_status,
      'inviteRevision', bounded.revision,
      'createdAt', bounded.created_at,
      'expiresAt', bounded.expires_at,
      'respondedAt', bounded.effective_responded_at,
      'summary', bounded.summary,
      'workout', bounded.workout
    ) order by bounded.active_pending desc, bounded.created_at desc, bounded.id
  ), '[]'::jsonb)
  into incoming_json
  from bounded
  join public.profiles as profile on profile.user_id = bounded.sender_user_id;

  with bounded as (
    select invite.*,
      case when invite.status = 'pending' and invite.expires_at <= read_time
        then 'expired' else invite.status end as effective_status,
      case when invite.status = 'pending' and invite.expires_at <= read_time
        then invite.expires_at else invite.responded_at end as effective_responded_at
    from gymapp_private.social_workout_invites as invite
    where invite.sender_user_id = caller_user_id
      and invite.summary is not null
      and (
        (invite.status = 'pending'
          and invite.expires_at > read_time - interval '24 hours')
        or (invite.status = 'accepted'
          and invite.responded_at > read_time - interval '30 days')
        or (invite.status in ('declined', 'cancelled', 'expired')
          and invite.responded_at > read_time - interval '24 hours')
      )
    order by invite.created_at desc, invite.id
    limit 25
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'inviteId', bounded.id,
      'profileId', profile.public_id,
      'displayName', gymapp_private.social_safe_display_name(profile.display_name),
      'status', bounded.effective_status,
      'inviteRevision', bounded.revision,
      'createdAt', bounded.created_at,
      'expiresAt', bounded.expires_at,
      'respondedAt', bounded.effective_responded_at,
      'summary', bounded.summary
    ) order by bounded.created_at desc, bounded.id
  ), '[]'::jsonb)
  into outgoing_json
  from bounded
  join public.profiles as profile on profile.user_id = bounded.recipient_user_id;

  select pg_catalog.count(*)::integer into pending_incoming_count
  from gymapp_private.social_workout_invites as invite
  where invite.recipient_user_id = caller_user_id
    and invite.status = 'pending'
    and invite.expires_at > read_time
    and gymapp_private.social_pair_is_accepted(invite.sender_user_id, caller_user_id);

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'pendingIncomingCount', pending_incoming_count,
    'incoming', incoming_json,
    'outgoing', outgoing_json
  );
end
$function$;

revoke all on function public.social_workout_inbox()
  from public, anon, authenticated, service_role;

create or replace function public.social_respond_workout_invite(
  p_invite_id text,
  p_decision text,
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
  invite_row record;
  desired_status text;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  caller_user_id := gymapp_private.social_require_caller('respond_workout');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);
  if p_invite_id is null or p_invite_id !~ '^wi_[0-9a-f]{32}$'
     or p_decision is null or p_decision not in ('accept', 'decline')
     or p_expected_revision is null
     or p_expected_revision not between 1 and 2147483647 then
    raise exception using errcode = '22023', message = 'Workout invite response is invalid.';
  end if;
  desired_status := case when p_decision = 'accept' then 'accepted' else 'declined' end;

  select invite.* into invite_row
  from gymapp_private.social_workout_invites as invite
  where invite.id = p_invite_id
    and invite.recipient_user_id = caller_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  perform gymapp_private.social_lock_pair(invite_row.sender_user_id, invite_row.recipient_user_id);
  select invite.* into strict invite_row
  from gymapp_private.social_workout_invites as invite
  where invite.id = p_invite_id
    and invite.recipient_user_id = caller_user_id
  for update;

  if not gymapp_private.social_pair_is_accepted(invite_row.sender_user_id, invite_row.recipient_user_id) then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  if invite_row.status = desired_status
     and invite_row.revision = p_expected_revision + 1 then
    if invite_row.status = 'accepted'
       and (
         invite_row.workout is null
         or invite_row.responded_at <= mutation_time - interval '30 days'
       ) then
      raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
    end if;
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'inviteId', invite_row.id,
      'status', invite_row.status,
      'inviteRevision', invite_row.revision,
      'workout', case when invite_row.status = 'accepted'
        then invite_row.workout else 'null'::jsonb end
    );
  end if;
  if invite_row.status <> 'pending' or invite_row.expires_at <= mutation_time then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  if invite_row.revision <> p_expected_revision
     or invite_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Workout invite changed.';
  end if;

  update gymapp_private.social_workout_invites as invite
  set status = desired_status,
      revision = invite.revision + 1,
      responded_at = mutation_time,
      updated_at = mutation_time
  where invite.id = invite_row.id
  returning invite.* into strict invite_row;
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'inviteId', invite_row.id,
    'status', invite_row.status,
    'inviteRevision', invite_row.revision,
    'workout', case when invite_row.status = 'accepted'
      then invite_row.workout else 'null'::jsonb end
  );
end
$function$;

revoke all on function public.social_respond_workout_invite(text, text, bigint)
  from public, anon, authenticated, service_role;

create or replace function public.social_cancel_workout_invite(
  p_invite_id text,
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
  invite_row record;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  caller_user_id := gymapp_private.social_require_caller('cancel_workout');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);
  if p_invite_id is null or p_invite_id !~ '^wi_[0-9a-f]{32}$'
     or p_expected_revision is null
     or p_expected_revision not between 1 and 2147483647 then
    raise exception using errcode = '22023', message = 'Workout invite cancellation is invalid.';
  end if;

  select invite.* into invite_row
  from gymapp_private.social_workout_invites as invite
  where invite.id = p_invite_id
    and invite.sender_user_id = caller_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  perform gymapp_private.social_lock_pair(invite_row.sender_user_id, invite_row.recipient_user_id);
  select invite.* into strict invite_row
  from gymapp_private.social_workout_invites as invite
  where invite.id = p_invite_id
    and invite.sender_user_id = caller_user_id
  for update;

  if invite_row.status = 'cancelled'
     and invite_row.revision = p_expected_revision + 1 then
    return pg_catalog.jsonb_build_object(
      'version', 1, 'inviteId', invite_row.id,
      'status', 'cancelled', 'inviteRevision', invite_row.revision
    );
  end if;
  if invite_row.status <> 'pending' or invite_row.expires_at <= mutation_time then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  if not gymapp_private.social_pair_is_accepted(invite_row.sender_user_id, invite_row.recipient_user_id) then
    raise exception using errcode = 'P0002', message = 'Social resource unavailable.';
  end if;
  if invite_row.revision <> p_expected_revision
     or invite_row.revision >= 2147483647 then
    raise exception using errcode = 'P0001', message = 'Workout invite changed.';
  end if;

  update gymapp_private.social_workout_invites as invite
  set status = 'cancelled',
      revision = invite.revision + 1,
      responded_at = mutation_time,
      updated_at = mutation_time
  where invite.id = invite_row.id
  returning invite.* into strict invite_row;
  return pg_catalog.jsonb_build_object(
    'version', 1, 'inviteId', invite_row.id,
    'status', 'cancelled', 'inviteRevision', invite_row.revision
  );
end
$function$;

revoke all on function public.social_cancel_workout_invite(text, bigint)
  from public, anon, authenticated, service_role;

grant execute on function public.social_dashboard() to authenticated;
grant execute on function public.social_friend_details(text) to authenticated;
grant execute on function public.social_send_friend_request(text) to authenticated;
grant execute on function public.social_respond_friend_request(text, text, bigint) to authenticated;
grant execute on function public.social_cancel_friend_request(text, bigint) to authenticated;
grant execute on function public.social_remove_friend(text, bigint) to authenticated;
grant execute on function public.social_block_profile(text) to authenticated;
grant execute on function public.social_unblock_profile(text) to authenticated;
grant execute on function public.social_update_privacy(boolean, boolean, boolean, boolean, bigint) to authenticated;
grant execute on function public.social_workout_inbox() to authenticated;
grant execute on function public.social_send_workout_invite(text, uuid, jsonb) to authenticated;
grant execute on function public.social_respond_workout_invite(text, text, bigint) to authenticated;
grant execute on function public.social_cancel_workout_invite(text, bigint) to authenticated;

comment on function public.social_dashboard() is
  'Authenticated RPC-only friends dashboard. Returns bounded UUID-free social JSON v1.';
comment on function public.social_friend_details(text) is
  'Accepted-friend-only bounded activity JSON v1; privacy and projection revision are checked at read time.';
comment on function public.social_send_friend_request(text) is
  'Rate-limited generic friend-code submission; reverse pending requests may mutually accept atomically.';
comment on function public.social_workout_inbox() is
  'Bounded workout invitation inbox JSON v1. Full canonical payload is returned only to its recipient while pending or during the accepted retry window.';
comment on function public.social_send_workout_invite(text, uuid, jsonb) is
  'Idempotent bounded static shared-workout v1 invitation between accepted, unblocked friends. Terminal payloads are purged opportunistically.';

do $verify$
declare
  rpc_signature text;
  private_relation text;
begin
  foreach rpc_signature in array array[
    'public.social_dashboard()',
    'public.social_friend_details(text)',
    'public.social_send_friend_request(text)',
    'public.social_respond_friend_request(text,text,bigint)',
    'public.social_cancel_friend_request(text,bigint)',
    'public.social_remove_friend(text,bigint)',
    'public.social_block_profile(text)',
    'public.social_unblock_profile(text)',
    'public.social_update_privacy(boolean,boolean,boolean,boolean,bigint)',
    'public.social_workout_inbox()',
    'public.social_send_workout_invite(text,uuid,jsonb)',
    'public.social_respond_workout_invite(text,text,bigint)',
    'public.social_cancel_workout_invite(text,bigint)'
  ] loop
    if pg_catalog.has_function_privilege('anon', rpc_signature, 'EXECUTE')
       or not pg_catalog.has_function_privilege('authenticated', rpc_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', rpc_signature, 'EXECUTE') then
      raise exception 'Social RPC % does not have the exact authenticated-only grant.', rpc_signature;
    end if;
  end loop;

  foreach private_relation in array array[
    'social_settings', 'friendships', 'friend_blocks',
    'social_activity_projection', 'social_rate_limits', 'social_workout_invites'
  ] loop
    if pg_catalog.has_table_privilege('anon', 'gymapp_private.' || private_relation, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.' || private_relation, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.' || private_relation, 'INSERT')
       or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.' || private_relation, 'UPDATE')
       or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.' || private_relation, 'DELETE')
       or exists (
         select 1
         from pg_catalog.pg_policy as policy
         where policy.polrelid = ('gymapp_private.' || private_relation)::pg_catalog.regclass
       ) then
      raise exception 'Private social relation % is not RPC-only.', private_relation;
    end if;
  end loop;

  if pg_catalog.to_regprocedure('public.leaderboard_public_rows()') is null
     or pg_catalog.to_regclass('public.leaderboard_public') is null then
    raise exception 'Legacy owner-only leaderboard compatibility API was removed unexpectedly.';
  end if;

  if pg_catalog.has_function_privilege('authenticated', 'gymapp_private.social_require_caller(text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'gymapp_private.social_purge_expired_workout_payloads(uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'gymapp_private.social_safe_display_name(text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'gymapp_private.social_pair_is_accepted(uuid,uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'gymapp_private.social_cancel_pending_workout_invites(uuid,uuid)', 'EXECUTE') then
    raise exception 'Private social activation helper grants are not least privilege.';
  end if;
end
$verify$;

select pg_catalog.pg_notify('pgrst', 'reload schema');

commit;
