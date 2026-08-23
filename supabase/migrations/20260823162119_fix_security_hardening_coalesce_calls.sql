begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $migration$
declare
  target_function regprocedure;
  function_definition text;
begin
  target_function := pg_catalog.to_regprocedure(
    'public.social_sync_workout_durations(jsonb)'
  );
  if target_function is null then
    raise exception 'GymApp workout-duration synchronization function is missing.';
  end if;
  select pg_catalog.pg_get_functiondef(target_function)
  into strict function_definition;
  if pg_catalog.regexp_count(
    function_definition,
    'pg_catalog[.]coalesce'
  ) <> 1 then
    raise exception 'Unexpected workout-duration synchronization definition.';
  end if;
  execute pg_catalog.replace(
    function_definition,
    'pg_catalog.coalesce',
    'coalesce'
  );

  target_function := pg_catalog.to_regprocedure(
    'gymapp_private.edge_preauth_debit(text,text)'
  );
  if target_function is null then
    raise exception 'GymApp Edge pre-authentication worker is missing.';
  end if;
  select pg_catalog.pg_get_functiondef(target_function)
  into strict function_definition;
  if pg_catalog.regexp_count(
    function_definition,
    'pg_catalog[.]coalesce'
  ) <> 3 then
    raise exception 'Unexpected Edge pre-authentication worker definition.';
  end if;
  execute pg_catalog.replace(
    function_definition,
    'pg_catalog.coalesce',
    'coalesce'
  );
end
$migration$;

notify pgrst, 'reload schema';

commit;
