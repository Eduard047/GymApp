-- Keep cursor validation wide enough for invitations accepted near the end
-- of their seven-day lifetime and retained for thirty days after response.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

create or replace function public.social_workout_inbox_page(
  p_cursor_created_at timestamptz default null,
  p_cursor_invite_id text default null,
  p_cursor_pending boolean default null,
  p_limit integer default 10
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  read_time timestamptz := pg_catalog.clock_timestamp();
  incoming_json jsonb;
  outgoing_json jsonb;
  pending_incoming_count integer;
  effective_limit integer;
  next_created_at timestamptz;
  next_invite_id text;
  next_pending boolean;
  has_more boolean := false;
  response_json jsonb;
begin
  caller_user_id := gymapp_private.social_require_caller('workout_inbox');
  perform gymapp_private.social_purge_expired_workout_payloads(caller_user_id);
  perform gymapp_private.social_ensure_account_rows(caller_user_id);

  if p_limit is null or p_limit not between 1 and 20
     or not (
       (p_cursor_created_at is null
         and p_cursor_invite_id is null
         and p_cursor_pending is null)
       or (p_cursor_created_at is not null
         and p_cursor_invite_id is not null
         and p_cursor_pending is not null)
     )
     or (p_cursor_created_at is not null and (
       p_cursor_invite_id !~ '^wi_[0-9a-f]{32}$'
       or p_cursor_created_at > read_time
       or p_cursor_created_at < read_time - interval '38 days'
     )) then
    raise exception using errcode = '22023',
      message = 'Workout inbox page is invalid.';
  end if;
  effective_limit := p_limit;

  with eligible as (
    select invite.*,
      invite.status = 'pending' and invite.expires_at > read_time as active_pending,
      case when invite.status = 'pending' and invite.expires_at <= read_time
        then 'expired' else invite.status end as effective_status,
      case when invite.status = 'pending' and invite.expires_at <= read_time
        then invite.expires_at else invite.responded_at end as effective_responded_at
    from gymapp_private.social_workout_invites as invite
    where invite.recipient_user_id = caller_user_id
      and invite.summary is not null
      and (
        (invite.status = 'accepted'
          and invite.responded_at > read_time - interval '30 days')
        or (invite.status = 'pending' and invite.expires_at > read_time)
      )
      and gymapp_private.social_pair_is_accepted(
        invite.sender_user_id, caller_user_id
      )
      and (
        p_cursor_created_at is null
        or (
          case when invite.status = 'pending' and invite.expires_at > read_time
            then 1 else 0 end,
          invite.created_at,
          invite.id
        ) < (
          case when p_cursor_pending then 1 else 0 end,
          p_cursor_created_at,
          p_cursor_invite_id
        )
      )
    order by active_pending desc, invite.created_at desc, invite.id desc
    limit effective_limit + 1
  ), page as (
    select * from eligible
    order by active_pending desc, created_at desc, id desc
    limit effective_limit
  )
  select
    coalesce(pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'inviteId', page.id,
        'profileId', profile.public_id,
        'displayName', gymapp_private.social_safe_display_name(profile.display_name),
        'status', page.effective_status,
        'inviteRevision', page.revision,
        'createdAt', page.created_at,
        'expiresAt', page.expires_at,
        'respondedAt', page.effective_responded_at,
        'summary', page.summary
      ) order by page.active_pending desc, page.created_at desc, page.id desc
    ), '[]'::jsonb),
    pg_catalog.count(*) = effective_limit and
      (select pg_catalog.count(*) from eligible) > effective_limit,
    (pg_catalog.array_agg(page.created_at
      order by page.active_pending desc, page.created_at desc, page.id desc))[effective_limit],
    (pg_catalog.array_agg(page.id
      order by page.active_pending desc, page.created_at desc, page.id desc))[effective_limit],
    (pg_catalog.array_agg(page.active_pending
      order by page.active_pending desc, page.created_at desc, page.id desc))[effective_limit]
  into incoming_json, has_more, next_created_at, next_invite_id, next_pending
  from page
  join public.profiles as profile on profile.user_id = page.sender_user_id;

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
    order by invite.created_at desc, invite.id desc
    limit 20
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
    ) order by bounded.created_at desc, bounded.id desc
  ), '[]'::jsonb)
  into outgoing_json
  from bounded
  join public.profiles as profile on profile.user_id = bounded.recipient_user_id;

  select pg_catalog.count(*)::integer into pending_incoming_count
  from gymapp_private.social_workout_invites as invite
  where invite.recipient_user_id = caller_user_id
    and invite.status = 'pending'
    and invite.expires_at > read_time
    and gymapp_private.social_pair_is_accepted(
      invite.sender_user_id, caller_user_id
    );

  response_json := pg_catalog.jsonb_build_object(
    'version', 2,
    'pendingIncomingCount', pending_incoming_count,
    'incoming', incoming_json,
    'outgoing', outgoing_json,
    'nextCursor', case when has_more then pg_catalog.jsonb_build_object(
      'createdAt', next_created_at,
      'inviteId', next_invite_id,
      'pending', next_pending
    ) else 'null'::jsonb end
  );
  if pg_catalog.octet_length(
       pg_catalog.convert_to(response_json::text, 'UTF8')
     ) > 262144 then
    raise exception using errcode = '54000',
      message = 'Workout inbox page exceeds the response limit.';
  end if;
  return response_json;
end
$function$;

revoke all on function public.social_workout_inbox_page(
  timestamptz, text, boolean, integer
) from public, anon, authenticated, service_role;
grant execute on function public.social_workout_inbox_page(
  timestamptz, text, boolean, integer
) to authenticated;

commit;
