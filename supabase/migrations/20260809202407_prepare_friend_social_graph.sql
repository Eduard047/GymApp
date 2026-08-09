begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

-- Phase 1 installs only private storage, bounded derivation/validation helpers,
-- and triggers which keep new state revisions current. Client access is added
-- only after the race-safe backfill in the two following migrations.
do $preflight$
begin
  if pg_catalog.current_setting('server_version_num')::integer < 170000 then
    raise exception 'GymApp social projections require PostgreSQL 17 or newer.';
  end if;

  if pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regclass('public.user_states') is null
     or pg_catalog.to_regclass('gymapp_private.user_state_progression') is null
     or pg_catalog.to_regclass('gymapp_private.user_state_quarantine') is null
     or pg_catalog.to_regprocedure('gymapp_private.validate_user_state(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.has_current_auth_session(uuid)') is null
     or pg_catalog.to_regprocedure('public.safe_leaderboard_display_name(text)') is null then
    raise exception 'GymApp social graph prerequisites are missing.';
  end if;

  if not exists (
    select 1
    from information_schema.columns as column_definition
    where column_definition.table_schema = 'public'
      and column_definition.table_name = 'profiles'
      and column_definition.column_name = 'public_id'
      and column_definition.data_type = 'text'
  ) then
    raise exception 'GymApp profiles.public_id friend-code prerequisite is missing.';
  end if;
end
$preflight$;

create table gymapp_private.social_settings (
  user_id uuid primary key
    references auth.users(id) on delete cascade,
  allow_requests boolean not null default true,
  share_progress boolean not null default true,
  share_recent_workouts boolean not null default true,
  share_records boolean not null default true,
  revision bigint not null default 1
    check (revision between 1 and 2147483647),
  updated_at timestamptz not null default pg_catalog.clock_timestamp()
);

create table gymapp_private.friendships (
  id text primary key default (
    'f_' || pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '')
  ) check (id ~ '^f_[0-9a-f]{32}$'),
  user_low_id uuid not null
    references auth.users(id) on delete cascade,
  user_high_id uuid not null
    references auth.users(id) on delete cascade,
  requester_user_id uuid not null
    references auth.users(id) on delete cascade,
  status text not null
    check (status in ('pending', 'accepted', 'declined', 'removed')),
  revision bigint not null default 1
    check (revision between 1 and 2147483647),
  requested_at timestamptz not null default pg_catalog.clock_timestamp(),
  responded_at timestamptz,
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint friendships_canonical_pair_check check (
    user_low_id::text < user_high_id::text
  ),
  constraint friendships_requester_check check (
    requester_user_id in (user_low_id, user_high_id)
  ),
  constraint friendships_status_time_check check (
    (status = 'pending' and responded_at is null)
    or (status <> 'pending' and responded_at is not null)
  ),
  constraint friendships_pair_key unique (user_low_id, user_high_id)
);

create index friendships_low_status_updated_idx
  on gymapp_private.friendships (user_low_id, status, updated_at desc);
create index friendships_high_status_updated_idx
  on gymapp_private.friendships (user_high_id, status, updated_at desc);
create index friendships_requester_status_requested_idx
  on gymapp_private.friendships (requester_user_id, status, requested_at desc);

create table gymapp_private.friend_blocks (
  blocker_user_id uuid not null
    references auth.users(id) on delete cascade,
  blocked_user_id uuid not null
    references auth.users(id) on delete cascade,
  blocked_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (blocker_user_id, blocked_user_id),
  check (blocker_user_id <> blocked_user_id)
);

create index friend_blocks_blocked_idx
  on gymapp_private.friend_blocks (blocked_user_id, blocker_user_id);

