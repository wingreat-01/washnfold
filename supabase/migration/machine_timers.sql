-- Run once in the Supabase SQL editor, BEFORE using the new app build.
-- Per-machine timers for washers and dryers:
--   cycle_minutes : how long one load runs on that machine (editable in the
--                   machine's Configure form); null = app default.
--   ends_at       : when the load now in the machine should finish; set when
--                   a load starts, adjustable from the machine card.
alter table public.washers
  add column if not exists cycle_minutes int
    check (cycle_minutes is null or cycle_minutes between 1 and 600),
  add column if not exists ends_at timestamptz;

alter table public.dryers
  add column if not exists cycle_minutes int
    check (cycle_minutes is null or cycle_minutes between 1 and 600),
  add column if not exists ends_at timestamptz;
