-- KlimaBilanz cloud schema (Supabase / Postgres)
-- Run in the Supabase SQL editor or with `supabase db push`.
-- Every row belongs to exactly one user (auth.uid()); Row Level Security enforces isolation.
-- Columns mirror the app's SyncService DTOs (snake_case). Soft deletes via deleted_at keep sync consistent.

create extension if not exists "pgcrypto";

-- Keeps updated_at monotonic on the server when a client sends an older timestamp.
create or replace function public.kb_touch_updated_at()
returns trigger language plpgsql as $$
begin
  if new.updated_at is null or new.updated_at < coalesce(old.updated_at, new.updated_at) then
    new.updated_at := now();
  end if;
  return new;
end $$;

-- Profiles ----------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.kb_handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (new.id,
          coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
          coalesce(new.raw_user_meta_data ->> 'avatar_url', new.raw_user_meta_data ->> 'picture'))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists kb_on_auth_user_created on auth.users;
create trigger kb_on_auth_user_created
  after insert on auth.users for each row execute function public.kb_handle_new_user();

-- Tickets -----------------------------------------------------------------
create table if not exists public.tickets (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  product_id text not null,
  name text not null,
  variant text not null default 'klassik',
  family text not null default 'oe',
  states text not null default '',
  price numeric(10,2) not null default 0,
  start_date timestamptz not null,
  end_date timestamptz not null,
  holder_name text not null default '',
  ticket_number text not null default '',
  theme text not null default 'aurora',
  reminders text not null default '30,7,1',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists tickets_user_updated on public.tickets (user_id, updated_at);

-- Trips -------------------------------------------------------------------
create table if not exists public.trips (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date timestamptz not null,
  from_name text not null,
  to_name text not null,
  from_station_id text,
  to_station_id text,
  mode text not null default 'train',
  distance_km double precision not null default 0,
  fare_eur numeric(10,2) not null default 0,
  is_fare_manual boolean not null default false,
  is_round_trip boolean not null default false,
  travel_class text not null default 'second',
  companions integer not null default 0,
  states text not null default '',
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists trips_user_updated on public.trips (user_id, updated_at);
create index if not exists trips_user_date on public.trips (user_id, date desc);

-- Favourite routes --------------------------------------------------------
create table if not exists public.favorite_routes (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null default '',
  from_name text not null,
  to_name text not null,
  from_station_id text,
  to_station_id text,
  mode text not null default 'train',
  distance_km double precision not null default 0,
  fare_eur numeric(10,2) not null default 0,
  is_round_trip boolean not null default false,
  states text not null default '',
  sort_index integer not null default 0,
  usage_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists favorite_routes_user_updated on public.favorite_routes (user_id, updated_at);

-- Triggers & RLS ----------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['profiles', 'tickets', 'trips', 'favorite_routes'] loop
    execute format('drop trigger if exists kb_touch on public.%I', t);
    execute format('create trigger kb_touch before update on public.%I for each row execute function public.kb_touch_updated_at()', t);
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles
  for all using (id = auth.uid()) with check (id = auth.uid());

do $$
declare t text;
begin
  foreach t in array array['tickets', 'trips', 'favorite_routes'] loop
    execute format('drop policy if exists "own rows" on public.%I', t);
    execute format('create policy "own rows" on public.%I for all using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end $$;
