begin;

set local lock_timeout = '5s';
set local statement_timeout = '15min';

-- Phase two is online and lossless: it never rewrites raw user_states. Validate
-- each legacy row independently so one state accepted by the historical 64 KiB
-- string contract cannot abort the whole deployment under the new conservative
-- 8,192-scalar ceiling. Only documented validation/range failures are privately
-- quarantined; unexpected database/runtime failures still abort the migration.
--
-- A concurrent valid state write either installs a newer projection first or
-- overwrites this older one afterward. On the failure path, lock and re-check
-- only that legacy row before quarantining it, so a stale snapshot can never
-- quarantine or delete the projection of a concurrently repaired state.
do $backfill$
declare
  state_row record;
  current_state jsonb;
  current_revision timestamptz;
  progression record;
  validation_error text;
begin
  for state_row in
    select state.user_id, state.state, state.updated_at
    from public.user_states as state
    where not exists (
      select 1
      from gymapp_private.user_state_quarantine as quarantine
      where quarantine.user_id = state.user_id
    )
    order by state.user_id
  loop
    validation_error := null;

    if pg_catalog.jsonb_typeof(state_row.state->'owner') = 'object'
       and pg_catalog.jsonb_typeof(state_row.state->'owner'->'userId') = 'string'
       and pg_catalog.btrim(state_row.state->'owner'->>'userId') <> ''
       and pg_catalog.lower(pg_catalog.btrim(state_row.state->'owner'->>'userId')) <> state_row.user_id::text then
      validation_error := 'Stored GymApp state owner does not match its database row.';
    else
      begin
        select * into strict progression
        from gymapp_private.progression_from_state(state_row.state);
      exception
        when sqlstate '22023' or sqlstate '22003' or sqlstate '54000' then
          validation_error := pg_catalog.left(
            coalesce(sqlerrm, 'Stored GymApp state failed validation.'),
            200
          );
      end;
    end if;

    if validation_error is null then
      insert into gymapp_private.user_state_progression (
        user_id, source_revision, xp, level, workouts,
        progression_version, projected_at
      ) values (
        state_row.user_id, state_row.updated_at, progression.xp,
        progression.level, progression.workouts, 1,
        pg_catalog.clock_timestamp()
      )
      on conflict (user_id) do nothing;
    else
      current_state := null;
      current_revision := null;

      select state.state, state.updated_at
      into current_state, current_revision
      from public.user_states as state
      where state.user_id = state_row.user_id
      for update;

      if found
         and current_revision is not distinct from state_row.updated_at
         and current_state is not distinct from state_row.state then
        insert into gymapp_private.user_state_quarantine (
          user_id, validation_error, quarantined_at
        ) values (
          state_row.user_id,
          pg_catalog.left(validation_error, 200),
          pg_catalog.clock_timestamp()
        )
        on conflict (user_id) do update
        set validation_error = excluded.validation_error,
            quarantined_at = excluded.quarantined_at;

        delete from gymapp_private.user_state_progression as projection
        where projection.user_id = state_row.user_id;
      end if;
    end if;
  end loop;
end
$backfill$;

-- The pre-activation guard recognizes quarantine and therefore canonicalizes
-- newly quarantined legacy profiles without traversing their state. A later
-- valid state write atomically removes quarantine and restores its projection.
update public.profiles as profile
set xp = 0,
    level = 1,
    workouts = 0,
    progression_version = 1,
    updated_at = pg_catalog.clock_timestamp()
where exists (
  select 1
  from gymapp_private.user_state_quarantine as quarantine
  where quarantine.user_id = profile.user_id
)
  and (
    profile.xp <> 0
    or profile.level <> 1
    or profile.workouts <> 0
    or profile.progression_version <> 1
  );

do $verify$
begin
  if exists (
    select 1
    from public.user_states as state
    where not exists (
      select 1
      from gymapp_private.user_state_quarantine as quarantine
      where quarantine.user_id = state.user_id
    )
      and not exists (
        select 1
        from gymapp_private.user_state_progression as projection
        where projection.user_id = state.user_id
          and projection.source_revision = state.updated_at
      )
  ) then
    raise exception 'A valid GymApp state is missing its revision-bound projection.';
  end if;

  if exists (
    select 1
    from gymapp_private.user_state_progression as projection
    join gymapp_private.user_state_quarantine as quarantine using (user_id)
  ) then
    raise exception 'A quarantined GymApp state still has a public progression projection.';
  end if;

  if exists (
    select 1
    from gymapp_private.user_state_progression as projection
    where not exists (
      select 1
      from public.user_states as state
      where state.user_id = projection.user_id
    )
  ) then
    raise exception 'An orphaned GymApp state projection remains after backfill.';
  end if;

  if exists (
    select 1
    from public.profiles as profile
    join gymapp_private.user_state_quarantine as quarantine using (user_id)
    where profile.xp <> 0
       or profile.level <> 1
       or profile.workouts <> 0
       or profile.progression_version <> 1
  ) then
    raise exception 'A quarantined GymApp profile retained public progression.';
  end if;
end
$verify$;

commit;
