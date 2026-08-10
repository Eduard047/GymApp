begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regprocedure(
       'gymapp_private.dispatch_push_notifications()'
     ) is null
     or pg_catalog.to_regclass(
       'gymapp_private.push_dispatch_requests'
     ) is null then
    raise exception 'GymApp push-dispatch scheduler prerequisites are missing.';
  end if;
end
$preflight$;

create or replace function gymapp_private.dispatch_push_notifications()
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  dispatch_url text;
  server_key text;
  dispatch_token text;
  request_id bigint;
begin
  select secret.decrypted_secret into dispatch_url
  from vault.decrypted_secrets as secret
  where secret.name = 'gymapp_push_dispatch_url'
  order by secret.created_at desc
  limit 1;
  select secret.decrypted_secret into server_key
  from vault.decrypted_secrets as secret
  where secret.name = 'gymapp_push_dispatch_server_key'
  order by secret.created_at desc
  limit 1;
  select secret.decrypted_secret into dispatch_token
  from vault.decrypted_secrets as secret
  where secret.name = 'gymapp_push_dispatch_token'
  order by secret.created_at desc
  limit 1;

  if dispatch_url is null or server_key is null or dispatch_token is null then
    return null;
  end if;
  if dispatch_url !~ '^https://[a-z0-9]{20}\.supabase\.co/functions/v1/push-dispatch$'
     or pg_catalog.octet_length(dispatch_url) > 128
     or pg_catalog.octet_length(server_key) not between 32 and 8192
     or server_key ~ '[[:space:]]'
     or pg_catalog.octet_length(dispatch_token) not between 43 and 256
     or dispatch_token !~ '^[A-Za-z0-9_-]+$' then
    return null;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gymapp-push-dispatch-scheduler-v1', 0)
  );
  if exists (
    select 1
    from gymapp_private.push_dispatch_requests as tracked
    where tracked.outcome = 'pending'
      and tracked.requested_at >= pg_catalog.clock_timestamp() - interval '5 minutes'
  ) then
    return null;
  end if;

  select net.http_post(
    url := dispatch_url,
    headers := pg_catalog.jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', server_key,
      'X-GymApp-Push-Dispatch-Token', dispatch_token
    ),
    body := pg_catalog.jsonb_build_object('version', 1, 'batchSize', 10),
    timeout_milliseconds := 120000
  ) into request_id;
  insert into gymapp_private.push_dispatch_requests (request_id)
  values (request_id);
  return request_id;
end
$function$;

revoke all on function gymapp_private.dispatch_push_notifications()
  from public, anon, authenticated, service_role;

comment on function gymapp_private.dispatch_push_notifications() is
  'Vault-backed, allowlisted pg_net trigger for the private push dispatcher. Returns null while configuration is absent or invalid.';

do $verify$
declare
  function_definition text := pg_catalog.pg_get_functiondef(
    'gymapp_private.dispatch_push_notifications()'::pg_catalog.regprocedure
  );
begin
  if function_definition not like '%octet_length(dispatch_token) not between 43 and 256%'
     or function_definition not like '%dispatch_token !~ ''^[A-Za-z0-9_-]+$''%'
     or function_definition like '%{43,256}%'
     or pg_catalog.has_function_privilege(
       'anon',
       'gymapp_private.dispatch_push_notifications()',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'gymapp_private.dispatch_push_notifications()',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'gymapp_private.dispatch_push_notifications()',
       'EXECUTE'
     ) then
    raise exception 'GymApp push-dispatch token validation is not hardened.';
  end if;
end
$verify$;

commit;
