-- Pins the final state of the Realtime authorization policy on realtime.messages
-- (migration 20260810075729_activate_live_workout_realtime.sql) and probes it as
-- real client roles. Skips cleanly when the local stack has no realtime.messages.
-- Synthetic fixtures and every write are rolled back.
begin;

select plan(16);

create temporary table realtime_probe_state (
  have_table boolean not null,
  can_insert boolean not null
) on commit drop;
grant select on realtime_probe_state to anon, authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'e1000000-0000-4000-8000-000000000001',
   'authenticated', 'authenticated', 'rt-policy-a@example.invalid', '',
   pg_catalog.clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb,
   '{}'::jsonb, pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()),
  ('00000000-0000-0000-0000-000000000000', 'e1000000-0000-4000-8000-000000000002',
   'authenticated', 'authenticated', 'rt-policy-b@example.invalid', '',
   pg_catalog.clock_timestamp(), '{"provider":"email","providers":["email"]}'::jsonb,
   '{}'::jsonb, pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp());

insert into auth.sessions (id, user_id, not_after, created_at, updated_at) values
  ('e2000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001',
   pg_catalog.clock_timestamp() + interval '1 day',
   pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp());

-- Fixture rows exist only when the table and a partition for today exist.
do $fixture$
declare
  has_table boolean := pg_catalog.to_regclass('realtime.messages') is not null;
  inserted boolean := false;
begin
  if has_table then
    begin
      insert into realtime.messages (topic, extension, payload, event, private)
      values
        ('gymapp:user:e1000000-0000-4000-8000-000000000001', 'broadcast',
         '{"probe":"a-broadcast"}'::jsonb, 'probe', true),
        ('gymapp:user:e1000000-0000-4000-8000-000000000001', 'presence',
         '{"probe":"a-presence"}'::jsonb, 'probe', true),
        ('gymapp:user:e1000000-0000-4000-8000-000000000002', 'broadcast',
         '{"probe":"b-broadcast"}'::jsonb, 'probe', true);
      inserted := true;
    exception when others then
      inserted := false;
    end;
  end if;
  insert into realtime_probe_state values (has_table, inserted);
end
$fixture$;

-- ---------------------------------------------------------------------------
-- Structural pin (catalog only).
-- ---------------------------------------------------------------------------
select case when (select have_table from realtime_probe_state) then
  is((select pg_catalog.count(*)::integer from pg_catalog.pg_policy
      where polrelid = 'realtime.messages'::pg_catalog.regclass
        and polname = 'gymapp_live_broadcast_personal_read'),
     1, 'gymapp_live_broadcast_personal_read exists exactly once on realtime.messages')
  else skip('realtime.messages missing in this stack', 1) end;

select case when (select have_table from realtime_probe_state) then
  is((select polcmd::text from pg_catalog.pg_policy
      where polrelid = 'realtime.messages'::pg_catalog.regclass
        and polname = 'gymapp_live_broadcast_personal_read'),
     'r', 'policy is a SELECT policy')
  else skip('realtime.messages missing in this stack', 1) end;

select case when (select have_table from realtime_probe_state) then
  is((select polroles::oid[] from pg_catalog.pg_policy
      where polrelid = 'realtime.messages'::pg_catalog.regclass
        and polname = 'gymapp_live_broadcast_personal_read'),
     array['authenticated'::pg_catalog.regrole::oid],
     'policy applies to authenticated only')
  else skip('realtime.messages missing in this stack', 1) end;

select case when (select have_table from realtime_probe_state) then
  ok((select polpermissive from pg_catalog.pg_policy
      where polrelid = 'realtime.messages'::pg_catalog.regclass
        and polname = 'gymapp_live_broadcast_personal_read'),
     'policy is permissive')
  else skip('realtime.messages missing in this stack', 1) end;

select case when (select have_table from realtime_probe_state) then
  ok((select polwithcheck is null from pg_catalog.pg_policy
      where polrelid = 'realtime.messages'::pg_catalog.regclass
        and polname = 'gymapp_live_broadcast_personal_read'),
     'policy has no WITH CHECK expression')
  else skip('realtime.messages missing in this stack', 1) end;

select case when (select have_table from realtime_probe_state) then
  ok((select pg_catalog.pg_get_expr(polqual, polrelid) like '%extension = ''broadcast''%'
      from pg_catalog.pg_policy
      where polrelid = 'realtime.messages'::pg_catalog.regclass
        and polname = 'gymapp_live_broadcast_personal_read'),
     'policy is limited to the broadcast extension')
  else skip('realtime.messages missing in this stack', 1) end;

select case when (select have_table from realtime_probe_state) then
  ok((select pg_catalog.pg_get_expr(polqual, polrelid) like '%gymapp_private.realtime_has_current_auth_session()%'
      from pg_catalog.pg_policy
      where polrelid = 'realtime.messages'::pg_catalog.regclass
        and polname = 'gymapp_live_broadcast_personal_read'),
     'policy requires a live auth session')
  else skip('realtime.messages missing in this stack', 1) end;

