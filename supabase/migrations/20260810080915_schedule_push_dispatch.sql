begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
begin
  if pg_catalog.to_regprocedure('public.push_claim_deliveries(uuid,integer,integer)') is null
     or pg_catalog.to_regprocedure('public.push_delivery_is_current(uuid,uuid)') is null then
    raise exception 'GymApp push dispatcher prerequisites are missing.';
  end if;
  if pg_catalog.to_regclass('vault.decrypted_secrets') is null then
    raise exception 'Supabase Vault is required for the push dispatcher schedule.';
  end if;
end
$preflight$;

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

create table gymapp_private.push_dispatch_requests (
  request_id bigint primary key,
  requested_at timestamptz not null default pg_catalog.clock_timestamp(),
  checked_at timestamptz,
  outcome text not null default 'pending'
    check (outcome in ('pending', 'succeeded', 'failed', 'timed_out', 'missing')),
  status_code integer check (status_code is null or status_code between 100 and 599),
  constraint push_dispatch_requests_result_check check (
    (outcome = 'pending' and checked_at is null and status_code is null)
    or (outcome <> 'pending' and checked_at is not null)
  )
);

create index push_dispatch_requests_pending_idx
  on gymapp_private.push_dispatch_requests (requested_at, request_id)
  where outcome = 'pending';
create index push_dispatch_requests_retention_idx
  on gymapp_private.push_dispatch_requests (checked_at, request_id)
  where outcome <> 'pending';

alter table gymapp_private.push_dispatch_requests enable row level security;
revoke all on table gymapp_private.push_dispatch_requests
  from public, anon, authenticated, service_role;

comment on table gymapp_private.push_dispatch_requests is
  'Private bounded monitor for asynchronous pg_net push-dispatch responses; stores no URL, header, token, payload, or response body.';

create or replace function gymapp_private.dispatch_push_notifications()
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  dispatch_url text;
  server_key text;
  dispatch_token text;
  request_id bigint;
begin
  select secret.decrypted_secret into dispatch_url
  from vault.decrypted_secrets as secret
  where secret.name = 'gymapp_push_dispatch_url'
  order by secret.created_at desc
  limit 1;
  select secret.decrypted_secret into server_key
  from vault.decrypted_secrets as secret
  where secret.name = 'gymapp_push_dispatch_server_key'
  order by secret.created_at desc
  limit 1;
  select secret.decrypted_secret into dispatch_token
  from vault.decrypted_secrets as secret
  where secret.name = 'gymapp_push_dispatch_token'
  order by secret.created_at desc
  limit 1;

  -- A fresh migration is deliberately dormant until all three secrets exist.
  -- The URL allowlist prevents a privileged configuration typo from turning
  -- pg_net into an arbitrary network destination.
  if dispatch_url is null or server_key is null or dispatch_token is null then
    return null;
  end if;
  if dispatch_url !~ '^https://[a-z0-9]{20}\.supabase\.co/functions/v1/push-dispatch$'
     or pg_catalog.octet_length(dispatch_url) > 128
     or pg_catalog.octet_length(server_key) not between 32 and 8192
     or server_key ~ '[[:space:]]'
     or dispatch_token !~ '^[A-Za-z0-9_-]{43,256}$' then
    return null;
  end if;

  -- pg_net is asynchronous, so pg_cron finishing does not prove the prior
  -- Edge invocation has finished. Serialize enqueue decisions and keep at
  -- most one recent unresolved scheduler request in flight. A request older
  -- than five minutes is already beyond the 240-second delivery lease and is
  -- classified by the monitor instead of blocking dispatch forever.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gymapp-push-dispatch-scheduler-v1', 0)
  );
  if exists (
    select 1
    from gymapp_private.push_dispatch_requests as tracked
    where tracked.outcome = 'pending'
      and tracked.requested_at >= pg_catalog.clock_timestamp() - interval '5 minutes'
  ) then
    return null;
  end if;

  select net.http_post(
    url := dispatch_url,
    headers := pg_catalog.jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', server_key,
      'X-GymApp-Push-Dispatch-Token', dispatch_token
    ),
    -- Ten deliveries need at most two provider waves with the dispatcher's
    -- five-worker cap. Keep the HTTP timeout comfortably below the delivery
    -- lease while still allowing bounded provider retries.
    body := pg_catalog.jsonb_build_object('version', 1, 'batchSize', 10),
    timeout_milliseconds := 120000
  ) into request_id;
  insert into gymapp_private.push_dispatch_requests (request_id)
  values (request_id);
  return request_id;
