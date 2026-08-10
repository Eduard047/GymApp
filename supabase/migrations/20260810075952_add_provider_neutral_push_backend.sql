begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regclass('auth.users') is null
     or pg_catalog.to_regprocedure('gymapp_private.has_current_auth_session(uuid)') is null then
    raise exception 'GymApp push backend prerequisites are missing.';
  end if;
  if pg_catalog.to_regclass('gymapp_private.friendships') is null
     or pg_catalog.to_regclass('gymapp_private.social_workout_invites') is null
     or pg_catalog.to_regclass('gymapp_private.live_workout_rooms') is null
     or pg_catalog.to_regclass('gymapp_private.live_workout_members') is null then
    raise exception 'GymApp social/live notification sources are missing.';
  end if;
  if pg_catalog.to_regprocedure('extensions.digest(bytea,text)') is null then
    raise exception 'GymApp push backend requires pgcrypto in the extensions schema.';
  end if;
end
$preflight$;

create table gymapp_private.notification_installations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null,
  binding_id uuid not null default pg_catalog.gen_random_uuid(),
  platform text not null check (platform in ('android', 'ios', 'web')),
  provider text not null check (provider in ('fcm', 'apns', 'web_push')),
  environment text not null check (environment in ('production', 'sandbox')),
  provider_token text,
  token_fingerprint text not null check (token_fingerprint ~ '^[0-9a-f]{64}$'),
  web_push_p256dh text,
  web_push_auth text,
  locale text check (
    locale is null
    or (locale ~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,2}$' and pg_catalog.octet_length(locale) <= 35)
  ),
  app_version text check (
    app_version is null
    or (app_version ~ '^[A-Za-z0-9._+-]{1,32}$' and pg_catalog.octet_length(app_version) <= 32)
  ),
  revision bigint not null default 1 check (revision between 1 and 2147483647),
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  last_seen_at timestamptz not null default pg_catalog.clock_timestamp(),
  revoked_at timestamptz,
  constraint notification_installations_platform_provider_check check (
    (platform = 'android' and provider = 'fcm' and environment = 'production')
    or (platform = 'ios' and provider = 'apns')
    or (platform = 'web' and provider = 'web_push' and environment = 'production')
  ),
  constraint notification_installations_material_check check (
    (
      revoked_at is null
      and provider_token is not null
      and pg_catalog.octet_length(provider_token) between 32 and 4096
      and (
        (provider <> 'web_push' and web_push_p256dh is null and web_push_auth is null)
        or (
          provider = 'web_push'
          and web_push_p256dh ~ '^[A-Za-z0-9_-]{80,120}$'
          and web_push_auth ~ '^[A-Za-z0-9_-]{20,64}$'
        )
      )
    )
    or (
      revoked_at is not null
      and provider_token is null
      and web_push_p256dh is null
      and web_push_auth is null
    )
  ),
  constraint notification_installations_owner_installation_key
    unique (user_id, installation_id)
);

create unique index notification_installations_active_installation_idx
  on gymapp_private.notification_installations (installation_id)
  where revoked_at is null;
create unique index notification_installations_active_token_idx
  on gymapp_private.notification_installations (provider, environment, token_fingerprint)
  where revoked_at is null;
create index notification_installations_user_active_idx
  on gymapp_private.notification_installations (user_id, last_seen_at desc)
  where revoked_at is null;
create index notification_installations_stale_active_idx
  on gymapp_private.notification_installations (last_seen_at, id)
  where revoked_at is null;
create index notification_installations_retired_idx
  on gymapp_private.notification_installations (revoked_at, id)
  where revoked_at is not null;

create table gymapp_private.notification_rate_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  bucket_action text not null check (bucket_action in ('register', 'revoke')),
  tokens numeric(20, 9) not null check (tokens between 0 and 60),
  refilled_at timestamptz not null,
  primary key (user_id, bucket_action)
);

create table gymapp_private.push_outbox (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null check (event_type in (
    'friend_request_received', 'friend_request_accepted',
    'workout_invite_received', 'workout_invite_accepted',
    'live_invite_received', 'live_invite_accepted', 'live_room_started',
    'live_participant_finished', 'live_room_closed'
  )),
  object_id text not null check (
    object_id ~ '^[A-Za-z0-9:_-]{1,128}$'
    and pg_catalog.octet_length(object_id) <= 128
  ),
  object_revision bigint not null check (object_revision between 0 and 2147483647),
  dedupe_key text not null check (
    dedupe_key ~ '^[A-Za-z0-9:_-]{1,160}$'
    and pg_catalog.octet_length(dedupe_key) <= 160
  ),
  collapse_key text not null check (
    collapse_key ~ '^[A-Za-z0-9_-]{1,32}$'
    and pg_catalog.octet_length(collapse_key) <= 32
  ),
  priority text not null default 'normal' check (priority in ('normal', 'high')),
  status text not null default 'pending' check (status in ('pending', 'complete', 'dead', 'expired')),
  completion_reason text check (
    completion_reason is null
    or completion_reason in ('delivered', 'no_installations', 'all_failed', 'expired')
  ),
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  not_before timestamptz not null default pg_catalog.clock_timestamp(),
  expires_at timestamptz not null,
  completed_at timestamptz,
  constraint push_outbox_lifetime_check check (
    not_before >= created_at - interval '5 seconds'
    and expires_at > not_before
    and expires_at <= created_at + interval '7 days'
  ),
  constraint push_outbox_completion_check check (
    (status = 'pending' and completion_reason is null and completed_at is null)
    or (status <> 'pending' and completion_reason is not null and completed_at is not null)
  ),
  constraint push_outbox_recipient_dedupe_key unique (recipient_user_id, dedupe_key)
);

create index push_outbox_pending_idx
  on gymapp_private.push_outbox (not_before, expires_at, created_at)
  where status = 'pending';

create table gymapp_private.push_outbox_deliveries (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  outbox_id uuid not null references gymapp_private.push_outbox(id) on delete cascade,
  installation_id uuid not null references gymapp_private.notification_installations(id) on delete cascade,
  installation_revision bigint not null check (installation_revision between 1 and 2147483647),
  status text not null default 'pending' check (
    status in ('pending', 'processing', 'delivered', 'invalid', 'dead', 'expired')
  ),
  attempt_count integer not null default 0 check (attempt_count between 0 and 12),
  next_attempt_at timestamptz not null default pg_catalog.clock_timestamp(),
  lease_owner uuid,
  lease_token uuid,
  lease_expires_at timestamptz,
  provider_status integer check (provider_status is null or provider_status between 100 and 599),
  error_code text check (
    error_code is null
    or (error_code ~ '^[a-z0-9_:-]{1,64}$' and pg_catalog.octet_length(error_code) <= 64)
  ),
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  delivered_at timestamptz,
  constraint push_outbox_deliveries_pair_key unique (outbox_id, installation_id),
  constraint push_outbox_deliveries_lease_check check (
    (
      status = 'processing'
      and lease_owner is not null
      and lease_token is not null
      and lease_expires_at is not null
    )
    or (
      status <> 'processing'
      and lease_owner is null
      and lease_token is null
      and lease_expires_at is null
    )
  )
);

