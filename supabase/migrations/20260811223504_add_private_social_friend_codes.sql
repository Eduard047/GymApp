begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regclass('auth.users') is null
     or pg_catalog.to_regclass('auth.sessions') is null
     or pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regclass('gymapp_private.friendships') is null
     or pg_catalog.to_regclass('gymapp_private.social_settings') is null
     or pg_catalog.to_regprocedure('gymapp_private.has_current_auth_session(uuid)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_require_caller(text)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_ensure_account_rows(uuid)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_lock_pair(uuid,uuid)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_pair_is_blocked(uuid,uuid)') is null
     or pg_catalog.to_regprocedure('public.social_send_friend_request(text)') is null then
    raise exception 'GymApp private friend-code prerequisites are missing.';
  end if;

  if pg_catalog.to_regclass('gymapp_private.social_friend_codes') is not null
     or pg_catalog.to_regprocedure('public.social_my_friend_code()') is not null
     or pg_catalog.to_regprocedure('gymapp_private.social_ensure_friend_code(uuid)') is not null then
    raise exception 'GymApp private friend-code objects already exist outside this migration.';
  end if;
end
$preflight$;

create table gymapp_private.social_friend_codes (
  user_id uuid primary key
    references auth.users(id) on delete cascade,
  friend_code text not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint social_friend_codes_format_check
    check (friend_code ~ '^g_[0-9a-f]{12}$'),
  constraint social_friend_codes_code_key unique (friend_code)
);

comment on table gymapp_private.social_friend_codes is
  'Private lazy-issued 48-bit friend codes. Access is RPC-only and bound to a live Supabase Auth session.';
comment on column gymapp_private.social_friend_codes.friend_code is
  'Random g_ plus twelve lowercase hexadecimal digits; never derived from auth.users.id or profiles.public_id.';

alter table gymapp_private.social_friend_codes enable row level security;
alter table gymapp_private.social_friend_codes force row level security;
revoke all on table gymapp_private.social_friend_codes
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_ensure_friend_code(
  p_user_id uuid
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  generation_attempt integer;
  candidate_friend_code text;
  stored_friend_code text;
begin
  if p_user_id is null
     or auth.uid() is distinct from p_user_id
     or not gymapp_private.has_current_auth_session(p_user_id) then
    raise exception using
      errcode = '42501',
      message = 'Friend-code creation requires the owner live session.';
  end if;

  -- Serialize lazy creation for this account. A hash collision can only add
  -- harmless contention; it cannot mix rows because user_id remains the key.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'gymapp-social-friend-code:' || p_user_id::text,
      0
    )
  );

  select code.friend_code into stored_friend_code
  from gymapp_private.social_friend_codes as code
  where code.user_id = p_user_id;
  if found then
    return stored_friend_code;
  end if;

  -- The first twelve UUIDv4 hex digits precede the fixed version nibble, so
  -- each candidate retains exactly 48 random bits. Unique collisions retry a
  -- fixed number of times rather than spinning or exposing another account.
  for generation_attempt in 1..16 loop
    candidate_friend_code := 'g_' || pg_catalog.left(
      pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', ''),
      12
    );

    insert into gymapp_private.social_friend_codes (
      user_id,
      friend_code,
      created_at
    ) values (
      p_user_id,
      candidate_friend_code,
      pg_catalog.clock_timestamp()
    )
    on conflict do nothing
    returning friend_code into stored_friend_code;

    if found then
      return stored_friend_code;
    end if;

    -- A concurrent privileged writer may have created the owner row. Return
    -- only that exact row; otherwise the conflict was on the random code.
    select code.friend_code into stored_friend_code
    from gymapp_private.social_friend_codes as code
    where code.user_id = p_user_id;
    if found then
      return stored_friend_code;
    end if;
  end loop;

  raise exception using
    errcode = 'P0001',
    message = 'Friend-code generation is temporarily unavailable.';
end
$function$;

revoke all on function gymapp_private.social_ensure_friend_code(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.social_my_friend_code()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  session_id_text text := auth.jwt() ->> 'session_id';
  current_session_id uuid;
  caller_friend_code text;
begin
  if caller_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception using
      errcode = '42501',
      message = 'A live authenticated session is required.';
  end if;

  current_session_id := session_id_text::uuid;
  perform 1
  from auth.sessions as session
  where session.id = current_session_id
    and session.user_id = caller_user_id
    and (
      session.not_after is null
      or session.not_after > pg_catalog.clock_timestamp()
    )
  for key share;
  if not found then
    raise exception using
      errcode = '42501',
      message = 'A live authenticated session is required.';
  end if;

  caller_friend_code := gymapp_private.social_ensure_friend_code(caller_user_id);
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'friendCode', caller_friend_code
  );
end
$function$;

revoke all on function public.social_my_friend_code()
  from public, anon, authenticated, service_role;
grant execute on function public.social_my_friend_code()
  to authenticated;

