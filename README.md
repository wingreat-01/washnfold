# WashNFold

Laundry shop management system — MVP scaffold. Single Flutter codebase
targeting mobile (staff counter use) and web (owner dashboard), backed by
Supabase for auth, database, and realtime queue sync.

## What's included (MVP scope)

- **Order intake** (`order_intake_screen.dart`) — pick services, enter
  weight/piece count, mark rush, running total, submit
- **Order queue** (`order_queue_screen.dart`) — status pipeline (Received →
  Washing → Drying → Folding/Pressing → Ready → Picked up), kanban view on
  wide screens, filtered list on mobile, realtime-synced across devices
- **Owner dashboard** (`dashboard_screen.dart`) — today/week/month revenue,
  active order count, top services
- **Pricing config** (`ServiceCatalogProvider`) — per-kg/per-piece services
  and add-ons, editable price
- **Customer tracking — no account, no login** (`customer_tracking_screen.dart`):
  every order gets a QR code (shown right after creation, and reopenable
  from its card in the queue) encoding a public link like
  `https://yourapp.com/track/<order-id>`. Scanning it opens a status page —
  where's my order, is it ready — with nothing to sign up for. This works
  because order ids are already unguessable UUIDs, and a Postgres function
  (`get_order_public_status`, see schema.sql) returns only that one order's
  status to anyone holding the link, without opening the `orders` table to
  public reads.
- Responsive **AppShell** — nav rail on web/wide, bottom nav on phones
- Supabase **schema.sql** matching the data model in the sketch plan, with
  starter row-level-security policies scoping everything to a shop via the
  `staff` table

## Not yet built (see sketch plan phases 2–4)

SMS/push notifications (currently the customer has to check the tracking
page themselves — no "your order is ready" ping), inventory consumption
tracking, staff role gating in the UI (the `StaffRole` model exists but
screens don't check it yet), delivery/rider module, receipt/thermal
printing (the QR renders on-screen; wiring it to a thermal printer is a
separate integration), payment gateway integration (PayMongo/GCash),
multi-branch switching in the UI.

## Setup

1. **Create a Supabase project** at supabase.com.
2. **Run the schema**: open the SQL editor and paste in `supabase/schema.sql`.
3. **Create your first shop, staff row, and services** manually via the
   Supabase table editor for now (an onboarding flow isn't built yet):
   - Insert a row into `shops` (owner_id = your auth user's id)
   - Insert a row into `staff` linking that same `user_id` to the shop,
     with `role = 'owner'`
   - Insert a few rows into `services` (e.g. "Wash & Fold", unit `kg`,
     price `60`)
4. **Create a Supabase Auth user** (Authentication → Users → Add user) with
   an email/password — this is what you'll sign in with.
5. **Get dependencies**:
   ```
   flutter pub get
   ```
6. **Run** with your Supabase credentials (Project Settings → API):
   ```
   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxxx
   ```
   For web:
   ```
   flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
   ```
7. **Set your deployed web URL** once you have one, so QR codes point
   somewhere real (defaults to `https://washnfold.app` otherwise):
   ```
   --dart-define=WEB_BASE_URL=https://your-actual-domain.com
   ```
   Every `flutter run`/`flutter build web` for the staff app should pass
   this so freshly-created orders' QR codes are correct. The customer
   tracking page itself needs no credentials or dart-defines beyond the
   Supabase ones — it's served by the same web build, just at `/track/:id`.

## Notes on the RLS policies

The schema's row-level security assumes one `staff` row per Supabase auth
user, linking them to exactly one `shop_id`. That's fine for MVP (one shop,
few staff) — revisit if a single person needs access to multiple shops
before multi-branch (phase 4) is built.

## If you already ran an earlier version of schema.sql

Just run the new block at the bottom (`get_order_public_status` function +
its `grant execute ... to anon`) — everything above it is unchanged, no
need to re-run the whole file.
