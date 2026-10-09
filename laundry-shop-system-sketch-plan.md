# Laundry Shop Management System — Sketch Plan

## 1. Who Uses It
- **Shop owner** — full control: pricing, staff, reports, multi-branch if applicable
- **Staff/attendant** — order intake, status updates, POS, day-to-day ops
- **Customer** (optional, phase 2+) — track order status, reorder, pay online

## 2. Core Modules

### Order & Queue Management
- Create order: customer info, service type (wash, dry, fold, press, dry-clean), weight/piece count, pricing auto-calc
- Order status pipeline: Received → Washing → Drying → Folding/Pressing → Ready → Picked up/Delivered
- Ticket/receipt printing (thermal printer support, like a POS)
- Rush/priority flag with surcharge

### Customer Management (CRM-lite)
- Customer profiles, order history, loyalty points/frequency discounts
- SMS/push notification when order is ready

### Pricing & Services Config
- Per-kg or per-piece pricing, service add-ons (fabric softener, stain treatment)
- Promo codes / bundle pricing

### POS & Payments
- Cash, GCash/Maya, card — mirrors what you'd expect from a retail POS
- Daily cash drawer reconciliation

### Inventory
- Detergent, fabric softener, plastic bags, hangers — consumption tracking tied to orders so owner sees supply burn rate

### Staff Management
- Shift logging, per-staff order handling (accountability), attendance
- Role-based access (staff can't see revenue reports, only their queue)

### Delivery/Pickup (optional module)
- Rider assignment, route/status tracking, delivery fee calc

### Reports & Analytics (owner dashboard, web-first)
- Daily/weekly/monthly revenue, busiest hours, top services, staff performance
- Expense tracking (utilities, supplies) → basic profit view

### Notifications
- Order ready, payment received, low stock alerts

## 3. Platform Split

| Surface | Primary users | Notes |
|---|---|---|
| **Mobile app (owner/staff)** | Staff at counter, owner on the go | Fast order intake, offline-tolerant queue updates, barcode/QR ticket scanning |
| **Web dashboard (owner)** | Owner, back-office | Reports, pricing config, staff management, multi-branch overview |
| **Customer-facing** (phase 2) | End customers | Simple: order tracking + notifications; could start as a web page via SMS link before building a full app |

## 4. Suggested Architecture (Sketch-Level)
- **Backend**: Supabase (Postgres + Auth + Realtime + Storage) — realtime order status sync between staff mobile app and owner dashboard is the killer feature here
- **Mobile**: Flutter (single codebase for Android/iOS, consistent with staff-facing speed needs)
- **Web dashboard**: could also be Flutter Web, or a lighter React/Next.js admin panel if you want richer charts/tables
- **Payments**: local gateway (PayMongo, GCash API) or manual entry for MVP
- **Notifications**: FCM push + SMS fallback (Semaphore/Twilio) for customers without the app

## 5. Rough Data Model

```
shops (id, name, owner_id, branch info)
staff (id, shop_id, name, role, pin/login)
customers (id, shop_id, name, phone, loyalty_points)
services (id, shop_id, name, unit [kg/piece], price)
orders (id, shop_id, customer_id, staff_id, status, items[], total, created_at, ready_at, picked_up_at)
order_items (order_id, service_id, qty/weight, subtotal)
payments (order_id, method, amount, paid_at)
inventory (id, shop_id, item_name, qty, reorder_threshold)
expenses (id, shop_id, category, amount, date)
```

## 6. Phased Roadmap
1. **MVP** — order intake, status pipeline, basic pricing, receipt printing, owner web dashboard with daily revenue
2. **Phase 2** — staff accounts/roles, inventory tracking, customer notifications (SMS)
3. **Phase 3** — customer-facing tracking page/app, online payments, loyalty program
4. **Phase 4** — delivery/rider module, multi-branch support, deeper analytics

## 7. Monetization (if this is a SaaS product, not internal tool)
- Tiered plans by staff seats / order volume / branches — similar shape to a Free trial → Starter → Basic → Pro ladder, gating things like staff accounts, transaction history retention, and AI features (e.g. demand forecasting, auto-restock suggestions)
