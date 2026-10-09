-- WashNFold: permanent per-shop QR + customer-entered receipt reference.
-- Apply in Supabase SQL Editor after backing up your project.

alter table public.orders
  add column if not exists public_reference text;

-- Give existing orders a reference, then enforce one reference per shop.
update public.orders
set public_reference = 'WF-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))
where public_reference is null or btrim(public_reference) = '';

alter table public.orders
  alter column public_reference set not null;

alter table public.orders
  alter column public_reference set default
    ('WF-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)));

create unique index if not exists orders_shop_public_reference_uidx
  on public.orders (shop_id, upper(public_reference));

-- Only return the same minimal fields already exposed by the existing
-- get_order_public_status function, and only when the order belongs to the
-- shop encoded in the permanent QR. Never grant anon direct table access.
create or replace function public.get_order_public_status_by_reference(
  p_shop_id uuid,
  p_reference text
)
returns table (
  id uuid,
  shop_name text,
  customer_name text,
  status text,
  is_rush boolean,
  total numeric,
  payment_status text,
  created_at timestamptz,
  ready_at timestamptz,
  picked_up_at timestamptz
)
language sql
security definer
set search_path = public, pg_temp
as $$
  select status_row.id,
         status_row.shop_name,
         status_row.customer_name,
         status_row.status,
         status_row.is_rush,
         status_row.total,
         status_row.payment_status,
         status_row.created_at,
         status_row.ready_at,
         status_row.picked_up_at
  from public.orders as o
  cross join lateral public.get_order_public_status(o.id) as status_row
  where o.shop_id = p_shop_id
    and upper(o.public_reference) = upper(btrim(p_reference))
  limit 1;
$$;

revoke all on function public.get_order_public_status_by_reference(uuid, text) from public;
grant execute on function public.get_order_public_status_by_reference(uuid, text) to anon, authenticated;
