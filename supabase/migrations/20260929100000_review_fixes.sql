-- Fixes from the pre-TestFlight code review, 2026-09-27.
--
-- 1. A bill's path is exactly <group id>/<expense id>/<uuid>.jpg.
--
-- 20260927100000 only checked that it started with the group id, so a member
-- could point an expense at `<group id>/../../mull.json`. Phones turn the path
-- into a file under their own storage, and removing that bill would have
-- deleted whatever the dots led to. The app now refuses such a path too; this
-- is the half that stops it being written for anyone else in the first place.
alter table public.expenses
  drop constraint if exists expenses_receipt_path_in_group,
  add constraint expenses_receipt_path_in_group check (
    receipt_path is null
    or receipt_path ~ (
      '^' || group_id::text || '/' || id::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
    )
  );

-- The same shape for the objects themselves: no dots, nothing extra.
create or replace function public.can_reach_receipt(object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  folder text := split_part(object_name, '/', 1);
begin
  if object_name !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$' then
    return false;
  end if;
  return public.is_member(folder::uuid) or public.is_group_creator(folder::uuid);
end;
$$;

-- ------------------------------------------------ a schedule's own day

-- The day of the month a monthly, quarterly or yearly schedule falls on.
--
-- Each occurrence used to be counted from the one before it, with the day
-- clamped to the month: rent on the 31st came due on 28 February, and then on
-- the 28th of every month after, for good. With the day it was set up on
-- kept separately, February still clamps and March goes back to the 31st.
--
-- Nullable: a schedule written before this has none, and the app takes its
-- current day the next time it moves on. The client probes for the column
-- and leaves it out until it exists.
alter table public.recurring_expenses
  add column if not exists anchor_day smallint
    check (anchor_day is null or anchor_day between 1 and 31);

-- A plain grant adds to the existing column list; no revoke, which would take
-- the others with it (see 20260920140000).
grant insert (anchor_day), update (anchor_day) on public.recurring_expenses to authenticated;

-- ------------------------------------------------ who may add a seat

-- Who is in a group is an admin's decision; the app only offers "Add people"
-- to admins. The server let any member insert a seat. A new seat now needs an
-- admin, or the group's creator (whose own admin seat is the first one in).
--
-- Dropped rather than refused. The push sends seats in one statement, and a
-- stale copy of a seat an admin has since removed would otherwise fail every
-- push from that phone — and bring the seat back, which is worse.
create or replace function public.guard_seat_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.members m where m.id = new.id) then
    return new;                        -- an upsert re-sending a seat
  end if;
  if public.is_group_admin(new.group_id) or public.is_group_creator(new.group_id) then
    return new;
  end if;
  return null;
end;
$$;

revoke all on function public.guard_seat_insert() from public, anon, authenticated;

drop trigger if exists guard_seat_insert on public.members;
create trigger guard_seat_insert before insert on public.members
  for each row execute function public.guard_seat_insert();
