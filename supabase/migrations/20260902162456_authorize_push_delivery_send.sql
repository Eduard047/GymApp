begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regclass('auth.sessions') is null
     or pg_catalog.to_regclass(
       'gymapp_private.notification_installations'
     ) is null
     or pg_catalog.to_regclass('gymapp_private.push_outbox') is null
     or pg_catalog.to_regclass(
       'gymapp_private.push_outbox_deliveries'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.push_delivery_is_current(uuid,uuid)'
     ) is null then
    raise exception 'GymApp push send-authorization prerequisites are missing.';
  end if;
  if pg_catalog.to_regprocedure(
       'public.push_authorize_delivery_send(uuid,uuid)'
     ) is not null then
    raise exception 'GymApp push send authorization already exists.';
  end if;
end
$preflight$;

alter table gymapp_private.push_outbox_deliveries
  add column send_authorized_at timestamptz,
  add column send_authorized_lease_token uuid;

comment on column gymapp_private.push_outbox_deliveries.send_authorized_at is
  'Commit time of the one provider-send authorization for the current delivery lease. A later Auth-session revocation cannot cancel this already-committed external side effect.';
comment on column gymapp_private.push_outbox_deliveries.send_authorized_lease_token is
  'Exact lease fenced by send_authorized_at; it is never a provider credential and is cleared on every lease/status transition.';

create or replace function gymapp_private.clear_push_send_authorization()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if new.status <> 'processing'
     or new.lease_token is null
     or new.lease_token is distinct from old.lease_token then
    new.send_authorized_at := null;
    new.send_authorized_lease_token := null;
  elsif new.send_authorized_at is null then
    new.send_authorized_lease_token := null;
  elsif new.send_authorized_lease_token is distinct from new.lease_token then
    raise exception using
      errcode = '23514',
      message = 'Push send authorization does not match its lease.';
  end if;
  return new;
end
$function$;

revoke all on function gymapp_private.clear_push_send_authorization()
  from public, anon, authenticated, service_role;

create trigger push_outbox_deliveries_send_authorization_guard
before update on gymapp_private.push_outbox_deliveries
for each row execute function gymapp_private.clear_push_send_authorization();

alter table gymapp_private.push_outbox_deliveries
  add constraint push_outbox_deliveries_send_authorization_check check (
    (
      send_authorized_at is null
      and send_authorized_lease_token is null
    )
    or (
      status = 'processing'
      and lease_token is not null
      and send_authorized_lease_token = lease_token
      and send_authorized_at <= lease_expires_at
    )
  );