create table gymapp_private.social_activity_projection (
  user_id uuid primary key
    references public.user_states(user_id) on delete cascade,
  source_revision timestamptz not null,
  recent_workouts jsonb not null default '[]'::jsonb,
  exercise_records jsonb not null default '[]'::jsonb,
  projected_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint social_activity_recent_shape_check check (
    pg_catalog.jsonb_typeof(recent_workouts) = 'array'
    and pg_catalog.jsonb_array_length(recent_workouts) <= 5
    and pg_catalog.pg_column_size(recent_workouts) <= 65536
  ),
  constraint social_activity_records_shape_check check (
    pg_catalog.jsonb_typeof(exercise_records) = 'array'
    and pg_catalog.jsonb_array_length(exercise_records) <= 100
    and pg_catalog.pg_column_size(exercise_records) <= 262144
  )
);

create table gymapp_private.social_rate_limits (
  user_id uuid not null
    references auth.users(id) on delete cascade,
  bucket_action text not null check (bucket_action in (
    'dashboard', 'friend_details', 'send_friend', 'respond_friend',
    'cancel_friend', 'remove_friend', 'block_profile', 'unblock_profile',
    'update_privacy', 'workout_inbox', 'send_workout',
    'respond_workout', 'cancel_workout'
  )),
  tokens numeric(20, 9) not null check (tokens between 0 and 120),
  refilled_at timestamptz not null,
  primary key (user_id, bucket_action)
);

create table gymapp_private.social_workout_invites (
  id text primary key default (
    'wi_' || pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '')
  ) check (id ~ '^wi_[0-9a-f]{32}$'),
  sender_user_id uuid not null
    references auth.users(id) on delete cascade,
  recipient_user_id uuid not null
    references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'cancelled', 'expired')),
  workout jsonb,
  summary jsonb,
  revision bigint not null default 1
    check (revision between 1 and 2147483647),
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  expires_at timestamptz not null,
  responded_at timestamptz,
  payload_purged_at timestamptz,
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint social_workout_invites_users_check check (
    sender_user_id <> recipient_user_id
  ),
  constraint social_workout_invites_status_time_check check (
    (status = 'pending' and responded_at is null)
    or (status <> 'pending' and responded_at is not null)
  ),
  constraint social_workout_invites_expiry_check check (
    expires_at = created_at + interval '7 days'
  ),
  constraint social_workout_invites_purge_time_check check (
    payload_purged_at is null
    or (
      responded_at is not null
      and payload_purged_at >= responded_at
    )
  ),
  constraint social_workout_invites_payload_check check (
    (
      payload_purged_at is null
      and workout is not null
      and pg_catalog.jsonb_typeof(workout) = 'object'
      and workout->>'version' = '1'
      and pg_catalog.pg_column_size(workout) <= 65536
    )
    or (
      payload_purged_at is not null
      and status <> 'pending'
      and workout is null
    )
  ),
  constraint social_workout_invites_summary_check check (
    (
      payload_purged_at is null
      and summary is not null
      and pg_catalog.jsonb_typeof(summary) = 'object'
      and pg_catalog.pg_column_size(summary) <= 16384
    )
    or (payload_purged_at is not null and summary is null)
  ),
  constraint social_workout_invites_sender_request_key unique (
    sender_user_id, client_request_id
  )
);

create index social_workout_invites_incoming_idx
  on gymapp_private.social_workout_invites (
    recipient_user_id, created_at desc
  );
create index social_workout_invites_outgoing_idx
  on gymapp_private.social_workout_invites (
    sender_user_id, created_at desc
  );
create index social_workout_invites_pending_expiry_idx
  on gymapp_private.social_workout_invites (expires_at)
  where status = 'pending';
create index social_workout_invites_pending_sender_idx
  on gymapp_private.social_workout_invites (sender_user_id, expires_at)
  where status = 'pending';
create index social_workout_invites_pending_recipient_idx
  on gymapp_private.social_workout_invites (recipient_user_id, expires_at)
  where status = 'pending';
create index social_workout_invites_retained_sender_idx
  on gymapp_private.social_workout_invites (sender_user_id, responded_at)
  where workout is not null and status <> 'pending';
create index social_workout_invites_retained_recipient_idx
  on gymapp_private.social_workout_invites (recipient_user_id, responded_at)
  where workout is not null and status <> 'pending';

comment on table gymapp_private.social_settings is
  'Private friend-discovery and per-category sharing consent. Clients use only bounded social RPCs.';