comment on function public.social_my_friend_code() is
  'Returns exactly friend-code response v1 for the current still-live Auth session, creating its private 48-bit code lazily.';

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
  -- Keep the existing live-session check and send_friend token debit ahead of
  -- every lookup so malformed, legacy, private, and unavailable codes consume
  -- the same bounded request budget.
  caller_user_id := gymapp_private.social_require_caller('send_friend');
  perform gymapp_private.social_ensure_account_rows(caller_user_id);

  if p_friend_code is null then
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  elsif pg_catalog.octet_length(p_friend_code) = 34
        and p_friend_code ~ '^p_[0-9a-f]{32}$' then
    select profile.user_id into target_user_id
    from public.profiles as profile
    where profile.public_id = p_friend_code;
  elsif pg_catalog.octet_length(p_friend_code) = 14
        and p_friend_code ~ '^g_[0-9a-f]{12}$' then
    select code.user_id into target_user_id
    from gymapp_private.social_friend_codes as code
    where code.friend_code = p_friend_code;
  else
    return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');
  end if;

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
grant execute on function public.social_send_friend_request(text)
  to authenticated;

comment on function public.social_send_friend_request(text) is
  'Submits a generic friend request by legacy p_ profile code or private g_ friend code without revealing lookup, block, privacy, cap, or friendship state.';

do $verify$
declare
  rpc_signature text;
begin
  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'gymapp_private'
      and relation.relname = 'social_friend_codes'
      and relation.relkind = 'r'
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ) then
    raise exception 'Private friend-code storage must have enabled and forced RLS.';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policy as policy
    where policy.polrelid = 'gymapp_private.social_friend_codes'::pg_catalog.regclass
  ) then
    raise exception 'Private friend-code storage must not expose an RLS policy.';
  end if;

  if pg_catalog.has_table_privilege('anon', 'gymapp_private.social_friend_codes', 'SELECT')
     or pg_catalog.has_table_privilege('anon', 'gymapp_private.social_friend_codes', 'INSERT')
     or pg_catalog.has_table_privilege('anon', 'gymapp_private.social_friend_codes', 'UPDATE')
     or pg_catalog.has_table_privilege('anon', 'gymapp_private.social_friend_codes', 'DELETE')
     or pg_catalog.has_table_privilege('anon', 'gymapp_private.social_friend_codes', 'TRUNCATE')
     or pg_catalog.has_table_privilege('anon', 'gymapp_private.social_friend_codes', 'REFERENCES')
     or pg_catalog.has_table_privilege('anon', 'gymapp_private.social_friend_codes', 'TRIGGER')
     or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.social_friend_codes', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.social_friend_codes', 'INSERT')
     or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.social_friend_codes', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.social_friend_codes', 'DELETE')
     or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.social_friend_codes', 'TRUNCATE')
     or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.social_friend_codes', 'REFERENCES')
     or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.social_friend_codes', 'TRIGGER')
     or pg_catalog.has_table_privilege('service_role', 'gymapp_private.social_friend_codes', 'SELECT')
     or pg_catalog.has_table_privilege('service_role', 'gymapp_private.social_friend_codes', 'INSERT')
     or pg_catalog.has_table_privilege('service_role', 'gymapp_private.social_friend_codes', 'UPDATE')
     or pg_catalog.has_table_privilege('service_role', 'gymapp_private.social_friend_codes', 'DELETE')
     or pg_catalog.has_table_privilege('service_role', 'gymapp_private.social_friend_codes', 'TRUNCATE')
     or pg_catalog.has_table_privilege('service_role', 'gymapp_private.social_friend_codes', 'REFERENCES')
     or pg_catalog.has_table_privilege('service_role', 'gymapp_private.social_friend_codes', 'TRIGGER') then
    raise exception 'Private friend-code table grants are broader than intended.';
  end if;

  foreach rpc_signature in array array[
    'public.social_my_friend_code()',
    'public.social_send_friend_request(text)'
  ] loop
    if not pg_catalog.has_function_privilege('authenticated', rpc_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege('anon', rpc_signature, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', rpc_signature, 'EXECUTE') then
      raise exception 'Friend-code RPC % grants are broader than intended.', rpc_signature;
    end if;
  end loop;

  if pg_catalog.has_function_privilege(
       'authenticated',
       'gymapp_private.social_ensure_friend_code(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'gymapp_private.social_ensure_friend_code(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'gymapp_private.social_ensure_friend_code(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Private friend-code helper must not be directly executable.';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('public', 'gymapp_private')
      and procedure.proname in (
        'social_my_friend_code',
        'social_send_friend_request',
        'social_ensure_friend_code'
      )
      and (
        not procedure.prosecdef
        or not (procedure.proconfig @> array['search_path=""'])
      )
  ) then
    raise exception 'Friend-code functions must be SECURITY DEFINER with an empty search_path.';
  end if;

  -- FORCE RLS intentionally has no policies, so every function that touches
  -- the private table must execute as a role which PostgreSQL allows to bypass
  -- forced RLS. Fail the migration instead of installing an RPC that cannot
  -- read its own private storage under a differently configured environment.
  foreach rpc_signature in array array[
    'gymapp_private.social_ensure_friend_code(uuid)',
    'public.social_my_friend_code()',
    'public.social_send_friend_request(text)'
  ] loop
    if not exists (
      select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_roles as owner_role
        on owner_role.oid = procedure.proowner
      where procedure.oid = pg_catalog.to_regprocedure(rpc_signature)
        and (owner_role.rolsuper or owner_role.rolbypassrls)
    ) then
      raise exception 'Friend-code function % owner cannot bypass forced RLS.', rpc_signature;
    end if;
  end loop;
end
$verify$;

notify pgrst, 'reload schema';

commit;
