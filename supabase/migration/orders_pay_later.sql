-- Run once in the Supabase SQL editor.
-- "Keep in queue" (every washer busy) marks the order as pay-at-the-end, so
-- every staff and owner device sees the same thing and the payment modal is
-- not shown when the order is later loaded into a washer.
alter table public.orders
  add column if not exists pay_later boolean not null default false;

comment on column public.orders.pay_later is
  'Cashier chose Keep in queue: collect payment after all services are finished (Ready -> Picked up).';

-- Existing rows default to false. No new RLS policy is needed if staff can
-- already update their shop's orders (status changes use the same UPDATE).
