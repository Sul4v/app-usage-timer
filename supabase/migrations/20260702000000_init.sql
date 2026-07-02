-- Capsule — Supabase schema
-- Run in the SQL editor of a new Supabase project (Auth > email enabled).
-- Both apps talk to these two tables through PostgREST with the user's JWT;
-- row-level security keeps every user inside their own rows.

-- Apps the user tracks, one row per (device-)app. iOS rows have no
-- package_name (Apple's app tokens are opaque and never leave the device);
-- Android rows carry the real package name. nickname + limit sync both ways,
-- last-write-wins by updated_at.
create table public.tracked_apps (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text not null check (platform in ('ios', 'android')),
  package_name text,
  nickname text not null,
  limit_minutes int not null default 45 check (limit_minutes between 1 and 1440),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One row per user × app × local calendar day.
-- sessions is an array of {start, end} timestamps (Android: exact;
-- iOS: approximated from Screen Time threshold events).
create table public.daily_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  app_id uuid not null,
  day date not null,
  minutes int not null default 0,
  opens int not null default 0,
  sessions jsonb not null default '[]',
  updated_at timestamptz not null default now(),
  primary key (user_id, app_id, day)
);

create index tracked_apps_user_idx on public.tracked_apps (user_id);
create index daily_usage_user_day_idx on public.daily_usage (user_id, day desc);

alter table public.tracked_apps enable row level security;
alter table public.daily_usage enable row level security;

create policy "own tracked_apps" on public.tracked_apps
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own daily_usage" on public.daily_usage
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Keep updated_at fresh on upserts from the apps.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

create trigger daily_usage_touch before update on public.daily_usage
  for each row execute function public.touch_updated_at();