comment on table gymapp_private.friendships is
  'One canonical unordered user pair with a revisioned mutual-friend state machine.';
comment on table gymapp_private.friend_blocks is
  'Private directional blocks; either direction immediately denies social reads and mutations.';
comment on table gymapp_private.social_activity_projection is
  'Revision-bound safe summaries derived from validated user_states; never stores notes, raw sets, owner metadata, email, or health data.';
comment on table gymapp_private.social_rate_limits is
  'Atomic per-account token buckets for committed social RPC calls. PostgreSQL rolls back a charge when the enclosing RPC raises, so rejected-error traffic also requires perimeter rate limiting.';
comment on table gymapp_private.social_workout_invites is
  'Static bounded shared-workout v1 invitations, with idempotency tombstones after bounded payload retention; not a live workout synchronization channel.';

alter table gymapp_private.social_settings enable row level security;
alter table gymapp_private.friendships enable row level security;
alter table gymapp_private.friend_blocks enable row level security;
alter table gymapp_private.social_activity_projection enable row level security;
alter table gymapp_private.social_rate_limits enable row level security;
alter table gymapp_private.social_workout_invites enable row level security;

revoke all on table gymapp_private.social_settings
  from public, anon, authenticated, service_role;
revoke all on table gymapp_private.friendships
  from public, anon, authenticated, service_role;
revoke all on table gymapp_private.friend_blocks
  from public, anon, authenticated, service_role;
revoke all on table gymapp_private.social_activity_projection
  from public, anon, authenticated, service_role;
revoke all on table gymapp_private.social_rate_limits
  from public, anon, authenticated, service_role;
revoke all on table gymapp_private.social_workout_invites
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_name_is_safe(p_value text)
returns boolean
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $function$
declare
  character_index integer;
  code_point integer;
begin
  if p_value <> pg_catalog.btrim(p_value)
     or pg_catalog.char_length(p_value) not between 1 and 120
     or pg_catalog.octet_length(pg_catalog.convert_to(p_value, 'UTF8')) > 480 then
    return false;
  end if;

  for character_index in 1..pg_catalog.char_length(p_value) loop
    code_point := pg_catalog.ascii(pg_catalog.substr(p_value, character_index, 1));
    if code_point between 0 and 31
       or code_point between 127 and 159
       or code_point in (
         173, 1564, 1757, 1807, 2192, 2193, 2274, 6158, 8203, 8204, 8205,
         8206, 8207, 8232, 8233, 8234, 8235, 8236, 8237, 8238,
         8288, 8289, 8290, 8291, 8292, 8294, 8295, 8296, 8297,
         8298, 8299, 8300, 8301, 8302, 8303, 65279, 65529, 65530, 65531,
         69821, 69837,
         113824, 113825, 113826, 113827, 119155, 119156, 119157,
         119158, 119159, 119160, 119161, 119162, 917505
       )
       or code_point between 1536 and 1541
       or code_point between 6068 and 6069
       or code_point between 8288 and 8303
       or code_point between 78896 and 78943
       or code_point between 917536 and 917631 then
      return false;
    end if;
  end loop;
  return true;
end
$function$;

