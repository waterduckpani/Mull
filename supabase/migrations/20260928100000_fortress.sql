-- The pre-launch security audit, 2026-09-27.
--
-- Every hole closed here was first reproduced against a Postgres built from
-- this exact migration history, as a member of the group using nothing but
-- the anon key and their own session, which is all a modified app needs:
--
--   1. Any member could move any seat, expense, schedule or settlement into
--      another group by updating its group_id. Moving a friend's seat put
--      them into a group of your making without asking, which is the one thing
--      the friend system exists to prevent.
--   2. A confirmed "net-off" could be written on its own. One offset, from you
--      to someone you owe, cleared the debt without a rupee moving and without
--      the matching offset the other way.
--   3. The payee could delete a payment after confirming it, and either side
--      could remove or dispute half of a net-off, reopening a debt the other
--      person had already paid off.
--   4. Any member could turn a group into a "direct" ledger, which nobody is
--      allowed to leave.
--   5. friend_list() showed the account id and real name behind any address
--      you sent a request to, before they answered: a lookup of who is on
--      Mull, and what they are called, by email.
--   6. Anyone in a group could rewrite the UPI ID of someone who had left it,
--      so that what the others paid the leaver went to them instead.
--   7. No text had a length limit. A megabyte of description is pulled by
--      every phone in the group on every sync.
--   8. A password could be set on an address nobody had confirmed yet, and it
--      kept working after the real owner confirmed it by code.
--   9. Nothing capped how many rows one account could create.
--
-- Additive, and safe to apply before the app that uses it: the only thing an
-- older build loses is automatic netting between two people on Mull, which it
-- wrote in a way the server no longer accepts (see 2). Those offsets are
-- dropped, not refused, so the rest of the push goes through.

-- ------------------------------------------------ 1, 4. identity is fixed

-- Which row this is, and which group it belongs to, never change. There is
-- no edit in the app that needs either, and the push re-sends both unchanged,
-- so a refusal here only ever meets a client that is up to something.
create or replace function public.pin_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  before_ jsonb := to_jsonb(old);
  after_  jsonb := to_jsonb(new);
  col     text;
begin
  if current_setting('mull.erasing', true) = 'on' then
    return new;
  end if;
  foreach col in array tg_argv loop
    if before_ -> col is distinct from after_ -> col then
      raise exception '%.% cannot be changed', tg_table_name, col using errcode = '42501';
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists pin_columns on public.groups;
create trigger pin_columns before update on public.groups
  for each row execute function public.pin_columns('id', 'kind');
drop trigger if exists pin_columns on public.members;
create trigger pin_columns before update on public.members
  for each row execute function public.pin_columns('id', 'group_id');
drop trigger if exists pin_columns on public.expenses;
create trigger pin_columns before update on public.expenses
  for each row execute function public.pin_columns('id', 'group_id');
drop trigger if exists pin_columns on public.recurring_expenses;
create trigger pin_columns before update on public.recurring_expenses
  for each row execute function public.pin_columns('id', 'group_id');
drop trigger if exists pin_columns on public.settlements;
create trigger pin_columns before update on public.settlements
  for each row execute function public.pin_columns('id', 'group_id');
drop trigger if exists pin_columns on public.expense_shares;
create trigger pin_columns before update on public.expense_shares
  for each row execute function public.pin_columns('expense_id', 'member_id');
drop trigger if exists pin_columns on public.recurring_shares;
create trigger pin_columns before update on public.recurring_shares
  for each row execute function public.pin_columns('recurring_id', 'member_id');

-- ------------------------------------------------------ 2. net-offs

