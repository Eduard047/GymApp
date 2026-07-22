begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- This first phase is deliberately metadata-only for the public tables.  It
-- installs a private, server-owned progression projection and starts keeping it
-- current before the online backfill in the next migration.  No user_states row
-- is rewritten here.
do $preflight$
begin
  -- The pre-canonical numeric guard below uses the SQL/JSON .string() item
  -- method added in PostgreSQL 17. Production and staging run PG17; make that
  -- deployment contract explicit so an older rebuild fails clearly before any
  -- object is changed.
  if pg_catalog.current_setting('server_version_num')::integer < 170000 then
    raise exception 'Bounded GymApp state validation requires PostgreSQL 17 or newer.';
  end if;

  if pg_catalog.to_regclass('public.user_states') is null
     or pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regclass('gymapp_private.user_state_quarantine') is null
     or pg_catalog.to_regprocedure('gymapp_private.validate_user_state(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.progression_from_state(jsonb)') is null then
    raise exception 'Cannot bound GymApp state validation: canonical state objects are missing.';
  end if;
end
$preflight$;

create table if not exists gymapp_private.user_state_progression (
  user_id uuid primary key,
  source_revision timestamptz not null,
  xp integer not null check (xp >= 0),
  level integer not null check (level >= 1),
  workouts integer not null check (workouts >= 0),
  progression_version integer not null default 1
    check (progression_version = 1),
  projected_at timestamptz not null default pg_catalog.clock_timestamp()
);

comment on table gymapp_private.user_state_progression is
  'Private server-owned projection of a validated user_states revision. It prevents profile-only writes from re-reading untrusted JSON.';
revoke all on table gymapp_private.user_state_progression
  from public, anon, authenticated;

-- Attach and validate the FK while the projection is still empty.  Adding the
-- constraint after a bulk insert would take SHARE ROW EXCLUSIVE on both tables
-- for the rest of the backfill transaction and can deadlock with a concurrent
-- owner update/delete.  NOT VALID keeps the DDL path online if this migration is
-- retried against an already-created private table; validation is immediate for
-- the normal empty-table path and future inserts are always FK-checked.
do $foreign_key$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'gymapp_private.user_state_progression'::pg_catalog.regclass
      and conname = 'user_state_progression_user_id_fkey'
  ) then
    alter table gymapp_private.user_state_progression
      add constraint user_state_progression_user_id_fkey
      foreign key (user_id)
      references public.user_states(user_id)
      on delete cascade
      not valid;
  end if;
end
$foreign_key$;

alter table gymapp_private.user_state_progression
  validate constraint user_state_progression_user_id_fkey;

-- The old global validator expanded every JSON value into a recursive SQL
-- worktable before enforcing its budget. This replacement preserves the total-
-- size, node, depth, and forbidden-key controls and uses a stricter conservative
-- key/string ceiling with native JSON/text primitives. In particular, the
-- structural budget is checked without any set-returning JSON function that can
-- materialize attacker-selected rows.
create or replace function gymapp_private.validate_user_state_global_budget(p_state jsonb)
returns void
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $function$
declare
  canonical_state text;
  structural_state text;
  container_count bigint;
  comma_count bigint;
