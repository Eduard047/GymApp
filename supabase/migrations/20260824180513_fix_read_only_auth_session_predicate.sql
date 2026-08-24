begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regclass('auth.sessions') is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.current_auth_session_is_live()'
     ) is null then
    raise exception 'GymApp live-session predicate prerequisites are missing.';
  end if;
end
$preflight$;

-- PostgREST executes GET and HEAD table requests in READ ONLY transactions.
-- Such requests must validate the exact Auth session without taking a row
-- lock. Mutating requests remain READ WRITE and retain the key-share lock so
-- session deletion/revocation stays ordered against owner writes.
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

  if pg_catalog.current_setting('transaction_read_only')::boolean then
    return exists (
      select 1
      from auth.sessions as session
      where session.id = session_id_text::uuid
        and session.user_id = caller_user_id
        and (
          session.not_after is null
          or session.not_after > pg_catalog.clock_timestamp()
        )
    );
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

comment on function gymapp_private.current_auth_session_is_live() is
  'RLS predicate that validates the exact unexpired Auth session without locking reads and key-share locks writes.';

notify pgrst, 'reload schema';

commit;
