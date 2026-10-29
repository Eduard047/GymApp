-- Execute on a local PostgreSQL database after migrations.
-- Clone the installed function with dependencies bound to temporary fixtures;
-- never invoke its real session/budget helpers or touch account data.
begin;

select plan(11);

set local statement_timeout = '15s';
create temporary table reservation_windows (
  route text, source_hash text, request_count integer
);
create temporary table reservation_snapshot (snapshot jsonb);
create function pg_temp.test_uid() returns uuid language sql as $$
  select nullif(current_setting('test.caller', true), '')::uuid
$$;
create function pg_temp.test_jwt() returns jsonb language sql as $$
  select jsonb_build_object('session_id', current_setting('test.session', true))
$$;
create function pg_temp.test_hash(text, uuid) returns text language sql as $$
  select 'target-session'::text
$$;
create function pg_temp.test_debit(text, uuid, uuid) returns jsonb language sql as $$
  select current_setting('test.debit')::jsonb
$$;

do $setup$
declare
  definition text := pg_get_functiondef(
    'gymapp_private.social_begin_direct_request()'::regprocedure
  );
begin
  definition := replace(definition, 'gymapp_private.social_begin_direct_request', 'pg_temp.test_reservation');
  definition := replace(definition, 'auth.uid()', 'pg_temp.test_uid()');
  definition := replace(definition, 'auth.jwt()', 'pg_temp.test_jwt()');
  definition := replace(definition, 'gymapp_private.social_session_budget_hash', 'pg_temp.test_hash');
  definition := replace(definition, 'gymapp_private.social_session_aggregate_debit', 'pg_temp.test_debit');
  definition := replace(definition, 'gymapp_private.edge_preauth_windows', 'pg_temp.reservation_windows');
  execute definition;
end
$setup$;

set local test.caller = '00000000-0000-4000-8000-000000000001';
set local test.session = '00000000-0000-4000-8000-000000000002';
set local test.debit = '{"allowed":true,"retryAfter":0}';
insert into pg_temp.reservation_windows values
  ('social_live', 'target-session', 1),
  ('social_live', 'other-session', 4),
  ('social_gateway', 'target-session', 7);

-- A single outstanding reservation is released.
select is(
  pg_temp.test_reservation(),
  '{"allowed":true,"retryAfter":0}'::jsonb,
  'Single reservation returns the allowed budget result'
);
select ok(
  not exists (
    select 1 from pg_temp.reservation_windows
    where route = 'social_live' and source_hash = 'target-session'
  ),
  'Single reservation was released'
);

-- Releasing from a larger window decrements only the target session and route.
insert into pg_temp.reservation_windows values ('social_live', 'target-session', 3);
select lives_ok(
  $$select pg_temp.test_reservation()$$,
  'Reservation release succeeds against a larger window'
);
select is(
  (select request_count from pg_temp.reservation_windows
   where route = 'social_live' and source_hash = 'target-session'),
  2,
  'Reservation release charged the target session exactly once'
);
select is(
  (select request_count from pg_temp.reservation_windows
   where route = 'social_live' and source_hash = 'other-session'),
  4,
  'Reservation release did not cross into another session'
);
select is(
  (select request_count from pg_temp.reservation_windows
   where route = 'social_gateway' and source_hash = 'target-session'),
  7,
  'Reservation release did not cross into another route'
);

-- A denied budget leaves every reservation untouched.
insert into pg_temp.reservation_snapshot
select jsonb_agg(to_jsonb(w) order by route, source_hash) from pg_temp.reservation_windows w;
set local test.debit = '{"allowed":false,"retryAfter":60}';
select is(
  pg_temp.test_reservation(),
  '{"allowed":false,"retryAfter":60}'::jsonb,
  'Denied budget returns the denial result'
);
select is(
  (select jsonb_agg(to_jsonb(w) order by route, source_hash) from pg_temp.reservation_windows w),
  (select snapshot from pg_temp.reservation_snapshot),
  'Denied budget did not change a reservation'
);

-- Rejected authentication never reaches the reservations.
set local test.debit = '{"allowed":true,"retryAfter":0}';
set local test.caller = '';
select throws_ok(
  $$select pg_temp.test_reservation()$$,
  '42501', null,
  'Anonymous caller is rejected'
);
set local test.caller = '00000000-0000-4000-8000-000000000001';
set local test.session = 'invalid';
select throws_ok(
  $$select pg_temp.test_reservation()$$,
  '42501', null,
  'Malformed session is rejected'
);
select is(
  (select jsonb_agg(to_jsonb(w) order by route, source_hash) from pg_temp.reservation_windows w),
  (select snapshot from pg_temp.reservation_snapshot),
  'Rejected authentication did not change a reservation'
);

select * from finish();
rollback;
