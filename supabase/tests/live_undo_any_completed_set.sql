-- Structural assertions against the deployed contract. No account or room writes.
-- Behavioural fixtures (older-set undo, denied paths) need a local database with
-- seeded rooms/sessions and are not covered here.
begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $test$
declare
  apply_function regprocedure :=
    'public.social_apply_live_workout_operation(uuid,uuid,text,uuid,bigint,jsonb)'::regprocedure;
  definition text := pg_catalog.pg_get_functiondef(apply_function);
begin
  if pg_catalog.strpos(definition, 'Live workout set is not completed.') = 0
     or pg_catalog.strpos(definition, 'Only the latest own set can be undone') > 0 then
    raise exception 'Undo rule is not the any-own-completed-set rule.';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc as p
    where p.oid = apply_function
      and p.prosecdef
      and p.provolatile = 'v'
      and p.proconfig @> array['search_path=""']
  ) then
    raise exception 'Apply RPC lost security-definer, volatility or search_path settings.';
  end if;
  if pg_catalog.has_function_privilege('anon', apply_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', apply_function, 'EXECUTE')
     or not pg_catalog.has_function_privilege('service_role', apply_function, 'EXECUTE') then
    raise exception 'Apply RPC is not exactly service-gateway-only.';
  end if;
end
$test$;

set local role authenticated;
do $test$
begin
  begin
    perform public.social_apply_live_workout_operation(
      null, null, null, null, null, null
    );
    raise exception 'Direct authenticated caller reached the apply RPC.';
  exception when insufficient_privilege then null;
  end;
end
$test$;
reset role;

select 'live_undo_any_completed_set: passed' as result;
rollback;
