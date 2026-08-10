begin;

select plan(16);

select has_function(
  'public',
  'garmin_fetch_pending_plan_core',
  array['text'],
  'Garmin fetch core keeps its existing signature'
);
select has_function(
  'public',
  'garmin_ack_plan_core',
  array['text', 'uuid', 'bigint'],
  'Garmin acknowledgement core keeps its existing signature'
);
select ok(
  (select procedure.prosecdef
   from pg_catalog.pg_proc as procedure
   where procedure.oid =
     'public.garmin_fetch_pending_plan_core(text)'::regprocedure),
  'Garmin fetch core remains security definer'
);
select ok(
  (select procedure.prosecdef
   from pg_catalog.pg_proc as procedure
   where procedure.oid =
     'public.garmin_ack_plan_core(text,uuid,bigint)'::regprocedure),
  'Garmin acknowledgement core remains security definer'
);
select ok(
  (select 'search_path=""' = any(procedure.proconfig)
   from pg_catalog.pg_proc as procedure
   where procedure.oid =
     'public.garmin_fetch_pending_plan_core(text)'::regprocedure),
  'Garmin fetch core keeps an empty fixed search_path'
);
select ok(
  (select 'search_path=""' = any(procedure.proconfig)
   from pg_catalog.pg_proc as procedure
   where procedure.oid =
     'public.garmin_ack_plan_core(text,uuid,bigint)'::regprocedure),
  'Garmin acknowledgement core keeps an empty fixed search_path'
);
select ok(
  not pg_catalog.has_function_privilege(
    'anon', 'public.garmin_fetch_pending_plan_core(text)', 'EXECUTE'
  ),
  'anonymous clients cannot bypass the fetch rate-limit wrapper'
);
select ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'public.garmin_fetch_pending_plan_core(text)', 'EXECUTE'
  ),
  'authenticated clients cannot bypass the fetch rate-limit wrapper'
);
select ok(
  not pg_catalog.has_function_privilege(
    'service_role', 'public.garmin_fetch_pending_plan_core(text)', 'EXECUTE'
  ),
  'service role cannot invoke the ungranted fetch core'
);
select ok(
  not pg_catalog.has_function_privilege(
    'anon', 'public.garmin_ack_plan_core(text,uuid,bigint)', 'EXECUTE'
  ),
  'anonymous clients cannot bypass the acknowledgement rate-limit wrapper'
);
select ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'public.garmin_ack_plan_core(text,uuid,bigint)', 'EXECUTE'
  ),
  'authenticated clients cannot bypass the acknowledgement rate-limit wrapper'
);
select ok(
  not pg_catalog.has_function_privilege(
    'service_role', 'public.garmin_ack_plan_core(text,uuid,bigint)', 'EXECUTE'
  ),
  'service role cannot invoke the ungranted acknowledgement core'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'public.garmin_fetch_pending_plan_core(text)'::regprocedure
  ) like '%plan_validation_message%'
  and pg_catalog.pg_get_functiondef(
    'public.garmin_fetch_pending_plan_core(text)'::regprocedure
  ) not like '%left(validation_error,%',
  'fetch invalid-plan path uses an unambiguous local variable'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'public.garmin_ack_plan_core(text,uuid,bigint)'::regprocedure
  ) like '%plan_validation_message%'
  and pg_catalog.pg_get_functiondef(
    'public.garmin_ack_plan_core(text,uuid,bigint)'::regprocedure
  ) not like '%left(validation_error,%',
  'acknowledgement invalid-plan path uses an unambiguous local variable'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'public.garmin_fetch_pending_plan(text)'::regprocedure
  ) like '%garmin_rate_limit_for_token%'
  and pg_catalog.pg_get_functiondef(
    'public.garmin_fetch_pending_plan(text)'::regprocedure
  ) like '%garmin_fetch_pending_plan_core%',
  'public fetch wrapper still rate-limits before its core'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'public.garmin_ack_plan(text,uuid,bigint)'::regprocedure
  ) like '%garmin_rate_limit_for_token%'
  and pg_catalog.pg_get_functiondef(
    'public.garmin_ack_plan(text,uuid,bigint)'::regprocedure
  ) like '%garmin_ack_plan_core%',
  'public acknowledgement wrapper still rate-limits before its core'
);

select * from finish();
rollback;
