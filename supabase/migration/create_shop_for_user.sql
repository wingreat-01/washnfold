-- Run once in the Supabase SQL Editor.
-- Lets a newly signed-up user create their own shop + owner staff row.
-- (RLS blocks direct inserts into shops/staff, so this runs as security definer.)

create or replace function public.create_shop_for_user(
  p_shop_name text,
  p_owner_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_shop_id uuid;
begin
  if v_uid is null then
    raise exception 'Not signed in';
  end if;

  -- Already has a shop? Return it instead of creating a duplicate.
  select shop_id into v_shop_id from public.staff where user_id = v_uid limit 1;
  if v_shop_id is not null then
    return v_shop_id;
  end if;

  insert into public.shops (id, name, owner_id)
  values (gen_random_uuid(), p_shop_name, v_uid)
  returning id into v_shop_id;

  insert into public.staff (id, user_id, shop_id, name, role)
  values (gen_random_uuid(), v_uid, v_shop_id, p_owner_name, 'owner');

  return v_shop_id;
end;
$$;

revoke all on function public.create_shop_for_user(text, text) from public;
grant execute on function public.create_shop_for_user(text, text) to authenticated;
