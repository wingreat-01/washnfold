-- WashNFold — Supabase schema (MVP)
-- Run this in the Supabase SQL editor for a fresh project.

create extension if not exists "uuid-ossp";

-- Shops (multi-branch ready: owner_id + optional branch_name)
create table shops (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  branch_name text,
  created_at timestamptz not null default now()
);

-- Staff/attendants, linked to a Supabase auth user
create table staff (
  id uuid primary key default uuid_generate_v4(),
  shop_id uuid not null references shops(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  name text not null,
  role text not null default 'attendant' check (role in ('owner', 'attendant')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table customers (
  id uuid primary key default uuid_generate_v4(),
  shop_id uuid not null references shops(id) on delete cascade,
  name text not null,
  phone text,
  loyalty_points int not null default 0,
  created_at timestamptz not null default now()
);

create table services (
  id uuid primary key default uuid_generate_v4(),
  shop_id uuid not null references shops(id) on delete cascade,
  name text not null,
  unit text not null default 'kg' check (unit in ('kg', 'piece')),
  price numeric(10, 2) not null,
  is_add_on boolean not null default false,
  active boolean not null default true
);

create table orders (
  id uuid primary key default uuid_generate_v4(),
  shop_id uuid not null references shops(id) on delete cascade,
  customer_id uuid not null references customers(id),
  customer_name text not null,
  staff_id uuid references staff(id),
  status text not null default 'received'
    check (status in ('received', 'washing', 'drying', 'folding_pressing', 'ready', 'picked_up')),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'paid')),
  is_rush boolean not null default false,
  rush_surcharge numeric(10, 2) not null default 0,
  total numeric(10, 2) not null default 0,
  created_at timestamptz not null default now(),
  ready_at timestamptz,
  picked_up_at timestamptz
);

create table order_items (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references orders(id) on delete cascade,
  service_id uuid not null references services(id),
  service_name text not null,
  quantity numeric(10, 2) not null,
  subtotal numeric(10, 2) not null
);

create table payments (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references orders(id) on delete cascade,
  method text not null default 'cash' check (method in ('cash', 'gcash', 'maya', 'card')),
  amount numeric(10, 2) not null,
  paid_at timestamptz not null default now()
);

create table inventory (
  id uuid primary key default uuid_generate_v4(),
  shop_id uuid not null references shops(id) on delete cascade,
  item_name text not null,
  qty numeric(10, 2) not null default 0,
  reorder_threshold numeric(10, 2) not null default 0
);

create table expenses (
  id uuid primary key default uuid_generate_v4(),
  shop_id uuid not null references shops(id) on delete cascade,
  category text not null,
  amount numeric(10, 2) not null,
  date date not null default current_date
);

-- Indexes for the queries the app makes constantly
create index idx_orders_shop_status on orders(shop_id, status);
create index idx_orders_shop_created on orders(shop_id, created_at);
create index idx_order_items_order on order_items(order_id);

-- Enable realtime on orders so staff + owner see the queue update live
alter publication supabase_realtime add table orders;
alter publication supabase_realtime add table order_items;

-- Row Level Security — scope everything to the staff member's own shop.
-- This assumes a JWT claim or a lookup via the staff table linking
-- auth.uid() to a shop_id. Adjust to your auth setup before going to
-- production; these are permissive starting policies for MVP development.
alter table shops enable row level security;
alter table staff enable row level security;
alter table customers enable row level security;
alter table services enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table payments enable row level security;
alter table inventory enable row level security;
alter table expenses enable row level security;

create or replace function auth_shop_id() returns uuid as $$
  select shop_id from staff where user_id = auth.uid() limit 1;
$$ language sql stable;

create policy "shop members can read their shop" on shops
  for select using (id = auth_shop_id() or owner_id = auth.uid());

create policy "shop members can read staff" on staff
  for select using (shop_id = auth_shop_id());

create policy "shop members can manage customers" on customers
  for all using (shop_id = auth_shop_id());

create policy "shop members can manage services" on services
  for all using (shop_id = auth_shop_id());

create policy "shop members can manage orders" on orders
  for all using (shop_id = auth_shop_id());

create policy "shop members can manage order items" on order_items
  for all using (order_id in (select id from orders where shop_id = auth_shop_id()));

create policy "shop members can manage payments" on payments
  for all using (order_id in (select id from orders where shop_id = auth_shop_id()));

create policy "shop members can manage inventory" on inventory
  for all using (shop_id = auth_shop_id());

create policy "shop owners can manage expenses" on expenses
  for all using (shop_id = auth_shop_id());

-- ---------------------------------------------------------------------
-- Public order tracking (no customer login)
-- ---------------------------------------------------------------------
-- Each order's QR code encodes a link containing its id (already an
-- unguessable uuid v4). Rather than opening RLS on `orders` to the public,
-- which would let anon enumerate every order via an unfiltered select,
-- this function returns only the single row matching the id you already
-- have. security definer lets it bypass RLS internally; there is no way
-- to use it to browse other orders without already knowing their id.
create or replace function get_order_public_status(p_order_id uuid)
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
set search_path = public
as $$
  select o.id, s.name as shop_name, o.customer_name, o.status, o.is_rush,
         o.total, o.payment_status, o.created_at, o.ready_at, o.picked_up_at
  from orders o
  join shops s on s.id = o.shop_id
  where o.id = p_order_id;
$$;

-- Let the anon key (unauthenticated customers) call this function.
grant execute on function get_order_public_status(uuid) to anon;