create or replace function gymapp_private.authorize_push_delivery_send(
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
  installation_user_id uuid;
  installation_session_id uuid;
  delivery_is_current boolean := false;
  request_time timestamptz := pg_catalog.clock_timestamp();
begin
  if p_delivery_id is null or p_lease_token is null then
    return false;
  end if;

  -- Resolve only identifiers first. No provider address or payload is copied,
  -- and every mutable predicate is rechecked after the session lock below.
  select installation.user_id, installation.auth_session_id
  into installation_user_id, installation_session_id
  from gymapp_private.push_outbox_deliveries as delivery
  join gymapp_private.notification_installations as installation
    on installation.id = delivery.installation_id
  where delivery.id = p_delivery_id
    and delivery.status = 'processing'
    and delivery.lease_token = p_lease_token;
  if not found or installation_session_id is null then
    return false;
  end if;

  -- Lock the Auth session first. A revocation/delete that commits first makes
  -- this fail after waiting. If this lock wins, the authorization row commits
  -- first and exactly one already-authorized minimal notification may finish.
  perform 1
  from auth.sessions as session
  where session.id = installation_session_id
    and session.user_id = installation_user_id
    and (
      session.not_after is null
      or session.not_after > request_time
    )
  for share;
  if not found then
    return false;
  end if;

  request_time := pg_catalog.clock_timestamp();

  select true into delivery_is_current
  from gymapp_private.push_outbox_deliveries as delivery
  join gymapp_private.push_outbox as outbox
    on outbox.id = delivery.outbox_id
  join gymapp_private.notification_installations as installation
    on installation.id = delivery.installation_id
  where delivery.id = p_delivery_id
    and delivery.status = 'processing'
    and delivery.lease_token = p_lease_token
    and delivery.lease_expires_at > request_time
    and outbox.status = 'pending'
    and outbox.expires_at > request_time
    and installation.revoked_at is null
    and installation.user_id = installation_user_id
    and installation.user_id = outbox.recipient_user_id
    and installation.auth_session_id = installation_session_id
    and installation.revision = delivery.installation_revision
  for update of delivery, outbox, installation;
  if not coalesce(delivery_is_current, false) then
    return false;
  end if;

  request_time := pg_catalog.clock_timestamp();
  perform 1
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
    and delivery.lease_expires_at > request_time
    and outbox.status = 'pending'
    and outbox.expires_at > request_time
    and installation.revoked_at is null
    and installation.user_id = installation_user_id
    and installation.user_id = outbox.recipient_user_id
    and installation.auth_session_id = installation_session_id
    and installation.revision = delivery.installation_revision
    and session.id = installation_session_id
    and session.user_id = installation_user_id
    and (
      session.not_after is null
      or session.not_after > request_time
    );
  if not found then
    return false;
  end if;

  update gymapp_private.push_outbox_deliveries as delivery
  set send_authorized_at = coalesce(
        delivery.send_authorized_at,
        request_time
      ),
      send_authorized_lease_token = p_lease_token,
      updated_at = request_time
  where delivery.id = p_delivery_id
    and delivery.status = 'processing'
    and delivery.lease_token = p_lease_token
    and delivery.lease_expires_at > request_time
    and (
      delivery.send_authorized_at is null
      or delivery.send_authorized_lease_token = p_lease_token
    );
  return found;
end
$function$;

revoke all on function gymapp_private.authorize_push_delivery_send(uuid, uuid)
  from public, anon, authenticated, service_role;

create function public.push_authorize_delivery_send(
  p_delivery_id uuid,
  p_lease_token uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if auth.role() is distinct from 'service_role' then
    return false;
  end if;
  return gymapp_private.authorize_push_delivery_send(
    p_delivery_id,
    p_lease_token
  );
end
$function$;

revoke all on function public.push_authorize_delivery_send(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.push_authorize_delivery_send(uuid, uuid)
  to service_role;

-- Mixed-version safety: an older dispatcher still calls this established RPC
-- immediately before its provider request. Make that call the same atomic
-- authorization so the migration is safe before the new Edge bundle lands.
create or replace function public.push_delivery_is_current(
  p_delivery_id uuid,
  p_lease_token uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if auth.role() is distinct from 'service_role' then
    return false;
  end if;
  return gymapp_private.authorize_push_delivery_send(
    p_delivery_id,
    p_lease_token
  );
end
$function$;

revoke all on function public.push_delivery_is_current(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.push_delivery_is_current(uuid, uuid)
  to service_role;

comment on function public.push_authorize_delivery_send(uuid, uuid) is
  'Atomically fences one provider send to the exact live Auth session, installation revision, outbox state, and unexpired delivery lease.';
comment on function public.push_delivery_is_current(uuid, uuid) is
  'Compatibility alias that atomically authorizes the current delivery lease before provider I/O.';

do $verify$
declare
  authorization_source text;
  compatibility_source text;
begin
  select procedure.prosrc into strict authorization_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'gymapp_private.authorize_push_delivery_send(uuid,uuid)'
  );
  select procedure.prosrc into strict compatibility_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'public.push_delivery_is_current(uuid,uuid)'
  );

  if pg_catalog.strpos(pg_catalog.lower(authorization_source), 'for share') = 0
     or pg_catalog.strpos(
       pg_catalog.lower(authorization_source),
       'send_authorized_at'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(compatibility_source),
       'authorize_push_delivery_send'
     ) = 0
     or pg_catalog.has_function_privilege(
       'anon',
       'public.push_authorize_delivery_send(uuid,uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.push_authorize_delivery_send(uuid,uuid)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.push_authorize_delivery_send(uuid,uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'gymapp_private.authorize_push_delivery_send(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'GymApp push send-authorization verification failed.';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
