begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
begin
  if pg_catalog.to_regprocedure(
    'public.edge_preauth_debit(text,text)'
  ) is null then
    raise exception 'GymApp Edge pre-authentication wrapper is missing.';
  end if;
end
$preflight$;

-- The service_role intentionally has no USAGE on gymapp_private. Keep that
-- least-privilege boundary and let this narrowly granted wrapper cross it as
-- its owner instead of granting the role access to the entire private schema.
alter function public.edge_preauth_debit(text, text) security definer;
alter function public.edge_preauth_debit(text, text) set search_path = '';
revoke all on function public.edge_preauth_debit(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.edge_preauth_debit(text, text)
  to service_role;

comment on function public.edge_preauth_debit(text, text) is
  'Service-only wrapper that crosses the private-schema boundary without granting schema-wide USAGE.';

notify pgrst, 'reload schema';

commit;
