create or replace function gymapp_private.social_begin_direct_request()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid := auth.uid();
  session_id_text text := auth.jwt() ->> 'session_id';
  session_id uuid;
  v_source_hash text;
  reservation_result jsonb;
  reservation_released boolean;
begin
  if caller_user_id is null
     or session_id_text is null
     or session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception using errcode = '42501', message = 'A live authenticated session is required.';
  end if;
  session_id := session_id_text::uuid;
  v_source_hash := gymapp_private.social_session_budget_hash(
    'social_live',
    session_id
  );
  reservation_result := gymapp_private.social_session_aggregate_debit(
    'social_live',
    caller_user_id,
    session_id
  );
  if reservation_result ->> 'allowed' <> 'true' then
    return reservation_result;
  end if;

  delete from gymapp_private.edge_preauth_windows as budget
  where budget.route = 'social_live'
    and budget.source_hash = v_source_hash
    and budget.request_count = 1
  returning true into reservation_released;
  if not found then
    update gymapp_private.edge_preauth_windows as budget
    set request_count = budget.request_count - 1
    where budget.route = 'social_live'
      and budget.source_hash = v_source_hash
      and budget.request_count > 1
    returning true into reservation_released;
  end if;
  if not coalesce(reservation_released, false) then
    raise exception 'GymApp social aggregate reservation could not be released.';
  end if;
  return reservation_result;
end
$function$;
