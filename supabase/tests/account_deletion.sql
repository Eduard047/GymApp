begin;

select plan(53);

-- Users: A and B hold live sessions, C holds an expired session, E is used for
-- the rate-limit path. Nothing below writes outside this rolled-back transaction.
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    'c9000000-0000-4000-8000-000000000001',
    'authenticated', 'authenticated', 'deletion-a@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'c9000000-0000-4000-8000-000000000002',
    'authenticated', 'authenticated', 'deletion-b@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'c9000000-0000-4000-8000-000000000003',
    'authenticated', 'authenticated', 'deletion-c@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'c9000000-0000-4000-8000-000000000004',
    'authenticated', 'authenticated', 'deletion-e@example.invalid', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

insert into auth.sessions (id, user_id, not_after, created_at, updated_at) values
  (
    'c9100000-0000-4000-8000-000000000001',
    'c9000000-0000-4000-8000-000000000001',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'c9100000-0000-4000-8000-000000000002',
    'c9000000-0000-4000-8000-000000000002',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'c9100000-0000-4000-8000-000000000003',
    'c9000000-0000-4000-8000-000000000003',
    pg_catalog.clock_timestamp() - interval '1 second',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    'c9100000-0000-4000-8000-000000000004',
    'c9000000-0000-4000-8000-000000000004',
    pg_catalog.clock_timestamp() + interval '1 day',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

-- Owned rows that must survive another account's deletion and that must be
-- removed with their own account.
insert into public.profiles (
  user_id, public_id, display_name, progression_version, updated_at
) values
  (
    'c9000000-0000-4000-8000-000000000001',
    'p_c9000000000000000000000000000001',
    'Deletion owner A', 1, pg_catalog.clock_timestamp()
  ),
  (
    'c9000000-0000-4000-8000-000000000002',
    'p_c9000000000000000000000000000002',
    'Deletion owner B', 1, pg_catalog.clock_timestamp()
  );

-- Builds the JWT claims PostgREST would hand the database: sub, role, the exact
-- session id and an amr password entry aged by p_password_age (NULL omits amr).
create function pg_temp.act_as(
  p_user uuid,
  p_session uuid,
  p_password_age interval default interval '0'
) returns void
language sql
as $$
  select pg_catalog.set_config(
    'request.jwt.claim.sub', coalesce(p_user::text, ''), true
  ), pg_catalog.set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'sub', p_user,
      'role', 'authenticated',
      'session_id', p_session,
      'amr', case
        when p_password_age is null then null
        else pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
          'method', 'password',
          'timestamp', pg_catalog.floor(extract(
            epoch from pg_catalog.clock_timestamp() - p_password_age
          ))::bigint
        ))
      end
    ))::text,
    true
  )
$$;

grant execute on function pg_temp.act_as(uuid, uuid, interval)
  to authenticated, anon;

create temporary table deletion_results (
  case_name text primary key,
  payload jsonb not null
) on commit drop;
grant all on deletion_results to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Contract shape: no argument can name a target account.
-- ---------------------------------------------------------------------------
select is(
  (select procedure_row.pronargs::integer
   from pg_catalog.pg_proc as procedure_row
   where procedure_row.oid =
     'public.prepare_account_deletion()'::pg_catalog.regprocedure),
  0,
  'prepare_account_deletion takes no target-account argument'
);
select is(
  (select procedure_row.pronargs::integer
   from pg_catalog.pg_proc as procedure_row
   where procedure_row.oid =
     'public.require_live_session_for_account_deletion()'::pg_catalog.regprocedure),
  0,
  'require_live_session_for_account_deletion takes no target-account argument'
);
select is(
  (select pg_catalog.pg_get_function_arguments(procedure_row.oid)
   from pg_catalog.pg_proc as procedure_row
   where procedure_row.oid =
     'public.commit_account_deletion_operation(text)'::pg_catalog.regprocedure),
  'p_grant text',
  'commit_account_deletion_operation takes only the one-time grant'
);

