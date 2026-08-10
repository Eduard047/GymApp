begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

-- Storage-only phase for two-person live workouts. Every relation remains
-- private and RPC-only; the service-role gateway API is activated by the next
-- migration, after all constraints and server-side invariants exist.
do $preflight$
begin
  if pg_catalog.current_setting('server_version_num')::integer < 170000 then
    raise exception 'GymApp live workouts require PostgreSQL 17 or newer.';
  end if;

  if pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regclass('gymapp_private.friendships') is null
     or pg_catalog.to_regclass('gymapp_private.friend_blocks') is null
     or pg_catalog.to_regprocedure('gymapp_private.validate_social_workout(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_workout_summary(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_name_is_safe(text)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_lock_pair(uuid,uuid)') is null then
    raise exception 'GymApp live-workout prerequisites are missing.';
  end if;
end
$preflight$;

create table gymapp_private.live_workout_rooms (
  id text primary key default (
    'lr_' || pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '')
  ) check (id ~ '^lr_[0-9a-f]{32}$'),
  owner_user_id uuid not null
    references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  status text not null default 'waiting'
    check (status in ('waiting', 'ready', 'active', 'completed', 'cancelled', 'expired')),
  close_reason text
    check (close_reason is null or close_reason in (
      'completed', 'declined', 'cancelled', 'left',
      'friend_removed', 'blocked', 'account_deleted', 'expired'
    )),
  plan jsonb,
  summary jsonb,
  revision bigint not null default 1
    check (revision between 1 and 2147483647),
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  invite_expires_at timestamptz not null,
  started_at timestamptz,
  active_expires_at timestamptz,
  last_activity_at timestamptz not null default pg_catalog.clock_timestamp(),
  ended_at timestamptz,
  payload_purged_at timestamptz,
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint live_workout_rooms_owner_request_key unique (
    owner_user_id, client_request_id
  ),
  constraint live_workout_rooms_invite_expiry_check check (
    invite_expires_at = created_at + interval '7 days'
  ),
  constraint live_workout_rooms_active_expiry_check check (
    active_expires_at is null
    or (
      started_at is not null
      and active_expires_at = started_at + interval '24 hours'
    )
  ),
  constraint live_workout_rooms_activity_time_check check (
    last_activity_at >= created_at
    and updated_at >= created_at
    and (ended_at is null or ended_at >= created_at)
    and (payload_purged_at is null or payload_purged_at >= ended_at)
  ),
  constraint live_workout_rooms_status_time_check check (
    (
      status in ('waiting', 'ready')
      and started_at is null
      and active_expires_at is null
      and ended_at is null
      and close_reason is null
    )
    or (
      status = 'active'
      and started_at is not null
      and active_expires_at is not null
      and ended_at is null
      and close_reason is null
    )
    or (
      status = 'completed'
      and started_at is not null
      and active_expires_at is not null
      and ended_at is not null
      and close_reason = 'completed'
    )
    or (
      status = 'cancelled'
      and ended_at is not null
      and close_reason in (
        'declined', 'cancelled', 'left',
        'friend_removed', 'blocked', 'account_deleted'
      )
    )
    or (
      status = 'expired'
      and ended_at is not null
      and close_reason = 'expired'
    )
  ),
  constraint live_workout_rooms_payload_check check (
    (
      payload_purged_at is null
      and plan is not null
      and summary is not null
      and pg_catalog.jsonb_typeof(plan) = 'object'
      and plan->>'version' = '1'
      and pg_catalog.pg_column_size(plan) <= 65536
      and pg_catalog.jsonb_typeof(summary) = 'object'
      and pg_catalog.pg_column_size(summary) <= 16384
    )
    or (
      payload_purged_at is not null
      and status in ('completed', 'cancelled', 'expired')
      and plan is null
      and summary is null
    )
  )
);

create unique index live_workout_rooms_owner_open_idx
  on gymapp_private.live_workout_rooms (owner_user_id)
  where status in ('waiting', 'ready', 'active');
create index live_workout_rooms_waiting_expiry_idx
  on gymapp_private.live_workout_rooms (invite_expires_at, id)
  where status in ('waiting', 'ready');
create index live_workout_rooms_active_expiry_idx
  on gymapp_private.live_workout_rooms (active_expires_at, id)
  where status = 'active';
create index live_workout_rooms_terminal_retention_idx
  on gymapp_private.live_workout_rooms (ended_at, id)
  where status in ('completed', 'cancelled', 'expired');