revoke all on function gymapp_private.social_name_is_safe(text)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_safe_display_name(p_value text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  safe_value text := public.safe_leaderboard_display_name(p_value);
begin
  if safe_value is null
     or not gymapp_private.social_name_is_safe(safe_value) then
    return 'GymApp user';
  end if;
  return safe_value;
end
$function$;

revoke all on function gymapp_private.social_safe_display_name(text)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_normalize_name(p_value text)
returns text
language sql
immutable
strict
security invoker
set search_path = ''
as $function$
  select pg_catalog.replace(
    pg_catalog.replace(
      pg_catalog.replace(
        pg_catalog.lower(
          pg_catalog.regexp_replace(pg_catalog.btrim(p_value), '[[:space:]]+', ' ', 'g')
        ),
        pg_catalog.chr(700),
        ''''
      ),
      pg_catalog.chr(8217),
      ''''
    ),
    'ё',
    'е'
  )
$function$;

revoke all on function gymapp_private.social_normalize_name(text)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.validate_social_workout(p_workout jsonb)
returns jsonb
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $function$
declare
  exercise_value jsonb;
  set_value jsonb;
  canonical_exercises jsonb := '[]'::jsonb;
  canonical_sets jsonb;
  canonical_workout jsonb;
  exercise_name text;
  catalog_key text;
  normalized_name text;
  names_seen jsonb := '{}'::jsonb;
  catalog_keys_seen jsonb := '{}'::jsonb;
  exercise_count integer;
  set_count integer;
  total_set_count integer := 0;
  weight_value numeric;
  reps_value numeric;
begin
  if pg_catalog.jsonb_typeof(p_workout) is distinct from 'object'
     or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_workout)) <> 2
     or not (p_workout ? 'version')
     or not (p_workout ? 'exercises')
     or pg_catalog.jsonb_typeof(p_workout->'version') is distinct from 'number'
     or (p_workout->>'version')::numeric <> 1
     or pg_catalog.jsonb_typeof(p_workout->'exercises') is distinct from 'array' then
    raise exception using errcode = '22023', message = 'Shared workout is invalid.';
  end if;

  -- Bound native numeric renderings before canonical jsonb-to-text conversion;
  -- compact exponent spellings must not expand into a large server allocation.
  if pg_catalog.jsonb_path_exists(
    p_workout,
    'strict $.** ? (@.type() == "number" && @.string() like_regex "^.{65}" flag "s")'::pg_catalog.jsonpath
  ) then
    raise exception using errcode = '54000', message = 'Shared workout number is oversized.';
  end if;

  if pg_catalog.octet_length(pg_catalog.convert_to(p_workout::text, 'UTF8')) > 32768 then
    raise exception using errcode = '54000', message = 'Shared workout exceeds 32 KiB.';
  end if;

  exercise_count := pg_catalog.jsonb_array_length(p_workout->'exercises');
  if exercise_count not between 1 and 20 then
    raise exception using errcode = '22023', message = 'Shared workout exercise count is invalid.';
  end if;

  for exercise_value in
    select item.value
    from pg_catalog.jsonb_array_elements(p_workout->'exercises') as item(value)
  loop
    if pg_catalog.jsonb_typeof(exercise_value) is distinct from 'object'
       or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(exercise_value)) not between 2 and 3
       or not (exercise_value ? 'name')
       or not (exercise_value ? 'sets')
       or exists (
         select 1
         from pg_catalog.jsonb_object_keys(exercise_value) as object_key(key)
         where object_key.key not in ('catalogKey', 'name', 'sets')
       )
       or pg_catalog.jsonb_typeof(exercise_value->'name') is distinct from 'string'
       or pg_catalog.jsonb_typeof(exercise_value->'sets') is distinct from 'array' then
      raise exception using errcode = '22023', message = 'Shared workout exercise is invalid.';
    end if;

    exercise_name := exercise_value->>'name';
    if not gymapp_private.social_name_is_safe(exercise_name) then
      raise exception using errcode = '22023', message = 'Shared workout exercise name is invalid.';
    end if;
    normalized_name := gymapp_private.social_normalize_name(exercise_name);
    if names_seen ? normalized_name then
      raise exception using errcode = '22023', message = 'Shared workout contains duplicate exercise names.';
    end if;
    names_seen := names_seen || pg_catalog.jsonb_build_object(normalized_name, true);

    catalog_key := null;
    if exercise_value ? 'catalogKey' then
      if pg_catalog.jsonb_typeof(exercise_value->'catalogKey') is distinct from 'string'
         or (exercise_value->>'catalogKey') !~ '^[a-z0-9_]{1,64}$' then
        raise exception using errcode = '22023', message = 'Shared workout catalog key is invalid.';
      end if;
      catalog_key := exercise_value->>'catalogKey';
      if catalog_keys_seen ? catalog_key then
        raise exception using errcode = '22023', message = 'Shared workout contains duplicate catalog keys.';
      end if;
      catalog_keys_seen := catalog_keys_seen || pg_catalog.jsonb_build_object(catalog_key, true);
    end if;

    set_count := pg_catalog.jsonb_array_length(exercise_value->'sets');
    if set_count not between 1 and 12 then
      raise exception using errcode = '22023', message = 'Shared workout set count is invalid.';
    end if;
    total_set_count := total_set_count + set_count;
    if total_set_count > 120 then
      raise exception using errcode = '54000', message = 'Shared workout contains too many sets.';
    end if;

    canonical_sets := '[]'::jsonb;
    for set_value in
      select item.value
      from pg_catalog.jsonb_array_elements(exercise_value->'sets') as item(value)
    loop
      if pg_catalog.jsonb_typeof(set_value) is distinct from 'object'
         or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(set_value)) <> 2
         or not (set_value ? 'weight')
         or not (set_value ? 'reps')
         or pg_catalog.jsonb_typeof(set_value->'weight') is distinct from 'number'
         or pg_catalog.jsonb_typeof(set_value->'reps') is distinct from 'number' then
        raise exception using errcode = '22023', message = 'Shared workout set is invalid.';
      end if;
      weight_value := (set_value->>'weight')::numeric;
      reps_value := (set_value->>'reps')::numeric;
      if weight_value not between 0 and 1000000
         or reps_value not between 1 and 10000
         or reps_value <> pg_catalog.trunc(reps_value) then
        raise exception using errcode = '22023', message = 'Shared workout set values are invalid.';
      end if;
      canonical_sets := canonical_sets || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'weight', case when weight_value = 0 then 0 else weight_value end,
          'reps', reps_value::integer
        )
      );
    end loop;

    canonical_exercises := canonical_exercises || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('name', exercise_name, 'sets', canonical_sets)
      || case when catalog_key is null then '{}'::jsonb
              else pg_catalog.jsonb_build_object('catalogKey', catalog_key) end
    );
  end loop;

  canonical_workout := pg_catalog.jsonb_build_object(
    'version', 1,
    'exercises', canonical_exercises
  );
  if pg_catalog.octet_length(pg_catalog.convert_to(canonical_workout::text, 'UTF8')) > 32768 then
    raise exception using errcode = '54000', message = 'Shared workout exceeds 32 KiB.';
  end if;
  return canonical_workout;