create index push_outbox_deliveries_claim_idx
  on gymapp_private.push_outbox_deliveries (next_attempt_at, created_at)
  where status in ('pending', 'processing');
create index push_outbox_deliveries_outbox_status_idx
  on gymapp_private.push_outbox_deliveries (outbox_id, status);
create index push_outbox_deliveries_installation_revision_status_idx
  on gymapp_private.push_outbox_deliveries (
    installation_id, installation_revision, status
  );

comment on table gymapp_private.notification_installations is
  'Private account-bound FCM/APNs/Web Push delivery addresses. Raw provider material is server-only and scrubbed on revocation.';
comment on table gymapp_private.push_outbox is
  'Durable provider-neutral notification intents. It contains only bounded opaque object references, never workout content or profile data.';
comment on table gymapp_private.push_outbox_deliveries is
  'Per-installation at-least-once delivery state with bounded leases and retries.';
comment on table gymapp_private.notification_rate_limits is
  'Private per-account token buckets bounding notification registration churn.';

alter table gymapp_private.notification_installations enable row level security;
alter table gymapp_private.notification_rate_limits enable row level security;
alter table gymapp_private.push_outbox enable row level security;
alter table gymapp_private.push_outbox_deliveries enable row level security;
revoke all on table gymapp_private.notification_installations
  from public, anon, authenticated, service_role;
revoke all on table gymapp_private.notification_rate_limits
  from public, anon, authenticated, service_role;
revoke all on table gymapp_private.push_outbox
  from public, anon, authenticated, service_role;
revoke all on table gymapp_private.push_outbox_deliveries
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.notification_web_push_endpoint_is_allowed(
  p_endpoint text
)
returns boolean
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $function$
declare
  host_name text;
begin
  if pg_catalog.octet_length(p_endpoint) not between 32 and 2048
     or p_endpoint !~ '^https://[^/?#:@]+/[^[:space:]#]*$' then
    return false;
  end if;
  host_name := pg_catalog.lower(
    substring(p_endpoint from '^https://([^/]+)/')
  );
  return host_name in (
      'fcm.googleapis.com',
      'updates.push.services.mozilla.com',
      'web.push.apple.com'
    )
    or host_name ~ '^[a-z0-9-]+\.notify\.windows\.com$';
end
$function$;

