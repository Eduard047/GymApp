begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regclass('auth.sessions') is null
     or pg_catalog.to_regclass('gymapp_private.notification_installations') is null
     or pg_catalog.to_regclass('gymapp_private.push_outbox') is null
     or pg_catalog.to_regclass('gymapp_private.push_outbox_deliveries') is null
     or pg_catalog.to_regprocedure(
       'public.notification_register_installation(uuid,text,text,text,text,text,text,text,text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.push_claim_deliveries(uuid,integer,integer)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.push_delivery_is_current(uuid,uuid)'
     ) is null then
    raise exception 'GymApp session-bound push prerequisites are missing.';
  end if;

  if pg_catalog.to_regprocedure(
       'gymapp_private.notification_register_installation_storage_v1(uuid,text,text,text,text,text,text,text,text)'
     ) is not null
     or pg_catalog.to_regprocedure(
       'gymapp_private.push_claim_deliveries_storage_v1(uuid,integer,integer)'
     ) is not null then
    raise exception 'GymApp session-bound push storage functions already exist.';
  end if;
end
$preflight$;

alter table gymapp_private.notification_installations
  add column auth_session_id uuid;

alter table gymapp_private.notification_installations
  add constraint notification_installations_auth_session_fkey
  foreign key (auth_session_id)
  references auth.sessions(id)
  on delete set null
  not valid;

alter table gymapp_private.notification_installations
  validate constraint notification_installations_auth_session_fkey;

create index notification_installations_auth_session_idx
  on gymapp_private.notification_installations (auth_session_id, id)
  where auth_session_id is not null;

comment on column gymapp_private.notification_installations.auth_session_id is
  'Exact Supabase Auth session that most recently registered this private provider address. NULL is never eligible for claim or send.';

create or replace function gymapp_private.notification_auth_session_is_current(
  p_user_id uuid,
  p_session_id uuid
)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $function$
  select p_user_id is not null
    and p_session_id is not null
    and exists (
      select 1
      from auth.sessions as session
      where session.id = p_session_id
        and session.user_id = p_user_id
        and (
          session.not_after is null
          or session.not_after > pg_catalog.clock_timestamp()
        )
    )
$function$;