-- ---------------------------------------------------------------------------
-- Anonymous callers.
-- ---------------------------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok(
  $$select public.prepare_account_deletion()$$,
  '42501',
  null,
  'anon cannot prepare account deletion'
);
select throws_ok(
  $$select public.require_live_session_for_account_deletion()$$,
  '42501',
  null,
  'anon cannot call the live-session check'
);
select throws_ok(
  $$select public.commit_account_deletion_operation(
    'c9aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  )$$,
  '42501',
  null,
  'anon cannot commit an account deletion'
);

-- ---------------------------------------------------------------------------
-- Authenticated callers without a usable identity or session.
-- ---------------------------------------------------------------------------
set local role authenticated;

select pg_temp.act_as(null, null, null);
select throws_ok(
  $$select public.prepare_account_deletion()$$,
  '42501',
  'Recent password authentication is required.',
  'a token without a subject cannot prepare account deletion'
);
select throws_ok(
  $$select public.require_live_session_for_account_deletion()$$,
  '42501',
  'A current authenticated session is required',
  'a token without a subject fails the live-session check'
);

-- Live session but no password method in amr (for example an OAuth or
-- refreshed-only session): recent password authentication is mandatory.
select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000001',
  'c9100000-0000-4000-8000-000000000001',
  null
);
select throws_ok(
  $$select public.prepare_account_deletion()$$,
  '42501',
  'Recent password authentication is required.',
  'a live session without a password amr entry is rejected'
);

select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000001',
  'c9100000-0000-4000-8000-000000000001',
  interval '6 minutes'
);
select throws_ok(
  $$select public.prepare_account_deletion()$$,
  '42501',
  'Recent password authentication is required.',
  'password authentication older than five minutes is rejected'
);

-- A token with a fresh password amr but no session_id claim.
do $claims$
begin
  perform pg_catalog.set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object(
      'sub', 'c9000000-0000-4000-8000-000000000001',
      'role', 'authenticated',
      'amr', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'method', 'password',
        'timestamp', pg_catalog.floor(extract(
          epoch from pg_catalog.clock_timestamp()
        ))::bigint
      ))
    )::text,
    true
  );
end
$claims$;
select throws_ok(
  $$select public.prepare_account_deletion()$$,
  '42501',
  'Recent password authentication is required.',
  'a token without a session_id claim cannot prepare account deletion'
);
select throws_ok(
  $$select public.require_live_session_for_account_deletion()$$,
  '42501',
  'A current authenticated session is required',
  'a token without a session_id claim fails the live-session check'
);

-- Expired session for C, even with a fresh password amr.
select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000003',
  'c9100000-0000-4000-8000-000000000003'
);
select throws_ok(
  $$select public.prepare_account_deletion()$$,
  '42501',
  'A current authenticated session is required.',
  'an expired session cannot prepare account deletion'
);
select throws_ok(
  $$select public.require_live_session_for_account_deletion()$$,
  '42501',
  'A current authenticated session is required',
  'an expired session fails the live-session check'
);
select throws_ok(
  $$select public.commit_account_deletion_operation(
    'c9aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  )$$,
  '42501',
  'A current authenticated session is required.',
  'an expired session cannot commit even with a well-formed grant'
);

-- Cross-account session binding: A's subject with B's session, and B's subject
-- with A's session, are both refused. A cannot borrow B's live session.
select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000001',
  'c9100000-0000-4000-8000-000000000002'
);
select throws_ok(
  $$select public.prepare_account_deletion()$$,
  '42501',
  'A current authenticated session is required.',
  'subject A with B''s session cannot prepare account deletion'
);
select throws_ok(
  $$select public.require_live_session_for_account_deletion()$$,
  '42501',
  'A current authenticated session is required',
  'subject A with B''s session fails the live-session check'
);
select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000002',
  'c9100000-0000-4000-8000-000000000001'
);
select throws_ok(
  $$select public.prepare_account_deletion()$$,
  '42501',
  'A current authenticated session is required.',
  'subject B with A''s session cannot prepare account deletion'
);

-- Nothing was created by any rejected attempt.
reset role;
select is(
  (select pg_catalog.count(*)
   from gymapp_private.account_deletion_grants as deletion_grant
   where deletion_grant.user_id in (
     'c9000000-0000-4000-8000-000000000001',
     'c9000000-0000-4000-8000-000000000002',
     'c9000000-0000-4000-8000-000000000003'
   )),
  0::bigint,
  'rejected preparations create no deletion grant'
);

-- ---------------------------------------------------------------------------
-- Happy path for B first, so A's later preparation must leave it untouched.
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000002',
  'c9100000-0000-4000-8000-000000000002'
);
insert into deletion_results
select 'prepare-b', public.prepare_account_deletion();
select is(
  public.require_live_session_for_account_deletion(),
  'c9000000-0000-4000-8000-000000000002'::uuid,
  'the live-session check returns only the caller''s own account id'
);

