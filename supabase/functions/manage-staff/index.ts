// supabase/functions/manage-staff/index.ts
//
// Lets a shop OWNER create attendant (staff) accounts and switch them on/off.
// This has to run server-side: creating another person's login needs the
// service-role key (auth.admin.*), and calling auth.signUp() from the app
// would sign the owner out and sign the new staff member in instead.
//
// Deploy:  supabase functions deploy manage-staff
// (SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided
// to every Edge Function automatically -- nothing to set.)
//
// Body:
//   { action: 'create',     name, email, password }
//   { action: 'set_active', staff_id, active }

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

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // The caller must be an active OWNER; their shop is taken from the DB.
    const { data: me, error: meError } = await admin
      .from('staff')
      .select('id, shop_id, role, active')
      .eq('user_id', userData.user.id)
      .maybeSingle();
    if (meError || !me) return json({ error: 'No shop is linked to this account.' }, 403);
    if (me.role !== 'owner' || me.active === false) {
      return json({ error: 'Only the shop owner can manage staff.' }, 403);
    }

    const body = await req.json();

    if (body.action === 'create') {
      const name = String(body.name ?? '').trim();
      const email = String(body.email ?? '').trim().toLowerCase();
      const password = String(body.password ?? '');
      if (!name || !email) return json({ error: 'Name and email are required.' }, 400);
      if (password.length < 6) return json({ error: 'Password must be at least 6 characters.' }, 400);

      // email_confirm: true so the staff member can sign in right away
      // without a confirmation email.
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });
      if (createError || !created.user) {
        const msg = createError?.message ?? 'Could not create the login.';
        return json({ error: /already|registered|exists/i.test(msg) ? 'That email is already in use.' : msg }, 400);
      }

      const { error: insertError } = await admin.from('staff').insert({
        user_id: created.user.id,
        shop_id: me.shop_id,
        name,
        role: 'attendant',
        active: true,
      });
      if (insertError) {
        // Don't leave an orphan login behind if the staff row failed.
        await admin.auth.admin.deleteUser(created.user.id);
        console.error('manage-staff: staff insert failed', insertError);
        return json({ error: 'Could not save the staff member.' }, 500);
      }
      return json({ ok: true });
    }

    if (body.action === 'set_active') {
      const staffId = String(body.staff_id ?? '');
      const active = body.active === true;

      const { data: target, error: targetError } = await admin
        .from('staff')
        .select('id, user_id, shop_id, role')
        .eq('id', staffId)
        .maybeSingle();
      if (targetError || !target || target.shop_id !== me.shop_id) {
        return json({ error: 'Staff member not found.' }, 404);
      }
      if (target.role === 'owner') return json({ error: "The owner account can't be switched off." }, 400);

      const { error: updateError } = await admin.from('staff').update({ active }).eq('id', staffId);
      if (updateError) {
        console.error('manage-staff: update failed', updateError);
        return json({ error: 'Could not update the staff member.' }, 500);
      }
      // Ban/unban the login too, so a switched-off account can't sign in
      // (or refresh its session) at all, not just be hidden by the app.
      if (target.user_id) {
        const { error: banError } = await admin.auth.admin.updateUserById(target.user_id, {
          ban_duration: active ? 'none' : '876000h',
        });
        if (banError) console.error('manage-staff: ban update failed (non-fatal)', banError);
      }
      return json({ ok: true });
    }

    return json({ error: 'Unknown action.' }, 400);
  } catch (err) {
    console.error('manage-staff unhandled:', err);
    return json({ error: 'Something went wrong.' }, 500);
  }
});
