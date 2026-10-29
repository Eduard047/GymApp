-- Runtime assertions against the deployed contract. No account or room writes.
begin;

select plan(13);

set local lock_timeout = '5s';
set local statement_timeout = '30s';

select is(
  (select p.provolatile::text from pg_catalog.pg_proc as p
   where p.oid = 'public.social_live_workout_snapshot(uuid,uuid,text)'::regprocedure),
  'v',
  'Snapshot RPC is volatile (no read-only POST transaction)'
);

select ok(
  pg_catalog.strpos(
    pg_catalog.lower(pg_catalog.pg_get_functiondef(
      'gymapp_private.live_gateway_require_session(uuid,uuid)'::regprocedure
    )),
    'for key share'
  ) > 0,
  'Session revocation lock (FOR KEY SHARE) is present in the session guard'
);

select ok(
  not exists (
    select 1 from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname in ('public', 'gymapp_private')
      and pg_catalog.strpos(p.prosrc, 'perform gymapp_private.live_gateway_require_session(') > 0
      and p.provolatile <> 'v'
  ),
  'No other locked-session RPC declares read-only volatility'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon', 'public.social_live_workout_snapshot(uuid,uuid,text)'::regprocedure, 'EXECUTE'),
  'Snapshot RPC is not executable by anon'
);
select ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'public.social_live_workout_snapshot(uuid,uuid,text)'::regprocedure, 'EXECUTE'),
  'Snapshot RPC is not executable by authenticated'
);
select ok(
  pg_catalog.has_function_privilege(
    'service_role', 'public.social_live_workout_snapshot(uuid,uuid,text)'::regprocedure, 'EXECUTE'),
  'Snapshot RPC is executable by service_role'
);
select ok(
  not pg_catalog.has_function_privilege(
    'anon', 'gymapp_private.live_gateway_require_session(uuid,uuid)'::regprocedure, 'EXECUTE'),
  'Session guard is not executable by anon'
);
select ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'gymapp_private.live_gateway_require_session(uuid,uuid)'::regprocedure, 'EXECUTE'),
  'Session guard is not executable by authenticated'
);
select ok(
  not pg_catalog.has_function_privilege(
    'service_role', 'gymapp_private.live_gateway_require_session(uuid,uuid)'::regprocedure, 'EXECUTE'),
  'Session guard is not executable by service_role'
);

set local role anon;
select throws_ok(
  $$select public.social_live_workout_snapshot(null, null, null)$$,
  '42501', null,
  'Anonymous caller cannot reach the snapshot'
);
reset role;

set local role authenticated;
select throws_ok(
  $$select public.social_live_workout_snapshot(null, null, null)$$,
  '42501', null,
  'Direct authenticated caller cannot reach the snapshot'
);
reset role;

set local role service_role;
select throws_ok(
  $$select public.social_live_workout_snapshot(null, null, null)$$,
  '42501', 'A current authenticated session is required.',
  'Missing session is rejected'
);
select throws_ok(
  $$select public.social_live_workout_snapshot(
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    'lr_00000000000000000000000000000000'
  )$$,
  '42501', 'A current authenticated session is required.',
  'Unknown session is rejected'
);
reset role;

select * from finish();
rollback;