select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000001',
  'c9100000-0000-4000-8000-000000000001'
);
insert into deletion_results
select 'prepare-a1', public.prepare_account_deletion();
select is(
  public.require_live_session_for_account_deletion(),
  'c9000000-0000-4000-8000-000000000001'::uuid,
  'the live-session check returns A''s own account id for A''s session'
);

-- The response is exactly what the delete-account Edge Function validates:
-- version 1, a UUID grant, and a bounded expiresAt timestamp string.
select is(
  (select payload -> 'version' from deletion_results where case_name = 'prepare-a1'),
  '1'::jsonb,
  'preparation returns response version 1'
);
select ok(
  (select payload ->> 'grant' ~
     '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   from deletion_results where case_name = 'prepare-a1'),
  'preparation returns a UUID grant'
);
select ok(
  (select pg_catalog.length(payload ->> 'expiresAt') <= 64
     and (payload ->> 'expiresAt')::timestamptz > pg_catalog.clock_timestamp()
   from deletion_results where case_name = 'prepare-a1'),
  'preparation returns a bounded future expiresAt'
);
select is(
  (select array_agg(key order by key)
   from deletion_results,
        lateral pg_catalog.jsonb_object_keys(payload) as key
   where case_name = 'prepare-a1'),
  array['expiresAt', 'grant', 'version'],
  'preparation exposes only version, grant and expiresAt'
);

-- Side effects, inspected as the table owner.
reset role;
select is(
  (select pg_catalog.count(*)
   from gymapp_private.account_deletion_grants as deletion_grant
   where deletion_grant.user_id = 'c9000000-0000-4000-8000-000000000001'),
  1::bigint,
  'preparation stores exactly one grant for the caller'
);
select ok(
  exists (
    select 1
    from gymapp_private.account_deletion_grants as deletion_grant
    where deletion_grant.user_id = 'c9000000-0000-4000-8000-000000000001'
      and deletion_grant.session_id = 'c9100000-0000-4000-8000-000000000001'
      and deletion_grant.purpose = 'delete_account'
      and deletion_grant.consumed_at is null
      and deletion_grant.expires_at > pg_catalog.clock_timestamp()
      and deletion_grant.expires_at <=
        pg_catalog.clock_timestamp() + interval '5 minutes'
  ),
  'the grant is bound to the caller session, unconsumed and expires within five minutes'
);
select ok(
  exists (
    select 1
    from gymapp_private.account_deletion_grants as deletion_grant
    where deletion_grant.user_id = 'c9000000-0000-4000-8000-000000000001'
      and deletion_grant.grant_hash = extensions.digest(
        pg_catalog.convert_to(
          (select payload ->> 'grant'
           from deletion_results where case_name = 'prepare-a1'),
          'UTF8'
        ),
        'sha256'
      )
  ),
  'only the SHA-256 digest of the returned grant is stored'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.account_deletion_grants as deletion_grant
   where deletion_grant.user_id = 'c9000000-0000-4000-8000-000000000002'
     and deletion_grant.session_id = 'c9100000-0000-4000-8000-000000000002'
     and deletion_grant.grant_hash = extensions.digest(
       pg_catalog.convert_to(
         (select payload ->> 'grant'
          from deletion_results where case_name = 'prepare-b'),
         'UTF8'
       ),
       'sha256'
     )),
  1::bigint,
  'A''s preparation left B''s grant untouched'
);

-- A second preparation replaces A's sole grant and never B's.
set local role authenticated;
select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000001',
  'c9100000-0000-4000-8000-000000000001'
);
insert into deletion_results
select 'prepare-a2', public.prepare_account_deletion();
reset role;
select is(
  (select pg_catalog.count(*)
   from gymapp_private.account_deletion_grants as deletion_grant
   where deletion_grant.user_id = 'c9000000-0000-4000-8000-000000000001'),
  1::bigint,
  'a second preparation replaces the caller''s sole grant'
);
select isnt(
  (select payload ->> 'grant' from deletion_results where case_name = 'prepare-a2'),
  (select payload ->> 'grant' from deletion_results where case_name = 'prepare-a1'),
  'a second preparation issues a different grant'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.account_deletion_grants as deletion_grant
   where deletion_grant.user_id = 'c9000000-0000-4000-8000-000000000002'),
  1::bigint,
  'A''s second preparation still leaves B''s grant in place'
);

