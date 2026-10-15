// Verifies a Google Play "Lifetime Plan" purchase and unlocks the shop.
//
// The app sends { productId, purchaseToken } after Google Play's purchase
// sheet succeeds. This function (1) checks who is calling, (2) asks Google
// whether the purchase is real, (3) unlocks the caller's shop, and
// (4) acknowledges the purchase (Google refunds unacknowledged purchases
// after 3 days).
//
// Secrets to set (Supabase -> Edge Functions -> Secrets, or `supabase secrets set`):
//   GOOGLE_SERVICE_ACCOUNT_JSON  the service account key (whole JSON)
//   ANDROID_PACKAGE_NAME         e.g. com.prohubapps.laundrymate
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided
// to every function automatically.
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const LIFETIME_PRODUCT_ID = "lifetime_plan";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

async function googleAccessToken(): Promise<string> {
  const key = JSON.parse(Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON")!);
  const privateKey = await importPKCS8(key.private_key, "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/androidpublisher",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(key.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("55m")
    .sign(privateKey);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`Google token request failed: ${res.status}`);
  return (await res.json()).access_token as string;
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    // 1) Who is calling?
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Not signed in" }, 401);

    const url = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "Not signed in" }, 401);

    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: staff, error: staffError } = await admin
      .from("staff")
      .select("shop_id, role")
      .eq("user_id", userData.user.id)
      .maybeSingle();
    if (staffError || !staff) return json({ error: "No shop for this account" }, 403);
    if (staff.role !== "owner") {
      return json({ error: "Only the shop owner can buy the Lifetime Plan" }, 403);
    }
    const shopId = staff.shop_id as string;

    // 2) What are they claiming?
    const { productId, purchaseToken } = await req.json();
    if (productId !== LIFETIME_PRODUCT_ID || !purchaseToken) {
      return json({ error: "Invalid request" }, 400);
    }

    // 3) Ask Google whether it is real.
    const pkg = Deno.env.get("ANDROID_PACKAGE_NAME")!;
    const accessToken = await googleAccessToken();
    const base =
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}` +
      `/purchases/products/${productId}/tokens/${encodeURIComponent(purchaseToken)}`;

    const googleRes = await fetch(base, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!googleRes.ok) {
      console.error("Google verify failed", googleRes.status, await googleRes.text());
      return json({ error: "Purchase could not be verified" }, 402);
    }
    const purchase = await googleRes.json();
    // purchaseState: 0 = purchased, 1 = canceled, 2 = pending
    if (purchase.purchaseState !== 0) {
      return json({ error: "Purchase is not completed" }, 402);
    }

    // 4) One purchase unlocks one shop only.
    const { data: existing } = await admin
      .from("lifetime_purchases")
      .select("shop_id")
      .eq("purchase_token", purchaseToken)
      .maybeSingle();
    if (existing && existing.shop_id !== shopId) {
      return json({ error: "This purchase was already used for another shop" }, 409);
    }
    if (!existing) {
      const { error: insertError } = await admin.from("lifetime_purchases").insert({
        purchase_token: purchaseToken,
        shop_id: shopId,
        product_id: productId,
        order_id: purchase.orderId ?? null,
        purchased_at: purchase.purchaseTimeMillis
          ? new Date(Number(purchase.purchaseTimeMillis)).toISOString()
          : null,
      });
      if (insertError) {
        console.error("record purchase failed", insertError);
        return json({ error: "Could not record the purchase" }, 500);
      }
    }

    // 5) Unlock the shop.
    const { error: updateError } = await admin
      .from("shops")
      .update({ is_lifetime: true })
      .eq("id", shopId);
    if (updateError) {
      console.error("unlock shop failed", updateError);
      return json({ error: "Could not unlock the shop" }, 500);
    }

    // 6) Acknowledge (only if Google still has it as unacknowledged).
    if (purchase.acknowledgementState === 0) {
      const ack = await fetch(`${base}:acknowledge`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: "{}",
      });
      if (!ack.ok) console.error("acknowledge failed", ack.status, await ack.text());
    }

    return json({ ok: true });
  } catch (err) {
    console.error("verify-lifetime-purchase unhandled", err);
    return json({ error: "Something went wrong" }, 500);
  }
});
