-- Run once in the Supabase SQL editor (after machine_timers.sql, since it
-- reads washers.ends_at / cycle_minutes). Safe to re-run to update.
-- Lets the public tracking page (no login) show "You're #N in line" for an
-- order that is still waiting for a washer. It returns nothing for orders
-- that are not Received or are already in a washer, and exposes only this
-- one order's place in line, never other customers' orders.
--
-- Assumes orders.id is uuid (orders.shop_id, status, is_rush, created_at)
-- and washers(shop_id, status, current_order_id, started_at). If your id
-- columns are text, change the p_order_id type below to text.

create or replace function public.get_order_queue_position(
  p_order_id uuid,
  p_cycle_minutes int default 45
)
returns table (
  queue_position int,
  available_washers int,
  running_remaining_secs int[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop uuid;
  v_status text;
  v_rush boolean;
  v_created timestamptz;
  v_pos int;
begin
  select o.shop_id, o.status, coalesce(o.is_rush, false), o.created_at
    into v_shop, v_status, v_rush, v_created
  from orders o
  where o.id = p_order_id;

  if v_shop is null or v_status is distinct from 'received' then
    return;
  end if;

  -- Already loaded into a washer: not waiting any more.
  if exists (select 1 from washers w where w.current_order_id = p_order_id) then
    return;
  end if;

  -- Orders ahead of this one: Received, not in a washer, and either rush
  -- when this one is not, or same rush flag and placed earlier.
  select count(*)::int + 1
    into v_pos
  from orders o
  where o.shop_id = v_shop
    and o.status = 'received'
    and o.id <> p_order_id
    and not exists (select 1 from washers w where w.current_order_id = o.id)
    and (
      (coalesce(o.is_rush, false) and not v_rush)
      or (coalesce(o.is_rush, false) = v_rush and o.created_at < v_created)
    );

  return query
  select
    v_pos,
    (select count(*)::int from washers w
       where w.shop_id = v_shop and w.status = 'available'),
    coalesce(
      (select array_agg(r.secs order by r.secs)
         from (
           select extract(epoch from (
                    coalesce(
                      w.ends_at,
                      coalesce(w.started_at, now())
                        + make_interval(mins => coalesce(w.cycle_minutes, p_cycle_minutes))
                    ) - now()
                  ))::int as secs
           from washers w
           where w.shop_id = v_shop and w.status = 'in_use'
         ) r),
      '{}'::int[]
    );
end;
$$;

revoke all on function public.get_order_queue_position(uuid, int) from public;
grant execute on function public.get_order_queue_position(uuid, int) to anon, authenticated;