create table gymapp_private.live_workout_members (
  room_id text not null
    references gymapp_private.live_workout_rooms(id) on delete cascade,
  user_id uuid not null
    references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'participant')),
  state text not null check (state in ('invited', 'joined', 'finished', 'left', 'revoked')),
  revision bigint not null default 1
    check (revision between 1 and 2147483647),
  invited_at timestamptz not null default pg_catalog.clock_timestamp(),
  joined_at timestamptz,
  finished_at timestamptz,
  departed_at timestamptz,
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (room_id, user_id),
  constraint live_workout_members_room_role_key unique (room_id, role),
  constraint live_workout_members_role_state_check check (
    role <> 'owner' or state <> 'invited'
  ),
  constraint live_workout_members_state_time_check check (
    (
      state = 'invited'
      and role = 'participant'
      and joined_at is null
      and finished_at is null
      and departed_at is null
    )
    or (
      state = 'joined'
      and joined_at is not null
      and finished_at is null
      and departed_at is null
    )
    or (
      state = 'finished'
      and joined_at is not null
      and finished_at is not null
      and departed_at is null
    )
    or (
      state = 'left'
      and joined_at is not null
      and departed_at is not null
    )
    or (
      state = 'revoked'
      and finished_at is null
      and departed_at is not null
    )
  ),
  constraint live_workout_members_time_order_check check (
    updated_at >= invited_at
    and (joined_at is null or joined_at >= invited_at)
    and (finished_at is null or finished_at >= joined_at)
    and (departed_at is null or departed_at >= invited_at)
  )
);

create index live_workout_members_user_state_updated_idx
  on gymapp_private.live_workout_members (user_id, state, updated_at desc, room_id);
create index live_workout_members_room_state_idx
  on gymapp_private.live_workout_members (room_id, state, user_id);

create or replace function gymapp_private.live_workout_progress_is_valid(
  p_progress jsonb
)
returns boolean
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $function$
declare
  completed_set jsonb;
  set_id text;
  weight_value numeric;
  reps_value numeric;
  seen_set_ids jsonb := '{}'::jsonb;
  last_set_id text;
begin
  if pg_catalog.jsonb_typeof(p_progress) is distinct from 'object'
     or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_progress)) <> 4
     or not (p_progress ? 'version')
     or not (p_progress ? 'completedSets')
     or not (p_progress ? 'undoableSetId')
     or not (p_progress ? 'finishedAt')
     or pg_catalog.jsonb_typeof(p_progress->'version') is distinct from 'number'
     or (p_progress->>'version')::numeric <> 1
     or pg_catalog.jsonb_typeof(p_progress->'completedSets') is distinct from 'array'
     or pg_catalog.jsonb_array_length(p_progress->'completedSets') > 120
     or pg_catalog.pg_column_size(p_progress) > 65536 then
    return false;
  end if;

  if pg_catalog.jsonb_typeof(p_progress->'undoableSetId') not in ('null', 'string')
     or pg_catalog.jsonb_typeof(p_progress->'finishedAt') not in ('null', 'string') then
    return false;
  end if;
  if pg_catalog.jsonb_typeof(p_progress->'undoableSetId') = 'string'
     and (p_progress->>'undoableSetId') !~ '^s_[0-9]{2}_[0-9]{2}$' then
    return false;
  end if;
  if pg_catalog.jsonb_typeof(p_progress->'finishedAt') = 'string'
     and (
       pg_catalog.char_length(p_progress->>'finishedAt') not between 20 and 40
       or (p_progress->>'finishedAt') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T]'
     ) then
    return false;
  end if;

  for completed_set in
    select item.value
    from pg_catalog.jsonb_array_elements(p_progress->'completedSets') as item(value)
  loop
    if pg_catalog.jsonb_typeof(completed_set) is distinct from 'object'
       or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(completed_set)) <> 4
       or not (completed_set ? 'setId')
       or not (completed_set ? 'weight')
       or not (completed_set ? 'reps')
       or not (completed_set ? 'completedAt')
       or pg_catalog.jsonb_typeof(completed_set->'setId') is distinct from 'string'
       or pg_catalog.jsonb_typeof(completed_set->'weight') is distinct from 'number'
       or pg_catalog.jsonb_typeof(completed_set->'reps') is distinct from 'number'
       or pg_catalog.jsonb_typeof(completed_set->'completedAt') is distinct from 'string' then
      return false;
    end if;

    set_id := completed_set->>'setId';
    if set_id !~ '^s_[0-9]{2}_[0-9]{2}$'
       or seen_set_ids ? set_id
       or pg_catalog.char_length(completed_set->>'completedAt') not between 20 and 40
       or (completed_set->>'completedAt') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T]' then
      return false;
    end if;
    weight_value := (completed_set->>'weight')::numeric;
    reps_value := (completed_set->>'reps')::numeric;
    if weight_value not between 0 and 1000000
       or reps_value not between 1 and 10000
       or reps_value <> pg_catalog.trunc(reps_value) then
      return false;
    end if;
    seen_set_ids := seen_set_ids || pg_catalog.jsonb_build_object(set_id, true);
    last_set_id := set_id;
  end loop;

  if pg_catalog.jsonb_array_length(p_progress->'completedSets') = 0 then
    return pg_catalog.jsonb_typeof(p_progress->'undoableSetId') = 'null';
  end if;
  return p_progress->>'undoableSetId' = last_set_id;
