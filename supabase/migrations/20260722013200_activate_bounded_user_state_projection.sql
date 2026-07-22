begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Profile-only writes must be constant-cost. Direct UPDATEs preserve the
-- already-derived values; INSERTs and the nested state refresh read only the
-- small private projection. No profile path reads or revalidates state JSON.
create or replace function gymapp_private.guard_profile_progression()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  trusted_refresh_owner text := nullif(
    pg_catalog.current_setting('gymapp.progression_refresh_user', true),
    ''
  );
  projection record;
begin
  if caller_user_id is not null and caller_user_id <> new.user_id then
    raise exception using errcode = '42501', message = 'A profile can only derive progression for its owner.';
  end if;
  if tg_op = 'UPDATE' and old.user_id is distinct from new.user_id then
    raise exception using errcode = '22023', message = 'A GymApp profile owner is immutable.';
  end if;

  if tg_op = 'UPDATE'
     and not (
       pg_catalog.pg_trigger_depth() > 1
       and trusted_refresh_owner = new.user_id::text
     ) then
    new.xp := old.xp;
    new.level := old.level;
    new.workouts := old.workouts;
  else
    select
      cached.xp, cached.level, cached.workouts
    into projection
    from gymapp_private.user_state_progression as cached
    where cached.user_id = new.user_id;

    if not found then
      new.xp := 0;
      new.level := 1;
      new.workouts := 0;
    else
      new.xp := projection.xp;
      new.level := projection.level;
      new.workouts := projection.workouts;
    end if;
  end if;

  new.progression_version := 1;
  new.updated_at := pg_catalog.clock_timestamp();
  return new;
end
$function$;

revoke all on function gymapp_private.guard_profile_progression()
  from public, anon, authenticated;

-- Recreate the canonical profile trigger so activation cannot inherit a
-- disabled trigger or a same-named trigger bound to a drifted function.
drop trigger if exists profiles_canonical_progression_guard on public.profiles;
create trigger profiles_canonical_progression_guard
before insert or update of user_id, xp, level, workouts
on public.profiles
for each row
execute function gymapp_private.guard_profile_progression();

do $verify$
declare
  guard_definition text := pg_catalog.pg_get_functiondef(
    'gymapp_private.guard_profile_progression()'::pg_catalog.regprocedure
  );
  profile_user_id_attnum smallint;
  profile_xp_attnum smallint;
  profile_level_attnum smallint;
  profile_workouts_attnum smallint;
  state_user_id_attnum smallint;
  state_attnum smallint;
begin
  select attribute.attnum::smallint
  into strict profile_user_id_attnum
  from pg_catalog.pg_attribute as attribute
  where attribute.attrelid = 'public.profiles'::pg_catalog.regclass
    and attribute.attname = 'user_id'
    and not attribute.attisdropped;

  select attribute.attnum::smallint
  into strict profile_xp_attnum
  from pg_catalog.pg_attribute as attribute
  where attribute.attrelid = 'public.profiles'::pg_catalog.regclass
    and attribute.attname = 'xp'
    and not attribute.attisdropped;

  select attribute.attnum::smallint
  into strict profile_level_attnum
  from pg_catalog.pg_attribute as attribute
  where attribute.attrelid = 'public.profiles'::pg_catalog.regclass
    and attribute.attname = 'level'
    and not attribute.attisdropped;

  select attribute.attnum::smallint
  into strict profile_workouts_attnum
  from pg_catalog.pg_attribute as attribute
  where attribute.attrelid = 'public.profiles'::pg_catalog.regclass
    and attribute.attname = 'workouts'
    and not attribute.attisdropped;

  select attribute.attnum::smallint
  into strict state_user_id_attnum
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

  if guard_definition like '%public.user_states%'
     or guard_definition like '%progression_from_state%'
     or guard_definition not like '%old.xp%'
     or guard_definition not like '%user_state_progression%'
     or has_function_privilege('anon', 'gymapp_private.guard_profile_progression()', 'EXECUTE')
     or has_function_privilege('authenticated', 'gymapp_private.guard_profile_progression()', 'EXECUTE')
     or 1 <> (
       select pg_catalog.count(*)
       from pg_catalog.pg_trigger as trigger_row
       where trigger_row.tgrelid = 'public.profiles'::pg_catalog.regclass
         and trigger_row.tgname = 'profiles_canonical_progression_guard'
         and not trigger_row.tgisinternal
         and trigger_row.tgenabled = 'O'
         and trigger_row.tgfoid = 'gymapp_private.guard_profile_progression()'::pg_catalog.regprocedure
         and trigger_row.tgtype = 23
         and trigger_row.tgattr::text =
           profile_user_id_attnum::text || ' '
           || profile_xp_attnum::text || ' '
           || profile_level_attnum::text || ' '
           || profile_workouts_attnum::text
         and trigger_row.tgqual is null
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
         and trigger_row.tgattr::text = state_user_id_attnum::text || ' ' || state_attnum::text
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
         and trigger_row.tgattr::text = state_user_id_attnum::text || ' ' || state_attnum::text
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
    raise exception 'Constant-cost GymApp profile guard verification failed.';
  end if;
end
$verify$;

commit;