begin
  if pg_catalog.jsonb_typeof(p_state) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'GymApp cloud state must be a JSON object.';
  end if;

  -- This cheap varlena check rejects extreme direct-SQL/Data-API inputs before
  -- canonical text conversion. The canonical 8 MiB contract remains authoritative
  -- because pg_column_size on a stored column reflects TOAST compression.
  -- PostgREST has already parsed an HTTP body into jsonb before this function is
  -- entered; gateway/Edge body admission remains a separate deployment control.
  if pg_catalog.pg_column_size(p_state) > 33554432 then
    raise exception using errcode = '54000', message = 'GymApp cloud state storage exceeds 32 MiB.';
  end if;

  -- jsonb stores numbers in PostgreSQL numeric form. Compact wire spellings
  -- such as 1e131071, -1e131071, and 0e-10000 can otherwise expand to very
  -- large canonical strings before the 8 MiB check below.  Bound each native
  -- numeric rendering first.  1,024 characters is far above every documented
  -- GymApp numeric field while keeping a forward-compatible safety margin.
  if pg_catalog.jsonb_path_exists(
    p_state,
    'strict $.** ? (@.type() == "number" && @.string() like_regex "^(.{255}){4}.{5}" flag "s")'::pg_catalog.jsonpath
  ) then
    raise exception using errcode = '54000', message = 'GymApp cloud state contains an oversized JSON number.';
  end if;

  canonical_state := p_state::text;
  if pg_catalog.octet_length(pg_catalog.convert_to(canonical_state, 'UTF8')) > 8388608 then
    raise exception using errcode = '54000', message = 'GymApp cloud state exceeds 8 MiB.';
  end if;

  -- For valid JSON, node_count <= 2 * container_count + comma_count. This scan
  -- runs in native string code and does not emit one SQL row per JSON value.
  -- Strip JSON string tokens first so punctuation in a legitimate note/key does
  -- not consume the structural budget.
  structural_state := pg_catalog.regexp_replace(
    canonical_state,
    E'"([^"\\\\]|\\\\.)*"',
    '""',
    'g'
  );
  container_count :=
    pg_catalog.char_length(structural_state)
    - pg_catalog.char_length(pg_catalog.translate(structural_state, '[{', ''));
  comma_count :=
    pg_catalog.char_length(structural_state)
    - pg_catalog.char_length(pg_catalog.replace(structural_state, ',', ''));
  if (2 * container_count) + comma_count > 1000000 then
    raise exception using errcode = '54000', message = 'GymApp cloud state contains too many JSON values.';
  end if;

  if pg_catalog.jsonb_path_exists(p_state, 'strict $.**{9}'::pg_catalog.jsonpath) then
    raise exception using errcode = '54000', message = 'GymApp cloud state exceeds the JSON nesting limit.';
  end if;

  -- Inspect actual object keys, never serialized value text. jsonb has already
  -- normalized Unicode escapes, so alternate spellings cannot bypass the exact
  -- comparison and a legitimate string containing `"constructor":` is harmless.
  if pg_catalog.jsonb_path_exists(
    p_state,
    'strict $.** ? (@.type() == "object").keyvalue() ? (@.key == "__proto__" || @.key == "prototype" || @.key == "constructor")'::pg_catalog.jsonpath
  ) then
    raise exception using errcode = '22023', message = 'GymApp cloud state contains a forbidden object key.';
  end if;

  -- The documented schema is tighter (notes are <= 4,000 characters / 16 KiB).
  -- A conservative 8,192-scalar global ceiling guarantees <= 32 KiB for every
  -- UTF-8 key/value and lets the native JSON path engine short-circuit without
  -- returning one SQL row per string. Schema growth requiring larger text must
  -- use a new reviewed schema version instead of an unbounded extension field.
  if pg_catalog.jsonb_path_exists(
    p_state,
    'strict $.** ? (@.type() == "string" && @ like_regex "^(.{255}){32}.{33}" flag "s")'::pg_catalog.jsonpath
  ) or pg_catalog.jsonb_path_exists(
    p_state,
    'strict $.** ? (@.type() == "object").keyvalue().key ? (@ like_regex "^(.{255}){32}.{33}" flag "s")'::pg_catalog.jsonpath
  ) then
    raise exception using errcode = '54000', message = 'GymApp cloud state contains an oversized JSON string.';
  end if;
end
$function$;

revoke all on function gymapp_private.validate_user_state_global_budget(jsonb)
  from public, anon, authenticated;