end
$function$;

revoke all on function gymapp_private.dispatch_push_notifications()
  from public, anon, authenticated, service_role;

comment on function gymapp_private.dispatch_push_notifications() is
  'Vault-backed, allowlisted pg_net trigger for the private push dispatcher. Returns null while configuration is absent or invalid.';

create or replace function gymapp_private.monitor_push_dispatch_responses()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  request_time timestamptz := pg_catalog.clock_timestamp();
  resolved_count bigint;
  missing_count bigint;
  deleted_count bigint;
begin
  -- pg_net retains responses for only a bounded TTL. Capture the status but
  -- never copy provider bodies, headers, URLs, tokens, or error strings.
  with responses as materialized (
    select tracked.request_id,
           response.status_code,
           response.timed_out,
           response.error_msg
    from gymapp_private.push_dispatch_requests as tracked
    join net._http_response as response on response.id = tracked.request_id
    where tracked.outcome = 'pending'
    order by tracked.requested_at, tracked.request_id
    for update of tracked skip locked
    limit 100
  )
  update gymapp_private.push_dispatch_requests as tracked
  set checked_at = request_time,
      outcome = case
        when responses.timed_out is true then 'timed_out'
        when responses.status_code between 200 and 299
          and responses.error_msg is null then 'succeeded'
        else 'failed'
      end,
      status_code = responses.status_code
  from responses
  where tracked.request_id = responses.request_id;
  get diagnostics resolved_count = row_count;

  with missing as materialized (
    select tracked.request_id
    from gymapp_private.push_dispatch_requests as tracked
    where tracked.outcome = 'pending'
      and tracked.requested_at < request_time - interval '5 minutes'
    order by tracked.requested_at, tracked.request_id
    for update skip locked
    limit 100
  )
  update gymapp_private.push_dispatch_requests as tracked
  set checked_at = request_time,
      outcome = 'missing'
  from missing
  where tracked.request_id = missing.request_id;
  get diagnostics missing_count = row_count;

  with expired as materialized (
    select tracked.request_id
    from gymapp_private.push_dispatch_requests as tracked
    where tracked.outcome <> 'pending'
      and tracked.checked_at < request_time - interval '30 days'
    order by tracked.checked_at, tracked.request_id
    for update skip locked
    limit 500
  )
  delete from gymapp_private.push_dispatch_requests as tracked
  using expired
  where tracked.request_id = expired.request_id;
  get diagnostics deleted_count = row_count;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'resolved', resolved_count,
    'missing', missing_count,
    'deleted', deleted_count
  );
end
$function$;

revoke all on function gymapp_private.monitor_push_dispatch_responses()
  from public, anon, authenticated, service_role;

comment on function gymapp_private.monitor_push_dispatch_responses() is
  'Captures at most 100 asynchronous pg_net outcomes and purges at most 500 private monitor rows per run.';

create or replace function gymapp_private.cleanup_push_dispatch_history()
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  deleted_count bigint;
begin
  -- pg_cron does not purge job_run_details automatically. Restrict cleanup to
  -- GymApp's four jobs and bound every run so a damaged/backlogged history can
  -- never turn the maintenance task into an unbounded delete.
  with expired as materialized (
    select history.runid
    from cron.job_run_details as history
    join cron.job as job on job.jobid = history.jobid
    where job.jobname in (
      'gymapp-push-dispatch-v1',
      'gymapp-push-dispatch-monitor-v1',
      'gymapp-push-dispatch-history-cleanup-v1',
      'gymapp-live-workout-cleanup-v1'
    )
      and job.username = current_user
      and job.database = current_database()
      and coalesce(history.end_time, history.start_time)
        < pg_catalog.clock_timestamp() - interval '7 days'
    order by history.start_time, history.runid
    limit 5000
  )
  delete from cron.job_run_details as history
  using expired
  where history.runid = expired.runid;
  get diagnostics deleted_count = row_count;
  return deleted_count;
end
$function$;

revoke all on function gymapp_private.cleanup_push_dispatch_history()
  from public, anon, authenticated, service_role;

comment on function gymapp_private.cleanup_push_dispatch_history() is
  'Deletes at most 5,000 GymApp live-workout and push cron history rows older than seven days; never touches other jobs.';

