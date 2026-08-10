begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

-- A PostgreSQL error that escapes an RPC aborts the complete request
-- transaction, including the token-bucket debit made by social_require_caller.
-- Keep that debit outside a nested exception block, roll back only the social
-- business work for expected domain errors, and ask PostgREST to emit the same
-- non-2xx status without raising another database exception.
do $preflight$
declare
  rpc_signature text;
begin
  if pg_catalog.to_regprocedure('gymapp_private.consume_social_rate_limit(uuid,text)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_require_caller(text)') is null
     or pg_catalog.to_regclass('gymapp_private.social_rate_limits') is null then
    raise exception 'GymApp durable social rate-limit prerequisites are missing.';
  end if;

  foreach rpc_signature in array array[
    'public.social_friend_details(text)',
    'public.social_respond_friend_request(text,text,bigint)',
    'public.social_cancel_friend_request(text,bigint)',
    'public.social_remove_friend(text,bigint)',
    'public.social_block_profile(text)',
    'public.social_unblock_profile(text)',
    'public.social_update_privacy(boolean,boolean,boolean,boolean,bigint)',
    'public.social_respond_workout_invite(text,text,bigint)',
    'public.social_cancel_workout_invite(text,bigint)'
  ] loop
    if pg_catalog.to_regprocedure(rpc_signature) is null then
      raise exception 'GymApp durable social rate-limit RPC % is missing.', rpc_signature;
    end if;
  end loop;
end
$preflight$;

create or replace function gymapp_private.social_domain_error_response(
  p_code text,
  p_message text,
  p_detail text,
  p_hint text
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
begin
  if p_code not in ('22023', 'P0001', 'P0002') or p_message is null then
    raise exception using
      errcode = '22023',
      message = 'Social domain error response is invalid.';
  end if;

  -- PostgREST maps 22023 and P0001 to 400, and the remaining P0* class to
  -- 500. Setting the response GUC preserves that wire behavior while allowing
  -- the outer request transaction (and its rate debit) to commit.
  perform pg_catalog.set_config(
    'response.status',
    case when p_code = 'P0002' then '500' else '400' end,
    true
  );
  return pg_catalog.jsonb_build_object(
    'code', p_code,
    'details', nullif(p_detail, ''),
    'hint', nullif(p_hint, ''),
    'message', p_message
  );
end
$function$;

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
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  caller_user_id := gymapp_private.social_require_caller('update_privacy');

  begin
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
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  caller_user_id := gymapp_private.social_require_caller('respond_workout');

  begin
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
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  caller_user_id := gymapp_private.social_require_caller('cancel_workout');

  begin
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
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  caller_user_id := gymapp_private.social_require_caller('remove_friend');

  begin
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
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  caller_user_id := gymapp_private.social_require_caller('block_profile');

  begin
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
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  caller_user_id := gymapp_private.social_require_caller('unblock_profile');

  begin
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
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  caller_user_id := gymapp_private.social_require_caller('respond_friend');

  begin
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
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  caller_user_id := gymapp_private.social_require_caller('cancel_friend');

  begin
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


revoke all on function gymapp_private.social_domain_error_response(text, text, text, text)
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

-- CREATE OR REPLACE retains existing ACLs, but restate the client boundary so
-- this forward migration is safe even if an environment has grant drift.
revoke all on function public.social_friend_details(text)
  from public, anon, authenticated, service_role;
revoke all on function public.social_respond_friend_request(text, text, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.social_cancel_friend_request(text, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.social_remove_friend(text, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.social_block_profile(text)
  from public, anon, authenticated, service_role;
revoke all on function public.social_unblock_profile(text)
  from public, anon, authenticated, service_role;
revoke all on function public.social_update_privacy(boolean, boolean, boolean, boolean, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.social_respond_workout_invite(text, text, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.social_cancel_workout_invite(text, bigint)
  from public, anon, authenticated, service_role;

grant execute on function public.social_friend_details(text) to authenticated;
grant execute on function public.social_respond_friend_request(text, text, bigint) to authenticated;
grant execute on function public.social_cancel_friend_request(text, bigint) to authenticated;
grant execute on function public.social_remove_friend(text, bigint) to authenticated;
grant execute on function public.social_block_profile(text) to authenticated;
grant execute on function public.social_unblock_profile(text) to authenticated;
grant execute on function public.social_update_privacy(boolean, boolean, boolean, boolean, bigint)
  to authenticated;
grant execute on function public.social_respond_workout_invite(text, text, bigint) to authenticated;
grant execute on function public.social_cancel_workout_invite(text, bigint) to authenticated;

comment on table gymapp_private.social_rate_limits is
  'Atomic per-account token buckets. Successful calls, generic submissions, and caught social domain errors commit one debit; authentication, gateway, cancellation, and unexpected database errors remain outside this transactional guarantee.';

do $verify$
declare
  rpc_signature text;
begin
  foreach rpc_signature in array array[
    'public.social_friend_details(text)',
    'public.social_respond_friend_request(text,text,bigint)',
    'public.social_cancel_friend_request(text,bigint)',
    'public.social_remove_friend(text,bigint)',
    'public.social_block_profile(text)',
    'public.social_unblock_profile(text)',
    'public.social_update_privacy(boolean,boolean,boolean,boolean,bigint)',
    'public.social_respond_workout_invite(text,text,bigint)',
    'public.social_cancel_workout_invite(text,bigint)'
  ] loop
    if not pg_catalog.has_function_privilege('authenticated', rpc_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege('anon', rpc_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', rpc_signature, 'EXECUTE') then
      raise exception 'GymApp durable social rate-limit RPC privilege verification failed for %.',
        rpc_signature;
    end if;
  end loop;

  if pg_catalog.has_function_privilege(
       'anon',
       'gymapp_private.social_domain_error_response(text,text,text,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'gymapp_private.social_domain_error_response(text,text,text,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'gymapp_private.social_domain_error_response(text,text,text,text)',
       'EXECUTE'
     ) then
    raise exception 'GymApp social domain error helper privilege verification failed.';
  end if;
end
$verify$;

select pg_catalog.pg_notify('pgrst', 'reload schema');

commit;