exception
  when data_exception then
    return false;
end
$function$;

revoke all on function gymapp_private.live_workout_progress_is_valid(jsonb)
  from public, anon, authenticated, service_role;

create table gymapp_private.live_workout_progress (
  room_id text not null,
  user_id uuid not null,
  payload jsonb not null default pg_catalog.jsonb_build_object(
    'version', 1,
    'completedSets', pg_catalog.jsonb_build_array(),
    'undoableSetId', null,
    'finishedAt', null
  ),
  revision bigint not null default 1
    check (revision between 1 and 2147483647),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (room_id, user_id),
  constraint live_workout_progress_member_fkey
    foreign key (room_id, user_id)
    references gymapp_private.live_workout_members(room_id, user_id)
    on delete cascade,
  constraint live_workout_progress_payload_check check (
    gymapp_private.live_workout_progress_is_valid(payload)
  )
);

create index live_workout_progress_user_updated_idx
  on gymapp_private.live_workout_progress (user_id, updated_at desc, room_id);

create table gymapp_private.live_workout_operation_receipts (
  room_id text not null,
  user_id uuid not null,
  client_operation_id uuid not null,
  request jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (room_id, user_id, client_operation_id),
  constraint live_workout_operation_receipts_member_fkey
    foreign key (room_id, user_id)
    references gymapp_private.live_workout_members(room_id, user_id)
    on delete cascade,
  constraint live_workout_operation_receipts_request_check check (
    pg_catalog.jsonb_typeof(request) = 'object'
    and pg_catalog.pg_column_size(request) <= 8192
  ),
  constraint live_workout_operation_receipts_result_check check (
    pg_catalog.jsonb_typeof(result) = 'object'
    and result->>'version' = '1'
    and pg_catalog.pg_column_size(result) <= 16384
  )
);

create index live_workout_operation_receipts_created_idx
  on gymapp_private.live_workout_operation_receipts (created_at, room_id);

comment on table gymapp_private.live_workout_rooms is
  'Immutable two-person live-workout plan and revisioned room lifecycle; accessible only through service-role gateway RPCs.';
comment on table gymapp_private.live_workout_members is
  'Exactly one owner role and at most one participant role per room; membership lifecycle is server-owned.';
comment on table gymapp_private.live_workout_progress is
  'Participant-owned committed-set projection. No RPC may mutate the other participant row.';
comment on table gymapp_private.live_workout_operation_receipts is
  'Durable exact-request receipts for idempotent invite, lifecycle, and progress commands.';

alter table gymapp_private.live_workout_rooms enable row level security;
alter table gymapp_private.live_workout_members enable row level security;
alter table gymapp_private.live_workout_progress enable row level security;
alter table gymapp_private.live_workout_operation_receipts enable row level security;

revoke all on table gymapp_private.live_workout_rooms
  from public, anon, authenticated, service_role;
revoke all on table gymapp_private.live_workout_members
  from public, anon, authenticated, service_role;
revoke all on table gymapp_private.live_workout_progress
  from public, anon, authenticated, service_role;
revoke all on table gymapp_private.live_workout_operation_receipts
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.validate_live_workout_plan(
  p_workout jsonb
)
returns jsonb
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $function$
declare
  canonical_workout jsonb;
  canonical_exercises jsonb := '[]'::jsonb;
  canonical_sets jsonb;
  exercise_row record;
  set_row record;
  live_plan jsonb;
begin
  canonical_workout := gymapp_private.validate_social_workout(p_workout);

  for exercise_row in
    select exercise.value, exercise.ordinality
    from pg_catalog.jsonb_array_elements(canonical_workout->'exercises')
      with ordinality as exercise(value, ordinality)
  loop
    canonical_sets := '[]'::jsonb;
    for set_row in
      select set_item.value, set_item.ordinality
      from pg_catalog.jsonb_array_elements(exercise_row.value->'sets')
        with ordinality as set_item(value, ordinality)
    loop
      canonical_sets := canonical_sets || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'setId', 's_' || pg_catalog.lpad(exercise_row.ordinality::text, 2, '0')
            || '_' || pg_catalog.lpad(set_row.ordinality::text, 2, '0'),
          'weight', set_row.value->'weight',
          'reps', set_row.value->'reps'
        )
      );
    end loop;

    canonical_exercises := canonical_exercises || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'exerciseId', 'e_' || pg_catalog.lpad(exercise_row.ordinality::text, 2, '0'),
        'name', exercise_row.value->'name',
        'sets', canonical_sets
      ) || case when exercise_row.value ? 'catalogKey'
        then pg_catalog.jsonb_build_object('catalogKey', exercise_row.value->'catalogKey')
        else '{}'::jsonb end
    );
  end loop;

  live_plan := pg_catalog.jsonb_build_object(
    'version', 1,
    'exercises', canonical_exercises
  );
  if pg_catalog.pg_column_size(live_plan) > 65536 then
    raise exception using errcode = '54000', message = 'Live workout plan is oversized.';
  end if;
  return live_plan;
