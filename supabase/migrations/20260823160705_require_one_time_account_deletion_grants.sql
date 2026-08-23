begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create table gymapp_private.account_deletion_grants (
  grant_hash bytea primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references auth.sessions(id) on delete cascade,
  purpose text not null check (purpose = 'delete_account'),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default pg_catalog.clock_timestamp()
);

create index account_deletion_grants_owner_expiry_idx
  on gymapp_private.account_deletion_grants (user_id, expires_at);

alter table gymapp_private.account_deletion_grants enable row level security;
revoke all on table gymapp_private.account_deletion_grants
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.current_password_auth_is_recent(
  p_maximum_age interval default interval '5 minutes'
)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $function$
  select p_maximum_age between interval '1 minute' and interval '10 minutes'
    and exists (
      select 1
      from pg_catalog.jsonb_array_elements(
        case
          when pg_catalog.jsonb_typeof(auth.jwt()->'amr') = 'array'
            then auth.jwt()->'amr'
          else '[]'::jsonb
        end
      ) as method(value)
      where method.value->>'method' = 'password'
        and method.value->>'timestamp' ~ '^[0-9]{1,12}$'
        and pg_catalog.to_timestamp((method.value->>'timestamp')::double precision)
          > pg_catalog.clock_timestamp() - p_maximum_age
        and pg_catalog.to_timestamp((method.value->>'timestamp')::double precision)
          <= pg_catalog.clock_timestamp() + interval '1 minute'
    )
$function$;

revoke all on function gymapp_private.current_password_auth_is_recent(interval)
  from public, anon, authenticated, service_role;

create or replace function public.prepare_account_deletion()
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
  raw_grant uuid := pg_catalog.gen_random_uuid();
  expiry timestamptz := pg_catalog.clock_timestamp() + interval '5 minutes';
begin
  if caller_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or not gymapp_private.current_password_auth_is_recent(interval '5 minutes') then
    raise exception using errcode = '42501', message = 'Recent password authentication is required.';
  end if;
  caller_session_id := session_id_text::uuid;

  perform 1
  from auth.sessions as session
  where session.id = caller_session_id
    and session.user_id = caller_user_id
    and (
      session.not_after is null
      or session.not_after > pg_catalog.clock_timestamp()
    )
  for key share;
  if not found then
    raise exception using errcode = '42501', message = 'A current authenticated session is required.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gymapp-account-deletion:' || caller_user_id::text, 0)
  );
  delete from gymapp_private.account_deletion_grants as grant_row
  where grant_row.user_id = caller_user_id
    and (
      grant_row.expires_at <= pg_catalog.clock_timestamp()
      or grant_row.consumed_at is not null
      or grant_row.session_id <> caller_session_id
    );
  insert into gymapp_private.account_deletion_grants (
    grant_hash, user_id, session_id, purpose, expires_at
  ) values (
    extensions.digest(
      pg_catalog.convert_to(raw_grant::text, 'UTF8'),
      'sha256'
    ),
    caller_user_id,
    caller_session_id,
    'delete_account',
    expiry
  );

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'grant', raw_grant::text,
    'expiresAt', expiry
  );
end
$function$;

create or replace function public.consume_account_deletion_grant(p_grant text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  session_id_text text := auth.jwt() ->> 'session_id';
  caller_session_id uuid;
  grant_row gymapp_private.account_deletion_grants%rowtype;
begin
  if caller_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or p_grant is null
     or p_grant !~* '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception using errcode = '42501', message = 'Account deletion authorization is invalid.';
  end if;
  caller_session_id := session_id_text::uuid;

  perform 1
  from auth.sessions as session
  where session.id = caller_session_id
    and session.user_id = caller_user_id
    and (
      session.not_after is null
      or session.not_after > pg_catalog.clock_timestamp()
    )
  for key share;
  if not found then
    raise exception using errcode = '42501', message = 'A current authenticated session is required.';
  end if;

  select grant_value.*
  into grant_row
  from gymapp_private.account_deletion_grants as grant_value
  where grant_value.grant_hash = extensions.digest(
      pg_catalog.convert_to(pg_catalog.lower(p_grant), 'UTF8'),
      'sha256'
    )
    and grant_value.user_id = caller_user_id
    and grant_value.session_id = caller_session_id
    and grant_value.purpose = 'delete_account'
    and grant_value.expires_at > pg_catalog.clock_timestamp()
    and grant_value.consumed_at is null
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Account deletion authorization is invalid.';
  end if;

  update gymapp_private.account_deletion_grants as grant_value
  set consumed_at = pg_catalog.clock_timestamp()
  where grant_value.grant_hash = grant_row.grant_hash
    and grant_value.consumed_at is null;
  if not found then
    raise exception using errcode = '42501', message = 'Account deletion authorization is invalid.';
  end if;
  return caller_user_id;
end
$function$;

revoke all on function public.prepare_account_deletion()
  from public, anon, authenticated, service_role;
revoke all on function public.consume_account_deletion_grant(text)
  from public, anon, authenticated, service_role;
grant execute on function public.prepare_account_deletion()
  to authenticated;
grant execute on function public.consume_account_deletion_grant(text)
  to authenticated;

comment on function public.prepare_account_deletion() is
  'Issues a five-minute single-use deletion capability after recent password authentication.';
comment on function public.consume_account_deletion_grant(text) is
  'Atomically consumes an exact user/session/delete_account capability before administrative deletion.';

notify pgrst, 'reload schema';

commit;
