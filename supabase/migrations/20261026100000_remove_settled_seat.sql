-- Taking a settled person out of a group, 2026-10-26.
--
-- A seat could only be removed while nothing referred to it, so somebody
-- added by name for one dinner, paid back in full, stayed in the group for
-- good: every expense they had a share of is a foreign key to their seat, and
-- deleting it would rewrite what everyone else owes.
--
-- A removed seat now stays, with its history, and is marked removed_at. The
-- app hides it from the people list and from new splits. Only remove_member()
-- sets the column, and only for a seat nobody can still owe or be owed by.
--
-- Additive: older builds never select the column, and the trigger below keeps
-- their re-sent seats from clearing it.

alter table public.members add column if not exists removed_at timestamptz;

-- Pinned, the way keep_leaver_upi pins left_by. The app never sends the
-- column; an upsert that did must not be able to bring someone back or take
-- someone out.
create or replace function public.keep_removed_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    -- Fires for an upsert re-sending an existing seat too. removed_at is not
    -- in what the app sends, so the update that follows leaves it alone.
    new.removed_at := null;
    return new;
  end if;
  if current_setting('mull.removing', true) = old.id::text then
    return new;
  end if;
  new.removed_at := old.removed_at;
  return new;
end;
$$;

drop trigger if exists keep_removed_at on public.members;
create trigger keep_removed_at before insert or update on public.members
  for each row execute function public.keep_removed_at();

revoke all on function public.keep_removed_at() from public, anon, authenticated;

-- Removes a seat that is not on Mull and has nothing open.
--
-- Only an admin of the group, and only a seat with no account behind it: a
-- person on Mull with history leaves for themselves (leave_group). Nothing
-- open means no amount between them and anyone else in the group, pair by
-- pair as the app counts it, no payment waiting to be confirmed, and no
-- repeating expense that would bill them again next month.
--
-- Their email and phone go too, so a removed seat is never claimed by an
-- invitation later.
create or replace function public.remove_member(target_member uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  seat public.members%rowtype;
begin
  if me is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  select * into seat from public.members where id = target_member for update;
  if not found then
    return 'not_found';
  end if;
  if seat.removed_at is not null then
    return 'removed';
  end if;

  if not exists (
    select 1 from public.members m
     where m.group_id = seat.group_id and m.user_id = me and m.role = 'admin'
  ) then
    raise exception 'only an admin can take someone out of a group' using errcode = '42501';
  end if;

  if exists (select 1 from public.groups g where g.id = seat.group_id and g.kind = 'direct') then
    raise exception 'a one-to-one ledger has nobody to remove' using errcode = '22023';
  end if;

  if seat.user_id is not null then
    raise exception 'someone on Mull leaves a group themselves' using errcode = '23514';
  end if;

  if exists (
    select 1 from public.settlements t
     where t.group_id = seat.group_id and t.deleted_at is null and t.status = 'pending'
       and seat.id in (t.from_member_id, t.to_member_id)
  ) then
    raise exception 'a payment with them is still waiting to be confirmed' using errcode = '23514';
  end if;

  if exists (
    select 1 from public.recurring_expenses r
     where r.group_id = seat.group_id and r.deleted_at is null
       and (r.payer_member_id = seat.id
            or exists (select 1 from public.recurring_shares s
                        where s.recurring_id = r.id and s.member_id = seat.id and s.amount > 0))
  ) then
    raise exception 'they are in a repeating expense' using errcode = '23514';
  end if;

  -- What each other seat owes them (positive) or they owe it, as Group.pairBalance
  -- counts it: a share of a bill someone else paid is a debt to the payer, and a
  -- confirmed payment from A to B cancels that much of what A owed B.
  if exists (
    with flows (debtor, creditor, amount) as (
      select s.member_id, e.payer_member_id, s.amount
        from public.expense_shares s
        join public.expenses e on e.id = s.expense_id
       where e.group_id = seat.group_id and e.deleted_at is null
         and s.member_id <> e.payer_member_id
      union all
      select t.to_member_id, t.from_member_id, t.amount
        from public.settlements t
       where t.group_id = seat.group_id and t.deleted_at is null and t.status = 'confirmed'
    )
    select 1
      from flows
     where seat.id in (debtor, creditor)
     group by case when creditor = seat.id then debtor else creditor end
    having sum(case when creditor = seat.id then amount else -amount end) <> 0
  ) then
    raise exception 'settle up with them first' using errcode = '23514';
  end if;

  perform set_config('mull.removing', seat.id::text, true);
  update public.members
     set removed_at = now(), email = null, phone = null
   where id = seat.id;
  perform set_config('mull.removing', '', true);
  return 'removed';
end;
$$;

revoke all on function public.remove_member(uuid) from public, anon;
grant execute on function public.remove_member(uuid) to authenticated;
