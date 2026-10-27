-- Leaving a group you created, 2026-10-27.
--
-- Every group-scoped policy, and my_group_revs(), lets a group's creator see
-- it whether or not they still sit in it. That clause exists so a new group is
-- not locked away from its author before its seats have been pushed. But it
-- outlived leaving: leave_group() took your seat and left `created_by`, so the
-- next pull handed the group straight back with no seat in it for you, and
-- the app, finding nobody to take out, said "Couldn't reach Mull" on every
-- try after that.
--
-- Leaving now gives up being the creator too. Nothing else reads the column
-- for anything a leaver should keep: the admin role is what runs a group.
--
-- Additive for every app version: an older build that has already been handed
-- such a group back drops it on its next pull, because it is no longer listed.

-- The author stamp keeps created_by fixed on every update. It steps aside for
-- leave_group(), for the one group being left, the way the member guards step
-- aside for `mull.leaving`.
create or replace function public.stamp_group_author()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_setting('mull.erasing', true) = 'on' then return new; end if;
  if current_setting('mull.leaving_group', true) = old.id::text then return new; end if;
  new.created_by := old.created_by;
  return new;
end;
$$;

-- Based on 20260928100000's body, which is live.
create or replace function public.leave_group(target_group uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  seat public.members%rowtype;
  admins_left integer;
  outcome text;
begin
  if me is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  select * into seat from public.members
   where group_id = target_group and user_id = me
   for update;
  if not found then
    -- Already out, possibly by an older build that left the creator behind.
    -- Letting go of the group is still what was asked for.
    perform public.forget_created_group(target_group, me);
    return 'not_member';
  end if;

  if exists (select 1 from public.groups g where g.id = target_group and g.kind = 'direct') then
    raise exception 'a one-to-one ledger is deleted, not left' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.settlements t
     where t.group_id = target_group and t.deleted_at is null and t.status = 'pending'
       and t.to_member_id = seat.id
  ) then
    raise exception 'a payment to you is still waiting for you to confirm it' using errcode = '23514';
  end if;

  select count(*) into admins_left from public.members m
   where m.group_id = target_group and m.role = 'admin' and m.id <> seat.id;
  if seat.role = 'admin' and admins_left = 0 and exists (
    select 1 from public.members m
     where m.group_id = target_group and m.id <> seat.id and m.user_id is not null
  ) then
    raise exception 'make someone else an admin before leaving' using errcode = '23514';
  end if;

  if not exists (select 1 from public.expenses e where e.payer_member_id = seat.id)
     and not exists (select 1 from public.expense_shares s where s.member_id = seat.id)
     and not exists (select 1 from public.settlements t where t.from_member_id = seat.id or t.to_member_id = seat.id)
     and not exists (select 1 from public.recurring_expenses r where r.payer_member_id = seat.id)
     and not exists (select 1 from public.recurring_shares r where r.member_id = seat.id) then
    delete from public.members where id = seat.id;
    outcome := 'deleted';
  else
    perform set_config('mull.leaving', seat.id::text, true);
    update public.members m
       set user_id = null,
           name = coalesce(nullif(trim((select p.name from public.profiles p where p.id = me)), ''), m.name),
           upi_id = (select p.upi_id from public.profiles p where p.id = me),
           left_by = me,
           role = case when admins_left > 0 then 'member'::public.member_role else m.role end
     where m.id = seat.id;
    perform set_config('mull.leaving', '', true);
    outcome := 'detached';
  end if;

  perform public.forget_created_group(target_group, me);
  return outcome;
end;
$$;
revoke all on function public.leave_group(uuid) from public, anon;
grant execute on function public.leave_group(uuid) to authenticated;

-- Clears created_by on a group [who] made, so being its creator stops
-- reaching it. Internal: only leave_group() calls it.
create or replace function public.forget_created_group(target_group uuid, who uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('mull.leaving_group', target_group::text, true);
  update public.groups set created_by = null
   where id = target_group and created_by = who;
  perform set_config('mull.leaving_group', '', true);
end;
$$;
revoke all on function public.forget_created_group(uuid, uuid) from public, anon, authenticated;

-- The groups already handed back: created by someone who left them and has
-- no seat there now.
do $$
begin
  perform set_config('mull.erasing', 'on', true);
  update public.groups g set created_by = null
   where g.created_by is not null
     and exists (select 1 from public.members m where m.group_id = g.id and m.left_by = g.created_by)
     and not exists (select 1 from public.members m where m.group_id = g.id and m.user_id = g.created_by);
  perform set_config('mull.erasing', '', true);
end;
$$;
