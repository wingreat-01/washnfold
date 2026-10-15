-- Laundry Mate: remembers which Google Play purchase unlocked which shop, so
-- one purchase can't be reused to unlock a second shop.
-- Run once in Supabase -> SQL Editor (after lifetime_plan.sql).
create table if not exists public.lifetime_purchases (
  purchase_token text primary key,
  shop_id        uuid not null references public.shops(id) on delete cascade,
  product_id     text not null,
  order_id       text,
  purchased_at   timestamptz,
  created_at     timestamptz not null default now()
);

-- RLS on with NO policies: only the service role (the Edge Function) can
-- read or write this table; the app itself never can.
alter table public.lifetime_purchases enable row level security;
