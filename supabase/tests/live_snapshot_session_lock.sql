-- Runtime assertions against the deployed contract. No account or room writes.
begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $test$
declare
  snapshot_function regprocedure := 'public.social_live_workout_snapshot(uuid,uuid,text)'::regprocedure;
  guard_function regprocedure := 'gymapp_private.live_gateway_require_session(uuid,uuid)'::regprocedure;
begin
  if (select p.provolatile from pg_catalog.pg_proc as p where p.oid = snapshot_function) <> 'v' then
    raise exception 'Snapshot RPC would use a read-only POST transaction.';
  end if;
  if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(guard_function)), 'for key share') = 0 then
    raise exception 'Session revocation lock was removed.';
  end if;
  if exists (
    select 1 from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname in ('public', 'gymapp_private')
      and pg_catalog.strpos(p.prosrc, 'perform gymapp_private.live_gateway_require_session(') > 0
      and p.provolatile <> 'v'
  ) then
    raise exception 'Another locked-session RPC declares read-only volatility.';
  end if;
  if pg_catalog.has_function_privilege('anon', snapshot_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', snapshot_function, 'EXECUTE')
     or not pg_catalog.has_function_privilege('service_role', snapshot_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', guard_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', guard_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', guard_function, 'EXECUTE') then
    raise exception 'LIVE service boundary changed.';
  end if;
end
$test$;

set local role anon;
do $test$
begin
  begin
    perform public.social_live_workout_snapshot(null, null, null);
    raise exception 'Anonymous caller reached the snapshot.';
  exception when insufficient_privilege then null;
  end;
end
$test$;
reset role;

set local role authenticated;
do $test$
begin
  begin
    perform public.social_live_workout_snapshot(null, null, null);
    raise exception 'Direct authenticated caller reached the snapshot.';
  exception when insufficient_privilege then null;
  end;
end
$test$;
reset role;

set local role service_role;
do $test$
begin
  begin
    perform public.social_live_workout_snapshot(null, null, null);
    raise exception 'Missing session was accepted.';
  exception when insufficient_privilege then
    if sqlerrm <> 'A current authenticated session is required.' then raise; end if;
  end;
  begin
    perform public.social_live_workout_snapshot(
      pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
      'lr_00000000000000000000000000000000'
    );
    raise exception 'Unknown session was accepted.';
  exception when insufficient_privilege then
    if sqlerrm <> 'A current authenticated session is required.' then raise; end if;
  end;
end
$test$;
reset role;

select 'live_snapshot_session_lock: passed' as result;
rollback;