do $schedule$
declare
  dispatch_job_id bigint;
  monitor_job_id bigint;
  cleanup_job_id bigint;
begin
  select job.jobid into dispatch_job_id
  from cron.job as job
  where job.jobname = 'gymapp-push-dispatch-v1'
    and job.username = current_user
    and job.database = current_database()
  order by job.jobid desc
  limit 1;
  if dispatch_job_id is null then
    dispatch_job_id := cron.schedule(
      'gymapp-push-dispatch-v1',
      '* * * * *',
      'select gymapp_private.dispatch_push_notifications();'
    );
  end if;
  -- Hosted Supabase does not grant the migration role permission to alter a
  -- cron job's username, even to the same value. The lookup above binds the
  -- job to the current owner/database, and the verification below rechecks
  -- both, so repair only the mutable schedule, command, and active state.
  perform cron.alter_job(
    dispatch_job_id,
    schedule := '* * * * *',
    command := 'select gymapp_private.dispatch_push_notifications();',
    active := true
  );

  select job.jobid into monitor_job_id
  from cron.job as job
  where job.jobname = 'gymapp-push-dispatch-monitor-v1'
    and job.username = current_user
    and job.database = current_database()
  order by job.jobid desc
  limit 1;
  if monitor_job_id is null then
    monitor_job_id := cron.schedule(
      'gymapp-push-dispatch-monitor-v1',
      '* * * * *',
      'select gymapp_private.monitor_push_dispatch_responses();'
    );
  end if;
  perform cron.alter_job(
    monitor_job_id,
    schedule := '* * * * *',
    command := 'select gymapp_private.monitor_push_dispatch_responses();',
    active := true
  );

  select job.jobid into cleanup_job_id
  from cron.job as job
  where job.jobname = 'gymapp-push-dispatch-history-cleanup-v1'
    and job.username = current_user
    and job.database = current_database()
  order by job.jobid desc
  limit 1;
  if cleanup_job_id is null then
    cleanup_job_id := cron.schedule(
      'gymapp-push-dispatch-history-cleanup-v1',
      '17 3 * * *',
      'select gymapp_private.cleanup_push_dispatch_history();'
    );
  end if;
  perform cron.alter_job(
    cleanup_job_id,
    schedule := '17 3 * * *',
    command := 'select gymapp_private.cleanup_push_dispatch_history();',
    active := true
  );
end
$schedule$;

do $verify$
begin
  if pg_catalog.has_function_privilege(
       'anon', 'gymapp_private.dispatch_push_notifications()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', 'gymapp_private.dispatch_push_notifications()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'gymapp_private.dispatch_push_notifications()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'gymapp_private.cleanup_push_dispatch_history()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', 'gymapp_private.cleanup_push_dispatch_history()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'gymapp_private.cleanup_push_dispatch_history()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'gymapp_private.monitor_push_dispatch_responses()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated', 'gymapp_private.monitor_push_dispatch_responses()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'gymapp_private.monitor_push_dispatch_responses()', 'EXECUTE'
     )
     or pg_catalog.has_table_privilege(
       'anon', 'gymapp_private.push_dispatch_requests', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'gymapp_private.push_dispatch_requests', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'service_role', 'gymapp_private.push_dispatch_requests', 'SELECT'
     )
     or not exists (
       select 1 from cron.job as job
       where job.jobname = 'gymapp-push-dispatch-v1'
         and job.schedule = '* * * * *'
         and job.command = 'select gymapp_private.dispatch_push_notifications();'
         and job.database = current_database()
         and job.username = current_user
         and job.active
     )
     or not exists (
       select 1 from cron.job as job
       where job.jobname = 'gymapp-push-dispatch-monitor-v1'
         and job.schedule = '* * * * *'
         and job.command = 'select gymapp_private.monitor_push_dispatch_responses();'
         and job.database = current_database()
         and job.username = current_user
         and job.active
     )
     or not exists (
       select 1 from cron.job as job
       where job.jobname = 'gymapp-push-dispatch-history-cleanup-v1'
         and job.schedule = '17 3 * * *'
         and job.command = 'select gymapp_private.cleanup_push_dispatch_history();'
         and job.database = current_database()
         and job.username = current_user
         and job.active
     ) then
    raise exception 'GymApp push dispatcher schedule is not deny-by-default or deterministic.';
  end if;
end
$verify$;

commit;
