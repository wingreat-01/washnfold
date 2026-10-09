-- Adds the Self Service / Full Service split to services.
-- Existing services become 'self'; change any that are full service in the
-- Services tab (tap a service → Self Service / Full Service).
alter table public.services
  add column if not exists service_type text not null default 'self'
  check (service_type in ('self', 'full'));
