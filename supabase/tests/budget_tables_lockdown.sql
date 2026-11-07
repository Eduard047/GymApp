-- The two server-only budget/queue tables in gymapp_private must be closed to
-- the client roles for every DML verb. Nothing is written: each statement is
-- rejected before touching a row, and the transaction rolls back regardless.
begin;

select plan(16);

-- anon
set local role anon;
select throws_ok($$select * from gymapp_private.workout_duration_sync_budgets$$,
  '42501', null, 'anon cannot select workout_duration_sync_budgets');
select throws_ok($$insert into gymapp_private.workout_duration_sync_budgets (user_id, tokens, refilled_at)
  values ('e3000000-0000-4000-8000-000000000001', 1, pg_catalog.now())$$,
  '42501', null, 'anon cannot insert workout_duration_sync_budgets');
select throws_ok($$update gymapp_private.workout_duration_sync_budgets set tokens = 600$$,
  '42501', null, 'anon cannot update workout_duration_sync_budgets');
select throws_ok($$delete from gymapp_private.workout_duration_sync_budgets$$,
  '42501', null, 'anon cannot delete workout_duration_sync_budgets');
select throws_ok($$select * from gymapp_private.push_dispatch_requests$$,
  '42501', null, 'anon cannot select push_dispatch_requests');
select throws_ok($$insert into gymapp_private.push_dispatch_requests (request_id) values (1)$$,
  '42501', null, 'anon cannot insert push_dispatch_requests');
select throws_ok($$update gymapp_private.push_dispatch_requests set outcome = 'succeeded'$$,
  '42501', null, 'anon cannot update push_dispatch_requests');
select throws_ok($$delete from gymapp_private.push_dispatch_requests$$,
  '42501', null, 'anon cannot delete push_dispatch_requests');
reset role;

-- authenticated
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims',
  '{"sub":"e3000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select throws_ok($$select * from gymapp_private.workout_duration_sync_budgets$$,
  '42501', null, 'authenticated cannot select workout_duration_sync_budgets');
select throws_ok($$insert into gymapp_private.workout_duration_sync_budgets (user_id, tokens, refilled_at)
  values ('e3000000-0000-4000-8000-000000000001', 600, pg_catalog.now())$$,
  '42501', null, 'authenticated cannot insert workout_duration_sync_budgets');
select throws_ok($$update gymapp_private.workout_duration_sync_budgets set tokens = 600$$,
  '42501', null, 'authenticated cannot update workout_duration_sync_budgets');
select throws_ok($$delete from gymapp_private.workout_duration_sync_budgets$$,
  '42501', null, 'authenticated cannot delete workout_duration_sync_budgets');
select throws_ok($$select * from gymapp_private.push_dispatch_requests$$,
  '42501', null, 'authenticated cannot select push_dispatch_requests');
select throws_ok($$insert into gymapp_private.push_dispatch_requests (request_id) values (1)$$,
  '42501', null, 'authenticated cannot insert push_dispatch_requests');
select throws_ok($$update gymapp_private.push_dispatch_requests set outcome = 'succeeded'$$,
  '42501', null, 'authenticated cannot update push_dispatch_requests');
select throws_ok($$delete from gymapp_private.push_dispatch_requests$$,
  '42501', null, 'authenticated cannot delete push_dispatch_requests');
reset role;

select * from finish();
rollback;
