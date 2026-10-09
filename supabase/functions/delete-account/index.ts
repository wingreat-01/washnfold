// supabase/functions/delete-account/index.ts
//
// Lets a signed-in user permanently delete their OWN account.
// Used by the in-app Settings -> Delete account and by the public
// /delete-account web page. Deleting an auth user needs the service-role
// key, so it has to run server-side.
//
// Deploy:  supabase functions deploy delete-account
// (SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided
// to every Edge Function automatically -- nothing to set.)
//
// Body: { confirm: true }
//
// What happens:
//   - Owner:     the shop row is deleted first (cascades to staff, customers,
//                services, orders, payments, machines, inventory, expenses),
//                then every attendant login of that shop, then the owner login.
//   - Attendant: their staff row is switched off and kept so old orders still
//                show who handled them; their login is deleted (staff.user_id
//                is set to null by the foreign key).
//   - No shop:   just the login is deleted.
// If deleting the shop data fails, nothing else is touched.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed.' }, 405);

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Missing Authorization header.' }, 401);

    // Who is calling? Verified from their own JWT, never from the body.
    const caller = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: userData, error: userError } = await caller.auth.getUser();
    if (userError || !userData.user) return json({ error: 'Invalid or expired session.' }, 401);
    const uid = userData.user.id;

    const body = await req.json().catch(() => ({}));
    if (body?.confirm !== true) return json({ error: 'Deletion was not confirmed.' }, 400);

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: me, error: meError } = await admin
      .from('staff')
      .select('id, shop_id, role')
      .eq('user_id', uid)
      .maybeSingle();
    if (meError) {
      console.error('delete-account: staff lookup failed', meError);
      return json({ error: 'Could not look up your account.' }, 500);
    }

    if (me?.role === 'owner') {
      // Collect attendant logins BEFORE the shop (and its staff rows) go.
      const { data: team, error: teamError } = await admin
        .from('staff')
        .select('user_id')
        .eq('shop_id', me.shop_id)
        .neq('user_id', uid)
        .not('user_id', 'is', null);
      if (teamError) {
        console.error('delete-account: team lookup failed', teamError);
        return json({ error: 'Could not look up your staff accounts.' }, 500);
      }

      const { error: shopError } = await admin.from('shops').delete().eq('id', me.shop_id);
      if (shopError) {
        console.error('delete-account: shop delete failed', shopError);
        return json({ error: 'Could not delete your shop data. Nothing was deleted.' }, 500);
      }

      for (const member of team ?? []) {
        const { error } = await admin.auth.admin.deleteUser(member.user_id as string);
        if (error) console.error('delete-account: attendant login delete failed (non-fatal)', error);
      }
    } else if (me) {
      // Keep the row for order history, but switch it off.
      const { error } = await admin.from('staff').update({ active: false }).eq('id', me.id);
      if (error) console.error('delete-account: staff deactivate failed (non-fatal)', error);
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
    if (deleteError) {
      console.error('delete-account: auth delete failed', deleteError);
      return json({ error: 'Could not delete your login. Please try again or contact support.' }, 500);
    }

    return json({ ok: true });
  } catch (err) {
    console.error('delete-account unhandled:', err);
    return json({ error: 'Something went wrong.' }, 500);
  }
});