-- A net-off between two people on Mull is two offsets, one in each direction,
-- and it only means anything as a pair: each half on its own is a payment
-- nobody made. The pair used to arrive as two ordinary inserts, one per
-- group's push, with nothing tying them together. Now it arrives through
-- record_offsets(), which takes every half at once and refuses a set that
-- does not cancel out.
--
-- Balanced is the whole check, and it is enough. Each offset moves the debt
-- between the same two people by its amount in one ledger; halves that sum to
-- zero per person leave what each owes the other, across all of their
-- ledgers, exactly where it was. Nobody can be made poorer by a balanced set,
-- only shown their debt in a different ledger.
--
-- Offsets against a seat with no account behind it are unchanged: nobody is
-- there to be protected yet, the same as recording a payment to one.
create or replace function public.record_offsets(offsets jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  me        uuid := auth.uid();
  item      jsonb;
  pending   jsonb := '[]'::jsonb;
  balance   jsonb := '{}'::jsonb;
  held      public.settlements%rowtype;
  row_id    uuid;
  grp       uuid;
  from_seat uuid;
  to_seat   uuid;
  amt       integer;
  from_user uuid;
  to_user   uuid;
  other     text;
  written   integer := 0;
begin
  if me is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  if jsonb_typeof(offsets) is distinct from 'array' or jsonb_array_length(offsets) > 500 then
    raise exception 'offsets come as a list of at most 500' using errcode = '22023';
  end if;

  for item in select value from jsonb_array_elements(offsets) loop
    row_id    := (item ->> 'id')::uuid;
    grp       := (item ->> 'group_id')::uuid;
    from_seat := (item ->> 'from_member_id')::uuid;
    to_seat   := (item ->> 'to_member_id')::uuid;
    amt       := (item ->> 'amount')::integer;
    if row_id is null or grp is null or from_seat is null or to_seat is null
       or amt is null or amt <= 0 or from_seat = to_seat then
      raise exception 'an offset needs an id, a group, two seats and an amount' using errcode = '22023';
    end if;
    if not public.is_member(grp) then
      raise exception 'you are not in that group' using errcode = '42501';
    end if;

    select m.user_id into from_user from public.members m where m.id = from_seat and m.group_id = grp;
    if not found then
      raise exception 'both ends of an offset have to be in its group' using errcode = '23503';
    end if;
    select m.user_id into to_user from public.members m where m.id = to_seat and m.group_id = grp;
    if not found then
      raise exception 'both ends of an offset have to be in its group' using errcode = '23503';
    end if;
    if from_user is null or to_user is null or from_user = to_user then
      raise exception 'this is for offsets between two people on Mull' using errcode = '22023';
    end if;
    if me is distinct from from_user and me is distinct from to_user then
      raise exception 'an offset has to be yours' using errcode = '42501';
    end if;

    -- Sent again after a reply that never arrived. Already checked as part of
    -- a balanced set, so it takes no part in this one.
    select * into held from public.settlements s where s.id = row_id;
    if found then
      if held.group_id <> grp or held.from_member_id <> from_seat or held.to_member_id <> to_seat
         or held.amount <> amt or not held.is_offset then
        raise exception 'that id belongs to a different payment' using errcode = '23505';
      end if;
      continue;
    end if;

    other := case when from_user = me then to_user else from_user end::text;
    balance := jsonb_set(
      balance,
      array[other],
      to_jsonb(coalesce((balance ->> other)::bigint, 0) + case when from_user = me then amt else -amt end)
    );
    pending := pending || jsonb_build_array(item);
  end loop;

  if exists (select 1 from jsonb_each_text(balance) b where b.value::bigint <> 0) then
    raise exception 'a net-off has to cancel by the same amount both ways' using errcode = '23514';
  end if;

  perform set_config('mull.netting', 'on', true);
  for item in select value from jsonb_array_elements(pending) loop
    insert into public.settlements
      (id, group_id, from_member_id, to_member_id, amount, status, is_offset,
       claimed_by, claimed_at, confirmed_at, confirmed_by)
    values (
      (item ->> 'id')::uuid, (item ->> 'group_id')::uuid,
      (item ->> 'from_member_id')::uuid, (item ->> 'to_member_id')::uuid,
      (item ->> 'amount')::integer, 'confirmed', true,
      me, coalesce((item ->> 'claimed_at')::timestamptz, now()), now(), me
    );
    written := written + 1;
  end loop;
  perform set_config('mull.netting', '', true);
  return written;
end;
$$;

revoke all on function public.record_offsets(jsonb) from public, anon;
grant execute on function public.record_offsets(jsonb) to authenticated;

-- Based on 20260926100000's body, which is live. The one change is the
-- offset check near the top.
create or replace function public.guard_settlement_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_payee        boolean;
  is_party        boolean;
  payee_unclaimed boolean;
  both_unclaimed  boolean;
begin
  if exists (select 1 from public.settlements s where s.id = new.id) then
    return new;
  end if;

  -- Half a net-off between two accounts, arriving on its own. Dropped rather
  -- than refused, so an older app's push carries on with everything else in
  -- it; see record_offsets().
  if new.is_offset
     and current_setting('mull.netting', true) is distinct from 'on'
     and exists (select 1 from public.members m where m.id = new.from_member_id and m.user_id is not null)
     and exists (select 1 from public.members m where m.id = new.to_member_id and m.user_id is not null) then
    return null;
  end if;

  select exists (
    select 1 from public.members m
     where m.id = new.to_member_id and m.user_id = auth.uid()
  ) into is_payee;
  select exists (
    select 1 from public.members m
     where m.id in (new.from_member_id, new.to_member_id) and m.user_id = auth.uid()
  ) into is_party;
  select exists (
    select 1 from public.members m
     where m.id = new.to_member_id and m.user_id is null
  ) into payee_unclaimed;
  select not exists (
    select 1 from public.members m
     where m.id in (new.from_member_id, new.to_member_id) and m.user_id is not null
  ) into both_unclaimed;

  -- Somebody else's money. Nothing to write.
  if not is_party and not both_unclaimed then
    return null;
  end if;

  -- An offset from a bystander is not an offset. Relabelled as the ordinary
  -- claim it is, and judged as one below.
  if new.is_offset and not is_party then
    new.is_offset := false;
  end if;

  if new.status <> 'pending' or new.confirmed_at is not null then
    if not (is_payee or payee_unclaimed or (new.is_offset and is_party)) then
      new.status := 'pending';
      new.confirmed_at := null;
    end if;
  end if;

  if new.status = 'confirmed' then
    new.confirmed_by := coalesce(new.confirmed_by, auth.uid());
  end if;
  return new;
end;
$$;

-- ------------------------------------------ 3. taking a payment back

-- Based on 20260921100000's body, which is live. Two changes:
--
-- A confirmed payment, and any offset, can only be taken off the record by
-- whoever it credits: the payer. Removing it puts the debt back on them and
-- on nobody else. The payee who thinks the money never came can still say
-- so, by disputing it, which leaves the record where everyone can see it.
-- The exception is a payment from a seat with no account, which has nobody
-- to take it back but the payee.
--
-- An offset is never pending and never disputed, so its status is pinned
-- outright; disputing half of a net-off reopened a debt that had been
-- cancelled by the other half.
create or replace function public.guard_settlement_facts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_payee boolean;
  is_payer boolean;
  is_party boolean;
begin
  if current_setting('mull.erasing', true) = 'on' then
    return new;
  end if;

  select exists (
    select 1 from public.members m
     where m.id = old.to_member_id and m.user_id = auth.uid()
  ) into is_payee;
  select exists (
    select 1 from public.members m
     where m.id = old.from_member_id and m.user_id = auth.uid()
  ) into is_payer;
  is_party := is_payee or is_payer;

  if new.deleted_at is distinct from old.deleted_at then
    if not is_party then
      raise exception 'only the two people a payment is between can remove it'
        using errcode = '42501';
    end if;
    -- A seat nobody has claimed cannot take anything back, so there the
    -- payee may correct their own record.
    if (old.status = 'confirmed' or old.is_offset) and not is_payer
       and exists (select 1 from public.members m
                    where m.id = old.from_member_id and m.user_id is not null) then
      raise exception 'only whoever paid can take a confirmed payment off the record'
        using errcode = '42501';
    end if;
  end if;

  new.is_offset := old.is_offset;

  if old.is_offset
     or ((new.status is distinct from old.status
          or new.confirmed_at is distinct from old.confirmed_at)
         and not is_payee) then
    new.status := old.status;
    new.confirmed_at := old.confirmed_at;
  end if;

  if new.status = 'confirmed' and old.status <> 'confirmed' then
    new.confirmed_by := auth.uid();
  end if;

  if new.group_id          is distinct from old.group_id
     or new.from_member_id is distinct from old.from_member_id
     or new.to_member_id   is distinct from old.to_member_id
     or new.amount         is distinct from old.amount
     or new.utr            is distinct from old.utr then
    if old.status <> 'pending' or auth.uid() is distinct from old.claimed_by then
      raise exception 'a settlement''s facts cannot be changed once confirmed'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

-- --------------------------------------------------- 5. friend requests

-- The app reads friendships only through friend_list() and writes them only
-- through send_friend_request() and accept_friend_request(). The table grants
-- let a client go round all three: read which account an address belongs to,
-- and send requests with no limit. What is left is deleting your own rows,
-- which a DELETE ... WHERE id = needs `select` on id for.
--
-- A table-level revoke takes the column-level grants with it, which is the
-- point here.
revoke select, insert, update on public.friendships from authenticated;
grant select (id) on public.friendships to authenticated;

-- Based on 20260921160000's body. A request you sent that has not been
-- answered shows the address you typed and nothing else: not the account it
-- reached, not its name. Their name arrives when they say yes.
create or replace function public.friend_list()
returns table (
  friendship_id uuid,
  requester_id uuid,
  addressee_id uuid,
  addressee_email text,
  status public.friendship_status,
  other_id uuid,
  other_name text,
  other_email text,
  other_upi_id text
)
language sql
stable
security definer
set search_path = public
as $$
  select f.id,
         f.requester_id,
         case when f.status = 'accepted' or f.requester_id <> auth.uid() then f.addressee_id end,
         f.addressee_email,
         f.status,
         case when f.status = 'accepted' or f.requester_id <> auth.uid() then p.id end,
         case when f.status = 'accepted' or f.requester_id <> auth.uid() then p.name end,
         case when f.status = 'accepted' or f.requester_id <> auth.uid() then p.email
              else coalesce(f.addressee_email, p.email) end,
         case when f.status = 'accepted' then p.upi_id end
    from public.friendships f
    left join public.profiles p
      on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
   where f.requester_id = auth.uid()
      or f.addressee_id = auth.uid()
      or (f.addressee_id is null and f.addressee_email = public.my_email());
$$;

-- Based on 20260917190000's body, which is live, with a daily limit. Thirty
-- is more people than anyone adds in a day, and far fewer than a list of
-- addresses somebody wants to spam.
create or replace function public.send_friend_request(target_email text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  address  text := lower(trim(target_email));
  me       uuid := auth.uid();
  my_email text;
  target   uuid;
begin
  if me is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  if address is null or length(address) > 254 or address !~ '^[^@\s]+@[^@\s.]+\.[^@\s]{2,}$' then
    raise exception 'that does not look like an email address' using errcode = '22023';
  end if;

  select email into my_email from public.profiles where id = me;
  if address = my_email then
    raise exception 'that is your own address' using errcode = '22023';
  end if;

  select id into target from public.profiles where email = address;

  -- Already connected, in either direction and at any stage. Returning the
  -- existing state rather than raising keeps the caller's message honest
  -- without telling it anything it could not already see.
  if target is not null and exists (
    select 1 from public.friendships f
     where (f.requester_id = me and f.addressee_id = target)
        or (f.requester_id = target and f.addressee_id = me)
  ) then
    return 'already';
  end if;
  if exists (
    select 1 from public.friendships f
     where f.requester_id = me and f.addressee_email = address
  ) then
    return 'already';
  end if;

  if (select count(*) from public.friendships f
       where f.requester_id = me and f.created_at > now() - interval '1 day') >= 30 then
    raise exception 'too many friend requests today' using errcode = '54000';
  end if;

  insert into public.friendships (requester_id, addressee_id, addressee_email, status)
  values (me, target, case when target is null then address else null end, 'pending');

  -- The same word whether or not anyone was there. This is the whole point.
  return 'sent';
end;
$$;

-- ------------------------------------------ 6. a leaver's UPI ID stays theirs

-- Who a detached seat used to belong to. Set only by leave_group(); the
-- client has no grant to write it.
alter table public.members add column if not exists left_by uuid;

-- A seat someone left keeps the UPI ID their account had, so the people they
-- still owe or are owed by can settle. That ID came from the account holder,
-- and nobody else gets to change it. Pinned rather than refused: the push
-- re-sends the seat as it last saw it, and a stale copy must not stop the
-- group syncing.
create or replace function public.keep_leaver_upi()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    -- The column is the server's to set. An upsert re-sending an existing seat
    -- passes through here too; left_by is not in what the app sends, so the
    -- update that follows leaves the stored value alone.
    new.left_by := null;
    return new;
  end if;
  if current_setting('mull.leaving', true) = old.id::text
     or current_setting('mull.erasing', true) = 'on' then
    return new;
  end if;
  new.left_by := old.left_by;
  if old.left_by is not null then
    new.upi_id := old.upi_id;
  end if;
  return new;
end;
$$;

drop trigger if exists keep_leaver_upi on public.members;
create trigger keep_leaver_upi before insert or update on public.members
  for each row execute function public.keep_leaver_upi();

-- Based on 20260926100000's body, which is live. Records who left.
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
begin
  if me is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  select * into seat from public.members
   where group_id = target_group and user_id = me
   for update;
  if not found then
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
    return 'deleted';
  end if;

  perform set_config('mull.leaving', seat.id::text, true);
  update public.members m
     set user_id = null,
         name = coalesce(nullif(trim((select p.name from public.profiles p where p.id = me)), ''), m.name),
         upi_id = (select p.upi_id from public.profiles p where p.id = me),
         left_by = me,
         role = case when admins_left > 0 then 'member'::public.member_role else m.role end
   where m.id = seat.id;
  perform set_config('mull.leaving', '', true);
  return 'detached';
end;
$$;

-- Based on 20260921100000's body, which is live. Deleting an account now also
-- takes its UPI ID off the seats it had already left, which it could not find
-- before: a detached seat has no user_id to look it up by.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  perform set_config('mull.erasing', 'on', true);

  update public.members
     set email = null, phone = null, upi_id = null
   where user_id = me or left_by = me;
  update public.members set left_by = null where left_by = me;

  delete from public.notices where recipient_id = me or actor_id = me;
  delete from public.friendships where requester_id = me or addressee_id = me;

  delete from auth.users where id = me;
end;
$$;

-- --------------------------------------------------------- 7. lengths

-- Far past anything the app lets anyone type (it stops well short of these),
-- so they only ever meet a client that is not the app.
alter table public.groups
  drop constraint if exists groups_name_length,
  add constraint groups_name_length check (length(name) <= 120);
alter table public.members
  drop constraint if exists members_text_lengths,
  add constraint members_text_lengths check (
    length(name) <= 120 and length(coalesce(email, '')) <= 320
    and length(coalesce(phone, '')) <= 40 and length(coalesce(upi_id, '')) <= 255
  );
alter table public.expenses
  drop constraint if exists expenses_text_lengths,
  add constraint expenses_text_lengths check (
    length(description) <= 200 and length(coalesce(note, '')) <= 2000
  );
alter table public.recurring_expenses
  drop constraint if exists recurring_text_lengths,
  add constraint recurring_text_lengths check (length(description) <= 200);
alter table public.settlements
  drop constraint if exists settlements_utr_length,
  add constraint settlements_utr_length check (length(coalesce(utr, '')) <= 64);
alter table public.profiles
  drop constraint if exists profiles_text_lengths,
  add constraint profiles_text_lengths check (
    length(coalesce(name, '')) <= 120 and length(coalesce(upi_id, '')) <= 255
  );

-- ------------------------------------------------ 8. unconfirmed passwords

-- Mull signs in by emailed code. Password sign-up is still open at the auth
-- API (the review account needs password sign-in), so anyone can register
-- someone else's address with a password of their choosing. The account sits
-- unconfirmed until the real owner signs in by code, which confirms it — and
-- the password the stranger chose used to survive that. Now the moment an
-- address is confirmed, any password set before then is replaced with one
-- nobody knows.
create or replace function public.forget_unconfirmed_password()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if old.email_confirmed_at is null
     and new.email_confirmed_at is not null
     and lower(coalesce(new.email, '')) <> 'review@mull.oblunestudio.com' then
    new.encrypted_password := extensions.crypt(
      gen_random_uuid()::text || gen_random_uuid()::text,
      extensions.gen_salt('bf')
    );
  end if;
  return new;
end;
$$;

revoke all on function public.forget_unconfirmed_password() from public, anon, authenticated;

drop trigger if exists forget_unconfirmed_password on auth.users;
create trigger forget_unconfirmed_password
  before update of email_confirmed_at on auth.users
  for each row execute function public.forget_unconfirmed_password();

-- ------------------------------------------------------------ 9. caps

-- Generous ceilings on how much one account can create, so a script with a
-- session cannot fill the database. Each one is far past real use: a flat
-- adding ten expenses a day for a year stays under the group cap.
--
-- BEFORE INSERT runs for every row of an upsert, including rows that already
-- exist and are about to be updated (see 20260920180000), so each check lets
-- an existing id straight through.
create or replace function public.cap_rows()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  over boolean := false;
begin
  if current_setting('mull.netting', true) = 'on' then
    return new;
  end if;
  case tg_table_name
    when 'groups' then
      if exists (select 1 from public.groups g where g.id = new.id) then return new; end if;
      new.created_at := now();
      over := (select count(*) from public.groups g
                where g.created_by = auth.uid() and g.created_at > now() - interval '1 day') >= 50;
    when 'members' then
      if exists (select 1 from public.members m where m.id = new.id) then return new; end if;
      over := (select count(*) from public.members m where m.group_id = new.group_id) >= 200;
    when 'expenses' then
      if exists (select 1 from public.expenses e where e.id = new.id) then return new; end if;
      new.created_at := now();
      over := (select count(*) from public.expenses e
                where e.created_by = auth.uid() and e.created_at > now() - interval '1 day') >= 1000
           or (select count(*) from public.expenses e where e.group_id = new.group_id) >= 20000;
    when 'settlements' then
      if exists (select 1 from public.settlements s where s.id = new.id) then return new; end if;
      over := (select count(*) from public.settlements s where s.group_id = new.group_id) >= 20000;
    when 'recurring_expenses' then
      if exists (select 1 from public.recurring_expenses r where r.id = new.id) then return new; end if;
      over := (select count(*) from public.recurring_expenses r where r.group_id = new.group_id) >= 200;
    else
      return new;
  end case;
  if over then
    raise exception 'too many % for one account or group', tg_table_name using errcode = '54000';
  end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['groups', 'members', 'expenses', 'settlements', 'recurring_expenses'] loop
    execute format('drop trigger if exists cap_rows on public.%I', t);
    execute format('create trigger cap_rows before insert on public.%I for each row execute function public.cap_rows()', t);
  end loop;
end;
$$;

-- Bills: sixty photos a day per account is a lot of dinners.
create or replace function public.receipt_quota_left()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select (select count(*) from storage.objects o
           where o.bucket_id = 'receipts'
             and o.owner_id = auth.uid()::text
             and o.created_at > now() - interval '1 day') < 60;
$$;

drop policy if exists receipts_insert on storage.objects;
create policy receipts_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'receipts' and public.can_reach_receipt(name) and public.receipt_quota_left());

-- Trigger functions are never called directly, but nothing needs to be able
-- to try.
revoke all on function public.pin_columns() from public, anon, authenticated;
revoke all on function public.keep_leaver_upi() from public, anon, authenticated;
revoke all on function public.cap_rows() from public, anon, authenticated;
revoke all on function public.guard_receipt_request() from public, anon;
