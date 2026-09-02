begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regclass('auth.users') is null
     or pg_catalog.to_regclass('auth.sessions') is null
     or pg_catalog.to_regclass(
       'gymapp_private.account_deletion_grants'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.consume_account_deletion_grant(text)'
     ) is null then
    raise exception 'GymApp account-deletion commit prerequisites are missing.';
  end if;
  if pg_catalog.to_regclass(
       'gymapp_private.account_deletion_operations'
     ) is not null
     or pg_catalog.to_regprocedure(
       'gymapp_private.commit_account_deletion_operation(text)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'public.commit_account_deletion_operation(text)'
     ) is not null then
    raise exception 'GymApp account-deletion operation journal already exists.';
  end if;
end
$preflight$;

create table gymapp_private.account_deletion_operations (
  operation_id uuid primary key default pg_catalog.gen_random_uuid(),
  grant_hash bytea not null unique,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  session_id uuid not null,
  status text not null default 'committed' check (status = 'committed'),
  committed_at timestamptz not null default pg_catalog.clock_timestamp()
);

create index account_deletion_operations_session_idx
  on gymapp_private.account_deletion_operations (session_id, operation_id);

alter table gymapp_private.account_deletion_operations enable row level security;
alter table gymapp_private.account_deletion_operations force row level security;
revoke all on table gymapp_private.account_deletion_operations
  from public, anon, authenticated, service_role;

comment on table gymapp_private.account_deletion_operations is
  'Private idempotency journal for the irreversible account-deletion decision. A committed row is the linearization point; revocation that commits first prevents it, while later revocation does not cancel the already-authorized admin delete.';

-- Keep the established UUID-returning public RPC for an older Edge bundle,
-- but put the irreversible decision in one private implementation. The new
-- versioned public RPC exposes the operation proof without breaking a rolling
-- deployment in either direction.
create function gymapp_private.commit_account_deletion_operation(p_grant text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  session_id_text text := auth.jwt() ->> 'session_id';
  caller_session_id uuid;
  requested_grant_hash bytea;
  grant_row gymapp_private.account_deletion_grants%rowtype;
  operation_row gymapp_private.account_deletion_operations%rowtype;
  operation_already_committed boolean := false;
  request_time timestamptz := pg_catalog.clock_timestamp();
begin
  if caller_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or p_grant is null
     or p_grant !~* '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception using
      errcode = '42501',
      message = 'Account deletion authorization is invalid.';
  end if;
  caller_session_id := session_id_text::uuid;
  requested_grant_hash := extensions.digest(
    pg_catalog.convert_to(pg_catalog.lower(p_grant), 'UTF8'),
    'sha256'
  );

  -- This immutable exact lookup is the retry path after the point of no
  -- return. It deliberately precedes the live-session lock so revocation
  -- cannot cancel an operation that already committed.
  select operation.* into operation_row
  from gymapp_private.account_deletion_operations as operation
  where operation.user_id = caller_user_id
    and operation.session_id = caller_session_id
    and operation.grant_hash = requested_grant_hash
    and operation.status = 'committed';
  if found then
    return pg_catalog.jsonb_build_object(
      'version', 2,
      'status', 'committed',
      'userId', caller_user_id,
      'operationId', operation_row.operation_id,
      'committedAt', operation_row.committed_at
    );
  end if;

  -- A new operation must serialize with revocation here. SHARE conflicts with
  -- session deletion and with expiry/revocation updates, so whichever
  -- transaction commits first defines the outcome. Keep the same
  -- session-then-owner-advisory lock order as preparation.
  request_time := pg_catalog.clock_timestamp();
  perform 1
  from auth.sessions as session
  where session.id = caller_session_id
    and session.user_id = caller_user_id
    and (
      session.not_after is null
      or session.not_after > request_time
    )
  for share;
  if not found then
    raise exception using
      errcode = '42501',
      message = 'A current authenticated session is required.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'gymapp-account-deletion:' || caller_user_id::text,
      0
    )
  );

  -- Recheck after serialization so two concurrent exact consumes converge.
  -- A different binding must prove a fresh live-session grant below before it
  -- can rotate the bounded replay binding on this same operation.
  select operation.* into operation_row
  from gymapp_private.account_deletion_operations as operation
  where operation.user_id = caller_user_id
  for update;
  operation_already_committed := found;
  if found then
    if operation_row.session_id = caller_session_id
       and operation_row.grant_hash = requested_grant_hash
       and operation_row.status = 'committed' then
      return pg_catalog.jsonb_build_object(
        'version', 2,
        'status', 'committed',
        'userId', caller_user_id,
        'operationId', operation_row.operation_id,
        'committedAt', operation_row.committed_at
      );
    end if;
    -- Clients deliberately do not persist the raw one-time grant. After an
    -- administrative delete transport/storage failure, a new password-bound
    -- live session may consume its own fresh grant and resume this same
    -- already-committed operation; it can never create a second operation.
  end if;

  select deletion_grant.* into grant_row
  from gymapp_private.account_deletion_grants as deletion_grant
  where deletion_grant.grant_hash = requested_grant_hash
    and deletion_grant.user_id = caller_user_id
    and deletion_grant.session_id = caller_session_id
    and deletion_grant.purpose = 'delete_account'
    and deletion_grant.expires_at > request_time
    and deletion_grant.consumed_at is null
  for update;
  if not found then
    raise exception using
      errcode = '42501',
      message = 'Account deletion authorization is invalid.';
  end if;

  if not operation_already_committed then
    insert into gymapp_private.account_deletion_operations (
      grant_hash,
      user_id,
      session_id,
      status,
      committed_at
    ) values (
      grant_row.grant_hash,
      caller_user_id,
      caller_session_id,
      'committed',
      request_time
    )
    returning * into operation_row;
  end if;

  update gymapp_private.account_deletion_grants as deletion_grant
  set consumed_at = request_time
  where deletion_grant.grant_hash = grant_row.grant_hash
    and deletion_grant.consumed_at is null;
  if not found then
    raise exception using
      errcode = '42501',
      message = 'Account deletion authorization is invalid.';
  end if;

  if operation_already_committed then
    -- Rotate only the bounded replay binding, never the operation identity or
    -- original commit time. This makes the newly consumed recovery grant
    -- idempotent without accumulating attacker-controlled journal rows.
    update gymapp_private.account_deletion_operations as operation
    set grant_hash = grant_row.grant_hash,
        session_id = caller_session_id
    where operation.operation_id = operation_row.operation_id
    returning * into operation_row;
  end if;

  return pg_catalog.jsonb_build_object(
    'version', 2,
    'status', 'committed',
    'userId', caller_user_id,
    'operationId', operation_row.operation_id,
    'committedAt', operation_row.committed_at
  );
