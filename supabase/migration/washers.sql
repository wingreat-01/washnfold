-- Washers table for the Washer Management tab.
-- NOTE: I didn't have your existing schema.sql, so the RLS policy below
-- assumes the same rule as your other tables: a user may access rows whose
-- shop_id matches their row in public.staff. Adjust to match your policies.

create table if not exists public.washers (
  id               uuid primary key,
  shop_id          uuid not null references public.shops(id) on delete cascade,
  name             text not null,
  capacity_kg      numeric,
  status           text not null default 'available'
                   check (status in ('available', 'in_use', 'maintenance')),
  current_order_id uuid references public.orders(id) on delete set null,
  started_at       timestamptz,
  notes            text,
  created_at       timestamptz not null default now()
);

create index if not exists washers_shop_idx on public.washers (shop_id);

-- One order can only sit in one washer at a time.
create unique index if not exists washers_one_order_each
  on public.washers (current_order_id)
  where current_order_id is not null;

alter table public.washers enable row level security;

create policy "shop staff manage washers" on public.washers
  for all
  using (exists (
    select 1 from public.staff s
    where s.user_id = auth.uid() and s.shop_id = washers.shop_id))
  with check (exists (
    select 1 from public.staff s
    where s.user_id = auth.uid() and s.shop_id = washers.shop_id));

-- Needed for the realtime stream used by WasherProvider.
alter publication supabase_realtime add table public.washers;
