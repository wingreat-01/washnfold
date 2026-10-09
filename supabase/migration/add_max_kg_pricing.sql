-- Run once in the Supabase SQL Editor BEFORE using the new Max kg option.
alter table public.services
  add column if not exists max_kg numeric,
  add column if not exists max_kg_price numeric;
