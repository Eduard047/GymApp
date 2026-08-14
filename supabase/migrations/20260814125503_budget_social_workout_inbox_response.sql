-- Keep the production v2 metadata inbox available even when every visible summary is near
-- its valid maximum size. Outgoing rows remain a deterministic newest-first
-- snapshot, while an incoming page may end early at an exact byte boundary and
-- continue from the last row it actually returned.

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
  incoming_json jsonb := '[]'::jsonb;
  outgoing_json jsonb := '[]'::jsonb;
  incoming_candidates jsonb;
  incoming_candidate_count integer;
  incoming_index integer;
  candidate_envelope jsonb;
  candidate_json jsonb;
  candidate_array jsonb;
  candidate_cursor jsonb;
  candidate_response jsonb;
  last_cursor jsonb := 'null'::jsonb;
  outgoing_row record;
  pending_incoming_count integer;
  effective_limit integer;
  has_more boolean := false;
  response_json jsonb;
  -- Keep 4 KiB below the clients' 256 KiB transport ceiling for the RPC/HTTP
  -- serializer envelope while measuring the exact JSON body produced here.
  response_byte_limit constant integer := 258048;
  -- This fixed array budget makes the outgoing snapshot independent from the
  -- incoming cursor/page size. Newest rows are kept; only the older tail can be
  -- omitted when unusually large summaries would otherwise exhaust the page.
  outgoing_array_byte_limit constant integer := 98304;
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

  select pg_catalog.count(*)::integer into pending_incoming_count
  from gymapp_private.social_workout_invites as invite
  where invite.recipient_user_id = caller_user_id
    and invite.status = 'pending'
    and invite.expires_at > read_time
    and gymapp_private.social_pair_is_accepted(
      invite.sender_user_id, caller_user_id
    );

  -- Build the outgoing snapshot first under a cursor-independent exact UTF-8
  -- budget. Stopping at the first row that does not fit preserves a strict
  -- newest-first prefix and keeps the snapshot identical on following pages.
  for outgoing_row in
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
    select
      bounded.id,
      profile.public_id,
      gymapp_private.social_safe_display_name(profile.display_name) as display_name,
      bounded.effective_status,
      bounded.revision,
      bounded.created_at,
      bounded.expires_at,
      bounded.effective_responded_at,
      bounded.summary
    from bounded
    join public.profiles as profile on profile.user_id = bounded.recipient_user_id
    order by bounded.created_at desc, bounded.id desc
  loop
    candidate_json := pg_catalog.jsonb_build_object(
      'inviteId', outgoing_row.id,
      'profileId', outgoing_row.public_id,
      'displayName', outgoing_row.display_name,
      'status', outgoing_row.effective_status,
      'inviteRevision', outgoing_row.revision,
      'createdAt', outgoing_row.created_at,
      'expiresAt', outgoing_row.expires_at,
      'respondedAt', outgoing_row.effective_responded_at,
      'summary', outgoing_row.summary
    );
    candidate_array := outgoing_json || pg_catalog.jsonb_build_array(candidate_json);
    if pg_catalog.octet_length(
         pg_catalog.convert_to(candidate_array::text, 'UTF8')
       ) > outgoing_array_byte_limit then
      exit;
    end if;
    outgoing_json := candidate_array;
  end loop;

  -- Materialize at most one look-ahead row. This keeps database work bounded
  -- while allowing the response cursor to describe exactly the last emitted
  -- row when either another row exists or the byte budget ends the page early.
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
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'row', pg_catalog.jsonb_build_object(
        'inviteId', eligible.id,
        'profileId', profile.public_id,
        'displayName', gymapp_private.social_safe_display_name(profile.display_name),
        'status', eligible.effective_status,
        'inviteRevision', eligible.revision,
        'createdAt', eligible.created_at,
        'expiresAt', eligible.expires_at,
        'respondedAt', eligible.effective_responded_at,
        'summary', eligible.summary
      ),
      'createdAt', eligible.created_at,
      'inviteId', eligible.id,
      'pending', eligible.active_pending
    ) order by eligible.active_pending desc, eligible.created_at desc, eligible.id desc
  ), '[]'::jsonb)
  into incoming_candidates
  from eligible
  join public.profiles as profile on profile.user_id = eligible.sender_user_id;

  incoming_candidate_count := pg_catalog.jsonb_array_length(incoming_candidates);
  if incoming_candidate_count > 0 then
    for incoming_index in 0 .. least(
      effective_limit, incoming_candidate_count
    ) - 1 loop
      candidate_envelope := incoming_candidates->incoming_index;
      candidate_json := candidate_envelope->'row';
      candidate_array := incoming_json || pg_catalog.jsonb_build_array(candidate_json);
      has_more := incoming_index + 1 < incoming_candidate_count;
      candidate_cursor := pg_catalog.jsonb_build_object(
        'createdAt', candidate_envelope->'createdAt',
        'inviteId', candidate_envelope->'inviteId',
        'pending', candidate_envelope->'pending'
      );
      candidate_response := pg_catalog.jsonb_build_object(
        'version', 2,
        'pendingIncomingCount', pending_incoming_count,
        'incoming', candidate_array,
        'outgoing', outgoing_json,
        'nextCursor', case when has_more then candidate_cursor
          else 'null'::jsonb end
      );
      if pg_catalog.octet_length(
           pg_catalog.convert_to(candidate_response::text, 'UTF8')
         ) > response_byte_limit then
        -- Structurally valid summaries fit beside the fixed outgoing budget.
        -- Unexpected stored metadata fails closed without changing the outgoing
        -- snapshot between cursor pages or returning an unpageable cursor.
        if pg_catalog.jsonb_array_length(incoming_json) = 0 then
          raise exception using errcode = '54000',
            message = 'Workout inbox row exceeds the response limit.';
        else
          has_more := true;
          exit;
        end if;
      end if;
      incoming_json := candidate_array;
      last_cursor := candidate_cursor;
    end loop;
  end if;

  response_json := pg_catalog.jsonb_build_object(
    'version', 2,
    'pendingIncomingCount', pending_incoming_count,
    'incoming', incoming_json,
    'outgoing', outgoing_json,
    'nextCursor', case when has_more then last_cursor else 'null'::jsonb end
  );
  if pg_catalog.octet_length(
       pg_catalog.convert_to(response_json::text, 'UTF8')
     ) > response_byte_limit then
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

comment on function public.social_workout_inbox_page(timestamptz, text, boolean, integer)
  is 'Owner-bound v2 metadata inbox. The JSON body stays within 252 KiB UTF-8, leaving 4 KiB below the client transport cap; incoming continues from the last emitted row and outgoing is the newest prefix within a stable 96 KiB array budget.';

commit;