select case when (select have_table from realtime_probe_state) then
  ok((select pg_catalog.pg_get_expr(polqual, polrelid) like '%realtime.topic()%'
        and pg_catalog.pg_get_expr(polqual, polrelid) like '%''gymapp:user:''%'
        and pg_catalog.pg_get_expr(polqual, polrelid) like '%auth.uid()%'
      from pg_catalog.pg_policy
      where polrelid = 'realtime.messages'::pg_catalog.regclass
        and polname = 'gymapp_live_broadcast_personal_read'),
     'policy binds the topic to gymapp:user:<auth.uid()>')
  else skip('realtime.messages missing in this stack', 1) end;

-- Any other policy that reaches anon/authenticated/public would widen access.
select case when (select have_table from realtime_probe_state) then
  is((select pg_catalog.count(*)::integer from pg_catalog.pg_policy as policy
      where policy.polrelid = 'realtime.messages'::pg_catalog.regclass
        and policy.polname <> 'gymapp_live_broadcast_personal_read'
        and (policy.polroles = array[0::oid]
             or 'anon'::pg_catalog.regrole::oid = any(policy.polroles)
             or 'authenticated'::pg_catalog.regrole::oid = any(policy.polroles))),
     0, 'no other policy applies to public, anon, or authenticated')
  else skip('realtime.messages missing in this stack', 1) end;

select case when (select have_table from realtime_probe_state) then
  is((select pg_catalog.count(*)::integer from pg_catalog.pg_policy as policy
      where policy.polrelid = 'realtime.messages'::pg_catalog.regclass
        and policy.polcmd in ('a', 'w', 'd', '*')
        and (policy.polroles = array[0::oid]
             or 'anon'::pg_catalog.regrole::oid = any(policy.polroles)
             or 'authenticated'::pg_catalog.regrole::oid = any(policy.polroles))),
     0, 'no INSERT/UPDATE/DELETE/ALL policy for public, anon, or authenticated')
  else skip('realtime.messages missing in this stack', 1) end;

select case when (select have_table from realtime_probe_state) then
  ok((select relrowsecurity from pg_catalog.pg_class
      where oid = 'realtime.messages'::pg_catalog.regclass),
     'realtime.messages has row level security enabled')
  else skip('realtime.messages missing in this stack', 1) end;

-- ---------------------------------------------------------------------------
-- Behavioral probe as real client roles, topic set the way Realtime sets it.
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims',
  '{"sub":"e1000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e2000000-0000-4000-8000-000000000001"}',
  true);

select set_config('realtime.topic', 'gymapp:user:e1000000-0000-4000-8000-000000000001', true);
select case when (select can_insert from realtime_probe_state) then
  is((select pg_catalog.count(*)::integer from realtime.messages
      where topic = 'gymapp:user:e1000000-0000-4000-8000-000000000001'),
     1, 'with its own topic set, A sees the broadcast row of that topic (presence row hidden)')
  else skip('cannot seed realtime.messages in this stack', 1) end;

select set_config('realtime.topic', 'gymapp:user:e1000000-0000-4000-8000-000000000002', true);
select case when (select can_insert from realtime_probe_state) then
  is((select pg_catalog.count(*)::integer from realtime.messages),
     0, 'with the topic of user B set, A reads nothing (policy gates the channel topic)')
  else skip('cannot seed realtime.messages in this stack', 1) end;

select case when (select have_table from realtime_probe_state) then
  throws_ok(
    $$insert into realtime.messages (topic, extension, payload, event, private)
      values ('gymapp:user:e1000000-0000-4000-8000-000000000001', 'broadcast',
              '{"probe":"forged"}'::jsonb, 'probe', true)$$,
    '42501', null, 'authenticated cannot insert into realtime.messages')
  else skip('realtime.messages missing in this stack', 1) end;

reset role;
-- The session is revoked while the JWT stays valid: the policy must close.
delete from auth.sessions where id = 'e2000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('realtime.topic', 'gymapp:user:e1000000-0000-4000-8000-000000000001', true);
select case when (select can_insert from realtime_probe_state) then
  is((select pg_catalog.count(*)::integer from realtime.messages),
     0, 'a revoked auth session reads nothing even with its own topic set')
  else skip('cannot seed realtime.messages in this stack', 1) end;
reset role;

set local role anon;
select set_config('realtime.topic', 'gymapp:user:e1000000-0000-4000-8000-000000000001', true);
select case when (select can_insert from realtime_probe_state) then
  is((select pg_catalog.count(*)::integer from realtime.messages), 0,
     'anon reads nothing from realtime.messages')
  else skip('cannot seed realtime.messages in this stack', 1) end;
reset role;

select * from finish();
rollback;
