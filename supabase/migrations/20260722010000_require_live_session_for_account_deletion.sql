begin;

do $preflight$
begin
  if pg_catalog.to_regprocedure('gymapp_private.has_current_auth_session(uuid)') is null then
    raise exception 'GymApp live-session helper is missing';
  end if;
end
$preflight$;

-- Account deletion crosses from an ordinary user bearer to an administrative
-- hard delete. Signature and expiry checks do not invalidate an access token as
-- soon as its Supabase session is removed, so derive both identifiers from the
-- signed request and require their live database binding before returning the
-- only user id the Edge Function may delete.
create or replace function public.require_live_session_for_account_deletion()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
begin
  if caller_user_id is null
     or not gymapp_private.has_current_auth_session(caller_user_id) then
    raise exception using
      errcode = '42501',
      message = 'A current authenticated session is required';
  end if;

  return caller_user_id;
end
$function$;

revoke all on function public.require_live_session_for_account_deletion()
  from public, anon, authenticated, service_role;
grant execute on function public.require_live_session_for_account_deletion()
  to authenticated;

do $verify$
begin
  if not has_function_privilege(
       'authenticated',
       'public.require_live_session_for_account_deletion()',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.require_live_session_for_account_deletion()',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'public.require_live_session_for_account_deletion()',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'gymapp_private.has_current_auth_session(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'gymapp_private.has_current_auth_session(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Account-deletion live-session grants are broader than intended';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
