begin;

set local lock_timeout = '5s';
set local statement_timeout = '15min';

-- Phase 2 derives bounded social summaries without rewriting raw user state.
-- The phase-1 trigger wins every concurrent race: an update either commits its
-- newer revision before this INSERT (which then does nothing) or overwrites the
-- older backfill row in the same state-update transaction afterward.
do $backfill$
declare
  state_row record;
  activity record;
begin
  for state_row in
    select state.user_id, state.state, state.updated_at
    from public.user_states as state
    join gymapp_private.user_state_progression as progression
      on progression.user_id = state.user_id
     and progression.source_revision = state.updated_at
    where not exists (
      select 1
      from gymapp_private.user_state_quarantine as quarantine
      where quarantine.user_id = state.user_id
    )
    order by state.user_id
  loop
    select * into strict activity
    from gymapp_private.social_activity_from_state(state_row.state);

    insert into gymapp_private.social_activity_projection (
      user_id, source_revision, recent_workouts, exercise_records, projected_at
    ) values (
      state_row.user_id, state_row.updated_at, activity.recent_workouts,
      activity.exercise_records, pg_catalog.clock_timestamp()
    )
    on conflict (user_id) do nothing;
  end loop;
end
$backfill$;

do $verify$
begin
  if exists (
    select 1
    from public.user_states as state
    join gymapp_private.user_state_progression as progression
      on progression.user_id = state.user_id
     and progression.source_revision = state.updated_at
    where not exists (
      select 1
      from gymapp_private.user_state_quarantine as quarantine
      where quarantine.user_id = state.user_id
    )
      and not exists (
        select 1
        from gymapp_private.social_activity_projection as activity
        where activity.user_id = state.user_id
          and activity.source_revision = state.updated_at
      )
  ) then
    raise exception 'A valid GymApp state is missing its revision-bound social projection.';
  end if;

  if exists (
    select 1
    from gymapp_private.social_activity_projection as activity
    join gymapp_private.user_state_quarantine as quarantine using (user_id)
  ) then
    raise exception 'A quarantined GymApp state retained a social activity projection.';
  end if;

  if exists (
    select 1
    from gymapp_private.social_activity_projection as activity
    where not exists (
      select 1
      from public.user_states as state
      where state.user_id = activity.user_id
        and state.updated_at = activity.source_revision
    )
  ) then
    raise exception 'A stale or orphaned GymApp social activity projection remains after backfill.';
  end if;
end
$verify$;

commit;
