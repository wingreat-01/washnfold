-- WashNFold customer tracking: one permanent QR per shop + receipt reference.
-- Test on a development project or backup before production.

alter table public.orders
  add column if not exists public_reference text;

-- Backfill existing orders with random, non-sequential references.
update public.orders
set public_reference = 'WF-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))
where public_reference is null or btrim(public_reference) = '';

alter table public.orders alter column public_reference set not null;
alter table public.orders alter column public_reference set default
  ('WF-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)));

create unique index if not exists orders_shop_public_reference_uidx
  on public.orders (shop_id, upper(public_reference));

-- Drop/recreate because PostgreSQL does not allow CREATE OR REPLACE to change
-- an existing function's RETURNS TABLE column list. Confirm no other code relies
-- on the old return shape before running this migration.
drop function if exists public.get_order_public_status_by_reference(uuid, text);

create function public.get_order_public_status_by_reference(
  p_shop_id uuid,
  p_reference text
)
returns table (
  shop_name text,
  status text,
  created_at timestamptz,
  ready_at timestamptz,
  picked_up_at timestamptz
)
language sql
security definer
set search_path = public, pg_temp
as $$
  select s.name as shop_name,
         o.status,
         o.created_at,
         o.ready_at,
         o.picked_up_at
  from public.orders as o
  join public.shops as s on s.id = o.shop_id
  where o.shop_id = p_shop_id
    and upper(o.public_reference) = upper(btrim(p_reference))
  limit 1;
$$;

revoke all on function public.get_order_public_status_by_reference(uuid, text) from public;
grant execute on function public.get_order_public_status_by_reference(uuid, text) to anon, authenticated;