end
$function$;

revoke all on function gymapp_private.validate_social_workout(jsonb)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_workout_summary(p_workout jsonb)
returns jsonb
language sql
immutable
strict
security invoker
set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'exerciseCount', pg_catalog.jsonb_array_length(p_workout->'exercises'),
    'setCount', (
      select coalesce(pg_catalog.sum(pg_catalog.jsonb_array_length(exercise.value->'sets')), 0)::integer
      from pg_catalog.jsonb_array_elements(p_workout->'exercises') as exercise(value)
    ),
    'exerciseNames', (
      select coalesce(
        pg_catalog.jsonb_agg(pg_catalog.to_jsonb(exercise.value->>'name') order by exercise.ordinality),
        '[]'::jsonb
      )
      from pg_catalog.jsonb_array_elements(p_workout->'exercises')
        with ordinality as exercise(value, ordinality)
    )
  )
$function$;

revoke all on function gymapp_private.social_workout_summary(jsonb)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_activity_from_state(p_state jsonb)
returns table (recent_workouts jsonb, exercise_records jsonb)
language plpgsql
volatile
strict
security invoker
set search_path = ''
as $function$
begin
  perform gymapp_private.validate_user_state(p_state);

  return query
  with raw_sessions as (
    select
      session.ordinality::bigint as session_number,
      session.value as session_value,
      coalesce(session.value->>'date', session.value->>'startedAt')::numeric as workout_millis
    from pg_catalog.jsonb_array_elements(
      case when pg_catalog.jsonb_typeof(p_state->'sessions') = 'array'
        then p_state->'sessions' else '[]'::jsonb end
    ) with ordinality as session(value, ordinality)
  ),
  eligible_sessions as (
    select *
    from raw_sessions
    where workout_millis <= (
      extract(epoch from pg_catalog.clock_timestamp() + interval '24 hours') * 1000
    )::numeric
  ),
  native_sets as (
    select
      session.session_number,
      session.workout_millis,
      pg_catalog.btrim(exercise.value->>'name') as exercise_name,
      case
        when pg_catalog.jsonb_typeof(exercise.value->'catalogKey') = 'string'
         and exercise.value->>'catalogKey' ~ '^[a-z0-9_]{1,64}$'
          then exercise.value->>'catalogKey'
        else null
      end as catalog_key,
      (set_item.value->>'weight')::numeric as weight_value,
      (set_item.value->>'reps')::integer as reps_value
    from eligible_sessions as session
    cross join lateral pg_catalog.jsonb_array_elements(
      case when pg_catalog.jsonb_typeof(session.session_value->'exercises') = 'array'
        then session.session_value->'exercises' else '[]'::jsonb end
    ) as exercise(value)
    cross join lateral pg_catalog.jsonb_array_elements(
      case when pg_catalog.jsonb_typeof(exercise.value->'sets') = 'array'
        then exercise.value->'sets' else '[]'::jsonb end
    ) as set_item(value)
    where not (
      pg_catalog.jsonb_typeof(session.session_value->'sets') is not distinct from 'array'
      and pg_catalog.jsonb_array_length(session.session_value->'sets') > 0
    )
      and gymapp_private.social_name_is_safe(pg_catalog.btrim(exercise.value->>'name'))
  ),
  flat_sets as (
    select
      session.session_number,
      session.workout_millis,
      pg_catalog.btrim(coalesce(set_item.value->>'exerciseName', set_item.value->>'name')) as exercise_name,
      case
        when pg_catalog.jsonb_typeof(set_item.value->'catalogKey') = 'string'
         and set_item.value->>'catalogKey' ~ '^[a-z0-9_]{1,64}$'
          then set_item.value->>'catalogKey'
        else null
      end as catalog_key,
      (set_item.value->>'weight')::numeric as weight_value,
      (set_item.value->>'reps')::integer as reps_value
    from eligible_sessions as session
    cross join lateral pg_catalog.jsonb_array_elements(
      case when pg_catalog.jsonb_typeof(session.session_value->'sets') = 'array'
        then session.session_value->'sets' else '[]'::jsonb end
    ) as set_item(value)
    where pg_catalog.jsonb_typeof(session.session_value->'sets') = 'array'
      and pg_catalog.jsonb_array_length(session.session_value->'sets') > 0
      and gymapp_private.social_name_is_safe(
        pg_catalog.btrim(coalesce(set_item.value->>'exerciseName', set_item.value->>'name'))
      )
  ),
  set_rows as (
    select * from native_sets
    union all
    select * from flat_sets
  ),
  identified_sets as (
    select
      set_row.*,
      case when set_row.catalog_key is not null
        then 'catalog:' || set_row.catalog_key
        else 'name:' || gymapp_private.social_normalize_name(set_row.exercise_name)
      end as exercise_identity
    from set_rows as set_row
  ),
  session_identity_rows as (
    select
      set_row.session_number,
      set_row.workout_millis,
      set_row.exercise_identity,
      pg_catalog.min(set_row.exercise_name) as exercise_name,
      pg_catalog.max(set_row.catalog_key) as catalog_key
    from identified_sets as set_row
    group by set_row.session_number, set_row.workout_millis, set_row.exercise_identity
  ),
  ranked_session_identities as (
    select
      identity_row.*,
      pg_catalog.row_number() over (
        partition by identity_row.session_number
        order by pg_catalog.lower(identity_row.exercise_name), identity_row.exercise_identity
      ) as identity_position
    from session_identity_rows as identity_row
  ),
  session_labels as (
    select
      identity_row.session_number,
      identity_row.workout_millis,
      pg_catalog.count(*)::integer as exercise_count,
      coalesce(
        pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'catalogKey', identity_row.catalog_key,
            'name', identity_row.exercise_name
          ) order by identity_row.identity_position
        ) filter (where identity_row.identity_position <= 20),
        '[]'::jsonb
      ) as exercises
    from ranked_session_identities as identity_row
    group by identity_row.session_number, identity_row.workout_millis
  ),
  session_summaries as (
    select
      labels.session_number,
      labels.workout_millis,
      labels.exercise_count,
      pg_catalog.count(*)::integer as set_count,
      labels.exercises
    from session_labels as labels
    join identified_sets as set_row
      on set_row.session_number = labels.session_number
    group by labels.session_number, labels.workout_millis,
      labels.exercise_count, labels.exercises
  ),
  latest_sessions as (
    select *
    from session_summaries
    order by workout_millis desc, session_number desc
    limit 5
  ),
  record_rows as (
    select
      set_row.exercise_identity,
      pg_catalog.min(set_row.exercise_name) as exercise_name,
      pg_catalog.max(set_row.catalog_key) as catalog_key,
      pg_catalog.max(set_row.weight_value) as best_weight,
      pg_catalog.max(set_row.reps_value) as best_reps,
      pg_catalog.count(distinct set_row.session_number)::integer as workout_count,
      pg_catalog.max(set_row.workout_millis) as last_workout_millis
    from identified_sets as set_row
    group by set_row.exercise_identity
  ),
  latest_records as (
    select *
    from record_rows
    order by last_workout_millis desc, pg_catalog.lower(exercise_name), exercise_identity
    limit 100
  )
  select
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'workoutDay', ((pg_catalog.to_timestamp((summary.workout_millis / 1000)::double precision)
            at time zone 'UTC')::date)::text,
          'exerciseCount', summary.exercise_count,
          'setCount', summary.set_count,
          'exercises', summary.exercises
        ) order by summary.workout_millis desc, summary.session_number desc
      )
      from latest_sessions as summary
    ), '[]'::jsonb),
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'catalogKey', record.catalog_key,
          'name', record.exercise_name,
          'bestWeightKg', record.best_weight,
          'bestReps', record.best_reps,
          'workoutCount', record.workout_count,
          'lastWorkoutDay', ((pg_catalog.to_timestamp((record.last_workout_millis / 1000)::double precision)
            at time zone 'UTC')::date)::text
        ) order by record.last_workout_millis desc,
          pg_catalog.lower(record.exercise_name), record.exercise_identity
      )
      from latest_records as record
    ), '[]'::jsonb);
