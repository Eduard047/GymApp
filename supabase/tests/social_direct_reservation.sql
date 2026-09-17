-- Execute on a local PostgreSQL database after migrations.
-- Clone the installed function with dependencies bound to temporary fixtures;
-- never invoke its real session/budget helpers or touch account data.
begin;
set local statement_timeout = '15s';
create temporary table reservation_windows (
  route text, source_hash text, request_count integer
);
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

do $test$
declare
  result jsonb;
  snapshot jsonb;
begin
  perform set_config('test.caller', '00000000-0000-4000-8000-000000000001', true);
  perform set_config('test.session', '00000000-0000-4000-8000-000000000002', true);
  perform set_config('test.debit', '{"allowed":true,"retryAfter":0}', true);
  insert into pg_temp.reservation_windows values
    ('social_live', 'target-session', 1),
    ('social_live', 'other-session', 4),
    ('social_gateway', 'target-session', 7);

  result := pg_temp.test_reservation();
  if result is distinct from '{"allowed":true,"retryAfter":0}'::jsonb
     or exists (select 1 from pg_temp.reservation_windows where route = 'social_live' and source_hash = 'target-session') then
    raise exception 'Single reservation was not released.';
  end if;

  insert into pg_temp.reservation_windows values ('social_live', 'target-session', 3);
  perform pg_temp.test_reservation();
  if (select request_count from pg_temp.reservation_windows where route = 'social_live' and source_hash = 'target-session') is distinct from 2
     or (select request_count from pg_temp.reservation_windows where route = 'social_live' and source_hash = 'other-session') is distinct from 4
     or (select request_count from pg_temp.reservation_windows where route = 'social_gateway' and source_hash = 'target-session') is distinct from 7 then
    raise exception 'Reservation release crossed session/route boundaries or charged incorrectly.';
  end if;

  select jsonb_agg(to_jsonb(w) order by route, source_hash) into snapshot from pg_temp.reservation_windows w;
  perform set_config('test.debit', '{"allowed":false,"retryAfter":60}', true);
  result := pg_temp.test_reservation();
  if result is distinct from '{"allowed":false,"retryAfter":60}'::jsonb
     or snapshot is distinct from (select jsonb_agg(to_jsonb(w) order by route, source_hash) from pg_temp.reservation_windows w) then
    raise exception 'Denied budget changed a reservation.';
  end if;

  perform set_config('test.debit', '{"allowed":true,"retryAfter":0}', true);
  perform set_config('test.caller', '', true);
  begin
    perform pg_temp.test_reservation();
    raise exception 'Anonymous caller was accepted.';
  exception when insufficient_privilege then null;
  end;
  perform set_config('test.caller', '00000000-0000-4000-8000-000000000001', true);
  perform set_config('test.session', 'invalid', true);
  begin
    perform pg_temp.test_reservation();
    raise exception 'Malformed session was accepted.';
  exception when insufficient_privilege then null;
  end;
  if snapshot is distinct from (select jsonb_agg(to_jsonb(w) order by route, source_hash) from pg_temp.reservation_windows w) then
    raise exception 'Rejected authentication changed a reservation.';
  end if;
end
$test$;
rollback;
