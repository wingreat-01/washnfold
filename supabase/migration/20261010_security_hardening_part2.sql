-- WashNFold security hardening, part 2 (run AFTER 20261010_security_hardening.sql).
-- TEST ON A COPY FIRST, then run in the SQL Editor.
-- Triggers are used (instead of guessing old policy names) because they apply
-- no matter which RLS policies already exist on these tables.

-- A. Orders: the caller can't choose shop_id / staff_id / status / paid flag.
--    shop_id is forced to the caller's shop and staff_id to the caller's own
--    staff row. New orders always start as 'received' and 'unpaid'.
--    (The app never sends staff_id, so nothing changes for it.)
--    Skipped when there is no signed-in user (SQL Editor, service role).
create or replace function public.orders_force_caller_fields()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_shop uuid;
  v_staff uuid;
begin
  if auth.uid() is null then return new; end if;
  select s.shop_id, s.id into v_shop, v_staff
  from public.staff s
  where s.user_id = auth.uid() and s.active is not false
  limit 1;
  if v_shop is null then raise exception 'Not allowed'; end if;
  new.shop_id := v_shop;
  new.staff_id := v_staff;
  new.status := 'received';
  new.payment_status := 'unpaid';
  return new;
end;
$$;

drop trigger if exists orders_force_caller_fields on public.orders;
create trigger orders_force_caller_fields
  before insert on public.orders
  for each row execute function public.orders_force_caller_fields();

-- B. Order items: the price of each line is computed by the database from the
--    shop's own services table (same rule as ServiceItem.priceFor in the app:
--    flat price up to max_kg, then the same rate per extra kg). The client's
--    subtotal and service_name are ignored.
create or replace function public.order_items_price_from_service()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_shop uuid;
  v_svc public.services%rowtype;
  v_price numeric;
begin
  if auth.uid() is null then return new; end if;

  select shop_id into v_shop from public.orders where id = new.order_id;
  if v_shop is null or v_shop is distinct from public.auth_shop_id() then
    raise exception 'Not allowed';
  end if;

  select * into v_svc from public.services
  where id = new.service_id and shop_id = v_shop;
  if not found then raise exception 'Unknown service'; end if;

  if new.quantity is null or new.quantity <= 0 or new.quantity > 100000 then
    raise exception 'Invalid quantity';
  end if;

  if coalesce(v_svc.unit, 'kg') = 'kg'
     and coalesce(v_svc.is_add_on, false) = false
     and v_svc.max_kg is not null and v_svc.max_kg > 0
     and v_svc.max_kg_price is not null then
    if new.quantity <= v_svc.max_kg then
      v_price := v_svc.max_kg_price;
    else
      v_price := v_svc.max_kg_price
                 + (new.quantity - v_svc.max_kg)
                   * (v_svc.max_kg_price / v_svc.max_kg);
    end if;
  else
    v_price := new.quantity * v_svc.price;
  end if;

  new.subtotal := round(v_price, 2);
  new.service_name := v_svc.name;
  return new;
end;
$$;

drop trigger if exists order_items_price_from_service on public.order_items;
create trigger order_items_price_from_service
  before insert or update on public.order_items
  for each row execute function public.order_items_price_from_service();

-- C. Order total = sum of its items + rush surcharge, recalculated whenever
--    items change. The app inserts the order first and its items right after,
--    so the total is corrected as soon as the items arrive.
create or replace function public.recalc_order_total()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_order uuid := coalesce(new.order_id, old.order_id);
begin
  update public.orders o
     set total = coalesce(
           (select sum(subtotal) from public.order_items where order_id = v_order), 0)
           + case when o.is_rush then coalesce(o.rush_surcharge, 0) else 0 end
   where o.id = v_order;
  return null;
end;
$$;

drop trigger if exists recalc_order_total on public.order_items;
create trigger recalc_order_total
  after insert or update or delete on public.order_items
  for each row execute function public.recalc_order_total();

-- D. Attendants may not edit order_items after the fact (so a price can't be
--    changed later). Owners can. Only UPDATE is guarded, so the app's cleanup
--    (deleting an order whose items failed to save) keeps working.
create or replace function public.order_items_block_attendant_edits()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is not null and not public.auth_is_owner() then
    raise exception 'Only the owner can change order items';
  end if;
  return new;
end;
$$;

drop trigger if exists order_items_block_attendant_edits on public.order_items;
create trigger order_items_block_attendant_edits
  before update on public.order_items
  for each row execute function public.order_items_block_attendant_edits();

-- ---------------------------------------------------------------------
-- NOT changed here (decide separately):
--  * rush_surcharge still comes from the client (the app has no server-side
--    setting for it). Totals are now correct for the items, but an attendant
--    calling the API directly could still send a different surcharge.
--  * Payments: amounts are still client-supplied; attendants can add but not
--    edit/delete (part 1). A check of amount vs orders.total needs your rule
--    for partial payments / pay-later before it can be enforced safely.
--  * Dashboard: attendants can still read their shop's orders via the API.
--    To block that, split orders into an owner-only view for reporting.
--
-- Checks to run first (read-only), to see what already exists:
--   select policyname, cmd, qual, with_check from pg_policies
--   where schemaname='public' and tablename in ('orders','order_items','customers');
--   select pg_get_function_result('public.get_order_queue_position(uuid,integer)'::regprocedure);
--
-- Test: create an order as an attendant (total should match the screen),
-- then try via the API to insert an order with another shop's shop_id (it is
-- forced to your shop) and an item with subtotal 0 (it is recomputed).
-- ---------------------------------------------------------------------