end
$function$;

revoke all on function gymapp_private.validate_live_workout_plan(jsonb)
  from public, anon, authenticated, service_role;

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

create trigger live_workout_rooms_guard
before update on gymapp_private.live_workout_rooms
for each row execute function gymapp_private.guard_live_workout_room();

create or replace function gymapp_private.guard_live_workout_member()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_row record;
begin
  select room.id, room.owner_user_id, room.status
  into strict room_row
  from gymapp_private.live_workout_rooms as room
  where room.id = new.room_id;

  if tg_op = 'INSERT' then
    if room_row.status <> 'waiting'
       or (new.role = 'owner' and (
         new.user_id <> room_row.owner_user_id or new.state <> 'joined'
       ))
       or (new.role = 'participant' and (
         new.user_id = room_row.owner_user_id or new.state <> 'invited'
       )) then
      raise exception using errcode = '42501', message = 'Live workout initial membership is invalid.';
    end if;
    return new;
  end if;

  if new.room_id is distinct from old.room_id
     or new.user_id is distinct from old.user_id
     or new.role is distinct from old.role
     or new.invited_at is distinct from old.invited_at then
    raise exception using errcode = '42501', message = 'Live workout membership identity is immutable.';
  end if;
  if new.revision <> old.revision + 1 then
    raise exception using errcode = '40001', message = 'Live workout membership revision must advance exactly once.';
  end if;
  if not (
    (old.state = 'invited' and new.state in ('joined', 'revoked'))
    or (old.state = 'joined' and new.state in ('finished', 'left', 'revoked'))
    or (old.state = 'finished' and new.state = 'left')
  ) then
    raise exception using errcode = '42501', message = 'Live workout membership transition is invalid.';
  end if;
  return new;
end
$function$;

revoke all on function gymapp_private.guard_live_workout_member()
  from public, anon, authenticated, service_role;

create trigger live_workout_members_guard
before insert or update on gymapp_private.live_workout_members
for each row execute function gymapp_private.guard_live_workout_member();

create or replace function gymapp_private.guard_live_workout_progress()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_status text;
  member_state text;
begin
  select room.status, member.state
  into strict room_status, member_state
  from gymapp_private.live_workout_rooms as room
  join gymapp_private.live_workout_members as member
    on member.room_id = room.id
   and member.user_id = new.user_id
  where room.id = new.room_id;

  if room_status <> 'active' or member_state <> 'joined' then
    raise exception using errcode = '42501', message = 'Live workout progress is not mutable.';
  end if;
  if tg_op = 'UPDATE' then
    if new.room_id is distinct from old.room_id
       or new.user_id is distinct from old.user_id then
      raise exception using errcode = '42501', message = 'Live workout progress owner is immutable.';
    end if;
    if new.revision <> old.revision + 1 then
      raise exception using errcode = '40001', message = 'Live workout progress revision must advance exactly once.';
    end if;
  end if;
  return new;
end
$function$;

revoke all on function gymapp_private.guard_live_workout_progress()
  from public, anon, authenticated, service_role;

create trigger live_workout_progress_guard
before insert or update on gymapp_private.live_workout_progress
for each row execute function gymapp_private.guard_live_workout_progress();

do $verify$
declare
  private_relation text;
begin
  foreach private_relation in array array[
    'live_workout_rooms',
    'live_workout_members',
    'live_workout_progress',
    'live_workout_operation_receipts'
  ] loop
    if pg_catalog.has_table_privilege('anon', 'gymapp_private.' || private_relation, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.' || private_relation, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.' || private_relation, 'INSERT')
       or pg_catalog.has_table_privilege('service_role', 'gymapp_private.' || private_relation, 'SELECT')
       or exists (
         select 1
         from pg_catalog.pg_policy as policy
         where policy.polrelid = ('gymapp_private.' || private_relation)::pg_catalog.regclass
       ) then
      raise exception 'Live-workout relation % is not private RPC-only storage.', private_relation;
    end if;
  end loop;

  if pg_catalog.to_regprocedure('gymapp_private.validate_live_workout_plan(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.live_workout_progress_is_valid(jsonb)') is null then
    raise exception 'Live-workout validators were not installed.';
  end if;
end
$verify$;

commit;
