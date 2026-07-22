begin;

-- The original production bootstrap logged and ignored ALTER TABLE failures.
-- Make the guard fail closed: a public table must not be created if RLS cannot
-- be enabled in the same DDL transaction.
create or replace function public.rls_auto_enable()
returns event_trigger
language plpgsql
security definer
set search_path = 'pg_catalog'
as $function$
declare
  command_record record;
begin
  for command_record in
    select *
    from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      and object_type in ('table', 'partitioned table')
  loop
    if command_record.schema_name = 'public' then
      execute format(
        'alter table if exists %s enable row level security',
        command_record.object_identity
      );
    end if;
  end loop;
end
$function$;

revoke all on function public.rls_auto_enable()
  from public, anon, authenticated;

do $guard_audit$
declare
  trigger_function regprocedure;
  trigger_event text;
  trigger_tags text[];
begin
  select
    trigger.evtfoid::regprocedure,
    trigger.evtevent,
    trigger.evttags
  into strict trigger_function, trigger_event, trigger_tags
  from pg_event_trigger as trigger
  where trigger.evtname = 'ensure_rls';

  if trigger_function <> 'public.rls_auto_enable()'::regprocedure
    or trigger_event <> 'ddl_command_end'
    or trigger_tags is distinct from
      array['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[] then
    raise exception 'ensure_rls exists with an unexpected definition';
  end if;

  if has_function_privilege('anon', 'public.rls_auto_enable()', 'EXECUTE')
    or has_function_privilege(
      'authenticated',
      'public.rls_auto_enable()',
      'EXECUTE'
    ) then
    raise exception 'rls_auto_enable remains client-executable';
  end if;
end
$guard_audit$;

comment on function public.rls_auto_enable() is
  'Fail-closed internal DDL guard that enables RLS on newly created public tables.';

commit;
