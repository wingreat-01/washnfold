-- Laundry Mate: 30-day free trial, enforced on the server.
-- Paste this whole file into Supabase -> SQL Editor -> Run (once).
-- Assumes the shop table is public.shops and staff rows are in public.staff
-- (staff.user_id, staff.shop_id). If a name differs, adjust it below.

-- 1) Trial / subscription dates on the shop -------------------------------
alter table public.shops
  add column if not exists trial_ends_at timestamptz,
  add column if not exists subscription_ends_at timestamptz;

-- Shops that already exist get 30 days from today (so nobody is locked out
-- the moment you deploy). Every NEW shop starts its 30 days when it is created.
update public.shops
   set trial_ends_at = now() + interval '30 days'
 where trial_ends_at is null;

alter table public.shops
  alter column trial_ends_at set default (now() + interval '30 days');
alter table public.shops
  alter column trial_ends_at set not null;

-- 2) "Locked in": nobody signed in through the app can change these dates --
create or replace function public.protect_trial_columns()
returns trigger
language plpgsql
as $$
begin
  if (new.trial_ends_at is distinct from old.trial_ends_at
      or new.subscription_ends_at is distinct from old.subscription_ends_at)
     and coalesce(auth.role(), '') in ('authenticated', 'anon') then
    raise exception 'Trial and subscription dates cannot be changed from the app.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_trial_columns on public.shops;
create trigger trg_protect_trial_columns
  before update on public.shops
  for each row execute function public.protect_trial_columns();

-- 3) What the app asks: "is my shop still allowed in?" ---------------------
-- Returns the server's clock too, so changing the phone's date does nothing.
create or replace function public.get_shop_access()
returns table (
  trial_ends_at timestamptz,
  subscription_ends_at timestamptz,
  server_now timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select s.trial_ends_at, s.subscription_ends_at, now()
    from public.staff st
    join public.shops s on s.id = st.shop_id
   where st.user_id = auth.uid()
   limit 1;
$$;

revoke all on function public.get_shop_access() from public;
grant execute on function public.get_shop_access() to authenticated;

-- 4) Server-side lock: no new orders once the trial/subscription is over ---
-- (a RESTRICTIVE policy is added on top of your existing policies; it does
-- not replace or loosen any of them)
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
       and (s.trial_ends_at > now()
            or coalesce(s.subscription_ends_at, 'epoch'::timestamptz) > now())
  );
$$;

revoke all on function public.shop_has_access(uuid) from public;
grant execute on function public.shop_has_access(uuid) to authenticated;

drop policy if exists "trial_or_subscription_required" on public.orders;
create policy "trial_or_subscription_required"
  on public.orders
  as restrictive
  for insert
  to authenticated
  with check (public.shop_has_access(shop_id));

-- To give a shop a paid period later (run as yourself in the SQL editor):
--   update public.shops set subscription_ends_at = now() + interval '30 days'
--    where id = '<shop id>';
