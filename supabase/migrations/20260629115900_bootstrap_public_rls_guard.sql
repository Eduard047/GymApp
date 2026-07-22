begin;

-- Production already had this DDL guard before the repository migration
-- history was captured. Recreate it only when bootstrapping a clean project so
-- the checked-in migrations are self-contained without rewriting an applied
-- migration or changing an existing production definition.
do $bootstrap_function$
begin
  if to_regprocedure('public.rls_auto_enable()') is null then
    execute $create_function$
      create function public.rls_auto_enable()
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
            begin
              execute format(
                'alter table if exists %s enable row level security',
                command_record.object_identity
              );
            exception
              when others then
                raise log 'rls_auto_enable: failed to enable RLS on %',
                  command_record.object_identity;
            end;
          end if;
        end loop;
      end
      $function$
    $create_function$;
  elsif not exists (
    select 1
    from pg_proc as procedure
    where procedure.oid = 'public.rls_auto_enable()'::regprocedure
      and procedure.prorettype = 'event_trigger'::regtype
  ) then
    raise exception 'public.rls_auto_enable() exists with an incompatible return type';
  end if;
end
$bootstrap_function$;

revoke all on function public.rls_auto_enable()
  from public, anon, authenticated;

do $bootstrap_trigger$
declare
  existing_function regprocedure;
  existing_event text;
  existing_tags text[];
begin
  select
    trigger.evtfoid::regprocedure,
    trigger.evtevent,
    trigger.evttags
  into existing_function, existing_event, existing_tags
  from pg_event_trigger as trigger
  where trigger.evtname = 'ensure_rls';

  if not found then
    create event trigger ensure_rls
      on ddl_command_end
      when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      execute function public.rls_auto_enable();
  elsif existing_function <> 'public.rls_auto_enable()'::regprocedure
    or existing_event <> 'ddl_command_end'
    or existing_tags is distinct from
      array['CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO']::text[] then
    raise exception 'ensure_rls exists with an unexpected definition';
  end if;
end
$bootstrap_trigger$;

comment on function public.rls_auto_enable() is
  'Internal DDL guard that enables RLS on newly created public tables.';

commit;
