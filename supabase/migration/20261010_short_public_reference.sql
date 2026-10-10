-- Short receipt references like WF-8FEC9X (new orders only; old references keep working).
-- Run in the Supabase SQL Editor.

-- Each reference must be unique within a shop. The app retries with a new
-- random reference if one is ever taken.
create unique index if not exists orders_shop_public_reference_uidx
  on public.orders (shop_id, public_reference);