end
$function$;

revoke all on function gymapp_private.social_activity_from_state(jsonb)
  from public, anon, authenticated, service_role;

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
  from gymapp_private.social_activity_from_state(new.state);

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

drop trigger if exists user_states_refresh_social_activity on public.user_states;
create trigger user_states_refresh_social_activity
after insert or update of user_id, state or delete
on public.user_states
for each row
execute function gymapp_private.refresh_social_activity_projection();

create or replace function gymapp_private.refresh_social_activity_revision_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update gymapp_private.social_activity_projection as projection
  set source_revision = new.updated_at
  where projection.user_id = new.user_id;
  return new;
end
$function$;

revoke all on function gymapp_private.refresh_social_activity_revision_only()
  from public, anon, authenticated, service_role;

drop trigger if exists user_states_social_activity_revision_only on public.user_states;
create trigger user_states_social_activity_revision_only
after update on public.user_states
for each row
when (
  old.state is not distinct from new.state
  and old.updated_at is distinct from new.updated_at
)
execute function gymapp_private.refresh_social_activity_revision_only();

create or replace function gymapp_private.consume_social_rate_limit(
  p_user_id uuid,
  p_action text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  bucket_capacity numeric(20, 9);
  refill_per_second numeric(20, 9);
  request_time timestamptz := pg_catalog.clock_timestamp();
  remaining_tokens numeric(20, 9);
begin
  select configuration.capacity, configuration.refill_rate
  into bucket_capacity, refill_per_second
  from (values
    ('dashboard', 120::numeric, 2::numeric),
    ('friend_details', 120::numeric, 2::numeric),
    ('send_friend', 12::numeric, (1::numeric / 300::numeric)),
    ('respond_friend', 30::numeric, (1::numeric / 30::numeric)),
    ('cancel_friend', 30::numeric, (1::numeric / 30::numeric)),
    ('remove_friend', 20::numeric, (1::numeric / 60::numeric)),
    ('block_profile', 30::numeric, (1::numeric / 30::numeric)),
    ('unblock_profile', 30::numeric, (1::numeric / 30::numeric)),
    ('update_privacy', 20::numeric, (1::numeric / 60::numeric)),
    ('workout_inbox', 120::numeric, 2::numeric),
    ('send_workout', 10::numeric, (1::numeric / 360::numeric)),
    ('respond_workout', 30::numeric, (1::numeric / 30::numeric)),
    ('cancel_workout', 30::numeric, (1::numeric / 30::numeric))
  ) as configuration(action, capacity, refill_rate)
  where configuration.action = p_action;

  if p_user_id is null or bucket_capacity is null then
    raise exception using errcode = '22023', message = 'Social rate-limit request is invalid.';
  end if;

  insert into gymapp_private.social_rate_limits (
    user_id, bucket_action, tokens, refilled_at
  ) values (
    p_user_id, p_action, bucket_capacity - 1, request_time
  )
  on conflict (user_id, bucket_action) do update
  set tokens = least(
        bucket_capacity,
        gymapp_private.social_rate_limits.tokens
          + greatest(
              extract(epoch from request_time - gymapp_private.social_rate_limits.refilled_at),
              0
            ) * refill_per_second
      ) - 1,
      refilled_at = request_time
  where least(
    bucket_capacity,
    gymapp_private.social_rate_limits.tokens
      + greatest(
          extract(epoch from request_time - gymapp_private.social_rate_limits.refilled_at),
          0
        ) * refill_per_second
  ) >= 1
  returning tokens into remaining_tokens;

  if not found then
    raise exception using errcode = 'P0001', message = 'Social request limit exceeded.';
  end if;
end
$function$;

revoke all on function gymapp_private.consume_social_rate_limit(uuid, text)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_lock_pair(
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
  low_user_id uuid;
  high_user_id uuid;
begin
  if p_first_user_id = p_second_user_id then
    raise exception using errcode = '22023', message = 'Social pair is invalid.';
  end if;
  low_user_id := case when p_first_user_id::text < p_second_user_id::text
    then p_first_user_id else p_second_user_id end;
  high_user_id := case when p_first_user_id::text < p_second_user_id::text
    then p_second_user_id else p_first_user_id end;
  -- The two account locks are acquired in canonical UUID order. They make
  -- per-account friend/invite caps race-safe even across different pairs.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gymapp-social-user:' || low_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gymapp-social-user:' || high_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'gymapp-social-pair:' || low_user_id::text || ':' || high_user_id::text,
      0
    )
  );
