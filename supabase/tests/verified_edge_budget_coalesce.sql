-- Runtime regression on PostgreSQL; no extensions or customer fixtures needed.
-- Every generated limiter row is rolled back, including after a failed assert.
begin;

select plan(29);

set local lock_timeout = '5s';
set local statement_timeout = '15s';

-- The DO block drives the limiter with synthetic identities and records every
-- observed result; pgTAP asserts on the recorded values below.
create temporary table budget_probe (
  route text not null,
  step text not null,
  allowance integer not null,
  got jsonb,
  stored_count integer
);

do $test$
declare
  route_row record;
  test_source_hash text;
  test_peer_hash text;
  actual jsonb;
  stored_count integer;
begin
  for route_row in select * from (values
    ('social_live', 180), ('social_gateway', 180), ('delete_account', 12)
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
    insert into budget_probe values (route_row.route, 'first', route_row.allowance, actual, null);

    update gymapp_private.edge_preauth_windows as budget
    set request_count = route_row.allowance - 1,
        window_started_at = pg_catalog.clock_timestamp() + interval '1 minute'
    where budget.route = route_row.route and budget.source_hash = test_source_hash;
    actual := public.edge_preauth_debit(route_row.route, test_source_hash);
    insert into budget_probe values (route_row.route, 'last_allowed', route_row.allowance, actual, null);

    actual := public.edge_preauth_debit(route_row.route, test_source_hash);
    select budget.request_count into strict stored_count
    from gymapp_private.edge_preauth_windows as budget
    where budget.route = route_row.route and budget.source_hash = test_source_hash;
    insert into budget_probe values (route_row.route, 'exhausted', route_row.allowance, actual, stored_count);

    actual := public.edge_preauth_debit(route_row.route, test_peer_hash);
    insert into budget_probe values (route_row.route, 'peer', route_row.allowance, actual, null);

    update gymapp_private.edge_preauth_windows as budget
    set window_started_at = pg_catalog.clock_timestamp() - interval '2 minutes'
    where budget.route = route_row.route and budget.source_hash = test_source_hash;
    actual := public.edge_preauth_debit(route_row.route, test_source_hash);
    select budget.request_count into strict stored_count
    from gymapp_private.edge_preauth_windows as budget
    where budget.route = route_row.route and budget.source_hash = test_source_hash;
    insert into budget_probe values (route_row.route, 'reset', route_row.allowance, actual, stored_count);
  end loop;

  perform pg_catalog.set_config('gymapp.test_budget_source', test_source_hash, true);
  perform pg_catalog.set_config('gymapp.test_budget_peer', test_peer_hash, true);
end
$test$;

-- Per route: first request, last allowed request, fail-closed exhaustion,
-- identity isolation, and expired-window reset.
select is(
  (select got from budget_probe where route = 'social_live' and step = 'first'),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'social_live: first request is allowed'
);
select is(
  (select got from budget_probe where route = 'social_live' and step = 'last_allowed'),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'social_live: last allowed request is allowed'
);
select is(
  (select got from budget_probe where route = 'social_live' and step = 'exhausted'),
  '{"allowed":false,"retryAfter":60}'::jsonb,
  'social_live: exhausted request fails closed'
);
select is(
  (select stored_count from budget_probe where route = 'social_live' and step = 'exhausted'),
  (select allowance from budget_probe where route = 'social_live' and step = 'exhausted'),
  'social_live: exhausted request does not increment past the allowance'
);
select is(
  (select got from budget_probe where route = 'social_live' and step = 'peer'),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'social_live: one identity does not consume another identity budget'
);
select is(
  (select got from budget_probe where route = 'social_live' and step = 'reset'),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'social_live: expired window allows the request'
);
select is(
  (select stored_count from budget_probe where route = 'social_live' and step = 'reset'),
  1,
  'social_live: expired window resets the count to 1'
);

select is(
  (select got from budget_probe where route = 'social_gateway' and step = 'first'),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'social_gateway: first request is allowed'
);
select is(
  (select got from budget_probe where route = 'social_gateway' and step = 'last_allowed'),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'social_gateway: last allowed request is allowed'
);
select is(
  (select got from budget_probe where route = 'social_gateway' and step = 'exhausted'),
  '{"allowed":false,"retryAfter":60}'::jsonb,
  'social_gateway: exhausted request fails closed'
);
select is(
  (select stored_count from budget_probe where route = 'social_gateway' and step = 'exhausted'),
  (select allowance from budget_probe where route = 'social_gateway' and step = 'exhausted'),
  'social_gateway: exhausted request does not increment past the allowance'
);
select is(
  (select got from budget_probe where route = 'social_gateway' and step = 'peer'),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'social_gateway: one identity does not consume another identity budget'
);
select is(
  (select got from budget_probe where route = 'social_gateway' and step = 'reset'),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'social_gateway: expired window allows the request'
);
select is(
  (select stored_count from budget_probe where route = 'social_gateway' and step = 'reset'),
  1,
  'social_gateway: expired window resets the count to 1'
);

select is(
  (select got from budget_probe where route = 'delete_account' and step = 'first'),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'delete_account: first request is allowed'
);
select is(
  (select got from budget_probe where route = 'delete_account' and step = 'last_allowed'),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'delete_account: last allowed request is allowed'
);
select is(
  (select got from budget_probe where route = 'delete_account' and step = 'exhausted'),
  '{"allowed":false,"retryAfter":60}'::jsonb,
  'delete_account: exhausted request fails closed'
);
select is(
  (select stored_count from budget_probe where route = 'delete_account' and step = 'exhausted'),
  (select allowance from budget_probe where route = 'delete_account' and step = 'exhausted'),
  'delete_account: exhausted request does not increment past the allowance'
);
select is(
  (select got from budget_probe where route = 'delete_account' and step = 'peer'),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'delete_account: one identity does not consume another identity budget'
);
select is(
  (select got from budget_probe where route = 'delete_account' and step = 'reset'),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'delete_account: expired window allows the request'
);
select is(
  (select stored_count from budget_probe where route = 'delete_account' and step = 'reset'),
  1,
  'delete_account: expired window resets the count to 1'
);

-- Input validation (SQLSTATE 22023 = invalid_parameter_value).
select throws_ok(
  $$select public.edge_preauth_debit('social_live', 'invalid')$$,
  '22023', null,
  'Malformed identity is rejected'
);
select throws_ok(
  format(
    $$select public.edge_preauth_debit('invalid_route', %L)$$,
    pg_catalog.current_setting('gymapp.test_budget_source')
  ),
  '22023', null,
  'Unknown route is rejected'
);
select throws_ok(
  format(
    $$select public.edge_preauth_debit('garmin_legacy', %L)$$,
    pg_catalog.current_setting('gymapp.test_budget_source')
  ),
  '22023', null,
  'Retired Garmin legacy route is rejected'
);

-- Client roles never reach the wrapper.
set local role anon;
select throws_ok(
  $$select public.edge_preauth_debit('social_live', 'invalid')$$,
  '42501', null,
  'Anonymous caller cannot reach the budget wrapper'
);
reset role;

set local role authenticated;
select throws_ok(
  $$select public.edge_preauth_debit('social_live', 'invalid')$$,
  '42501', null,
  'Authenticated caller cannot reach the budget wrapper'
);
reset role;

-- service_role crosses the private-schema boundary only through the wrapper.
set local role service_role;
select is(
  public.edge_preauth_debit(
    'social_live', pg_catalog.current_setting('gymapp.test_budget_peer')
  ),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'Service wrapper crosses the private-schema boundary'
);
select throws_ok(
  $$select gymapp_private.edge_preauth_debit('social_live', 'invalid')$$,
  '42501', null,
  'Service role cannot bypass the public wrapper'
);
select throws_ok(
  $$select 1 from gymapp_private.edge_preauth_windows limit 1$$,
  '42501', null,
  'Service role has no direct budget-table access'
);
reset role;

select * from finish();
rollback;
