begin;

-- The native clients persist their own profile row in public.profiles, while the
-- leaderboard is a read-only cross-user projection. Keep the Auth UUID inside
-- trusted database code and expose a separate random, immutable public ID.
do $migration$
declare
  missing_columns text;
begin
  if to_regclass('public.profiles') is null then
    raise exception 'Cannot create leaderboard_public: public.profiles does not exist';
  end if;

  select string_agg(required.column_name, ', ' order by required.column_name)
    into missing_columns
  from (
    values
      ('user_id'),
      ('display_name'),
      ('xp'),
      ('level'),
      ('workouts')
  ) as required(column_name)
  where not exists (
    select 1
    from information_schema.columns existing
    where existing.table_schema = 'public'
      and existing.table_name = 'profiles'
      and existing.column_name = required.column_name
  );

  if missing_columns is not null then
    raise exception
      'Cannot create leaderboard_public: public.profiles is missing columns: %',
      missing_columns;
  end if;
end
$migration$;

-- Auth user IDs are never suitable as public leaderboard identifiers. A prefixed
-- 128-bit random value remains stable for reporting/hiding without revealing or
-- being mathematically derived from auth.users.id.
alter table public.profiles
  add column if not exists public_id text;

update public.profiles
set public_id = 'p_' || replace(pg_catalog.gen_random_uuid()::text, '-', '')
where public_id is null;

alter table public.profiles
  alter column public_id
    set default ('p_' || replace(pg_catalog.gen_random_uuid()::text, '-', '')),
  alter column public_id set not null;

create unique index if not exists profiles_public_id_key
  on public.profiles (public_id);

alter table public.profiles
  add constraint profiles_public_id_format
  check (public_id ~ '^p_[0-9a-f]{32}$');

comment on column public.profiles.public_id is
  'Random immutable public leaderboard identifier; unrelated to auth.users.id.';

-- Deleting and recreating a profile would rotate its public ID and bypass report/
-- hide identity. Account deletion must continue through the privileged server flow;
-- its auth.users delete still cascades to profiles and reports.
revoke delete on table public.profiles from public, anon, authenticated;

-- Operators can extend this server-only blocklist without releasing a client.
-- Token matching avoids broad substring false positives; compact matching is
-- reserved for brand-impersonation phrases where separators must not bypass it.
create table public.leaderboard_blocked_terms (
  term text primary key,
  match_mode text not null default 'token'
    check (match_mode in ('token', 'compact')),
  enabled boolean not null default true,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  check (term = pg_catalog.lower(pg_catalog.btrim(term))),
  check (char_length(term) between 3 and 64),
  check (term !~ '[[:space:]]')
);

alter table public.leaderboard_blocked_terms enable row level security;
revoke all on table public.leaderboard_blocked_terms from public, anon, authenticated;
grant select, insert, update, delete
  on table public.leaderboard_blocked_terms
  to service_role;

insert into public.leaderboard_blocked_terms (term, match_mode)
values
  ('fuck', 'token'),
  ('fucker', 'token'),
  ('fucking', 'token'),
  ('shit', 'token'),
  ('bitch', 'token'),
  ('whore', 'token'),
  ('nigger', 'token'),
  ('nigga', 'token'),
  ('faggot', 'token'),
  ('kike', 'token'),
  ('chink', 'token'),
  ('retard', 'token'),
  ('хуй', 'token'),
  ('хуесос', 'token'),
  ('пизда', 'token'),
  ('пиздец', 'token'),
  ('блядь', 'token'),
  ('блять', 'token'),
  ('ебать', 'token'),
  ('ёбать', 'token'),
  ('пидор', 'token'),
  ('підар', 'token'),
  ('сука', 'token'),
  ('gymappadmin', 'compact'),
  ('gymappmoderator', 'compact'),
  ('gymappsupport', 'compact'),
  ('officialgymapp', 'compact'),
  ('setforgeadmin', 'compact'),
  ('setforgesupport', 'compact')
on conflict (term) do nothing;

comment on table public.leaderboard_blocked_terms is
  'Server-managed display-name safety terms. Client roles have no direct access.';

