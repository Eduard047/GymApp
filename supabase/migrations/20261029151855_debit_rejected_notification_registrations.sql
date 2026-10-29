begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regclass('gymapp_private.notification_installations') is null
     or pg_catalog.to_regclass('gymapp_private.notification_rate_limits') is null
     or pg_catalog.to_regprocedure(
       'public.notification_register_installation(uuid,text,text,text,text,text,text,text,text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.notification_register_installation_session_v2(uuid,text,text,text,text,text,text,text,text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.consume_notification_rate_limit(uuid,text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.notification_domain_error_response(text,text,text,text)'
     ) is null then
    raise exception 'GymApp push registration debit prerequisites are missing.';
  end if;
end
$preflight$;

-- The ownership wrapper used to raise 22023 for malformed ids, malformed
-- addresses, and foreign-installation mismatches before the rate-limit debit
-- inside the delegated worker ran. Those rejections were never debited and
-- surfaced as raw errors instead of the legacy JSON body. The pre-checks now
-- run in a nested block whose 22023 handler debits the register bucket after
-- the block rolled back and returns the same body the worker returns. Valid
-- and worker-rejected calls still debit exactly once, inside the worker.
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
  requested_fingerprint text;
  foreign_installation gymapp_private.notification_installations%rowtype;
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  if caller_user_id is null
     or not gymapp_private.current_auth_session_is_live() then
    raise exception using errcode = '42501', message = 'A current authenticated session is required.';
  end if;

  begin
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
  exception
    when sqlstate '22023' then
      get stacked diagnostics
        domain_error_code = returned_sqlstate,
        domain_error_message = message_text,
        domain_error_detail = pg_exception_detail,
        domain_error_hint = pg_exception_hint;
      if domain_error_code is null or domain_error_message is null
         or domain_error_code <> '22023'
         or domain_error_message <> 'Notification registration is invalid.' then
        raise;
      end if;
      -- The nested block has rolled back, so this debit persists. An empty
      -- bucket raises the same P0001 rate-limit error as the delegated path.
      perform gymapp_private.consume_notification_rate_limit(caller_user_id, 'register');
      return gymapp_private.notification_domain_error_response(
        domain_error_code,
        domain_error_message,
        domain_error_detail,
        domain_error_hint
      );
  end;

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

comment on function public.notification_register_installation(
  uuid, text, text, text, text, text, text, text, text
) is
  'Registers an owner session-bound push address; foreign installation UUID transfer requires exact provider-address possession; rejected registrations are debited and return the legacy 22023 body.';

notify pgrst, 'reload schema';

commit;