end
$function$;

revoke all on function gymapp_private.commit_account_deletion_operation(text)
  from public, anon, authenticated, service_role;

create function public.commit_account_deletion_operation(p_grant text)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $function$
  select gymapp_private.commit_account_deletion_operation(p_grant)
$function$;

revoke all on function public.commit_account_deletion_operation(text)
  from public, anon, authenticated, service_role;
grant execute on function public.commit_account_deletion_operation(text)
  to authenticated;

create or replace function public.consume_account_deletion_grant(p_grant text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  committed_operation jsonb;
begin
  committed_operation :=
    gymapp_private.commit_account_deletion_operation(p_grant);
  if committed_operation ->> 'version' <> '2'
     or committed_operation ->> 'status' <> 'committed'
     or coalesce(committed_operation ->> 'userId', '') !~*
       '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'GymApp account-deletion commit returned an invalid proof.';
  end if;
  return (committed_operation ->> 'userId')::uuid;
end
$function$;

revoke all on function public.consume_account_deletion_grant(text)
  from public, anon, authenticated, service_role;
grant execute on function public.consume_account_deletion_grant(text)
  to authenticated;

comment on function public.commit_account_deletion_operation(text) is
  'Atomically commits and idempotently resumes a version-2 deletion operation for the exact user, Auth session claim, and fresh one-time grant. A new commit requires the live session; an exact committed replay remains non-cancellable.';
comment on function public.consume_account_deletion_grant(text) is
  'Rolling-deploy compatibility RPC returning the caller UUID from the same atomically committed version-2 deletion operation.';

do $verify$
declare
  claim_source text;
  compatibility_source text;
begin
  select procedure.prosrc into strict claim_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'gymapp_private.commit_account_deletion_operation(text)'
  );
  select procedure.prosrc into strict compatibility_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'public.consume_account_deletion_grant(text)'
  );

  if pg_catalog.strpos(pg_catalog.lower(claim_source), 'for share') = 0
     or pg_catalog.strpos(
       pg_catalog.lower(claim_source),
       'account_deletion_operations'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(claim_source),
       '''version'', 2'
     ) = 0
     or not (
       select relation.relrowsecurity and relation.relforcerowsecurity
       from pg_catalog.pg_class as relation
       where relation.oid =
         'gymapp_private.account_deletion_operations'::regclass
     )
     or pg_catalog.strpos(
       pg_catalog.lower(compatibility_source),
       'commit_account_deletion_operation'
     ) = 0
     or pg_catalog.pg_get_function_result(
       'public.consume_account_deletion_grant(text)'::regprocedure
     ) <> 'uuid'
     or pg_catalog.pg_get_function_result(
       'public.commit_account_deletion_operation(text)'::regprocedure
     ) <> 'jsonb'
     or pg_catalog.has_table_privilege(
       'authenticated',
       'gymapp_private.account_deletion_operations',
       'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'service_role',
       'gymapp_private.account_deletion_operations',
       'SELECT'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.consume_account_deletion_grant(text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.commit_account_deletion_operation(text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'public.consume_account_deletion_grant(text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'public.commit_account_deletion_operation(text)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.consume_account_deletion_grant(text)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.commit_account_deletion_operation(text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'gymapp_private.commit_account_deletion_operation(text)',
       'EXECUTE'
     ) then
    raise exception 'GymApp account-deletion commit verification failed.';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
