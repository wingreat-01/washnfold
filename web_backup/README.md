# WashNFold customer tracking website

This is a static, mobile-friendly customer tracking page for the Supabase schema in the supplied `supabase.zip`.

## What it does
- One permanent QR link per laundry shop, for example `https://YOUR-SITE.netlify.app/?shop=SHOP_UUID`.
- Customer enters the reference printed on the receipt.
- Calls `get_order_public_status_by_reference(p_shop_id, p_reference)` in Supabase.
- Displays order status and a progress timeline; it does not intentionally display customer name, payment status, or total.

## 1. Configure Supabase
Open `index.html` and replace:
- `YOUR_SUPABASE_PROJECT_URL` with your Supabase Project URL (Project Settings → API).
- `YOUR_SUPABASE_ANON_OR_PUBLISHABLE_KEY` with the anon/publishable key (Project Settings → API).

Never use the `service_role` key in browser code.

## 2. Apply the SQL migration
Use the revised migration in `supabase/20261009_public_shop_tracking_reference.sql` in the Supabase SQL Editor. It adds `orders.public_reference`, fills references for existing orders, and creates the RPC used by this page.

**Security note:** The supplied migration's existing public RPC accepts only a shop UUID and reference, and the reference is generated as a random `WF-` value. This page only displays status-related fields, but a public RPC should return only fields intended for anonymous users. The revised migration narrows its returned columns to shop name, status, and timestamps. If the previous function already exists, the migration drops and recreates it because PostgreSQL cannot change a function's `RETURNS TABLE` shape with `CREATE OR REPLACE` alone.

Test this migration on a development project or backup first, and confirm no other app code depends on the old function's return shape.

## 3. Deploy to Netlify
1. Go to https://app.netlify.com/ and sign in.
2. Choose **Add new site → Deploy manually** (wording may vary).
3. Drag the folder containing `index.html` into the deployment area, or upload a ZIP containing `index.html` at its root.
4. Netlify provides an HTTPS URL.

Vercel or any static host can also serve this page. It uses a Supabase JS CDN import, so the deployed page needs internet access.

## 4. Create each shop's permanent QR
Use this URL shape:

`https://YOUR-SITE.netlify.app/?shop=SHOP_UUID`

Replace `SHOP_UUID` with that shop's `shops.id` value. Create one QR image per shop using its URL and display it at that shop's counter. The customer still types their order reference number.

## 5. Test before production
- Test a known reference from a test shop.
- Test a reference belonging to another shop; it must not return an order.
- Test an invalid reference and a malformed shop UUID.
- Confirm the anonymous RPC does not return customer name, total, or payment information.
- Consider adding rate limiting / abuse monitoring at an Edge Function or gateway before public launch. Because this version uses reference-only lookup, treat references as secrets and make sure they are random and unguessable. For stronger protection, add a receipt PIN and verify it server-side before returning status.

## Files
- `index.html`: customer-facing tracking page.
- `supabase/20261009_public_shop_tracking_reference.sql`: migration tailored to the supplied schema and this page's RPC.