create or replace function public.safe_leaderboard_display_name(raw_name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  cleaned text;
  tokenized text;
  compact text;
  digit_count integer;
begin
  if raw_name is null
     or raw_name ~ '[[:cntrl:]]'
     or pg_catalog.strpos(raw_name, pg_catalog.chr(8203)) > 0
     or pg_catalog.strpos(raw_name, pg_catalog.chr(8204)) > 0
     or pg_catalog.strpos(raw_name, pg_catalog.chr(8205)) > 0
     or pg_catalog.strpos(raw_name, pg_catalog.chr(65279)) > 0 then
    return null;
  end if;

  cleaned := pg_catalog.regexp_replace(
    pg_catalog.btrim(raw_name),
    '[[:space:]]+',
    ' ',
    'g'
  );

  if char_length(cleaned) < 2
     or char_length(cleaned) > 40
     or cleaned !~ '[[:alnum:]]'
     or cleaned ~ '@'
     or cleaned ~* '(https?://|www[.]|discord[.]gg|t[.]me/|[[:alnum:]_-]+[.](com|net|org|io|gg)(/|$))' then
    return null;
  end if;

  digit_count := char_length(
    pg_catalog.regexp_replace(cleaned, '[^0-9]', '', 'g')
  );
  if digit_count >= 7 then
    return null;
  end if;

  tokenized := pg_catalog.lower(
    pg_catalog.regexp_replace(cleaned, '[^[:alnum:]]+', ' ', 'g')
  );
  compact := pg_catalog.lower(
    pg_catalog.regexp_replace(cleaned, '[^[:alnum:]]+', '', 'g')
  );

  if exists (
    select 1
    from public.leaderboard_blocked_terms as blocked
    where blocked.enabled
      and (
        (
          blocked.match_mode = 'token'
          and pg_catalog.strpos(
            ' ' || tokenized || ' ',
            ' ' || blocked.term || ' '
          ) > 0
        )
        or (
          blocked.match_mode = 'compact'
          and pg_catalog.strpos(compact, blocked.term) > 0
        )
      )
  ) then
    return null;
  end if;

  return cleaned;
end
$function$;

comment on function public.safe_leaderboard_display_name(text) is
  'Normalizes a public display name and returns NULL when it violates server safety rules.';

revoke all on function public.safe_leaderboard_display_name(text)
  from public, anon, authenticated;
grant execute on function public.safe_leaderboard_display_name(text)
  to service_role;

create or replace function public.enforce_profile_public_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  safe_name text;
begin
  if tg_op = 'INSERT' then
    -- Always replace a client-supplied value so users cannot choose or correlate IDs.
    new.public_id := 'p_' || replace(pg_catalog.gen_random_uuid()::text, '-', '');
  elsif new.public_id is distinct from old.public_id then
    raise exception using
      errcode = '23514',
      message = 'Profile public_id is immutable.';
  end if;

  safe_name := public.safe_leaderboard_display_name(new.display_name::text);
  if safe_name is null then
    -- Some deployments create a profile from an auth.users trigger before an
    -- authenticated JWT exists. Keep that internal signup transaction available,
    -- but never persist its unreviewed name. Authenticated client writes receive a
    -- validation error so the UI can ask for a different name.
    if tg_op = 'INSERT' and auth.uid() is null then
      safe_name := 'GymApp user';
    else
      raise exception using
        errcode = '23514',
        message = 'Display name violates the leaderboard safety policy.';
    end if;
  end if;

  new.display_name := safe_name;
  return new;
end
$function$;

comment on function public.enforce_profile_public_fields() is
  'Guards immutable public profile IDs and rejects unsafe public display names.';

revoke all on function public.enforce_profile_public_fields()
  from public, anon, authenticated;

drop trigger if exists profiles_public_fields_guard on public.profiles;
create trigger profiles_public_fields_guard
before insert or update of public_id, display_name
on public.profiles
for each row
execute function public.enforce_profile_public_fields();

create or replace function public.leaderboard_public_rows()
returns table (
  profile_id text,
  display_name text,
  xp bigint,
  level bigint,
  workouts bigint,
  is_current_user boolean
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    profile.public_id::text,
    coalesce(
      public.safe_leaderboard_display_name(profile.display_name::text),
      'GymApp user'
    )::text,
    greatest(coalesce(profile.xp, 0), 0)::bigint,
    greatest(coalesce(profile.level, 1), 1)::bigint,
    greatest(coalesce(profile.workouts, 0), 0)::bigint,
    coalesce(profile.user_id = (select auth.uid()), false)
  from public.profiles as profile
  where profile.user_id is not null
$function$;

comment on function public.leaderboard_public_rows() is
  'Authenticated leaderboard projection. SECURITY DEFINER is intentional; it has no arguments or dynamic SQL and returns no Auth UUID.';

-- Functions receive EXECUTE for PUBLIC by default. Remove that implicit grant
-- before exposing the narrowly-scoped capability only to signed-in clients.
revoke all on function public.leaderboard_public_rows() from public, anon, authenticated;
grant execute on function public.leaderboard_public_rows() to authenticated, service_role;

create or replace view public.leaderboard_public
with (security_invoker = true, security_barrier = true)
as
select
  leaderboard_row.profile_id,
  leaderboard_row.display_name,
  leaderboard_row.xp,
  leaderboard_row.level,
  leaderboard_row.workouts,
  leaderboard_row.is_current_user
from public.leaderboard_public_rows() as leaderboard_row;

comment on view public.leaderboard_public is
  'Read-only leaderboard API. profile_id is random and unrelated to auth.users.id.';

revoke all on table public.leaderboard_public from public, anon, authenticated;
grant select on table public.leaderboard_public to authenticated, service_role;

-- Reports are append-only for signed-in clients. Both foreign keys cascade so
-- deleting either account removes its associated report rows.
create table public.leaderboard_reports (
  id text primary key
    default ('r_' || replace(pg_catalog.gen_random_uuid()::text, '-', '')),
  reporter_user_id uuid not null
    references auth.users (id) on delete cascade,
  reported_profile_id text not null
    references public.profiles (public_id) on delete cascade,
  reported_display_name text not null,
  reason text not null
    check (reason in (
      'inappropriate_name',
      'hate_or_harassment',
      'impersonation',
      'spam_or_scam',
      'personal_information',
      'other'
    )),
  status text not null default 'pending'
    check (status in ('pending', 'reviewed', 'actioned', 'dismissed')),
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  check (id ~ '^r_[0-9a-f]{32}$'),
  unique (
    reporter_user_id,
    reported_profile_id,
    reason,
    reported_display_name
  )
);

create index leaderboard_reports_profile_created_idx
  on public.leaderboard_reports (reported_profile_id, created_at desc);

create index leaderboard_reports_status_created_idx
  on public.leaderboard_reports (status, created_at asc);

comment on table public.leaderboard_reports is
  'Insert-only client reports for public leaderboard names; readable only by trusted moderation roles.';

create or replace function public.prepare_leaderboard_report()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_user_id uuid;
  target_user_id uuid;
  target_display_name text;
begin
  caller_user_id := auth.uid();
  if caller_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required to report a leaderboard profile.';
  end if;

  select
    profile.user_id,
    coalesce(
      public.safe_leaderboard_display_name(profile.display_name::text),
      'GymApp user'
    )
  into target_user_id, target_display_name
  from public.profiles as profile
  where profile.public_id = new.reported_profile_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'The reported leaderboard profile does not exist.';
  end if;

  if target_user_id = caller_user_id then
    raise exception using
      errcode = '23514',
      message = 'A profile cannot report itself.';
  end if;

  new.id := 'r_' || replace(pg_catalog.gen_random_uuid()::text, '-', '');
  new.reporter_user_id := caller_user_id;
  new.reported_display_name := target_display_name;
  new.status := 'pending';
  new.created_at := pg_catalog.clock_timestamp();
  return new;
end
$function$;

comment on function public.prepare_leaderboard_report() is
  'Binds a report to the authenticated caller and snapshots the server-filtered target name.';

revoke all on function public.prepare_leaderboard_report()
  from public, anon, authenticated;

create trigger leaderboard_reports_prepare_insert
before insert on public.leaderboard_reports
for each row
execute function public.prepare_leaderboard_report();

alter table public.leaderboard_reports enable row level security;

create policy "authenticated users can submit leaderboard reports"
on public.leaderboard_reports
for insert
to authenticated
with check (reporter_user_id = (select auth.uid()));

revoke all on table public.leaderboard_reports from public, anon, authenticated;
grant insert (reported_profile_id, reason)
  on table public.leaderboard_reports
  to authenticated;
grant select, insert, update, delete
  on table public.leaderboard_reports
  to service_role;

notify pgrst, 'reload schema';

commit;
