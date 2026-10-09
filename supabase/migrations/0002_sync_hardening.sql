-- KlimaBilanz cloud schema – migration 0002 "sync hardening" (Supabase / Postgres 15+)
-- Apply AFTER 0001_init.sql (SQL editor or `supabase db push`). Idempotent: running it again is a no-op.
-- Requires an app build that sends `on_conflict=user_id,id` (SyncService from this migration on).
--
-- What changes compared to 0001:
--  * server_rev (bigint) on every synced table, assigned by the SERVER on each insert/update.
--    It is the pull cursor (keyset pagination on (server_rev, id)), so device clocks are never used as a cursor.
--    Value = microseconds since epoch of clock_timestamp(), and always > the row's previous value.
--    It is time based instead of a plain sequence on purpose: neither a sequence nor a clock is visible in commit
--    order, but a time based value lets clients re-read a fixed overlap window (2 minutes) behind their cursor,
--    which covers transactions that committed late. Re-read rows are harmless (the client merge is idempotent).
--  * Last-writer-wins guard instead of 0001's kb_touch_updated_at (which bumped stale writes to now(), so a device
--    with old data could overwrite newer edits):
--      - far-future client clocks are clamped (updated_at > now() + 10 min → now()),
--      - an UPDATE with an older updated_at than the stored row is skipped (BEFORE trigger returns NULL; this is
--        silent, also inside INSERT … ON CONFLICT DO UPDATE as used by PostgREST upserts),
--      - an UPDATE that changes nothing but updated_at is skipped too (no server_rev bump → no echo loops),
--      - user_id, id and created_at are immutable on UPDATE.
--  * Primary key (user_id, id) instead of (id): the same local row can be copied into another account
--    (account switch → "merge") without colliding with the previous account's copy.
--  * Foreign keys to auth.users are ON DELETE CASCADE (account deletion removes every row).
--  * Columns for newer app models (ticket add-ons / employer share / auto renewal, trip & favourite category,
--    induced trips) and the table benefits (used KlimaTicket holder benefits).
--  * RLS per command (select / insert / update) `to authenticated` using `(select auth.uid())`, no DELETE for
--    clients (deletes are soft: deleted_at tombstones, so every device learns about them), no access for anon,
--    explicit grants.
--
-- Client contract (App/Sources/Services/SyncService.swift):
--   push: POST /rest/v1/<table>?on_conflict=user_id,id&columns=<all keys>
--         Prefer: resolution=merge-duplicates,return=minimal   (every object carries every key; nil → null)
--   pull: GET  /rest/v1/<table>?select=*&user_id=eq.<uid>&order=server_rev.asc,id.asc&limit=500
--              &server_rev=gte.<cursor − 120 s>                                     (first page)
--              &or=(server_rev.gt.<rev>,and(server_rev.eq.<rev>,id.gt.<id>))       (following pages)
--         until a page returns fewer than 500 rows. Keep the API setting "Max rows" ≥ 500 (Supabase default 1000).

-- ---------------------------------------------------------------------------
-- 1. Remove 0001's updated_at trigger (and our own triggers, so a re-run starts clean)
-- ---------------------------------------------------------------------------
drop trigger if exists kb_touch on public.profiles;
drop trigger if exists kb_touch on public.tickets;
drop trigger if exists kb_touch on public.trips;
drop trigger if exists kb_touch on public.favorite_routes;
drop function if exists public.kb_touch_updated_at();

drop trigger if exists kb_sync_guard on public.profiles;
drop trigger if exists kb_sync_guard on public.tickets;
drop trigger if exists kb_sync_guard on public.trips;
drop trigger if exists kb_sync_guard on public.favorite_routes;

-- ---------------------------------------------------------------------------
-- 1b. Columns and tables of newer app models (SyncService DTOs)
-- ---------------------------------------------------------------------------
alter table public.tickets add column if not exists auto_renews boolean not null default false;
alter table public.tickets add column if not exists employer_contribution numeric(10,2) not null default 0;
alter table public.tickets add column if not exists add_on_price numeric(10,2) not null default 0;
alter table public.tickets add column if not exists add_ons text not null default '';
alter table public.trips add column if not exists category text not null default '';
alter table public.trips add column if not exists is_induced boolean not null default false;
alter table public.favorite_routes add column if not exists category text not null default '';

create table if not exists public.benefits (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date timestamptz not null,
  partner_id text not null default 'custom',
  title text not null default '',
  saved_eur numeric(10,2) not null default 0,
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint benefits_pkey primary key (user_id, id)
);
drop trigger if exists kb_sync_guard on public.benefits;

