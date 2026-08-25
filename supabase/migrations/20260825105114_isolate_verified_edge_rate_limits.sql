begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Keep the existing service-only RPC signature during the Edge rollout, but
-- remove the shared route-wide bucket. Edge callers now pass an HMAC of an
-- already-verified account or Auth session, so one principal can consume only
-- its own fixed-window allowance. The legacy Garmin Edge pre-check is removed;
-- its existing database wrappers resolve a valid device before charging the
-- durable per-device limiter.
create or replace function gymapp_private.edge_preauth_debit(
  p_route text,
  p_source_hash text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  source_limit integer;
  current_window timestamptz := pg_catalog.date_trunc(
    'minute',
    pg_catalog.clock_timestamp()
  );
  source_allowed boolean;
begin
  if p_source_hash is null or p_source_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'Invalid verified identity.';
  end if;

  select limits.source_limit
  into source_limit
  from (values
    ('delete_account', 12),
    ('social_live', 180),
    ('garmin_legacy', 90)
  ) as limits(route, source_limit)
  where limits.route = p_route;
  if not found then
    raise exception using errcode = '22023', message = 'Invalid verified-identity route.';
  end if;

  insert into gymapp_private.edge_preauth_windows as budget (
    route, source_hash, window_started_at, request_count
  ) values (
    p_route, p_source_hash, current_window, 1
  )
  on conflict (route, source_hash) do update
  set window_started_at = case
        when budget.window_started_at < current_window then current_window
        else budget.window_started_at
      end,
      request_count = case
        when budget.window_started_at < current_window then 1
        else budget.request_count + 1
      end
  where budget.window_started_at < current_window
     or budget.request_count < source_limit
  returning true into source_allowed;

  if pg_catalog.mod(pg_catalog.hashtextextended(p_source_hash, 0), 128) = 0 then
    delete from gymapp_private.edge_preauth_windows
    where window_started_at < current_window - interval '10 minutes';
  end if;

  return pg_catalog.jsonb_build_object(
    'allowed', pg_catalog.coalesce(source_allowed, false),
    'retryAfter', case
      when pg_catalog.coalesce(source_allowed, false) then 0
      else 60
    end
  );
end
$function$;

revoke all on function gymapp_private.edge_preauth_debit(text, text)
  from public, anon, authenticated, service_role;

comment on function gymapp_private.edge_preauth_debit(text, text) is
  'Durable fixed-window budget for an HMAC-pseudonymized identity verified by an Edge Function.';

-- The previous all-zero rows were shared route-wide counters. They contain no
-- user data and are no longer read by the replacement function.
delete from gymapp_private.edge_preauth_windows
where source_hash = pg_catalog.repeat('0', 64);

do $verify$
declare
  limiter_source text;
begin
  select procedure.prosrc
  into strict limiter_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'gymapp_private.edge_preauth_debit(text,text)'
  );

  if pg_catalog.strpos(limiter_source, 'global_hash') <> 0
     or pg_catalog.strpos(limiter_source, 'global_limit') <> 0
     or pg_catalog.strpos(limiter_source, 'p_source_hash') = 0
     or pg_catalog.has_function_privilege(
       'anon',
       'public.edge_preauth_debit(text,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.edge_preauth_debit(text,text)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.edge_preauth_debit(text,text)',
       'EXECUTE'
     ) then
    raise exception 'Verified Edge identity budget contract is not isolated';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
