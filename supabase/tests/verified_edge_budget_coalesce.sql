-- Runtime regression on PostgreSQL; no extensions or customer fixtures needed.
-- Every generated limiter row is rolled back, including after a failed assert.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '15s';

do $test$
declare
  route_row record;
  test_source_hash text;
  test_peer_hash text;
  actual jsonb;
  stored_count integer;
begin
  for route_row in select * from (values
    ('social_live', 180), ('delete_account', 12), ('garmin_legacy', 90)
  ) as routes(route, allowance) loop
    -- Avoid the opportunistic cleanup branch: touch only our synthetic rows.
    loop
      test_source_hash := pg_catalog.md5(pg_catalog.gen_random_uuid()::text)
                     || pg_catalog.md5(pg_catalog.gen_random_uuid()::text);
      exit when pg_catalog.mod(pg_catalog.hashtextextended(test_source_hash, 0), 128) <> 0;
    end loop;
    loop
      test_peer_hash := pg_catalog.md5(pg_catalog.gen_random_uuid()::text)
                   || pg_catalog.md5(pg_catalog.gen_random_uuid()::text);
      exit when test_peer_hash <> test_source_hash
        and pg_catalog.mod(pg_catalog.hashtextextended(test_peer_hash, 0), 128) <> 0;
    end loop;
    if exists (
      select 1 from gymapp_private.edge_preauth_windows as budget
      where budget.source_hash in (test_source_hash, test_peer_hash)
    ) then
      raise exception 'Synthetic budget collision.';
    end if;

    actual := public.edge_preauth_debit(route_row.route, test_source_hash);
    if actual is distinct from '{"allowed":true,"retryAfter":0}'::jsonb then
      raise exception 'First request failed for %.', route_row.route;
    end if;

    update gymapp_private.edge_preauth_windows as budget
    set request_count = route_row.allowance - 1,
        window_started_at = pg_catalog.clock_timestamp() + interval '1 minute'
    where budget.route = route_row.route and budget.source_hash = test_source_hash;
    actual := public.edge_preauth_debit(route_row.route, test_source_hash);
    if actual is distinct from '{"allowed":true,"retryAfter":0}'::jsonb then
      raise exception 'Last allowed request failed for %.', route_row.route;
    end if;

    actual := public.edge_preauth_debit(route_row.route, test_source_hash);
    select budget.request_count into strict stored_count
    from gymapp_private.edge_preauth_windows as budget
    where budget.route = route_row.route and budget.source_hash = test_source_hash;
    if actual is distinct from '{"allowed":false,"retryAfter":60}'::jsonb
       or stored_count <> route_row.allowance then
      raise exception 'Exhausted request did not fail closed for %.', route_row.route;
    end if;

    actual := public.edge_preauth_debit(route_row.route, test_peer_hash);
    if actual is distinct from '{"allowed":true,"retryAfter":0}'::jsonb then
      raise exception 'One identity consumed another identity budget.';
    end if;

    update gymapp_private.edge_preauth_windows as budget
    set window_started_at = pg_catalog.clock_timestamp() - interval '2 minutes'
    where budget.route = route_row.route and budget.source_hash = test_source_hash;
    actual := public.edge_preauth_debit(route_row.route, test_source_hash);
    select budget.request_count into strict stored_count
    from gymapp_private.edge_preauth_windows as budget
    where budget.route = route_row.route and budget.source_hash = test_source_hash;
    if actual is distinct from '{"allowed":true,"retryAfter":0}'::jsonb
       or stored_count <> 1 then
      raise exception 'Expired window did not reset for %.', route_row.route;
    end if;
  end loop;

  begin
    perform public.edge_preauth_debit('social_live', 'invalid');
    raise exception 'Malformed identity was accepted.';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.edge_preauth_debit('invalid_route', test_source_hash);
    raise exception 'Unknown route was accepted.';
  exception when invalid_parameter_value then null;
  end;

  perform pg_catalog.set_config('gymapp.test_budget_source', test_peer_hash, true);
end
$test$;

set local role anon;
do $test$
begin
  begin
    perform public.edge_preauth_debit('social_live', 'invalid');
    raise exception 'Anonymous caller reached the budget wrapper.';
  exception when insufficient_privilege then null;
  end;
end
$test$;
reset role;

set local role authenticated;
do $test$
begin
  begin
    perform public.edge_preauth_debit('social_live', 'invalid');
    raise exception 'Authenticated caller reached the budget wrapper.';
  exception when insufficient_privilege then null;
  end;
end
$test$;
reset role;

set local role service_role;
do $test$
declare
  actual jsonb;
begin
  actual := public.edge_preauth_debit(
    'social_live', pg_catalog.current_setting('gymapp.test_budget_source')
  );
  if actual is distinct from '{"allowed":true,"retryAfter":0}'::jsonb then
    raise exception 'Service wrapper could not cross the private-schema boundary.';
  end if;
  begin
    perform gymapp_private.edge_preauth_debit('social_live', 'invalid');
    raise exception 'Service role bypassed the public wrapper.';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from gymapp_private.edge_preauth_windows limit 1;
    raise exception 'Service role obtained direct budget-table access.';
  exception when insufficient_privilege then null;
  end;
end
$test$;
reset role;

select 'verified_edge_budget_coalesce: passed' as result;
rollback;