-- Replace only the unbounded recursive-walk section of the already-deployed
-- canonical validator. The exact-source assertion makes migration drift fail
-- closed instead of silently leaving the expensive implementation active.
do $replace_recursive_walk$
declare
  validator_body text;
  hardened_body text;
  old_guard constant text := $old_guard$
  if p_state is null or pg_catalog.jsonb_typeof(p_state) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'GymApp cloud state must be a JSON object.';
  end if;
  if pg_catalog.octet_length(pg_catalog.convert_to(p_state::text, 'UTF8')) > 8388608 then
    raise exception using errcode = '54000', message = 'GymApp cloud state exceeds 8 MiB.';
  end if;

  with recursive json_walk(value, depth, object_key) as (
    select p_state, 0, null::text
    union all
    select child.value, parent.depth + 1, child.object_key
    from json_walk as parent
    cross join lateral (
      select object_item.value, object_item.key
      from pg_catalog.jsonb_each(
        case when pg_catalog.jsonb_typeof(parent.value) = 'object'
          then parent.value else '{}'::jsonb end
      ) as object_item(key, value)
      union all
      select array_item.value, null::text
      from pg_catalog.jsonb_array_elements(
        case when pg_catalog.jsonb_typeof(parent.value) = 'array'
          then parent.value else '[]'::jsonb end
      ) as array_item(value)
    ) as child(value, object_key)
    where parent.depth < 9
  )
  select
    pg_catalog.count(*)::bigint,
    coalesce(pg_catalog.max(depth), 0)::integer,
    coalesce(pg_catalog.bool_or(object_key in ('__proto__', 'prototype', 'constructor')), false),
    coalesce(pg_catalog.bool_or(
      (object_key is not null and
       pg_catalog.octet_length(pg_catalog.convert_to(object_key, 'UTF8')) > 65536)
      or (pg_catalog.jsonb_typeof(value) = 'string' and
          pg_catalog.octet_length(pg_catalog.convert_to(value #>> '{}', 'UTF8')) > 65536)
    ), false)
  into json_node_count, json_max_depth, json_has_forbidden_key, json_has_oversized_string
  from json_walk;

  if json_node_count > 1000000 then
    raise exception using errcode = '54000', message = 'GymApp cloud state contains too many JSON values.';
  end if;
  if json_max_depth > 8 then
    raise exception using errcode = '54000', message = 'GymApp cloud state exceeds the JSON nesting limit.';
  end if;
  if json_has_forbidden_key then
    raise exception using errcode = '22023', message = 'GymApp cloud state contains a forbidden object key.';
  end if;
  if json_has_oversized_string then
    raise exception using errcode = '54000', message = 'GymApp cloud state contains an oversized JSON string.';
  end if;
$old_guard$;
  new_guard constant text := $new_guard$
  if p_state is null then
    raise exception using errcode = '22023', message = 'GymApp cloud state must be a JSON object.';
  end if;
  perform gymapp_private.validate_user_state_global_budget(p_state);
$new_guard$;
begin
  select procedure.prosrc
  into validator_body
  from pg_catalog.pg_proc as procedure
  where procedure.oid = 'gymapp_private.validate_user_state(jsonb)'::pg_catalog.regprocedure;

  if pg_catalog.strpos(validator_body, old_guard) = 0 then
    raise exception 'Canonical GymApp validator changed; refusing an unsafe partial replacement.';
  end if;
  hardened_body := pg_catalog.replace(validator_body, old_guard, new_guard);
  if pg_catalog.strpos(hardened_body, 'with recursive json_walk') > 0 then
    raise exception 'Recursive GymApp JSON walk remains after replacement.';
  end if;

  execute pg_catalog.format(
    'create or replace function gymapp_private.validate_user_state(p_state jsonb) returns void language plpgsql stable security invoker set search_path = '''' as %L',
    hardened_body
  );
end
$replace_recursive_walk$;

revoke all on function gymapp_private.validate_user_state(jsonb)
  from public, anon, authenticated;

-- Reject storage/canonicalization bombs before PostgreSQL writes the heap/TOAST
-- tuple. The AFTER projection trigger still runs the complete schema validator
-- exactly once before the transaction can commit. UPDATEs which merely name a
-- column without changing it retain compatibility with already-quarantined
-- legacy rows and are handled by the constant-cost revision trigger below.
create or replace function gymapp_private.validate_user_state_storage_budget()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'UPDATE' and old.user_id is distinct from new.user_id then
    raise exception using errcode = '22023', message = 'GymApp cloud state owner is immutable.';
  end if;

  if tg_op = 'INSERT' or old.state is distinct from new.state then
    perform gymapp_private.validate_user_state_global_budget(new.state);
  end if;
  return new;
end
$function$;

revoke all on function gymapp_private.validate_user_state_storage_budget()
  from public, anon, authenticated;

drop trigger if exists user_states_validate_storage_budget on public.user_states;
create trigger user_states_validate_storage_budget
before insert or update of user_id, state
on public.user_states
for each row
execute function gymapp_private.validate_user_state_storage_budget();

-- From this commit forward, every accepted state revision receives a projection
-- in the same transaction. The following migration can therefore backfill old
-- rows online with ON CONFLICT DO NOTHING and cannot overwrite a newer revision.
create or replace function gymapp_private.refresh_profile_progression()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  owner_user_id uuid;
  progression record;
  previous_refresh_owner text := nullif(
    pg_catalog.current_setting('gymapp.progression_refresh_user', true),
    ''
  );
begin
  owner_user_id := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
  if tg_op = 'UPDATE' and old.user_id is distinct from new.user_id then
    raise exception using errcode = '22023', message = 'GymApp cloud state owner is immutable.';
  end if;
  if caller_user_id is not null and caller_user_id <> owner_user_id then
    raise exception using errcode = '42501', message = 'Cloud state can only refresh its owner profile.';
  end if;

  -- UPDATE OF is syntactic: it also fires when a client names state/user_id but
  -- leaves both values unchanged. The revision-only trigger updates the cache
  -- timestamp for that case, so do not revalidate a legacy payload here.
  if tg_op = 'UPDATE'
     and old.user_id is not distinct from new.user_id
     and old.state is not distinct from new.state then
    return new;
  end if;

  if tg_op = 'DELETE' then
    delete from gymapp_private.user_state_progression as projection
    where projection.user_id = owner_user_id;
    perform pg_catalog.set_config('gymapp.progression_refresh_user', owner_user_id::text, true);
    update public.profiles
    set xp = 0, level = 1, workouts = 0, progression_version = 1,
        updated_at = pg_catalog.clock_timestamp()
    where user_id = owner_user_id;
    perform pg_catalog.set_config(
      'gymapp.progression_refresh_user',
      coalesce(previous_refresh_owner, ''),
      true
    );
    return old;
  end if;

  if pg_catalog.jsonb_typeof(new.state->'owner') = 'object'
     and pg_catalog.jsonb_typeof(new.state->'owner'->'userId') = 'string'
     and pg_catalog.btrim(new.state->'owner'->>'userId') <> ''
     and pg_catalog.lower(pg_catalog.btrim(new.state->'owner'->>'userId')) <> new.user_id::text then
    raise exception using errcode = '42501', message = 'GymApp cloud state owner does not match its authenticated row.';
  end if;

  select * into strict progression
  from gymapp_private.progression_from_state(new.state);

  insert into gymapp_private.user_state_progression (
    user_id, source_revision, xp, level, workouts, progression_version, projected_at
  ) values (
    new.user_id, new.updated_at, progression.xp, progression.level,
    progression.workouts, 1, pg_catalog.clock_timestamp()
  )
  on conflict (user_id) do update
  set source_revision = excluded.source_revision,
      xp = excluded.xp,
      level = excluded.level,
      workouts = excluded.workouts,
      progression_version = 1,
      projected_at = excluded.projected_at;

  delete from gymapp_private.user_state_quarantine as quarantine
  where quarantine.user_id = new.user_id;

  perform pg_catalog.set_config('gymapp.progression_refresh_user', new.user_id::text, true);
  insert into public.profiles (
    user_id, display_name, xp, level, workouts, progression_version, updated_at
  ) values (
    new.user_id, 'GymApp user', progression.xp, progression.level,
    progression.workouts, 1, pg_catalog.clock_timestamp()
  )
  on conflict (user_id) do update
  set xp = excluded.xp,
      level = excluded.level,
      workouts = excluded.workouts,
      progression_version = 1,
      updated_at = excluded.updated_at;
  perform pg_catalog.set_config(
    'gymapp.progression_refresh_user',
    coalesce(previous_refresh_owner, ''),
    true
  );
  return new;
exception
  when others then
    perform pg_catalog.set_config(
      'gymapp.progression_refresh_user',
      coalesce(previous_refresh_owner, ''),
      true
    );
    raise;
end
$function$;

revoke all on function gymapp_private.refresh_profile_progression()
  from public, anon, authenticated;

-- Recreate the canonical trigger instead of assuming an earlier migration left
-- it present, enabled, and bound to the expected function.
drop trigger if exists user_states_refresh_profile_progression on public.user_states;
create trigger user_states_refresh_profile_progression
after insert or update of user_id, state or delete
on public.user_states
for each row
execute function gymapp_private.refresh_profile_progression();

-- set_user_state_server_revision advances updated_at for every UPDATE, including
-- a PATCH that does not name state. Keep the cache's source revision aligned in
-- constant time without revalidating unchanged JSON; state-changing writes are
-- handled by refresh_profile_progression above.
create or replace function gymapp_private.refresh_projection_revision_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update gymapp_private.user_state_progression as projection
  set source_revision = new.updated_at
  where projection.user_id = new.user_id;
  return new;
end
$function$;

revoke all on function gymapp_private.refresh_projection_revision_only()
  from public, anon, authenticated;

drop trigger if exists user_states_projection_revision_only on public.user_states;
create trigger user_states_projection_revision_only
after update on public.user_states
for each row
when (
  old.state is not distinct from new.state
  and old.updated_at is distinct from new.updated_at
)
execute function gymapp_private.refresh_projection_revision_only();

do $verify$
declare
  validator_definition text := pg_catalog.pg_get_functiondef(
    'gymapp_private.validate_user_state(jsonb)'::pg_catalog.regprocedure
  );
  user_id_attnum smallint;
  state_attnum smallint;
begin
  select attribute.attnum::smallint
  into strict user_id_attnum
  from pg_catalog.pg_attribute as attribute
  where attribute.attrelid = 'public.user_states'::pg_catalog.regclass
    and attribute.attname = 'user_id'
    and not attribute.attisdropped;

  select attribute.attnum::smallint
  into strict state_attnum
  from pg_catalog.pg_attribute as attribute
  where attribute.attrelid = 'public.user_states'::pg_catalog.regclass
    and attribute.attname = 'state'
    and not attribute.attisdropped;

  if validator_definition not like '%validate_user_state_global_budget%'
     or validator_definition like '%with recursive json_walk%'
     or has_function_privilege('anon', 'gymapp_private.validate_user_state_global_budget(jsonb)', 'EXECUTE')
     or has_function_privilege('authenticated', 'gymapp_private.validate_user_state_global_budget(jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'gymapp_private.refresh_projection_revision_only()', 'EXECUTE')
     or has_function_privilege('authenticated', 'gymapp_private.refresh_projection_revision_only()', 'EXECUTE')
     or has_table_privilege('anon', 'gymapp_private.user_state_progression', 'SELECT')
     or has_table_privilege('authenticated', 'gymapp_private.user_state_progression', 'SELECT')
     or not exists (
       select 1
       from pg_catalog.pg_constraint as constraint_row
       where constraint_row.conrelid = 'gymapp_private.user_state_progression'::pg_catalog.regclass
         and constraint_row.confrelid = 'public.user_states'::pg_catalog.regclass
         and constraint_row.conname = 'user_state_progression_user_id_fkey'
         and constraint_row.contype = 'f'
         and constraint_row.convalidated
     )
     or 1 <> (
       select pg_catalog.count(*)
       from pg_catalog.pg_trigger as trigger_row
       where trigger_row.tgrelid = 'public.user_states'::pg_catalog.regclass
         and trigger_row.tgname = 'user_states_validate_storage_budget'
         and not trigger_row.tgisinternal
         and trigger_row.tgenabled = 'O'
         and trigger_row.tgfoid = 'gymapp_private.validate_user_state_storage_budget()'::pg_catalog.regprocedure
         and trigger_row.tgtype = 23
         and trigger_row.tgattr::text = user_id_attnum::text || ' ' || state_attnum::text
         and trigger_row.tgqual is null
     )
     or 1 <> (
       select pg_catalog.count(*)
       from pg_catalog.pg_trigger as trigger_row
       where trigger_row.tgrelid = 'public.user_states'::pg_catalog.regclass
         and trigger_row.tgname = 'user_states_refresh_profile_progression'
         and not trigger_row.tgisinternal
         and trigger_row.tgenabled = 'O'
         and trigger_row.tgfoid = 'gymapp_private.refresh_profile_progression()'::pg_catalog.regprocedure
         and trigger_row.tgtype = 29
         and trigger_row.tgattr::text = user_id_attnum::text || ' ' || state_attnum::text
         and trigger_row.tgqual is null
     )
     or 1 <> (
       select pg_catalog.count(*)
       from pg_catalog.pg_trigger as trigger_row
       where trigger_row.tgrelid = 'public.user_states'::pg_catalog.regclass
         and trigger_row.tgname = 'user_states_projection_revision_only'
         and not trigger_row.tgisinternal
         and trigger_row.tgenabled = 'O'
         and trigger_row.tgfoid = 'gymapp_private.refresh_projection_revision_only()'::pg_catalog.regprocedure
         and trigger_row.tgtype = 17
         and trigger_row.tgattr::text = ''
         and trigger_row.tgqual is not null
     ) then
    raise exception 'Bounded GymApp state validation verification failed.';
  end if;
end
$verify$;

commit;
