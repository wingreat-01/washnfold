-- WashNFold part 3: "My sales today" for attendants.
-- Run AFTER part 1 and part 2. TEST ON A COPY FIRST.
-- Adds: who collected each payment, and a function that returns ONLY
-- (a) the caller's own collections today and (b) the shop's total today.
-- Attendants still can't read older days through this.

-- 1. Record who took each payment.
alter table public.payments
  add column if not exists staff_id uuid references public.staff(id) on delete set null;
create index if not exists payments_staff_paid_at_idx
  on public.payments (staff_id, paid_at);

-- 2. The database, not the app, decides who collected a payment and when.
--    staff_id = the signed-in staff member; paid_at = server time.
--    Skipped when there is no signed-in user (SQL Editor / service role).
create or replace function public.payments_force_caller_fields()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
begin
  if auth.uid() is null then return new; end if;
  select s.id into v_staff
  from public.staff s
  where s.user_id = auth.uid() and s.active is not false
  limit 1;
  if v_staff is null then raise exception 'Not allowed'; end if;
  new.staff_id := v_staff;
  new.paid_at := now();
  return new;
end;
$$;

drop trigger if exists payments_force_caller_fields on public.payments;
create trigger payments_force_caller_fields
  before insert on public.payments
  for each row execute function public.payments_force_caller_fields();

-- 3. Today's numbers. "Today" = the Philippine calendar day (Asia/Manila).
--    Returns rows: scope 'mine' (one per payment method) and scope 'shop'
--    (one row, all staff). Payments made before step 1 have no staff_id, so
--    they appear in the shop total but not in anyone's own total.
create or replace function public.get_my_sales_today()
returns table (
  scope text,
  method text,
  order_count bigint,
  payment_count bigint,
  total numeric
)
language sql stable security definer
set search_path = public, pg_temp
as $$
  with me as (
    select s.id, s.shop_id
    from public.staff s
    where s.user_id = auth.uid() and s.active is not false
    limit 1
  ),
  day as (
    select (date_trunc('day', now() at time zone 'Asia/Manila')
            at time zone 'Asia/Manila') as start_at
  ),
  todays as (
    select p.method::text as method, p.amount, p.order_id, p.staff_id
    from public.payments p
    join public.orders o on o.id = p.order_id
    join me on o.shop_id = me.shop_id
    cross join day
    where p.paid_at >= day.start_at
      and p.paid_at <  day.start_at + interval '1 day'
  )
  select 'mine'::text, t.method, count(distinct t.order_id), count(*),
         coalesce(sum(t.amount), 0)
  from todays t
  join me on t.staff_id = me.id
  group by t.method
  union all
  select 'shop'::text, 'all'::text, count(distinct order_id), count(*),
         coalesce(sum(amount), 0)
  from todays
  where exists (select 1 from me);
$$;

revoke all on function public.get_my_sales_today() from public, anon;
grant execute on function public.get_my_sales_today() to authenticated;

-- ---------------------------------------------------------------------
-- Check first (read-only): the type of payments.paid_at. This file expects
-- "timestamp with time zone".
--   select data_type from information_schema.columns
--   where table_schema='public' and table_name='payments' and column_name='paid_at';
-- Test: as an attendant record a cash payment, open My sales -> it appears
-- under "I collected" and in the shop total; as a second attendant the shop
-- total includes it but "I collected" does not.
-- ---------------------------------------------------------------------
