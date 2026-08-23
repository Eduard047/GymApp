begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regclass('auth.sessions') is null
     or pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regclass('public.user_states') is null
     or pg_catalog.to_regclass('public.garmin_devices') is null
     or pg_catalog.to_regclass('public.garmin_plans') is null
     or pg_catalog.to_regclass('gymapp_private.notification_installations') is null
     or pg_catalog.to_regprocedure(
       'public.social_live_gateway_debit(uuid,uuid,text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'public.notification_register_installation(uuid,text,text,text,text,text,text,text,text)'
     ) is null then
    raise exception 'GymApp session and push hardening prerequisites are missing.';
  end if;
end
$preflight$;

-- This is the single authenticated-table predicate. The key-share lock keeps
-- session deletion/revocation ordered against the owner statement so a write
-- cannot commit after the exact Auth session has been removed.
create or replace function gymapp_private.current_auth_session_is_live()
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  session_id_text text := auth.jwt() ->> 'session_id';
begin
  if caller_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;

  perform 1
  from auth.sessions as session
  where session.id = session_id_text::uuid
    and session.user_id = caller_user_id
    and (
      session.not_after is null
      or session.not_after > pg_catalog.clock_timestamp()
    )
  for key share;
  return found;
end
$function$;

revoke all on function gymapp_private.current_auth_session_is_live()
  from public, anon, authenticated, service_role;
grant execute on function gymapp_private.current_auth_session_is_live()
  to authenticated;

drop policy if exists "Users can read own profile" on public.profiles;
drop policy if exists "Users can insert own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can read own profile"
on public.profiles for select to authenticated
using (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
);
create policy "Users can insert own profile"
on public.profiles for insert to authenticated
with check (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
);
create policy "Users can update own profile"
on public.profiles for update to authenticated
using (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
)
with check (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
);

drop policy if exists "Users can read own state" on public.user_states;
drop policy if exists "Users can insert own state" on public.user_states;
drop policy if exists "Users can update own state" on public.user_states;
create policy "Users can read own state"
on public.user_states for select to authenticated
using (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
);
create policy "Users can insert own state"
on public.user_states for insert to authenticated
with check (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
);
create policy "Users can update own state"
on public.user_states for update to authenticated
using (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
)
with check (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
);

drop policy if exists "Users can read own Garmin devices" on public.garmin_devices;
drop policy if exists "Users can insert own Garmin devices" on public.garmin_devices;
drop policy if exists "Users can update own Garmin devices" on public.garmin_devices;
create policy "Users can read own Garmin devices"
on public.garmin_devices for select to authenticated
using (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
);
create policy "Users can insert own Garmin devices"
on public.garmin_devices for insert to authenticated
with check (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
);
create policy "Users can update own Garmin devices"
on public.garmin_devices for update to authenticated
using (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
)
with check (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
);

drop policy if exists "Users can read own Garmin plans" on public.garmin_plans;
drop policy if exists "Users can insert own Garmin plans" on public.garmin_plans;
drop policy if exists "Users can update own Garmin plans" on public.garmin_plans;
create policy "Users can read own Garmin plans"
on public.garmin_plans for select to authenticated
using (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
);
create policy "Users can insert own Garmin plans"
on public.garmin_plans for insert to authenticated
with check (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
);
create policy "Users can update own Garmin plans"
on public.garmin_plans for update to authenticated
using (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
)
with check (
  (select auth.uid()) = user_id
  and (select gymapp_private.current_auth_session_is_live())
);

create or replace function gymapp_private.live_gateway_require_session(
  p_caller_user_id uuid,
  p_session_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if p_caller_user_id is null or p_session_id is null then
    raise exception using errcode = '42501', message = 'A current authenticated session is required.';
  end if;

  perform 1
  from auth.sessions as session
  where session.id = p_session_id
    and session.user_id = p_caller_user_id
    and (
      session.not_after is null
      or session.not_after > pg_catalog.clock_timestamp()
    )
  for key share;
  if not found then
    raise exception using errcode = '42501', message = 'A current authenticated session is required.';
  end if;
end
$function$;

revoke all on function gymapp_private.live_gateway_require_session(uuid, uuid)
  from public, anon, authenticated, service_role;

alter function public.social_live_gateway_debit(uuid, uuid, text)
  set schema gymapp_private;
alter function gymapp_private.social_live_gateway_debit(uuid, uuid, text)
  rename to social_live_gateway_debit_storage_v1;
revoke all on function gymapp_private.social_live_gateway_debit_storage_v1(uuid, uuid, text)
  from public, anon, authenticated, service_role;

create function public.social_live_gateway_debit(
  p_user_id uuid,
  p_session_id uuid,
  p_action text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform gymapp_private.live_gateway_require_session(p_user_id, p_session_id);
  return gymapp_private.social_live_gateway_debit_storage_v1(
    p_user_id,
    p_session_id,
    p_action
  );
end
$function$;

revoke all on function public.social_live_gateway_debit(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.social_live_gateway_debit(uuid, uuid, text)
  to service_role;

-- Keep the established session-bound implementation as a private worker. The
-- new wrapper rejects a foreign installation UUID unless the caller also proves
-- possession of the exact active provider address.
alter function public.notification_register_installation(
  uuid, text, text, text, text, text, text, text, text
) set schema gymapp_private;
alter function gymapp_private.notification_register_installation(
  uuid, text, text, text, text, text, text, text, text
) rename to notification_register_installation_session_v2;
revoke all on function gymapp_private.notification_register_installation_session_v2(
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
  normalized_token text;
  requested_fingerprint text;
  foreign_installation gymapp_private.notification_installations%rowtype;
begin
  if caller_user_id is null
     or not gymapp_private.current_auth_session_is_live() then
    raise exception using errcode = '42501', message = 'A current authenticated session is required.';
  end if;
  if p_installation_id is null or p_provider is null or p_environment is null then
    raise exception using errcode = '22023', message = 'Notification registration is invalid.';
  end if;

  normalized_token := gymapp_private.notification_normalize_token(
    p_provider,
    p_provider_token
  );
  requested_fingerprint := pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        p_provider || pg_catalog.chr(31) || p_environment || pg_catalog.chr(31) || normalized_token,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'gymapp-notification-installation:' || p_installation_id::text,
      0
    )
  );
  select installation.*
  into foreign_installation
  from gymapp_private.notification_installations as installation
  where installation.installation_id = p_installation_id
    and installation.user_id <> caller_user_id
    and installation.revoked_at is null
  for update;
  if found and (
    foreign_installation.provider is distinct from p_provider
    or foreign_installation.environment is distinct from p_environment
    or foreign_installation.token_fingerprint is distinct from requested_fingerprint
  ) then
    raise exception using errcode = '22023', message = 'Notification registration is invalid.';
  end if;

  return gymapp_private.notification_register_installation_session_v2(
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
end
$function$;

revoke all on function public.notification_register_installation(
  uuid, text, text, text, text, text, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.notification_register_installation(
  uuid, text, text, text, text, text, text, text, text
) to authenticated;

comment on function gymapp_private.current_auth_session_is_live() is
  'RLS predicate that locks and validates the exact unexpired Auth session.';
comment on function public.notification_register_installation(
  uuid, text, text, text, text, text, text, text, text
) is
  'Registers an owner session-bound push address; foreign installation UUID transfer requires exact provider-address possession.';

notify pgrst, 'reload schema';

commit;
