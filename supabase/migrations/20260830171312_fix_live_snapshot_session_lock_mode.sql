begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- PostgREST runs STABLE RPCs in read-only transactions, but the session guard
-- takes FOR KEY SHARE to prevent concurrent session revocation. Preserve the
-- guard and snapshot body; allow the POST RPC to use a read-write transaction.
do $migration$
declare
  snapshot_function regprocedure := pg_catalog.to_regprocedure(
    'public.social_live_workout_snapshot(uuid,uuid,text)'
  );
  guard_function regprocedure := pg_catalog.to_regprocedure(
    'gymapp_private.live_gateway_require_session(uuid,uuid)'
  );
  original_contract jsonb;
  current_contract jsonb;
  guard_definition text;
begin
  if snapshot_function is null or guard_function is null then
    raise exception 'LIVE snapshot or session guard is missing.';
  end if;

  select pg_catalog.to_jsonb(p) - 'provolatile'
  into strict original_contract
  from pg_catalog.pg_proc as p where p.oid = snapshot_function;
  guard_definition := pg_catalog.pg_get_functiondef(guard_function);

  if not exists (
    select 1 from pg_catalog.pg_proc as p
    where p.oid = snapshot_function
      and p.provolatile in ('s', 'v')
      and p.prosecdef
      and pg_catalog.strpos(p.prosrc, 'live_gateway_require_session(') > 0
  ) or pg_catalog.strpos(pg_catalog.lower(guard_definition), 'for key share') = 0 then
    raise exception 'Unexpected LIVE snapshot or session guard contract.';
  end if;

  alter function public.social_live_workout_snapshot(uuid, uuid, text) volatile;

  select pg_catalog.to_jsonb(p) - 'provolatile'
  into strict current_contract
  from pg_catalog.pg_proc as p where p.oid = snapshot_function;
  if current_contract is distinct from original_contract
     or pg_catalog.pg_get_functiondef(guard_function) is distinct from guard_definition
     or (select p.provolatile from pg_catalog.pg_proc as p where p.oid = snapshot_function) <> 'v' then
    raise exception 'LIVE snapshot repair changed more than volatility.';
  end if;

  if pg_catalog.has_function_privilege('anon', snapshot_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', snapshot_function, 'EXECUTE')
     or not pg_catalog.has_function_privilege('service_role', snapshot_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', guard_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', guard_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', guard_function, 'EXECUTE') then
    raise exception 'LIVE snapshot or session guard privileges are not isolated.';
  end if;
end
$migration$;

notify pgrst, 'reload schema';

commit;
