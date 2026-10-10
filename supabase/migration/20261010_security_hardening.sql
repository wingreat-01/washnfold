-- WashNFold security hardening.
-- TEST ON A COPY FIRST (Supabase branch or a second project), then run in the
-- SQL Editor. After running, sign in as an ATTENDANT and as an OWNER and check
-- that every screen still works (see the checklist at the bottom).

-- 1. Which shop is the caller in? Now ignores switched-off staff and no
--    longer depends on the caller's own RLS (security definer).
create or replace function public.auth_shop_id()
returns uuid
language sql stable security definer
set search_path = public, pg_temp
as $$
  select shop_id from public.staff
  where user_id = auth.uid() and active is not false
  limit 1;
$$;

create or replace function public.auth_is_owner()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.staff
    where user_id = auth.uid() and role = 'owner' and active is not false
  );
$$;

-- A switched-off user can still read their OWN staff row, so the app can show
-- "This account has been switched off" instead of a setup screen.
drop policy if exists "read own staff row" on public.staff;
create policy "read own staff row" on public.staff
  for select using (user_id = auth.uid());

-- 2. Services (prices): everyone in the shop can read, only owners can change.
drop policy if exists "shop members can manage services" on public.services;
drop policy if exists "shop members read services" on public.services;
drop policy if exists "owners write services" on public.services;
create policy "shop members read services" on public.services
  for select using (shop_id = public.auth_shop_id());
create policy "owners write services" on public.services
  for all
  using (shop_id = public.auth_shop_id() and public.auth_is_owner())
  with check (shop_id = public.auth_shop_id() and public.auth_is_owner());

-- 3. Expenses and inventory: the app doesn't use them yet, and the expenses
--    policy was labelled "owners" but allowed every member. Owners only.
drop policy if exists "shop owners can manage expenses" on public.expenses;
drop policy if exists "owners manage expenses" on public.expenses;
create policy "owners manage expenses" on public.expenses
  for all
  using (shop_id = public.auth_shop_id() and public.auth_is_owner())
  with check (shop_id = public.auth_shop_id() and public.auth_is_owner());

drop policy if exists "shop members can manage inventory" on public.inventory;
drop policy if exists "owners manage inventory" on public.inventory;
create policy "owners manage inventory" on public.inventory
  for all
  using (shop_id = public.auth_shop_id() and public.auth_is_owner())
  with check (shop_id = public.auth_shop_id() and public.auth_is_owner());

-- 4. Payments: attendants can record a payment but not edit or delete one.
drop policy if exists "shop members can manage payments" on public.payments;
drop policy if exists "members read payments" on public.payments;
drop policy if exists "members add payments" on public.payments;
drop policy if exists "owners change payments" on public.payments;
create policy "members read payments" on public.payments
  for select using (order_id in
    (select id from public.orders where shop_id = public.auth_shop_id()));
create policy "members add payments" on public.payments
  for insert with check (order_id in
    (select id from public.orders where shop_id = public.auth_shop_id()));
create policy "owners change payments" on public.payments
  for update using (public.auth_is_owner() and order_id in
    (select id from public.orders where shop_id = public.auth_shop_id()));
create policy "owners delete payments" on public.payments
  for delete using (public.auth_is_owner() and order_id in
    (select id from public.orders where shop_id = public.auth_shop_id()));

-- 5. Washers: same shop rule, and switched-off staff are locked out.
drop policy if exists "shop staff manage washers" on public.washers;
drop policy if exists "shop members manage washers" on public.washers;
create policy "shop members manage washers" on public.washers
  for all
  using (shop_id = public.auth_shop_id())
  with check (shop_id = public.auth_shop_id());

-- 6. Public order status (opened from the QR / order link): don't hand out the
--    customer's name, the total or the payment status. Same columns and types,
--    so the app keeps working (it falls back to defaults for these three).
create or replace function public.get_order_public_status(p_order_id uuid)
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
language sql security definer
set search_path = public, pg_temp
as $$
  select o.id, s.name, null::text, o.status, o.is_rush,
         null::numeric, null::text, o.created_at, o.ready_at, o.picked_up_at
  from public.orders o
  join public.shops s on s.id = o.shop_id
  where o.id = p_order_id;
$$;

-- 7. Shop sign-up: sane length limits (same behaviour otherwise).
create or replace function public.create_shop_for_user(
  p_shop_name text,
  p_owner_name text
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_shop_id uuid;
  v_shop text := btrim(coalesce(p_shop_name, ''));
  v_owner text := btrim(coalesce(p_owner_name, ''));
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if char_length(v_shop) not between 1 and 80 then
    raise exception 'Shop name must be 1 to 80 characters';
  end if;
  if char_length(v_owner) not between 1 and 80 then
    raise exception 'Your name must be 1 to 80 characters';
  end if;

  select shop_id into v_shop_id from public.staff where user_id = v_uid limit 1;
  if v_shop_id is not null then return v_shop_id; end if;

  insert into public.shops (id, name, owner_id)
  values (gen_random_uuid(), v_shop, v_uid) returning id into v_shop_id;
  insert into public.staff (id, user_id, shop_id, name, role)
  values (gen_random_uuid(), v_uid, v_shop_id, v_owner, 'owner');
  return v_shop_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Checks to run afterwards (SQL Editor, read-only):
--   -- which version of the reference lookup is live? It should list only
--   -- shop_name, status, created_at, ready_at, picked_up_at:
--   select pg_get_function_result(
--     'public.get_order_public_status_by_reference(uuid,text)'::regprocedure);
--   -- policies on the machine tables (dryers has none in your migrations):
--   select tablename, policyname, cmd from pg_policies
--   where schemaname = 'public' and tablename in ('dryers','washers');
--
-- Manual test checklist:
--   Attendant: New order, Queue, Washers, Dryers work; pay an order; cannot
--              open Services/Staff/Dashboard; edits to services fail.
--   Owner:     everything above plus Services, Staff and Dashboard.
--   Switch an attendant off: they can no longer read or write anything.
-- ---------------------------------------------------------------------
