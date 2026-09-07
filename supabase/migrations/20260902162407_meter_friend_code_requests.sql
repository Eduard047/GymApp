begin;

set local lock_timeout = '5s';
set local statement_timeout = '2min';

do $preflight$
begin
  if pg_catalog.to_regprocedure('public.social_my_friend_code()') is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.social_begin_direct_request()'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.social_require_caller(text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.social_commit_direct_rejection(text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.social_rate_limit_response(text)'
     ) is null
     or pg_catalog.to_regprocedure(
       'gymapp_private.social_domain_error_response(text,text,text,text)'
     ) is null then
    raise exception 'GymApp friend-code budget prerequisites are missing.';
  end if;
  if pg_catalog.to_regprocedure(
       'gymapp_private.social_my_friend_code_storage_v1()'
     ) is not null
     or pg_catalog.to_regprocedure(
       'gymapp_private.social_my_friend_code_direct_worker()'
     ) is not null then
    raise exception 'GymApp friend-code budget worker already exists.';
  end if;
end
$preflight$;

-- Preserve the established response and lazy code creation as an unreachable
-- storage worker. The public signature below adds the same durable aggregate,
-- gateway-action, and domain-action accounting used by other direct social
-- reads. Friend-code lookup shares the existing bounded friend_details read
-- lane instead of adding a divergent public contract or unbounded state.
alter function public.social_my_friend_code()
  set schema gymapp_private;
alter function gymapp_private.social_my_friend_code()
  rename to social_my_friend_code_storage_v1;
revoke all on function gymapp_private.social_my_friend_code_storage_v1()
  from public, anon, authenticated, service_role;

create or replace function gymapp_private.social_my_friend_code_direct_worker()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  reservation_result jsonb;
  rejection_result jsonb;
  domain_error_code text;
  domain_error_message text;
  domain_error_detail text;
  domain_error_hint text;
begin
  reservation_result := gymapp_private.social_begin_direct_request();
  if reservation_result ->> 'allowed' <> 'true' then
    return gymapp_private.social_rate_limit_response(
      'retry_after=' || coalesce(
        reservation_result ->> 'retryAfter',
        '60'
      )
    );
  end if;

  begin
    -- social_require_caller performs one exact-session aggregate debit plus
    -- both durable read-action debits. The original worker repeats its live
    -- session check before creating or returning the private code.
    perform gymapp_private.social_require_caller('friend_details');
    return gymapp_private.social_my_friend_code_storage_v1();
  exception
    when sqlstate 'PT429' then
      get stacked diagnostics domain_error_detail = pg_exception_detail;
      rejection_result := gymapp_private.social_commit_direct_rejection(
        'friend_details'
      );
      return gymapp_private.social_rate_limit_response(
        case
          when rejection_result ->> 'allowed' <> 'true' then
            'retry_after=' || coalesce(
              rejection_result ->> 'retryAfter',
              '60'
            )
          else domain_error_detail
        end
      );
    when sqlstate '22023' or sqlstate 'P0001' or sqlstate 'P0002' then
      get stacked diagnostics
        domain_error_code = returned_sqlstate,
        domain_error_message = message_text,
        domain_error_detail = pg_exception_detail,
        domain_error_hint = pg_exception_hint;
      rejection_result := gymapp_private.social_commit_direct_rejection(
        'friend_details'
      );
      if rejection_result ->> 'allowed' <> 'true' then
        return gymapp_private.social_rate_limit_response(
          'retry_after=' || coalesce(
            rejection_result ->> 'retryAfter',
            '60'
          )
        );
      end if;
      return gymapp_private.social_domain_error_response(
        domain_error_code,
        domain_error_message,
        domain_error_detail,
        domain_error_hint
      );
  end;
end
$function$;

revoke all on function gymapp_private.social_my_friend_code_direct_worker()
  from public, anon, authenticated, service_role;

create function public.social_my_friend_code()
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $function$
  select gymapp_private.social_my_friend_code_direct_worker()
$function$;

revoke all on function public.social_my_friend_code()
  from public, anon, authenticated, service_role;
grant execute on function public.social_my_friend_code()
  to authenticated;

comment on function public.social_my_friend_code() is
  'Returns friend-code response v1 through exact-session aggregate and shared bounded social-read budgets, creating the private code lazily.';
comment on function gymapp_private.social_my_friend_code_direct_worker() is
  'Durably accounts successful and expected-rejection friend-code requests before preserving the established response contract.';

do $verify$
declare
  wrapper_source text;
  worker_source text;
begin
  select procedure.prosrc into strict wrapper_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'public.social_my_friend_code()'
  );
  select procedure.prosrc into strict worker_source
  from pg_catalog.pg_proc as procedure
  where procedure.oid = pg_catalog.to_regprocedure(
    'gymapp_private.social_my_friend_code_direct_worker()'
  );

  if pg_catalog.strpos(
       pg_catalog.lower(wrapper_source),
       'social_my_friend_code_direct_worker'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(worker_source),
       'social_begin_direct_request'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(worker_source),
       'social_require_caller'
     ) = 0
     or pg_catalog.strpos(
       pg_catalog.lower(worker_source),
       'social_commit_direct_rejection'
     ) = 0
     or pg_catalog.has_function_privilege(
       'anon', 'public.social_my_friend_code()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'public.social_my_friend_code()', 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', 'public.social_my_friend_code()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'gymapp_private.social_my_friend_code_storage_v1()',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'gymapp_private.social_my_friend_code_direct_worker()',
       'EXECUTE'
     ) then
    raise exception 'GymApp friend-code budget verification failed.';
  end if;
end
$verify$;

notify pgrst, 'reload schema';

commit;
