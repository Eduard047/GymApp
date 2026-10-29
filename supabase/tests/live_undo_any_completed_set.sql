-- Structural assertions against the deployed contract. No account or room writes.
-- Behavioural fixtures (older-set undo, denied paths) need a local database with
-- seeded rooms/sessions and are not covered here.
begin;

select plan(7);

set local lock_timeout = '5s';
set local statement_timeout = '30s';

select ok(
  pg_catalog.strpos(
    pg_catalog.pg_get_functiondef(
      'public.social_apply_live_workout_operation(uuid,uuid,text,uuid,bigint,jsonb)'::regprocedure
    ),
    'Live workout set is not completed.'
  ) > 0,
  'Undo rule requires the own set to be completed'
);

select ok(
  pg_catalog.strpos(
    pg_catalog.pg_get_functiondef(
      'public.social_apply_live_workout_operation(uuid,uuid,text,uuid,bigint,jsonb)'::regprocedure
    ),
    'Only the latest own set can be undone'
  ) = 0,
  'Undo rule no longer restricts undo to the latest own set'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_proc as p
    where p.oid = 'public.social_apply_live_workout_operation(uuid,uuid,text,uuid,bigint,jsonb)'::regprocedure
      and p.prosecdef
      and p.provolatile = 'v'
      and p.proconfig @> array['search_path=""']
  ),
  'Apply RPC keeps security-definer, volatile and empty search_path settings'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.social_apply_live_workout_operation(uuid,uuid,text,uuid,bigint,jsonb)'::regprocedure,
    'EXECUTE'
  ),
  'Apply RPC is not executable by anon'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.social_apply_live_workout_operation(uuid,uuid,text,uuid,bigint,jsonb)'::regprocedure,
    'EXECUTE'
  ),
  'Apply RPC is not executable by authenticated'
);

select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.social_apply_live_workout_operation(uuid,uuid,text,uuid,bigint,jsonb)'::regprocedure,
    'EXECUTE'
  ),
  'Apply RPC is executable by service_role (service-gateway-only)'
);

set local role authenticated;
select throws_ok(
  $$select public.social_apply_live_workout_operation(null, null, null, null, null, null)$$,
  '42501', null,
  'Direct authenticated caller cannot reach the apply RPC'
);
reset role;

select * from finish();
rollback;
