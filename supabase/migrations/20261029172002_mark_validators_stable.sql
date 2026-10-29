begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regprocedure('gymapp_private.validate_user_state_global_budget(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.validate_social_workout(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.social_name_is_safe(text)') is null
     or pg_catalog.to_regprocedure('gymapp_private.validate_live_workout_plan(jsonb)') is null
     or pg_catalog.to_regprocedure('gymapp_private.live_workout_progress_is_valid(jsonb)') is null then
    raise exception 'GymApp validator volatility prerequisites are missing.';
  end if;
end
$preflight$;

-- These validators evaluate STABLE expressions, so IMMUTABLE overstated what
-- the planner may assume about them. None backs an index or a generated
-- column; live_workout_progress_payload_check keeps working with a STABLE
-- function. Bodies, ownership, and grants are unchanged.
alter function gymapp_private.validate_user_state_global_budget(jsonb) stable;
alter function gymapp_private.validate_social_workout(jsonb) stable;
alter function gymapp_private.social_name_is_safe(text) stable;
alter function gymapp_private.validate_live_workout_plan(jsonb) stable;
alter function gymapp_private.live_workout_progress_is_valid(jsonb) stable;

commit;