-- ---------------------------------------------------------------------------
-- Commit: grants are account-, session- and time-bound, single use.
-- ---------------------------------------------------------------------------
set local role authenticated;

-- The superseded grant A first received no longer authorizes anything.
select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000001',
  'c9100000-0000-4000-8000-000000000001'
);
select throws_ok(
  pg_catalog.format(
    'select public.commit_account_deletion_operation(%L)',
    (select payload ->> 'grant' from deletion_results where case_name = 'prepare-a1')
  ),
  '42501',
  'Account deletion authorization is invalid.',
  'a superseded grant cannot commit a deletion'
);
select throws_ok(
  $$select public.commit_account_deletion_operation('not-a-uuid')$$,
  '42501',
  'Account deletion authorization is invalid.',
  'a malformed grant cannot commit a deletion'
);

-- B presents A's current grant with B's own live session.
select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000002',
  'c9100000-0000-4000-8000-000000000002'
);
select throws_ok(
  pg_catalog.format(
    'select public.commit_account_deletion_operation(%L)',
    (select payload ->> 'grant' from deletion_results where case_name = 'prepare-a2')
  ),
  '42501',
  'Account deletion authorization is invalid.',
  'B cannot commit a deletion with A''s grant'
);
select throws_ok(
  pg_catalog.format(
    'select public.consume_account_deletion_grant(%L)',
    (select payload ->> 'grant' from deletion_results where case_name = 'prepare-a2')
  ),
  '42501',
  'Account deletion authorization is invalid.',
  'B cannot consume A''s grant through the legacy RPC'
);

-- A presents B's grant with A's session.
select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000001',
  'c9100000-0000-4000-8000-000000000001'
);
select throws_ok(
  pg_catalog.format(
    'select public.commit_account_deletion_operation(%L)',
    (select payload ->> 'grant' from deletion_results where case_name = 'prepare-b')
  ),
  '42501',
  'Account deletion authorization is invalid.',
  'A cannot commit a deletion with B''s grant'
);

reset role;
select is(
  (select pg_catalog.count(*)
   from gymapp_private.account_deletion_operations as operation
   where operation.user_id in (
     'c9000000-0000-4000-8000-000000000001',
     'c9000000-0000-4000-8000-000000000002'
   )),
  0::bigint,
  'rejected commits create no deletion operation'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.account_deletion_grants as deletion_grant
   where deletion_grant.user_id in (
     'c9000000-0000-4000-8000-000000000001',
     'c9000000-0000-4000-8000-000000000002'
   ) and deletion_grant.consumed_at is not null),
  0::bigint,
  'rejected commits consume no grant'
);

-- Expired grant: B's grant, aged past its expiry as the table owner.
update gymapp_private.account_deletion_grants as deletion_grant
set expires_at = pg_catalog.clock_timestamp() - interval '1 second'
where deletion_grant.user_id = 'c9000000-0000-4000-8000-000000000002';

set local role authenticated;
select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000002',
  'c9100000-0000-4000-8000-000000000002'
);
select throws_ok(
  pg_catalog.format(
    'select public.commit_account_deletion_operation(%L)',
    (select payload ->> 'grant' from deletion_results where case_name = 'prepare-b')
  ),
  '42501',
  'Account deletion authorization is invalid.',
  'an expired grant cannot commit a deletion'
);

-- A commits with its own current grant, exactly as the Edge Function does.
select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000001',
  'c9100000-0000-4000-8000-000000000001'
);
insert into deletion_results
select 'commit-a',
  public.commit_account_deletion_operation(
    (select payload ->> 'grant' from deletion_results where case_name = 'prepare-a2')
  );
select is(
  (select array_agg(key order by key)
   from deletion_results,
        lateral pg_catalog.jsonb_object_keys(payload) as key
   where case_name = 'commit-a'),
  array['committedAt', 'operationId', 'status', 'userId', 'version'],
  'commit returns exactly the proof fields the Edge Function validates'
);
select ok(
  (select payload -> 'version' = '2'::jsonb
     and payload ->> 'status' = 'committed'
     and payload ->> 'userId' = 'c9000000-0000-4000-8000-000000000001'
   from deletion_results where case_name = 'commit-a'),
  'commit proves version 2, committed status and the caller''s own user id'
);

-- Replaying the same grant is an idempotent no-op returning the same proof.
insert into deletion_results
select 'commit-a-replay',
  public.commit_account_deletion_operation(
    (select payload ->> 'grant' from deletion_results where case_name = 'prepare-a2')
  );