-- ---------------------------------------------------------------------------
-- 2. server_rev: add, backfill existing rows, default, not null
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['profiles', 'tickets', 'trips', 'favorite_routes', 'benefits'] loop
    execute format('alter table public.%I add column if not exists server_rev bigint', t);
    -- clock_timestamp() is evaluated per row, so backfilled rows get distinct, increasing values.
    execute format('update public.%I set server_rev = (extract(epoch from clock_timestamp()) * 1000000)::bigint
                     where server_rev is null', t);
    execute format('alter table public.%I alter column server_rev
                      set default (extract(epoch from clock_timestamp()) * 1000000)::bigint', t);
    execute format('alter table public.%I alter column server_rev set not null', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. Primary key (user_id, id) for user-owned tables
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
  pk_name text;
  pk_cols name[];
begin
  foreach t in array array['tickets', 'trips', 'favorite_routes', 'benefits'] loop
    pk_name := null;
    pk_cols := null;
    select c.conname,
           array(select a.attname
                   from unnest(c.conkey) with ordinality as k(attnum, ord)
                   join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
                  order by k.ord)
      into pk_name, pk_cols
      from pg_constraint c
     where c.conrelid = format('public.%I', t)::regclass
       and c.contype = 'p';
    if pk_cols is distinct from array['user_id', 'id']::name[] then
      if pk_name is not null then
        execute format('alter table public.%I drop constraint %I', t, pk_name);
      end if;
      execute format('alter table public.%I add constraint %I primary key (user_id, id)', t, t || '_pkey');
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. Every row is removed together with its auth user (ON DELETE CASCADE)
-- ---------------------------------------------------------------------------
do $$
declare
  spec record;
  fk record;
  has_cascade boolean;
  fk_name text;
begin
  for spec in
    select * from (values ('profiles', 'id'), ('tickets', 'user_id'), ('trips', 'user_id'), ('favorite_routes', 'user_id'),
                          ('benefits', 'user_id'))
      as v(tbl, col)
  loop
    has_cascade := false;
    for fk in
      select c.conname, c.confdeltype
        from pg_constraint c
        join pg_attribute a on a.attrelid = c.conrelid and a.attname = spec.col
       where c.contype = 'f'
         and c.conrelid = format('public.%I', spec.tbl)::regclass
         and c.confrelid = 'auth.users'::regclass
         and c.conkey = array[a.attnum]
    loop
      if fk.confdeltype = 'c' then
        has_cascade := true;
      else
        execute format('alter table public.%I drop constraint %I', spec.tbl, fk.conname);
      end if;
    end loop;
    if not has_cascade then
      fk_name := spec.tbl || '_' || spec.col || '_fkey';
      execute format('alter table public.%I add constraint %I foreign key (%I) references auth.users (id)
                        on delete cascade not valid', spec.tbl, fk_name, spec.col);
      begin
        execute format('alter table public.%I validate constraint %I', spec.tbl, fk_name);
      exception when foreign_key_violation then
        raise notice 'public.%: rows without auth user exist, % stays NOT VALID (new rows are checked)', spec.tbl, fk_name;
      end;
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 5. Last-writer-wins guard + server_rev (BEFORE INSERT OR UPDATE)
-- ---------------------------------------------------------------------------
-- tickets / trips / favorite_routes / benefits (owner column user_id)
create or replace function public.kb_sync_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- A device whose clock runs far ahead must not win every future conflict.
  if new.updated_at is null or new.updated_at > now() + interval '10 minutes' then
    new.updated_at := now();
  end if;

  if tg_op = 'UPDATE' then
    -- Ownership, identity and creation time never change.
    new.user_id := old.user_id;
    new.id := old.id;
    new.created_at := old.created_at;
    -- Stale write (older client edit time than the stored row): keep the stored row, no error.
    -- Returning NULL skips this row, also for INSERT … ON CONFLICT DO UPDATE (PostgREST upsert).
    if new.updated_at < old.updated_at then
      return null;
    end if;
    -- Nothing but updated_at changed (e.g. a device re-pushing what it just pulled): skip, keep server_rev.
    if (to_jsonb(new) - 'updated_at' - 'server_rev') = (to_jsonb(old) - 'updated_at' - 'server_rev') then
      return null;
    end if;
    new.server_rev := greatest((extract(epoch from clock_timestamp()) * 1000000)::bigint, old.server_rev + 1);
  else
    if new.created_at is null then
      new.created_at := now();
    end if;
    new.server_rev := (extract(epoch from clock_timestamp()) * 1000000)::bigint;
  end if;
  return new;
end
$$;

-- profiles (owner column id)
create or replace function public.kb_profile_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.updated_at is null or new.updated_at > now() + interval '10 minutes' then
    new.updated_at := now();
  end if;

  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.created_at := old.created_at;
    if new.updated_at < old.updated_at then
      return null;
    end if;
    if (to_jsonb(new) - 'updated_at' - 'server_rev') = (to_jsonb(old) - 'updated_at' - 'server_rev') then
      return null;
    end if;
    new.server_rev := greatest((extract(epoch from clock_timestamp()) * 1000000)::bigint, old.server_rev + 1);
  else
    if new.created_at is null then
      new.created_at := now();
    end if;
    new.server_rev := (extract(epoch from clock_timestamp()) * 1000000)::bigint;
  end if;
  return new;
end
$$;

create trigger kb_sync_guard before insert or update on public.tickets
  for each row execute function public.kb_sync_guard();
create trigger kb_sync_guard before insert or update on public.trips
  for each row execute function public.kb_sync_guard();
create trigger kb_sync_guard before insert or update on public.favorite_routes
  for each row execute function public.kb_sync_guard();
create trigger kb_sync_guard before insert or update on public.benefits
  for each row execute function public.kb_sync_guard();
create trigger kb_sync_guard before insert or update on public.profiles
  for each row execute function public.kb_profile_guard();

-- Trigger functions are not callable through the API anyway; keep them out of every role's reach.
revoke all on function public.kb_sync_guard() from public, anon, authenticated;
revoke all on function public.kb_profile_guard() from public, anon, authenticated;
revoke all on function public.kb_handle_new_user() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Indexes: keyset pull on (user_id, server_rev, id); the updated_at cursor indexes of 0001 are unused now
-- ---------------------------------------------------------------------------
create index if not exists tickets_user_rev         on public.tickets         (user_id, server_rev, id);
create index if not exists trips_user_rev           on public.trips           (user_id, server_rev, id);
create index if not exists favorite_routes_user_rev on public.favorite_routes (user_id, server_rev, id);
create index if not exists benefits_user_rev        on public.benefits        (user_id, server_rev, id);
drop index if exists public.tickets_user_updated;
drop index if exists public.trips_user_updated;
drop index if exists public.favorite_routes_user_updated;

-- ---------------------------------------------------------------------------
-- 7. Row Level Security per command + explicit grants
-- ---------------------------------------------------------------------------
alter table public.profiles        enable row level security;
alter table public.tickets         enable row level security;
alter table public.trips           enable row level security;
alter table public.favorite_routes enable row level security;
alter table public.benefits        enable row level security;

-- 0001 policies ("for all", no role restriction)
drop policy if exists "own profile" on public.profiles;
drop policy if exists "own rows" on public.tickets;
drop policy if exists "own rows" on public.trips;
drop policy if exists "own rows" on public.favorite_routes;

drop policy if exists kb_select_own on public.profiles;
drop policy if exists kb_insert_own on public.profiles;
drop policy if exists kb_update_own on public.profiles;
create policy kb_select_own on public.profiles for select to authenticated
  using ((select auth.uid()) = id);
create policy kb_insert_own on public.profiles for insert to authenticated
  with check ((select auth.uid()) = id);
create policy kb_update_own on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

do $$
declare
  t text;
begin
  foreach t in array array['tickets', 'trips', 'favorite_routes', 'benefits'] loop
    execute format('drop policy if exists kb_select_own on public.%I', t);
    execute format('drop policy if exists kb_insert_own on public.%I', t);
    execute format('drop policy if exists kb_update_own on public.%I', t);
    execute format('create policy kb_select_own on public.%I for select to authenticated
                      using ((select auth.uid()) = user_id)', t);
    execute format('create policy kb_insert_own on public.%I for insert to authenticated
                      with check ((select auth.uid()) = user_id)', t);
    execute format('create policy kb_update_own on public.%I for update to authenticated
                      using ((select auth.uid()) = user_id)
                      with check ((select auth.uid()) = user_id)', t);
  end loop;
end
$$;

-- No DELETE / TRUNCATE for clients (soft deletes only), nothing at all for anon.
revoke all on table public.profiles, public.tickets, public.trips, public.favorite_routes, public.benefits
  from public, anon, authenticated;
grant select, insert, update on table public.profiles, public.tickets, public.trips, public.favorite_routes, public.benefits
  to authenticated;
grant all on table public.profiles, public.tickets, public.trips, public.favorite_routes, public.benefits
  to service_role;

-- Let PostgREST pick up the new primary keys / columns right away.
notify pgrst, 'reload schema';
