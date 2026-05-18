create table if not exists public.user_states (
  user_id uuid primary key references auth.users(id) on delete cascade,
  state jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  xp integer not null default 0,
  level integer not null default 1,
  workouts integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.user_states enable row level security;
alter table public.profiles enable row level security;

drop policy if exists "Users can read own state" on public.user_states;
create policy "Users can read own state"
on public.user_states for select
using (auth.uid() = user_id);

drop policy if exists "Users can write own state" on public.user_states;
create policy "Users can write own state"
on public.user_states for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own state" on public.user_states;
create policy "Users can update own state"
on public.user_states for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Leaderboard is public" on public.profiles;
create policy "Leaderboard is public"
on public.profiles for select
using (true);

drop policy if exists "Users can insert own profile" on public.profiles;
create policy "Users can insert own profile"
on public.profiles for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
on public.profiles for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create or replace view public.leaderboard as
select
  display_name,
  xp,
  level,
  workouts,
  updated_at
from public.profiles
order by xp desc, workouts desc, updated_at asc;
