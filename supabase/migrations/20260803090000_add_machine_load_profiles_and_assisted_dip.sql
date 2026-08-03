-- Keep optional selectorized-machine load profiles bounded at the database
-- boundary. Existing states without loadProfile remain valid.
create or replace function gymapp_private.validate_exercise_load_profiles(p_state jsonb)
returns void
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $function$
declare
  catalog_field text;
  catalog_value jsonb;
  exercise_value jsonb;
  profile_value jsonb;
  weight_value jsonb;
  numeric_weight numeric;
  previous_weight numeric;
begin
  if pg_catalog.jsonb_typeof(p_state) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'GymApp cloud state must be a JSON object.';
  end if;

  foreach catalog_field in array array['exercises', 'exerciseCatalog'] loop
    if not (p_state ? catalog_field) or p_state->catalog_field = 'null'::jsonb then
      continue;
    end if;
    catalog_value := p_state->catalog_field;
    if pg_catalog.jsonb_typeof(catalog_value) is distinct from 'array'
       or pg_catalog.jsonb_array_length(catalog_value) > 2000 then
      raise exception using errcode = '22023', message = 'GymApp exercise catalog is invalid.';
    end if;

    for exercise_value in
      select value from pg_catalog.jsonb_array_elements(catalog_value)
    loop
      if pg_catalog.jsonb_typeof(exercise_value) is distinct from 'object' then
        raise exception using errcode = '22023', message = 'GymApp exercise catalog item is invalid.';
      end if;
      if not (exercise_value ? 'loadProfile') or exercise_value->'loadProfile' = 'null'::jsonb then
        continue;
      end if;

      profile_value := exercise_value->'loadProfile';
      if pg_catalog.jsonb_typeof(profile_value) is distinct from 'object'
         or pg_catalog.jsonb_typeof(profile_value->'direction') is distinct from 'string'
         or profile_value->>'direction' not in ('higherIsHarder', 'lowerIsHarder')
         or pg_catalog.jsonb_typeof(profile_value->'allowedWeightsKg') is distinct from 'array'
         or pg_catalog.jsonb_array_length(profile_value->'allowedWeightsKg') not between 1 and 128 then
        raise exception using errcode = '22023', message = 'GymApp exercise load profile is invalid.';
      end if;

      previous_weight := null;
      for weight_value in
        select value from pg_catalog.jsonb_array_elements(profile_value->'allowedWeightsKg')
      loop
        if pg_catalog.jsonb_typeof(weight_value) is distinct from 'number' then
          raise exception using errcode = '22023', message = 'GymApp exercise load profile weight must be numeric.';
        end if;
        numeric_weight := (weight_value #>> '{}')::numeric;
        if numeric_weight < 0 or numeric_weight > 1000000
           or (previous_weight is not null and numeric_weight <= previous_weight) then
          raise exception using errcode = '22023', message = 'GymApp exercise load profile weights must be sorted, unique, and in range.';
        end if;
        previous_weight := numeric_weight;
      end loop;
    end loop;
  end loop;
end
$function$;

revoke all on function gymapp_private.validate_exercise_load_profiles(jsonb)
  from public, anon, authenticated;

create or replace function gymapp_private.validate_user_state_load_profiles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT' or old.state is distinct from new.state then
    perform gymapp_private.validate_exercise_load_profiles(new.state);
  end if;
  return new;
end
$function$;

revoke all on function gymapp_private.validate_user_state_load_profiles()
  from public, anon, authenticated;

drop trigger if exists user_states_validate_load_profiles on public.user_states;
create trigger user_states_validate_load_profiles
before insert or update of state on public.user_states
for each row
execute function gymapp_private.validate_user_state_load_profiles();

insert into public.exercise_catalog (
  key,
  name_en,
  name_uk,
  muscle_ids,
  display_order
) values
  ('assisted_dip', 'Assisted Dip', 'Віджимання на брусах у гравітроні', array['triceps', 'chest', 'shoulders'], 53)
on conflict (key) do update set
  name_en = excluded.name_en,
  name_uk = excluded.name_uk,
  muscle_ids = excluded.muscle_ids,
  display_order = excluded.display_order;

comment on function gymapp_private.validate_exercise_load_profiles(jsonb) is
  'Validates bounded optional selectorized-machine weight profiles in GymApp cloud state.';
