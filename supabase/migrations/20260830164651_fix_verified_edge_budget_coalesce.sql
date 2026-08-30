begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- COALESCE is a SQL expression, not a schema-qualified function. The verified
-- identity limiter reintroduced two qualified calls after the earlier repair.
-- Replace only those calls in the existing function; preserve its owner,
-- privileges, search path, limits, and the service-only public wrapper.
do $migration$
declare
  target_function regprocedure := pg_catalog.to_regprocedure(
    'gymapp_private.edge_preauth_debit(text,text)'
  );
  wrapper_function regprocedure := pg_catalog.to_regprocedure(
    'public.edge_preauth_debit(text,text)'
  );
  original_definition text;
  expected_definition text;
  wrapper_definition text;
  original_security record;
  current_security record;
  invalid_calls integer;
begin
  if target_function is null or wrapper_function is null then
    raise exception 'Verified Edge budget functions are missing.';
  end if;

  select pg_catalog.pg_get_functiondef(target_function),
         pg_catalog.pg_get_functiondef(wrapper_function)
  into strict original_definition, wrapper_definition;

  select p.proowner, p.proacl, p.proconfig, p.prosecdef, p.provolatile
  into strict original_security
  from pg_catalog.pg_proc as p where p.oid = target_function;

  invalid_calls := pg_catalog.regexp_count(
    original_definition, 'pg_catalog[.]coalesce'
  );
  if invalid_calls = 2 and pg_catalog.regexp_count(
    original_definition,
    'pg_catalog[.]coalesce[(]source_allowed, false[)]'
  ) = 2 then
    expected_definition := pg_catalog.replace(
      original_definition,
      'pg_catalog.coalesce(source_allowed, false)',
      'coalesce(source_allowed, false)'
    );
    execute expected_definition;
  elsif invalid_calls = 0 and pg_catalog.regexp_count(
    original_definition, 'coalesce[(]source_allowed, false[)]'
  ) = 2 then
    -- Allow safe reapplication without rewriting an already-repaired function.
    expected_definition := original_definition;
  else
    raise exception 'Unexpected verified Edge budget definition.';
  end if;

  select p.proowner, p.proacl, p.proconfig, p.prosecdef, p.provolatile
  into strict current_security
  from pg_catalog.pg_proc as p where p.oid = target_function;

  if current_security is distinct from original_security
     or pg_catalog.pg_get_functiondef(target_function)
        is distinct from expected_definition
     or pg_catalog.pg_get_functiondef(wrapper_function)
        is distinct from wrapper_definition then
    raise exception 'Verified Edge budget repair changed its contract.';
  end if;

  if pg_catalog.has_function_privilege('anon', wrapper_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', wrapper_function, 'EXECUTE')
     or not pg_catalog.has_function_privilege('service_role', wrapper_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', target_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', target_function, 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', target_function, 'EXECUTE') then
    raise exception 'Verified Edge budget privileges are not isolated.';
  end if;
end
$migration$;

notify pgrst, 'reload schema';

commit;
