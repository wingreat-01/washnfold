-- Laundry Mate: Lifetime Plan (run AFTER trial_30_days.sql, once).
-- Paste into Supabase -> SQL Editor -> Run.

alter table public.shops
  add column if not exists is_lifetime boolean not null default false;

-- Nobody signed in through the app can change the trial, subscription or
-- lifetime flag (replaces the earlier version of this trigger function).
create or replace function public.protect_trial_columns()
returns trigger
language plpgsql
as $$
begin
  if (new.trial_ends_at is distinct from old.trial_ends_at
      or new.subscription_ends_at is distinct from old.subscription_ends_at
      or new.is_lifetime is distinct from old.is_lifetime)
     and coalesce(auth.role(), '') in ('authenticated', 'anon') then
    raise exception 'Plan details cannot be changed from the app.';
  end if;
  return new;
end;
$$;

-- The function's return columns change, so it has to be dropped first.
drop function if exists public.get_shop_access();
create function public.get_shop_access()
returns table (
  trial_ends_at timestamptz,
  subscription_ends_at timestamptz,
  is_lifetime boolean,
  server_now timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select s.trial_ends_at, s.subscription_ends_at, s.is_lifetime, now()
    from public.staff st
    join public.shops s on s.id = st.shop_id
   where st.user_id = auth.uid()
   limit 1;
$$;

revoke all on function public.get_shop_access() from public;
grant execute on function public.get_shop_access() to authenticated;

-- Server-side lock now lets lifetime shops through.
create or replace function public.shop_has_access(p_shop uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.shops s
     where s.id = p_shop
       and (s.is_lifetime
            or s.trial_ends_at > now()
            or coalesce(s.subscription_ends_at, 'epoch'::timestamptz) > now())
  );
$$;

-- To activate a customer who paid for the Lifetime Plan (run as yourself in
-- the SQL editor; the shop id is in the email the app prepares for them):
--   update public.shops set is_lifetime = true where id = '<shop id>';
