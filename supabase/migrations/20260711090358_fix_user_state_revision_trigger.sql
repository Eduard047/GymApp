-- Fix the server-owned user_states revision trigger deployed by the hardening
-- migration. GREATEST is PostgreSQL conditional syntax, not a schema-qualified
-- pg_catalog function, so pg_catalog.greatest(...) failed at runtime.

create or replace function public.set_user_state_server_revision()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  current_revision timestamp with time zone := pg_catalog.clock_timestamp();
begin
  if tg_op = 'INSERT' then
    new.updated_at := current_revision;
  else
    new.updated_at := old.updated_at + interval '1 microsecond';
    if current_revision > new.updated_at then
      new.updated_at := current_revision;
    end if;
  end if;

  return new;
end
$function$;

comment on function public.set_user_state_server_revision() is
  'Owns the user_states optimistic-concurrency revision on the database server.';

revoke all on function public.set_user_state_server_revision()
  from public, anon, authenticated;