end
$function$;

revoke all on function gymapp_private.social_lock_pair(uuid, uuid)
  from public, anon, authenticated, service_role;

do $verify$
declare
  relation_name text;
begin
  foreach relation_name in array array[
    'social_settings', 'friendships', 'friend_blocks',
    'social_activity_projection', 'social_rate_limits', 'social_workout_invites'
  ] loop
    if not exists (
      select 1
      from pg_catalog.pg_class as relation
      join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
      where namespace.nspname = 'gymapp_private'
        and relation.relname = relation_name
        and relation.relrowsecurity
    )
       or pg_catalog.has_table_privilege('anon', 'gymapp_private.' || relation_name, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.' || relation_name, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.' || relation_name, 'INSERT')
       or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.' || relation_name, 'UPDATE')
       or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.' || relation_name, 'DELETE') then
      raise exception 'Private social relation % is not deny-by-default.', relation_name;
    end if;
  end loop;

  if pg_catalog.has_function_privilege('anon', 'gymapp_private.validate_social_workout(jsonb)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'gymapp_private.validate_social_workout(jsonb)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'gymapp_private.social_activity_from_state(jsonb)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'gymapp_private.consume_social_rate_limit(uuid,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'gymapp_private.social_lock_pair(uuid,uuid)', 'EXECUTE') then
    raise exception 'Private social helper grants are not least privilege.';
  end if;
end
$verify$;

commit;