revoke all on function gymapp_private.notification_web_push_endpoint_is_allowed(text)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.consume_notification_rate_limit(
  p_user_id uuid,
  p_action text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  request_time timestamptz := pg_catalog.clock_timestamp();
  capacity numeric;
  refill_per_second numeric;
  bucket_row gymapp_private.notification_rate_limits%rowtype;
  available_tokens numeric;
begin
  if p_user_id is null or auth.uid() is distinct from p_user_id
     or p_action not in ('register', 'revoke') then
    raise exception using errcode = '42501', message = 'Notification rate limit is unavailable.';
  end if;
  if p_action = 'register' then
    capacity := 30;
    refill_per_second := 30::numeric / 3600::numeric;
  else
    capacity := 60;
    refill_per_second := 60::numeric / 3600::numeric;
  end if;
  select bucket.* into bucket_row
  from gymapp_private.notification_rate_limits as bucket
  where bucket.user_id = p_user_id and bucket.bucket_action = p_action
  for update;
  if not found then
    insert into gymapp_private.notification_rate_limits (
      user_id, bucket_action, tokens, refilled_at
    ) values (
      p_user_id, p_action, capacity - 1, request_time
    );
    return;
  end if;
  available_tokens := least(
    capacity,
    bucket_row.tokens + greatest(
      0,
      extract(epoch from request_time - bucket_row.refilled_at)
    ) * refill_per_second
  );
  if available_tokens < 1 then
    raise exception using errcode = 'P0001', message = 'Notification request rate limit exceeded.';
  end if;
  update gymapp_private.notification_rate_limits as bucket
  set tokens = available_tokens - 1,
      refilled_at = request_time
  where bucket.user_id = p_user_id and bucket.bucket_action = p_action;
end
$function$;

revoke all on function gymapp_private.consume_notification_rate_limit(uuid, text)
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.notification_normalize_token(
  p_provider text,
  p_token text
)
returns text
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $function$
declare
  normalized_token text := pg_catalog.btrim(p_token);
begin
  if p_token <> normalized_token or normalized_token ~ '[[:space:][:cntrl:]]' then
    raise exception using errcode = '22023', message = 'Notification registration is invalid.';
  end if;
  if p_provider = 'fcm' then
    if pg_catalog.octet_length(normalized_token) not between 32 and 4096
       or normalized_token !~ '^[A-Za-z0-9_:-]+$' then
      raise exception using errcode = '22023', message = 'Notification registration is invalid.';
    end if;
  elsif p_provider = 'apns' then
    normalized_token := pg_catalog.lower(normalized_token);
    if normalized_token !~ '^[0-9a-f]{32,200}$'
       or pg_catalog.octet_length(normalized_token) % 2 <> 0 then
      raise exception using errcode = '22023', message = 'Notification registration is invalid.';
    end if;
  elsif p_provider = 'web_push' then
    if not gymapp_private.notification_web_push_endpoint_is_allowed(normalized_token) then
      raise exception using errcode = '22023', message = 'Notification registration is invalid.';
    end if;
  else
    raise exception using errcode = '22023', message = 'Notification registration is invalid.';
  end if;
  return normalized_token;
end
$function$;

revoke all on function gymapp_private.notification_normalize_token(text, text)
  from public, anon, authenticated, service_role;

-- PostgREST normally turns a raised 22023/54000 into a non-2xx response, but
-- the raised exception also rolls back the notification token-bucket debit.
-- The public RPCs below keep their debit outside a nested subtransaction,
-- roll back only failed business work, and use this helper to preserve the
-- exact legacy PostgREST error envelope and status without raising again.
create or replace function gymapp_private.notification_domain_error_response(
  p_code text,
  p_message text,
  p_detail text,
  p_hint text
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
begin
  if p_code is null or p_message is null or not (
    (p_code = '22023' and p_message in (
      'Notification registration is invalid.',
      'Notification revocation is invalid.'
    ))
    or (p_code = '54000' and p_message in (
      'Notification registration cannot be updated.',
      'Notification installation limit exceeded.'
    ))
  ) then
    raise exception using
      errcode = '22023',
      message = 'Notification domain error response is invalid.';
  end if;

  perform pg_catalog.set_config(
    'response.status',
    case when p_code = '54000' then '500' else '400' end,
    true
  );
  return pg_catalog.jsonb_build_object(
    'code', p_code,
    'details', nullif(p_detail, ''),
    'hint', nullif(p_hint, ''),
    'message', p_message
  );
end
$function$;

revoke all on function gymapp_private.notification_domain_error_response(
  text, text, text, text
) from public, anon, authenticated, service_role;

create or replace function public.notification_register_installation(
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
  token_fingerprint_value text;
  normalized_locale text := nullif(pg_catalog.btrim(p_locale), '');
  normalized_app_version text := nullif(pg_catalog.btrim(p_app_version), '');
  existing_revision bigint;
  address_changed boolean := true;
  active_count integer;
  total_count integer;
  existing_row gymapp_private.notification_installations%rowtype;
  stored_row gymapp_private.notification_installations%rowtype;
  request_time timestamptz := pg_catalog.clock_timestamp();
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  if caller_user_id is null
     or not gymapp_private.has_current_auth_session(caller_user_id) then
    raise exception using errcode = '42501', message = 'A current authenticated session is required.';
  end if;
  perform gymapp_private.consume_notification_rate_limit(caller_user_id, 'register');

  begin
  if p_installation_id is null
     or p_platform is null
     or p_provider is null
     or p_environment is null
     or p_platform not in ('android', 'ios', 'web')
     or p_provider not in ('fcm', 'apns', 'web_push')
     or p_environment not in ('production', 'sandbox')
     or p_provider_token is null
     or not (
       (p_platform = 'android' and p_provider = 'fcm' and p_environment = 'production')
       or (p_platform = 'ios' and p_provider = 'apns')
       or (p_platform = 'web' and p_provider = 'web_push' and p_environment = 'production')
     ) then
    raise exception using errcode = '22023', message = 'Notification registration is invalid.';
  end if;
  if (p_locale is not null and p_locale <> coalesce(normalized_locale, ''))
     or (normalized_locale is not null and (
       normalized_locale !~ '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,2}$'
       or pg_catalog.octet_length(normalized_locale) > 35
     ))
     or (p_app_version is not null and p_app_version <> coalesce(normalized_app_version, ''))
     or (normalized_app_version is not null and (
       normalized_app_version !~ '^[A-Za-z0-9._+-]{1,32}$'
       or pg_catalog.octet_length(normalized_app_version) > 32
     )) then
    raise exception using errcode = '22023', message = 'Notification registration is invalid.';
  end if;
  if p_provider = 'web_push' then
    if p_web_push_p256dh is null
       or p_web_push_p256dh !~ '^[A-Za-z0-9_-]{80,120}$'
       or p_web_push_auth is null
       or p_web_push_auth !~ '^[A-Za-z0-9_-]{20,64}$' then
      raise exception using errcode = '22023', message = 'Notification registration is invalid.';
    end if;
  elsif p_web_push_p256dh is not null or p_web_push_auth is not null then
    raise exception using errcode = '22023', message = 'Notification registration is invalid.';
  end if;

  normalized_token := gymapp_private.notification_normalize_token(p_provider, p_provider_token);
  token_fingerprint_value := pg_catalog.encode(
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
    pg_catalog.hashtextextended('gymapp-notification-user:' || caller_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gymapp-notification-installation:' || p_installation_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gymapp-notification-token:' || token_fingerprint_value, 0)
  );

  select installation.* into existing_row
  from gymapp_private.notification_installations as installation
  where installation.user_id = caller_user_id
    and installation.installation_id = p_installation_id
  for update;
  if found then
    existing_revision := existing_row.revision;
    address_changed := existing_row.revoked_at is not null
      or existing_row.platform is distinct from p_platform
      or existing_row.provider is distinct from p_provider
      or existing_row.environment is distinct from p_environment
      or existing_row.provider_token is distinct from normalized_token
      or existing_row.token_fingerprint is distinct from token_fingerprint_value
      or existing_row.web_push_p256dh is distinct from p_web_push_p256dh
      or existing_row.web_push_auth is distinct from p_web_push_auth;
    if address_changed and existing_revision >= 2147483647 then
      raise exception using errcode = '54000', message = 'Notification registration cannot be updated.';
    end if;
  end if;

  -- One physical/browser installation or provider address may be active for only
  -- one account. Account switching therefore revokes and scrubs the old binding
  -- before the new owner is made visible.
  update gymapp_private.notification_installations as installation
  set provider_token = null,
      web_push_p256dh = null,
      web_push_auth = null,
      binding_id = pg_catalog.gen_random_uuid(),
      revoked_at = request_time,
      updated_at = request_time,
      revision = least(installation.revision + 1, 2147483647)
  where installation.revoked_at is null
    and (
      installation.installation_id = p_installation_id
      or (
        installation.provider = p_provider
        and installation.environment = p_environment
        and installation.token_fingerprint = token_fingerprint_value
      )
    )
    and not (
      installation.user_id = caller_user_id
      and installation.installation_id = p_installation_id
    );

  -- A bounded historical row cap prevents register/revoke churn from growing
  -- private storage forever. Old scrubbed rows are deleted only after every
  -- referenced delivery has already been removed by outbox retention cleanup.
  with cleanup_candidates as (
    select installation.id
    from gymapp_private.notification_installations as installation
    where installation.user_id = caller_user_id
      and installation.installation_id <> p_installation_id
      and installation.revoked_at < request_time - interval '7 days'
      and not exists (
        select 1
        from gymapp_private.push_outbox_deliveries as delivery
        where delivery.installation_id = installation.id
      )
    order by installation.revoked_at, installation.id
    for update skip locked
    limit 32
  )
  delete from gymapp_private.notification_installations as installation
  using cleanup_candidates
  where installation.id = cleanup_candidates.id;

  select pg_catalog.count(*)::integer into active_count
  from gymapp_private.notification_installations as installation
  where installation.user_id = caller_user_id
    and installation.revoked_at is null
    and installation.installation_id <> p_installation_id;
  if active_count >= 12 then
    raise exception using errcode = '54000', message = 'Notification installation limit exceeded.';
  end if;
  select pg_catalog.count(*)::integer into total_count
  from gymapp_private.notification_installations as installation
  where installation.user_id = caller_user_id
    and installation.installation_id <> p_installation_id;
  if total_count >= 64 then
    raise exception using errcode = '54000', message = 'Notification installation limit exceeded.';
  end if;

  insert into gymapp_private.notification_installations (
    user_id, installation_id, platform, provider, environment,
    provider_token, token_fingerprint, web_push_p256dh, web_push_auth,
    locale, app_version, revision, created_at, updated_at, last_seen_at, revoked_at
  ) values (
    caller_user_id, p_installation_id, p_platform, p_provider, p_environment,
    normalized_token, token_fingerprint_value, p_web_push_p256dh, p_web_push_auth,
    normalized_locale, normalized_app_version, 1,
    request_time, request_time, request_time, null
  )
  on conflict (user_id, installation_id) do update
  set platform = excluded.platform,
      provider = excluded.provider,
      environment = excluded.environment,
      provider_token = excluded.provider_token,
      token_fingerprint = excluded.token_fingerprint,
      web_push_p256dh = excluded.web_push_p256dh,
      web_push_auth = excluded.web_push_auth,
      locale = excluded.locale,
      app_version = excluded.app_version,
      binding_id = case
        when gymapp_private.notification_installations.revoked_at is null
         and gymapp_private.notification_installations.platform = excluded.platform
         and gymapp_private.notification_installations.provider = excluded.provider
         and gymapp_private.notification_installations.environment = excluded.environment
         and gymapp_private.notification_installations.provider_token = excluded.provider_token
         and gymapp_private.notification_installations.token_fingerprint = excluded.token_fingerprint
         and gymapp_private.notification_installations.web_push_p256dh
           is not distinct from excluded.web_push_p256dh
         and gymapp_private.notification_installations.web_push_auth
           is not distinct from excluded.web_push_auth
        then gymapp_private.notification_installations.binding_id
        else excluded.binding_id
      end,
      revision = case
        when gymapp_private.notification_installations.revoked_at is null
         and gymapp_private.notification_installations.platform = excluded.platform
         and gymapp_private.notification_installations.provider = excluded.provider
         and gymapp_private.notification_installations.environment = excluded.environment
         and gymapp_private.notification_installations.provider_token = excluded.provider_token
         and gymapp_private.notification_installations.token_fingerprint = excluded.token_fingerprint
         and gymapp_private.notification_installations.web_push_p256dh
           is not distinct from excluded.web_push_p256dh
         and gymapp_private.notification_installations.web_push_auth
           is not distinct from excluded.web_push_auth
        then gymapp_private.notification_installations.revision
        else gymapp_private.notification_installations.revision + 1
      end,
      updated_at = request_time,
      last_seen_at = request_time,
      revoked_at = null
  returning * into strict stored_row;

  -- A provider can rotate an address between enqueue and dispatch. Pending
  -- work for this same account/installation follows the new revision; an
  -- already leased delivery keeps its immutable snapshot and stale result
  -- guards, so cross-account or late invalid-token responses cannot revoke it.
  if existing_revision is not null and stored_row.revision > existing_revision then
    update gymapp_private.push_outbox_deliveries as delivery
    set installation_revision = stored_row.revision,
        attempt_count = 0,
        next_attempt_at = request_time,
        provider_status = null,
        error_code = 'registration_refreshed',
        updated_at = request_time
    from gymapp_private.push_outbox as outbox
    where delivery.installation_id = stored_row.id
      and delivery.outbox_id = outbox.id
      and delivery.status = 'pending'
      and delivery.installation_revision <> stored_row.revision
      and outbox.status = 'pending'
      and outbox.recipient_user_id = caller_user_id;
  end if;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'installationId', stored_row.installation_id,
    'provider', stored_row.provider,
    'environment', stored_row.environment,
    'bindingId', stored_row.binding_id,
    'registrationRevision', stored_row.revision,
    'registeredAt', stored_row.updated_at
  );
  exception
    when sqlstate '22023' or sqlstate '54000' then
      get stacked diagnostics
        domain_error_code = returned_sqlstate,
        domain_error_message = message_text,
        domain_error_detail = pg_exception_detail,
        domain_error_hint = pg_exception_hint;
      if domain_error_code is null or domain_error_message is null or not (
        (domain_error_code = '22023'
          and domain_error_message = 'Notification registration is invalid.')
        or (domain_error_code = '54000' and domain_error_message in (
          'Notification registration cannot be updated.',
          'Notification installation limit exceeded.'
        ))
      ) then
        raise;
      end if;
      return gymapp_private.notification_domain_error_response(
        domain_error_code,
        domain_error_message,
        domain_error_detail,
        domain_error_hint
      );
  end;
end
$function$;

revoke all on function public.notification_register_installation(
  uuid, text, text, text, text, text, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.notification_register_installation(
  uuid, text, text, text, text, text, text, text, text
) to authenticated;

create or replace function public.notification_revoke_installation(
  p_installation_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  request_time timestamptz := pg_catalog.clock_timestamp();
  revoked_count integer;
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  if caller_user_id is null
     or not gymapp_private.has_current_auth_session(caller_user_id) then
    raise exception using errcode = '42501', message = 'A current authenticated session is required.';
  end if;
  perform gymapp_private.consume_notification_rate_limit(caller_user_id, 'revoke');

  begin
  if p_installation_id is null then
    raise exception using errcode = '22023', message = 'Notification revocation is invalid.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gymapp-notification-user:' || caller_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gymapp-notification-installation:' || p_installation_id::text, 0)
  );
  update gymapp_private.notification_installations as installation
  set provider_token = null,
      web_push_p256dh = null,
      web_push_auth = null,
      binding_id = pg_catalog.gen_random_uuid(),
      revoked_at = request_time,
      updated_at = request_time,
      revision = least(installation.revision + 1, 2147483647)
  where installation.user_id = caller_user_id
    and installation.installation_id = p_installation_id
    and installation.revoked_at is null;
  get diagnostics revoked_count = row_count;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'installationId', p_installation_id,
    'revoked', revoked_count = 1
  );
  exception
    when sqlstate '22023' then
      get stacked diagnostics
        domain_error_code = returned_sqlstate,
        domain_error_message = message_text,
        domain_error_detail = pg_exception_detail,
        domain_error_hint = pg_exception_hint;
      if domain_error_code is distinct from '22023'
         or domain_error_message is distinct from 'Notification revocation is invalid.' then
        raise;
      end if;
      return gymapp_private.notification_domain_error_response(
        domain_error_code,
        domain_error_message,
        domain_error_detail,
        domain_error_hint
      );
  end;
end
$function$;

revoke all on function public.notification_revoke_installation(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notification_revoke_installation(uuid)
  to authenticated;

create or replace function gymapp_private.enqueue_push_notification(
  p_recipient_user_id uuid,
  p_event_type text,
  p_object_id text,
  p_object_revision bigint,
  p_dedupe_key text,
  p_collapse_key text,
  p_priority text default 'normal',
  p_expires_at timestamptz default (pg_catalog.clock_timestamp() + interval '1 day')
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  request_time timestamptz := pg_catalog.clock_timestamp();
  outbox_id_value uuid;
  delivery_count integer;
  existing_row record;
begin
  if p_recipient_user_id is null
     or not exists (select 1 from auth.users as app_user where app_user.id = p_recipient_user_id)
     or p_event_type is null
     or p_event_type not in (
       'friend_request_received', 'friend_request_accepted',
       'workout_invite_received', 'workout_invite_accepted',
       'live_invite_received', 'live_invite_accepted', 'live_room_started',
       'live_participant_finished', 'live_room_closed'
     )
     or p_object_id is null
     or p_object_id !~ '^[A-Za-z0-9:_-]{1,128}$'
     or pg_catalog.octet_length(p_object_id) > 128
     or p_object_revision is null
     or p_object_revision not between 0 and 2147483647
     or p_dedupe_key is null
     or p_dedupe_key !~ '^[A-Za-z0-9:_-]{1,160}$'
     or pg_catalog.octet_length(p_dedupe_key) > 160
     or p_collapse_key is null
     or p_collapse_key !~ '^[A-Za-z0-9_-]{1,32}$'
     or pg_catalog.octet_length(p_collapse_key) > 32
     or p_priority is null
     or p_priority not in ('normal', 'high')
     or p_expires_at is null
     or p_expires_at <= request_time + interval '1 minute'
     or p_expires_at > request_time + interval '7 days' then
    raise exception using errcode = '22023', message = 'Push notification intent is invalid.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'gymapp-notification-user:' || p_recipient_user_id::text,
      0
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'gymapp-push-dedupe:' || p_recipient_user_id::text || ':' || p_dedupe_key,
      0
    )
  );
  select outbox.* into existing_row
  from gymapp_private.push_outbox as outbox
  where outbox.recipient_user_id = p_recipient_user_id
    and outbox.dedupe_key = p_dedupe_key;
  if found then
    if existing_row.event_type <> p_event_type
       or existing_row.object_id <> p_object_id
       or existing_row.object_revision <> p_object_revision then
      raise exception using errcode = '23505', message = 'Push notification dedupe key conflicts.';
    end if;
    return existing_row.id;
  end if;

  insert into gymapp_private.push_outbox (
    recipient_user_id, event_type, object_id, object_revision,
    dedupe_key, collapse_key, priority,
    status, completion_reason, created_at, not_before, expires_at, completed_at
  ) values (
    p_recipient_user_id, p_event_type, p_object_id, p_object_revision,
    p_dedupe_key, p_collapse_key, p_priority,
    'pending', null, request_time, request_time, p_expires_at, null
  ) returning id into strict outbox_id_value;

  insert into gymapp_private.push_outbox_deliveries (
    outbox_id, installation_id, installation_revision, status, attempt_count,
    next_attempt_at, created_at, updated_at
  )
  select outbox_id_value, installation.id, installation.revision, 'pending', 0,
         request_time, request_time, request_time
  from gymapp_private.notification_installations as installation
  where installation.user_id = p_recipient_user_id
    and installation.revoked_at is null;
  get diagnostics delivery_count = row_count;

  if delivery_count = 0 then
    update gymapp_private.push_outbox as outbox
    set status = 'complete',
        completion_reason = 'no_installations',
        completed_at = request_time
    where outbox.id = outbox_id_value;
  end if;
  return outbox_id_value;
end
$function$;

revoke all on function gymapp_private.enqueue_push_notification(
  uuid, text, text, bigint, text, text, text, timestamptz
) from public, anon, authenticated, service_role;

create or replace function gymapp_private.enqueue_friendship_push()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  recipient_user_id uuid;
  event_type_value text;
begin
  if new.status = 'pending'
     and (tg_op = 'INSERT' or old.status <> 'pending') then
    recipient_user_id := case
      when new.requester_user_id = new.user_low_id then new.user_high_id
      else new.user_low_id
    end;
    event_type_value := 'friend_request_received';
  elsif tg_op = 'UPDATE'
        and old.status = 'pending'
        and new.status = 'accepted' then
    recipient_user_id := new.requester_user_id;
    event_type_value := 'friend_request_accepted';
  else
    return new;
  end if;

  perform gymapp_private.enqueue_push_notification(
    recipient_user_id,
    event_type_value,
    new.id,
    new.revision,
    event_type_value || ':' || new.id || ':' || new.revision::text,
    'friend_request',
    'normal',
    pg_catalog.clock_timestamp() + interval '1 day'
  );
  return new;
end
$function$;

revoke all on function gymapp_private.enqueue_friendship_push()
  from public, anon, authenticated, service_role;

create trigger friendships_enqueue_push
after insert or update of status on gymapp_private.friendships
for each row execute function gymapp_private.enqueue_friendship_push();

create or replace function gymapp_private.enqueue_static_workout_push()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  recipient_user_id uuid;
  event_type_value text;
  notification_expires_at timestamptz;
begin
  if new.status = 'pending'
     and (tg_op = 'INSERT' or old.status <> 'pending') then
    recipient_user_id := new.recipient_user_id;
    event_type_value := 'workout_invite_received';
    notification_expires_at := least(
      new.expires_at,
      pg_catalog.clock_timestamp() + interval '7 days'
    );
  elsif tg_op = 'UPDATE'
        and old.status = 'pending'
        and new.status = 'accepted' then
    recipient_user_id := new.sender_user_id;
    event_type_value := 'workout_invite_accepted';
    notification_expires_at := pg_catalog.clock_timestamp() + interval '1 day';
  else
    return new;
  end if;

  perform gymapp_private.enqueue_push_notification(
    recipient_user_id,
    event_type_value,
    new.id,
    new.revision,
    event_type_value || ':' || new.id || ':' || new.revision::text,
    'workout_invite',
    'high',
    notification_expires_at
  );
  return new;
end
$function$;

revoke all on function gymapp_private.enqueue_static_workout_push()
  from public, anon, authenticated, service_role;

create trigger social_workout_invites_enqueue_push
after insert or update of status on gymapp_private.social_workout_invites
for each row execute function gymapp_private.enqueue_static_workout_push();

create or replace function gymapp_private.enqueue_live_workout_member_push()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_revision bigint;
  invite_expires_at timestamptz;
begin
  -- Lifecycle changes after the invitation are emitted from the room trigger,
  -- where its final revision is available. Per-set progress is Realtime-only.
  if tg_op <> 'INSERT'
     or new.role <> 'participant'
     or new.state <> 'invited' then
    return new;
  end if;

  select room.revision, room.invite_expires_at
  into room_revision, invite_expires_at
  from gymapp_private.live_workout_rooms as room
  where room.id = new.room_id;
  if not found then
    return new;
  end if;

  perform gymapp_private.enqueue_push_notification(
    new.user_id,
    'live_invite_received',
    new.room_id,
    room_revision,
    'live_invite_received:' || new.room_id || ':' || room_revision::text,
    'live_workout',
    'high',
    least(invite_expires_at, pg_catalog.clock_timestamp() + interval '7 days')
  );
  return new;
end
$function$;

revoke all on function gymapp_private.enqueue_live_workout_member_push()
  from public, anon, authenticated, service_role;

create trigger live_workout_members_enqueue_push
after insert or update on gymapp_private.live_workout_members
for each row execute function gymapp_private.enqueue_live_workout_member_push();

create or replace function gymapp_private.enqueue_live_workout_room_push()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  recipient record;
  finished_member record;
begin
  if old.status = 'waiting' and new.status = 'ready' then
    perform gymapp_private.enqueue_push_notification(
      new.owner_user_id,
      'live_invite_accepted',
      new.id,
      new.revision,
      'live_invite_accepted:' || new.id || ':' || new.revision::text,
      'live_workout',
      'high',
      pg_catalog.clock_timestamp() + interval '1 day'
    );
  elsif old.status = 'ready' and new.status = 'active' then
    for recipient in
      select member.user_id
      from gymapp_private.live_workout_members as member
      where member.room_id = new.id
        and member.role = 'participant'
      order by member.user_id
    loop
      perform gymapp_private.enqueue_push_notification(
        recipient.user_id,
        'live_room_started',
        new.id,
        new.revision,
        'live_room_started:' || new.id || ':' || new.revision::text,
        'live_workout',
        'high',
        pg_catalog.clock_timestamp() + interval '1 day'
      );
    end loop;
  end if;

  -- Finish updates a membership and then advances the room with the same
  -- mutation timestamp. Emitting here gives clients the committed room
  -- revision, while ordinary set/progress room revisions produce no push.
  if old.status = 'active' and new.status in ('active', 'completed') then
    for finished_member in
      select member.user_id
      from gymapp_private.live_workout_members as member
      where member.room_id = new.id
        and member.state = 'finished'
        and member.updated_at = new.updated_at
      order by member.user_id
    loop
      for recipient in
        select member.user_id
        from gymapp_private.live_workout_members as member
        where member.room_id = new.id
          and member.user_id <> finished_member.user_id
        order by member.user_id
      loop
        perform gymapp_private.enqueue_push_notification(
          recipient.user_id,
          'live_participant_finished',
          new.id,
          new.revision,
          'live_participant_finished:' || new.id || ':' || new.revision::text,
          'live_workout',
          'high',
          pg_catalog.clock_timestamp() + interval '1 day'
        );
      end loop;
    end loop;
  end if;

  if old.status in ('waiting', 'ready', 'active')
     and new.status in ('completed', 'cancelled', 'expired') then
    for recipient in
      select member.user_id
      from gymapp_private.live_workout_members as member
      where member.room_id = new.id
      order by member.user_id
    loop
      perform gymapp_private.enqueue_push_notification(
        recipient.user_id,
        'live_room_closed',
        new.id,
        new.revision,
        'live_room_closed:' || new.id || ':' || new.revision::text,
        'live_workout',
        'high',
        pg_catalog.clock_timestamp() + interval '1 day'
      );
    end loop;
  end if;
  return new;
end
$function$;

revoke all on function gymapp_private.enqueue_live_workout_room_push()
  from public, anon, authenticated, service_role;

create trigger live_workout_rooms_enqueue_push
after update on gymapp_private.live_workout_rooms
for each row
when (old.revision is distinct from new.revision)
execute function gymapp_private.enqueue_live_workout_room_push();

create or replace function gymapp_private.reconcile_push_outbox(
  p_outbox_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  request_time timestamptz := pg_catalog.clock_timestamp();
begin
  update gymapp_private.push_outbox as outbox
  set status = case
        when outbox.expires_at <= request_time then 'expired'
        when exists (
          select 1 from gymapp_private.push_outbox_deliveries as delivery
          where delivery.outbox_id = outbox.id and delivery.status = 'delivered'
        ) then 'complete'
        else 'dead'
      end,
      completion_reason = case
        when outbox.expires_at <= request_time then 'expired'
        when exists (
          select 1 from gymapp_private.push_outbox_deliveries as delivery
          where delivery.outbox_id = outbox.id and delivery.status = 'delivered'
        ) then 'delivered'
        else 'all_failed'
      end,
      completed_at = request_time
  where outbox.id = p_outbox_id
    and outbox.status = 'pending'
    and not exists (
      select 1
      from gymapp_private.push_outbox_deliveries as delivery
      where delivery.outbox_id = outbox.id
        and delivery.status in ('pending', 'processing')
    );
end
$function$;

revoke all on function gymapp_private.reconcile_push_outbox(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.push_claim_deliveries(
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
  request_time timestamptz := pg_catalog.clock_timestamp();
begin
  if p_worker_id is null
     or p_limit is null
     or p_lease_seconds is null
     or p_limit not between 1 and 100
     or p_lease_seconds not between 15 and 300 then
    raise exception using errcode = '22023', message = 'Push claim request is invalid.';
  end if;

  -- Keep durable dedupe/diagnostic state for a bounded window. Each dispatch
  -- invocation removes at most 500 terminal intents, cascading their delivery
  -- rows without taking an unbounded table lock.
  with cleanup_candidates as (
    select outbox.id
    from gymapp_private.push_outbox as outbox
    where outbox.status in ('complete', 'dead', 'expired')
      and outbox.completed_at < request_time - interval '30 days'
    order by outbox.completed_at, outbox.id
    for update skip locked
    limit 500
  )
  delete from gymapp_private.push_outbox as outbox
  using cleanup_candidates
  where outbox.id = cleanup_candidates.id;

  -- Active addresses must be refreshed by a signed-in client. This bounds raw
  -- provider-address retention when a client uninstalls or loses permission
  -- without completing the authenticated revoke call.
  with stale_installations as (
    select installation.id
    from gymapp_private.notification_installations as installation
    where installation.revoked_at is null
      and installation.last_seen_at < request_time - interval '180 days'
    order by installation.last_seen_at, installation.id
    for update skip locked
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
  from stale_installations
  where installation.id = stale_installations.id;

  -- Once outbox retention has removed every referencing delivery, retain only
  -- a short scrubbed tombstone for replay/account-switch diagnostics.
  with retired_installations as (
    select installation.id
    from gymapp_private.notification_installations as installation
    where installation.revoked_at < request_time - interval '30 days'
      and not exists (
        select 1
        from gymapp_private.push_outbox_deliveries as delivery
        where delivery.installation_id = installation.id
      )
    order by installation.revoked_at, installation.id
    for update skip locked
    limit 500
  )
  delete from gymapp_private.notification_installations as installation
  using retired_installations
  where installation.id = retired_installations.id;

  update gymapp_private.push_outbox_deliveries as delivery
  set status = case when delivery.attempt_count >= 8 then 'dead' else 'pending' end,
      next_attempt_at = case
        when delivery.attempt_count >= 8 then delivery.next_attempt_at
        else request_time
      end,
      lease_owner = null,
      lease_token = null,
      lease_expires_at = null,
      error_code = case
        when delivery.attempt_count >= 8 then 'lease_attempts_exhausted'
        else 'lease_expired'
      end,
      updated_at = request_time
  where delivery.status = 'processing'
    and delivery.lease_expires_at <= request_time;

  update gymapp_private.push_outbox_deliveries as delivery
  set status = 'expired',
      lease_owner = null,
      lease_token = null,
      lease_expires_at = null,
      error_code = 'notification_expired',
      updated_at = request_time
  from gymapp_private.push_outbox as outbox
  where delivery.outbox_id = outbox.id
    and delivery.status in ('pending', 'processing')
    and outbox.expires_at <= request_time;

  update gymapp_private.push_outbox as outbox
  set status = 'expired',
      completion_reason = 'expired',
      completed_at = request_time
  where outbox.status = 'pending'
    and outbox.expires_at <= request_time;

  update gymapp_private.push_outbox_deliveries as delivery
  set status = 'invalid',
      lease_owner = null,
      lease_token = null,
      lease_expires_at = null,
      error_code = case
        when installation.revoked_at is not null then 'registration_revoked'
        else 'registration_superseded'
      end,
      updated_at = request_time
  from gymapp_private.notification_installations as installation
  where delivery.installation_id = installation.id
    and delivery.status in ('pending', 'processing')
    and (
      installation.revoked_at is not null
      or installation.revision <> delivery.installation_revision
    );

  update gymapp_private.push_outbox as outbox
  set status = case
        when exists (
          select 1 from gymapp_private.push_outbox_deliveries as delivery
          where delivery.outbox_id = outbox.id and delivery.status = 'delivered'
        ) then 'complete'
        else 'dead'
      end,
      completion_reason = case
        when exists (
          select 1 from gymapp_private.push_outbox_deliveries as delivery
          where delivery.outbox_id = outbox.id and delivery.status = 'delivered'
        ) then 'delivered'
        else 'all_failed'
      end,
      completed_at = request_time
  where outbox.status = 'pending'
    and exists (
      select 1 from gymapp_private.push_outbox_deliveries as delivery
      where delivery.outbox_id = outbox.id
    )
    and not exists (
      select 1 from gymapp_private.push_outbox_deliveries as delivery
      where delivery.outbox_id = outbox.id
        and delivery.status in ('pending', 'processing')
    );

  return query
  with candidates as (
    select delivery.id
    from gymapp_private.push_outbox_deliveries as delivery
    join gymapp_private.push_outbox as outbox on outbox.id = delivery.outbox_id
    join gymapp_private.notification_installations as installation
      on installation.id = delivery.installation_id
    where delivery.status = 'pending'
      and delivery.next_attempt_at <= request_time
      and delivery.attempt_count < 8
      and outbox.status = 'pending'
      and outbox.not_before <= request_time
      and outbox.expires_at > request_time
      and installation.revoked_at is null
      and installation.user_id = outbox.recipient_user_id
      and installation.revision = delivery.installation_revision
    order by case when outbox.priority = 'high' then 0 else 1 end,
             delivery.next_attempt_at, delivery.created_at, delivery.id
    for update of delivery skip locked
    limit p_limit
  ), claimed as (
    update gymapp_private.push_outbox_deliveries as delivery
    set status = 'processing',
        attempt_count = delivery.attempt_count + 1,
        lease_owner = p_worker_id,
        lease_token = pg_catalog.gen_random_uuid(),
        lease_expires_at = request_time + pg_catalog.make_interval(secs => p_lease_seconds),
        error_code = null,
        provider_status = null,
        updated_at = request_time
    from candidates
    where delivery.id = candidates.id
    returning delivery.*
  )
  select claimed.id,
         claimed.lease_token,
         outbox.id,
         outbox.event_type,
         outbox.object_id,
         outbox.object_revision,
         outbox.collapse_key,
         outbox.priority,
         outbox.expires_at,
         installation.provider,
         installation.environment,
         installation.binding_id,
         installation.provider_token,
         installation.web_push_p256dh,
         installation.web_push_auth,
         installation.locale,
         claimed.attempt_count
  from claimed
  join gymapp_private.push_outbox as outbox on outbox.id = claimed.outbox_id
  join gymapp_private.notification_installations as installation
    on installation.id = claimed.installation_id
  order by claimed.created_at, claimed.id;
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
  select case
    when auth.role() is distinct from 'service_role' then false
    else exists (
      select 1
      from gymapp_private.push_outbox_deliveries as delivery
      join gymapp_private.push_outbox as outbox on outbox.id = delivery.outbox_id
      join gymapp_private.notification_installations as installation
        on installation.id = delivery.installation_id
      where delivery.id = p_delivery_id
        and delivery.status = 'processing'
        and delivery.lease_token = p_lease_token
        and delivery.lease_expires_at > pg_catalog.clock_timestamp()
        and outbox.status = 'pending'
        and outbox.expires_at > pg_catalog.clock_timestamp()
        and installation.revoked_at is null
        and installation.user_id = outbox.recipient_user_id
        and installation.revision = delivery.installation_revision
    )
  end
$function$;

revoke all on function public.push_delivery_is_current(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.push_delivery_is_current(uuid, uuid)
  to service_role;

create or replace function public.push_mark_delivered(
  p_delivery_id uuid,
  p_lease_token uuid,
  p_provider_status integer
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  outbox_id_value uuid;
  request_time timestamptz := pg_catalog.clock_timestamp();
begin
  if p_delivery_id is null
     or p_lease_token is null
     or p_provider_status is null
     or p_provider_status not between 200 and 299 then
    raise exception using errcode = '22023', message = 'Push delivery result is invalid.';
  end if;
  update gymapp_private.push_outbox_deliveries as delivery
  set status = 'delivered',
      lease_owner = null,
      lease_token = null,
      lease_expires_at = null,
      provider_status = p_provider_status,
      error_code = null,
      delivered_at = request_time,
      updated_at = request_time
  where delivery.id = p_delivery_id
    and delivery.status = 'processing'
    and delivery.lease_token = p_lease_token
    and delivery.lease_expires_at > request_time
  returning delivery.outbox_id into outbox_id_value;
  if not found then
    return false;
  end if;
  perform gymapp_private.reconcile_push_outbox(outbox_id_value);
  return true;
end
$function$;

revoke all on function public.push_mark_delivered(uuid, uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.push_mark_delivered(uuid, uuid, integer)
  to service_role;

create or replace function public.push_mark_retry(
  p_delivery_id uuid,
  p_lease_token uuid,
  p_error_code text,
  p_provider_status integer default null,
  p_retry_after_seconds integer default null,
  p_invalid_registration boolean default false,
  p_permanent_failure boolean default false
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  delivery_row gymapp_private.push_outbox_deliveries%rowtype;
  request_time timestamptz := pg_catalog.clock_timestamp();
  backoff_seconds integer;
  affected_outbox_id uuid;
begin
  if p_delivery_id is null
     or p_lease_token is null
     or p_error_code is null
     or p_error_code !~ '^[a-z0-9_:-]{1,64}$'
     or pg_catalog.octet_length(p_error_code) > 64
     or (p_provider_status is not null and p_provider_status not between 100 and 599)
     or (p_retry_after_seconds is not null and p_retry_after_seconds not between 1 and 3600)
     or p_invalid_registration is null
     or p_permanent_failure is null
     or (p_invalid_registration and p_permanent_failure) then
    raise exception using errcode = '22023', message = 'Push retry result is invalid.';
  end if;
  select delivery.* into delivery_row
  from gymapp_private.push_outbox_deliveries as delivery
  where delivery.id = p_delivery_id
    and delivery.status = 'processing'
    and delivery.lease_token = p_lease_token
    and delivery.lease_expires_at > request_time
  for update;
  if not found then
    return false;
  end if;

  if p_invalid_registration then
    update gymapp_private.notification_installations as installation
    set provider_token = null,
        web_push_p256dh = null,
        web_push_auth = null,
        binding_id = pg_catalog.gen_random_uuid(),
        revoked_at = request_time,
        updated_at = request_time,
        revision = least(installation.revision + 1, 2147483647)
    where installation.id = delivery_row.installation_id
      and installation.revision = delivery_row.installation_revision
      and installation.revoked_at is null;
    for affected_outbox_id in
      with affected_deliveries as (
        select delivery.id
        from gymapp_private.push_outbox_deliveries as delivery
        where delivery.installation_id = delivery_row.installation_id
          and delivery.installation_revision = delivery_row.installation_revision
          and delivery.status in ('pending', 'processing')
        order by (delivery.id = delivery_row.id) desc,
                 delivery.created_at, delivery.id
        for update skip locked
        limit 500
      ), changed_deliveries as (
        update gymapp_private.push_outbox_deliveries as delivery
        set status = 'invalid',
            lease_owner = null,
            lease_token = null,
            lease_expires_at = null,
            provider_status = p_provider_status,
            error_code = p_error_code,
            updated_at = request_time
        from affected_deliveries
        where delivery.id = affected_deliveries.id
        returning delivery.outbox_id
      )
      select distinct changed.outbox_id
      from changed_deliveries as changed
    loop
      perform gymapp_private.reconcile_push_outbox(affected_outbox_id);
    end loop;
  elsif p_permanent_failure or delivery_row.attempt_count >= 8 then
    update gymapp_private.push_outbox_deliveries as delivery
    set status = 'dead',
        lease_owner = null,
        lease_token = null,
        lease_expires_at = null,
        provider_status = p_provider_status,
        error_code = p_error_code,
        updated_at = request_time
    where delivery.id = delivery_row.id;
  else
    backoff_seconds := coalesce(
      p_retry_after_seconds,
      least(3600, (15 * pg_catalog.power(2::numeric, delivery_row.attempt_count - 1))::integer)
    );
    update gymapp_private.push_outbox_deliveries as delivery
    set status = 'pending',
        next_attempt_at = request_time + pg_catalog.make_interval(secs => backoff_seconds),
        lease_owner = null,
        lease_token = null,
        lease_expires_at = null,
        provider_status = p_provider_status,
        error_code = p_error_code,
        updated_at = request_time
    where delivery.id = delivery_row.id;
  end if;

  if not p_invalid_registration then
    perform gymapp_private.reconcile_push_outbox(delivery_row.outbox_id);
  end if;
  return true;
end
$function$;

revoke all on function public.push_mark_retry(
  uuid, uuid, text, integer, integer, boolean, boolean
) from public, anon, authenticated, service_role;
grant execute on function public.push_mark_retry(
  uuid, uuid, text, integer, integer, boolean, boolean
) to service_role;

do $verify$
declare
  relation_name text;
begin
  foreach relation_name in array array[
    'notification_installations', 'notification_rate_limits',
    'push_outbox', 'push_outbox_deliveries'
  ] loop
    if not exists (
      select 1
      from pg_catalog.pg_class as relation
      join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
      where namespace.nspname = 'gymapp_private'
        and relation.relname = relation_name
        and relation.relrowsecurity
    )
       or pg_catalog.has_table_privilege('anon', 'gymapp_private.' || relation_name, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', 'gymapp_private.' || relation_name, 'SELECT')
       or pg_catalog.has_table_privilege('service_role', 'gymapp_private.' || relation_name, 'SELECT') then
      raise exception 'Private push relation % is not deny-by-default.', relation_name;
    end if;
  end loop;

  if not pg_catalog.has_function_privilege(
       'authenticated',
       'public.notification_register_installation(uuid,text,text,text,text,text,text,text,text)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', 'public.notification_revoke_installation(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.notification_register_installation(uuid,text,text,text,text,text,text,text,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', 'public.push_claim_deliveries(uuid,integer,integer)', 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role', 'public.push_claim_deliveries(uuid,integer,integer)', 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role', 'public.push_delivery_is_current(uuid,uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', 'public.push_delivery_is_current(uuid,uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'gymapp_private.enqueue_push_notification(uuid,text,text,bigint,text,text,text,timestamptz)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'gymapp_private.notification_domain_error_response(text,text,text,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'gymapp_private.notification_domain_error_response(text,text,text,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'gymapp_private.notification_domain_error_response(text,text,text,text)',
       'EXECUTE'
     ) then
    raise exception 'Push function grants are broader or narrower than intended.';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