select is(
  (select payload ->> 'operationId' from deletion_results where case_name = 'commit-a-replay'),
  (select payload ->> 'operationId' from deletion_results where case_name = 'commit-a'),
  'replaying the committed grant returns the same operation'
);
select is(
  public.consume_account_deletion_grant(
    (select payload ->> 'grant' from deletion_results where case_name = 'prepare-a2')
  ),
  'c9000000-0000-4000-8000-000000000001'::uuid,
  'the legacy consume RPC returns only the caller''s own user id'
);

reset role;
select ok(
  exists (
    select 1
    from gymapp_private.account_deletion_operations as operation
    where operation.user_id = 'c9000000-0000-4000-8000-000000000001'
      and operation.session_id = 'c9100000-0000-4000-8000-000000000001'
      and operation.status = 'committed'
      and operation.operation_id::text =
        (select payload ->> 'operationId' from deletion_results where case_name = 'commit-a')
  ),
  'commit journals one operation bound to the caller and session'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.account_deletion_operations as operation
   where operation.user_id = 'c9000000-0000-4000-8000-000000000001'),
  1::bigint,
  'replays never create a second operation for the account'
);
select ok(
  (select deletion_grant.consumed_at is not null
   from gymapp_private.account_deletion_grants as deletion_grant
   where deletion_grant.user_id = 'c9000000-0000-4000-8000-000000000001'),
  'the committed grant is marked consumed'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.account_deletion_operations as operation
   where operation.user_id = 'c9000000-0000-4000-8000-000000000002'),
  0::bigint,
  'A''s commit created no operation for B'
);

-- ---------------------------------------------------------------------------
-- Preparation rate limit (fixed-window budget per account).
-- ---------------------------------------------------------------------------
insert into gymapp_private.edge_preauth_windows (
  route, source_hash, window_started_at, request_count
) values (
  'delete_account',
  pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        'delete_account' || pg_catalog.chr(10) ||
          'account:c9000000-0000-4000-8000-000000000004',
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  ),
  -- A future window cannot roll over mid-test, so the exhausted budget is stable.
  pg_catalog.clock_timestamp() + interval '1 hour',
  12
);

set local role authenticated;
select pg_temp.act_as(
  'c9000000-0000-4000-8000-000000000004',
  'c9100000-0000-4000-8000-000000000004'
);
insert into deletion_results
select 'prepare-e-limited', public.prepare_account_deletion();
select is(
  (select payload from deletion_results where case_name = 'prepare-e-limited'),
  '{"version":1,"error":"rate_limited","retryAfter":60}'::jsonb,
  'an exhausted preparation budget returns the rate_limited body without a grant'
);
reset role;
select is(
  (select pg_catalog.count(*)
   from gymapp_private.account_deletion_grants as deletion_grant
   where deletion_grant.user_id = 'c9000000-0000-4000-8000-000000000004'),
  0::bigint,
  'a rate-limited preparation creates no grant'
);

-- ---------------------------------------------------------------------------
-- Hard delete (what the Edge Function does after the commit): the account's own
-- rows cascade away and B's rows are untouched.
-- ---------------------------------------------------------------------------
delete from auth.users
where id = 'c9000000-0000-4000-8000-000000000001';

select is(
  (select pg_catalog.count(*)
   from gymapp_private.account_deletion_operations as operation
   where operation.user_id = 'c9000000-0000-4000-8000-000000000001')
  + (select pg_catalog.count(*)
     from gymapp_private.account_deletion_grants as deletion_grant
     where deletion_grant.user_id = 'c9000000-0000-4000-8000-000000000001')
  + (select pg_catalog.count(*)
     from public.profiles as profile
     where profile.user_id = 'c9000000-0000-4000-8000-000000000001'),
  0::bigint,
  'deleting the auth user cascades the deletion journal, grants and profile'
);
select is(
  (select pg_catalog.count(*)
   from public.profiles as profile
   where profile.user_id = 'c9000000-0000-4000-8000-000000000002'),
  1::bigint,
  'deleting A leaves B''s profile in place'
);
select is(
  (select pg_catalog.count(*)
   from gymapp_private.account_deletion_grants as deletion_grant
   where deletion_grant.user_id = 'c9000000-0000-4000-8000-000000000002'),
  1::bigint,
  'deleting A leaves B''s pending grant in place'
);

select * from finish();

rollback;