revoke all on function gymapp_private.notification_auth_session_is_current(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.notification_require_current_auth_session_id(
  p_user_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  session_id_text text := auth.jwt() ->> 'session_id';
  current_session_id uuid;
begin
  if p_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;

  select session.id into current_session_id
  from auth.sessions as session
  where session.id = session_id_text::uuid
    and session.user_id = p_user_id
    and (
      session.not_after is null
      or session.not_after > pg_catalog.clock_timestamp()
    )
  for key share;

  return current_session_id;
end
$function$;

revoke all on function gymapp_private.notification_require_current_auth_session_id(uuid)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.notification_installation_session_guard()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  expected_session_text text := pg_catalog.current_setting(
    'gymapp.notification_registration_session_id',
    true
  );
  current_session_id uuid;
  request_time timestamptz := pg_catalog.clock_timestamp();
begin
  -- Every revocation path (explicit revoke, provider invalidation, account/token
  -- rebind, age cleanup) also drops the session reference. Provider material is
  -- already required to be NULL by the table's revocation constraint.
  if new.revoked_at is not null then
    new.auth_session_id := null;
    return new;
  end if;

  if expected_session_text is not null and expected_session_text <> '' then
    current_session_id := gymapp_private.notification_require_current_auth_session_id(
      new.user_id
    );
    if current_session_id is null
       or current_session_id::text <> expected_session_text then
      raise exception using
        errcode = '42501',
        message = 'A current authenticated session is required.';
    end if;

    if tg_op = 'UPDATE'
       and old.auth_session_id is distinct from current_session_id then
      if new.revision = old.revision and old.revision >= 2147483647 then
        raise exception using
          errcode = '54000',
          message = 'Notification registration cannot be updated.';
      end if;
      if new.binding_id is not distinct from old.binding_id then
        new.binding_id := pg_catalog.gen_random_uuid();
      end if;
      if new.revision = old.revision then
        new.revision := old.revision + 1;
      end if;
    end if;

    new.auth_session_id := current_session_id;
    return new;
  end if;

  -- auth.sessions deletion executes the FK's SET NULL update without an app
  -- JWT. Convert that transition into an immediate fail-closed revocation so a
  -- concurrent claim cannot observe an active address without a live session.
  if tg_op = 'UPDATE'
     and old.auth_session_id is not null
     and new.auth_session_id is null then
    new.provider_token := null;
    new.web_push_p256dh := null;
    new.web_push_auth := null;
    new.binding_id := pg_catalog.gen_random_uuid();
    new.revoked_at := request_time;
    new.updated_at := request_time;
    new.revision := least(old.revision + 1, 2147483647);
    return new;
  end if;

  -- The relation has no client/table grants. Still reject accidental new active
  -- private rows unless trusted internal SQL supplies a live exact session.
  if new.auth_session_id is null
     or not gymapp_private.notification_auth_session_is_current(
       new.user_id,
       new.auth_session_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'A current authenticated session is required.';
  end if;

  return new;
end
$function$;

revoke all on function gymapp_private.notification_installation_session_guard()
  from public, anon, authenticated, service_role;

create trigger notification_installations_session_guard
before insert or update on gymapp_private.notification_installations
for each row execute function gymapp_private.notification_installation_session_guard();

-- Pre-migration rows cannot be assigned to a particular login safely. Scrub a
-- bounded first batch now; the claim wrapper below fail-closes and retires any
-- bounded remainder before provider material can leave Postgres.
with legacy_unbound as (
  select installation.id
  from gymapp_private.notification_installations as installation
  where installation.revoked_at is null
    and installation.auth_session_id is null
  order by installation.last_seen_at, installation.id
  for update skip locked
  limit 500
)
update gymapp_private.notification_installations as installation
set provider_token = null,
    web_push_p256dh = null,
    web_push_auth = null,
    binding_id = pg_catalog.gen_random_uuid(),
    revoked_at = pg_catalog.clock_timestamp(),
    updated_at = pg_catalog.clock_timestamp(),
    revision = least(installation.revision + 1, 2147483647)
from legacy_unbound
where installation.id = legacy_unbound.id;

-- Keep the original, already-deployed implementation private as the bounded
-- storage worker. The public wrapper below preserves the exact RPC signature
-- while binding every successful active insert/upsert to the signed JWT session.
alter function public.notification_register_installation(
  uuid, text, text, text, text, text, text, text, text
) set schema gymapp_private;
alter function gymapp_private.notification_register_installation(
  uuid, text, text, text, text, text, text, text, text
) rename to notification_register_installation_storage_v1;
revoke all on function gymapp_private.notification_register_installation_storage_v1(
  uuid, text, text, text, text, text, text, text, text
) from public, anon, authenticated, service_role;

create function public.notification_register_installation(
  p_installation_id uuid,
  p_platform text,
  p_provider text,
  p_environment text,
  p_provider_token text,
  p_web_push_p256dh text default null,
  p_web_push_auth text default null,
  p_locale text default null,
  p_app_version text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  caller_session_id uuid;
  previous_session_setting text := pg_catalog.current_setting(
    'gymapp.notification_registration_session_id',
    true
  );
  result jsonb;
begin
  caller_session_id := gymapp_private.notification_require_current_auth_session_id(
    caller_user_id
  );
  if caller_user_id is null or caller_session_id is null then
    raise exception using
      errcode = '42501',
      message = 'A current authenticated session is required.';
  end if;

  perform pg_catalog.set_config(
    'gymapp.notification_registration_session_id',
    caller_session_id::text,
    true
  );
  begin
    result := gymapp_private.notification_register_installation_storage_v1(
      p_installation_id,
      p_platform,
      p_provider,
      p_environment,
      p_provider_token,
      p_web_push_p256dh,
      p_web_push_auth,
      p_locale,
      p_app_version
    );
  exception
    when others then
      perform pg_catalog.set_config(
        'gymapp.notification_registration_session_id',
        coalesce(previous_session_setting, ''),
        true
      );
      raise;
  end;
  perform pg_catalog.set_config(
    'gymapp.notification_registration_session_id',
    coalesce(previous_session_setting, ''),
    true
  );
  return result;
end
$function$;

revoke all on function public.notification_register_installation(
  uuid, text, text, text, text, text, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.notification_register_installation(
  uuid, text, text, text, text, text, text, text, text
) to authenticated;

create or replace function gymapp_private.push_delivery_session_is_current(
  p_delivery_id uuid,
  p_lease_token uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  delivery_is_current boolean := false;
begin
  if p_delivery_id is null or p_lease_token is null then
    return false;
  end if;

  select true into delivery_is_current
  from gymapp_private.push_outbox_deliveries as delivery
  join gymapp_private.push_outbox as outbox
    on outbox.id = delivery.outbox_id
  join gymapp_private.notification_installations as installation
    on installation.id = delivery.installation_id
  join auth.sessions as session
    on session.id = installation.auth_session_id
   and session.user_id = installation.user_id
  where delivery.id = p_delivery_id
    and delivery.status = 'processing'
    and delivery.lease_token = p_lease_token
    and delivery.lease_expires_at > pg_catalog.clock_timestamp()
    and outbox.status = 'pending'
    and outbox.expires_at > pg_catalog.clock_timestamp()
    and installation.revoked_at is null
    and installation.user_id = outbox.recipient_user_id
    and installation.revision = delivery.installation_revision
    and (
      session.not_after is null
      or session.not_after > pg_catalog.clock_timestamp()
    )
  for key share of session;

  return coalesce(delivery_is_current, false);
end
$function$;

revoke all on function gymapp_private.push_delivery_session_is_current(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Preserve the public claim signature and the deployed queue implementation,
-- but keep its result inside Postgres until every claimed row passes the exact
-- session check. Invalid legacy/expired-session rows are retired in a batch
-- bounded by p_limit (which the storage function caps at 100).
alter function public.push_claim_deliveries(uuid, integer, integer)
  set schema gymapp_private;
alter function gymapp_private.push_claim_deliveries(uuid, integer, integer)
  rename to push_claim_deliveries_storage_v1;
revoke all on function gymapp_private.push_claim_deliveries_storage_v1(
  uuid, integer, integer
) from public, anon, authenticated, service_role;

create function public.push_claim_deliveries(
  p_worker_id uuid,
  p_limit integer default 25,
  p_lease_seconds integer default 45
)
returns table (
  delivery_id uuid,
  lease_token uuid,
  outbox_id uuid,
  event_type text,
  object_id text,
  object_revision bigint,
  collapse_key text,
  priority text,
  expires_at timestamptz,
  provider text,
  environment text,
  binding_id uuid,
  provider_token text,
  web_push_p256dh text,
  web_push_auth text,
  locale text,
  attempt_count integer
)
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  claimed_row record;
  invalid_outbox_id uuid;
  invalid_error_code text;
  request_time timestamptz := pg_catalog.clock_timestamp();
begin
  if p_worker_id is null
     or p_limit is null
     or p_lease_seconds is null
     or p_limit not between 1 and 100
     or p_lease_seconds not between 15 and 300 then
    raise exception using
      errcode = '22023',
      message = 'Push claim request is invalid.';
  end if;

  -- Every dispatcher run retires at most 500 legacy, deleted-session, or
  -- time-box-expired registrations even when no notification currently targets
  -- them. Claim/current checks below remain fail-closed for any bounded remainder.
  with invalid_session_installations as (
    select installation.id
    from gymapp_private.notification_installations as installation
    where installation.revoked_at is null
      and (
        installation.auth_session_id is null
        or not exists (
          select 1
          from auth.sessions as session
          where session.id = installation.auth_session_id
            and session.user_id = installation.user_id
            and (
              session.not_after is null
              or session.not_after > request_time
            )
        )
      )
    order by installation.last_seen_at, installation.id
    for update of installation skip locked
    limit 500
  )
  update gymapp_private.notification_installations as installation
  set provider_token = null,
      web_push_p256dh = null,
      web_push_auth = null,
      binding_id = pg_catalog.gen_random_uuid(),
      revoked_at = request_time,
      updated_at = request_time,
      revision = least(installation.revision + 1, 2147483647)
  from invalid_session_installations
  where installation.id = invalid_session_installations.id;

  for claimed_row in
    select *
    from gymapp_private.push_claim_deliveries_storage_v1(
      p_worker_id,
      p_limit,
      p_lease_seconds
    )
  loop
    if gymapp_private.push_delivery_session_is_current(
      claimed_row.delivery_id,
      claimed_row.lease_token
    ) then
      return query select
        claimed_row.delivery_id::uuid,
        claimed_row.lease_token::uuid,
        claimed_row.outbox_id::uuid,
        claimed_row.event_type::text,
        claimed_row.object_id::text,
        claimed_row.object_revision::bigint,
        claimed_row.collapse_key::text,
        claimed_row.priority::text,
        claimed_row.expires_at::timestamptz,
        claimed_row.provider::text,
        claimed_row.environment::text,
        claimed_row.binding_id::uuid,
        claimed_row.provider_token::text,
        claimed_row.web_push_p256dh::text,
        claimed_row.web_push_auth::text,
        claimed_row.locale::text,
        claimed_row.attempt_count::integer;
      continue;
    end if;

    request_time := pg_catalog.clock_timestamp();
    invalid_outbox_id := null;
    invalid_error_code := null;

    select delivery.outbox_id,
           case
             when installation.revoked_at is not null then 'registration_revoked'
             when installation.revision <> delivery.installation_revision
               then 'registration_superseded'
             when not gymapp_private.notification_auth_session_is_current(
               installation.user_id,
               installation.auth_session_id
             ) then 'registration_session_revoked'
             else 'registration_superseded'
           end
    into invalid_outbox_id, invalid_error_code
    from gymapp_private.push_outbox_deliveries as delivery
    join gymapp_private.notification_installations as installation
      on installation.id = delivery.installation_id
    where delivery.id = claimed_row.delivery_id
      and delivery.status = 'processing'
      and delivery.lease_token = claimed_row.lease_token
    for update of delivery, installation;

    if not found then
      continue;
    end if;

    update gymapp_private.notification_installations as installation
    set provider_token = null,
        web_push_p256dh = null,
        web_push_auth = null,
        binding_id = pg_catalog.gen_random_uuid(),
        revoked_at = request_time,
        updated_at = request_time,
        revision = least(installation.revision + 1, 2147483647)
    from gymapp_private.push_outbox_deliveries as delivery
    where delivery.id = claimed_row.delivery_id
      and delivery.installation_id = installation.id
      and installation.revoked_at is null
      and installation.revision = delivery.installation_revision
      and not gymapp_private.notification_auth_session_is_current(
        installation.user_id,
        installation.auth_session_id
      );

    update gymapp_private.push_outbox_deliveries as delivery
    set status = 'invalid',
        lease_owner = null,
        lease_token = null,
        lease_expires_at = null,
        error_code = invalid_error_code,
        updated_at = request_time
    where delivery.id = claimed_row.delivery_id
      and delivery.status = 'processing'
      and delivery.lease_token = claimed_row.lease_token;

    perform gymapp_private.reconcile_push_outbox(invalid_outbox_id);
  end loop;
end
$function$;

revoke all on function public.push_claim_deliveries(uuid, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.push_claim_deliveries(uuid, integer, integer)
  to service_role;

create or replace function public.push_delivery_is_current(
  p_delivery_id uuid,
  p_lease_token uuid
)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $function$
  select gymapp_private.push_delivery_session_is_current(
    p_delivery_id,
    p_lease_token
  )
$function$;

revoke all on function public.push_delivery_is_current(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.push_delivery_is_current(uuid, uuid)
  to service_role;

do $verify$
begin
  if not exists (
    select 1
    from pg_catalog.pg_attribute as attribute
    where attribute.attrelid = 'gymapp_private.notification_installations'::pg_catalog.regclass
      and attribute.attname = 'auth_session_id'
      and attribute.atttypid = 'uuid'::pg_catalog.regtype
      and not attribute.attisdropped
  )
     or pg_catalog.to_regclass(
       'gymapp_private.notification_installations_auth_session_idx'
     ) is null
     or not exists (
       select 1
       from pg_catalog.pg_constraint as constraint_record
       where constraint_record.conrelid =
         'gymapp_private.notification_installations'::pg_catalog.regclass
         and constraint_record.conname = 'notification_installations_auth_session_fkey'
         and constraint_record.contype = 'f'
         and constraint_record.confrelid = 'auth.sessions'::pg_catalog.regclass
         and constraint_record.confdeltype = 'n'
         and constraint_record.convalidated
     ) then
    raise exception 'Notification installation Auth-session binding is incomplete.';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgrelid =
      'gymapp_private.notification_installations'::pg_catalog.regclass
      and trigger_record.tgname = 'notification_installations_session_guard'
      and not trigger_record.tgisinternal
      and trigger_record.tgenabled <> 'D'
  ) then
    raise exception 'Notification installation session guard is missing.';
  end if;

  if not (
    select relation.relrowsecurity
    from pg_catalog.pg_class as relation
    where relation.oid = 'gymapp_private.notification_installations'::pg_catalog.regclass
  )
     or pg_catalog.has_table_privilege(
       'anon',
       'gymapp_private.notification_installations',
       'SELECT,INSERT,UPDATE,DELETE'
     )
     or pg_catalog.has_table_privilege(
       'authenticated',
       'gymapp_private.notification_installations',
       'SELECT,INSERT,UPDATE,DELETE'
     )
     or pg_catalog.has_table_privilege(
       'service_role',
       'gymapp_private.notification_installations',
       'SELECT,INSERT,UPDATE,DELETE'
     ) then
    raise exception 'Notification installation relation is not deny-by-default.';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated',
       'public.notification_register_installation(uuid,text,text,text,text,text,text,text,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.notification_register_installation(uuid,text,text,text,text,text,text,text,text)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.push_claim_deliveries(uuid,integer,integer)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.push_claim_deliveries(uuid,integer,integer)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.push_delivery_is_current(uuid,uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.push_delivery_is_current(uuid,uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'gymapp_private.notification_register_installation_storage_v1(uuid,text,text,text,text,text,text,text,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'gymapp_private.push_claim_deliveries_storage_v1(uuid,integer,integer)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'gymapp_private.push_delivery_session_is_current(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'Session-bound push grants are broader or narrower than intended.';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
