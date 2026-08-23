begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create table gymapp_private.edge_preauth_windows (
  route text not null,
  source_hash text not null,
  window_started_at timestamptz not null,
  request_count integer not null check (request_count >= 1),
  primary key (route, source_hash)
);

alter table gymapp_private.edge_preauth_windows enable row level security;
revoke all on table gymapp_private.edge_preauth_windows
  from public, anon, authenticated, service_role;

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
  global_limit integer;
  current_window timestamptz := pg_catalog.date_trunc('minute', pg_catalog.clock_timestamp());
  global_hash constant text := pg_catalog.repeat('0', 64);
  source_allowed boolean;
  global_allowed boolean;
begin
  if p_source_hash is null or p_source_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'Invalid pre-authentication source.';
  end if;

  select limits.source_limit, limits.global_limit
  into source_limit, global_limit
  from (values
    ('delete_account', 12, 1200),
    ('social_live', 180, 6000),
    ('garmin_legacy', 90, 3000)
  ) as limits(route, source_limit, global_limit)
  where limits.route = p_route;
  if not found then
    raise exception using errcode = '22023', message = 'Invalid pre-authentication route.';
  end if;

  insert into gymapp_private.edge_preauth_windows as budget (
    route, source_hash, window_started_at, request_count
  ) values (
    p_route, global_hash, current_window, 1
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
     or budget.request_count < global_limit
  returning true into global_allowed;

  if not pg_catalog.coalesce(global_allowed, false) then
    return pg_catalog.jsonb_build_object('allowed', false, 'retryAfter', 60);
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
    'retryAfter', case when pg_catalog.coalesce(source_allowed, false) then 0 else 60 end
  );
end
$function$;

revoke all on function gymapp_private.edge_preauth_debit(text, text)
  from public, anon, authenticated, service_role;
grant execute on function gymapp_private.edge_preauth_debit(text, text)
  to service_role;

create or replace function public.edge_preauth_debit(
  p_route text,
  p_source_hash text
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select gymapp_private.edge_preauth_debit(p_route, p_source_hash)
$function$;

revoke all on function public.edge_preauth_debit(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.edge_preauth_debit(text, text)
  to service_role;

comment on function gymapp_private.edge_preauth_debit(text, text) is
  'Durable per-source and global fixed-window budget before costly public Edge authentication work.';

notify pgrst, 'reload schema';

commit;
