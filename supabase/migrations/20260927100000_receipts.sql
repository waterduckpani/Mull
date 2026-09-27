-- Receipts: a photo of the bill on an expense, and a way to ask for one.
--
-- Someone puts ₹500 on you for dinner; you can already be told what you owe,
-- and now you can ask to see what it was for. The request is a seat id on the
-- expense row, cleared when a photo is attached, so it syncs with the ledger
-- like everything else and needs no table of its own.
--
-- Additive only. The client probes `expenses.receipt_path` and sends neither
-- column until this is applied.

-- ------------------------------------------------------------------ columns

alter table public.expenses
  add column if not exists receipt_path text,
  add column if not exists receipt_requested_by uuid
    references public.members(id) on delete set null;

-- The photo lives under its own group's folder, which is what the storage
-- policies below check membership against. A path pointing into another
-- group's folder would show a stranger's bill to anyone who could read this row.
alter table public.expenses
  drop constraint if exists expenses_receipt_path_in_group,
  add constraint expenses_receipt_path_in_group check (
    receipt_path is null
    or (receipt_path like group_id::text || '/%' and length(receipt_path) <= 200)
  );

-- A plain grant adds to the column list 20260919120000 set up. No revoke first:
-- a revoke wipes every column-level grant on the table, and the client sends
-- all of them on every push (see the settlements trap in 20260920140000).
grant update (receipt_path, receipt_requested_by) on public.expenses to authenticated;

-- Whoever asked has to be somebody in the group.
create or replace function public.guard_receipt_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.receipt_requested_by is not null
     and not public.seat_in_group(new.receipt_requested_by, new.group_id) then
    raise exception 'whoever asks for a bill has to be in the group' using errcode = '23503';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_receipt_request on public.expenses;
create trigger guard_receipt_request
  before insert or update of receipt_requested_by on public.expenses
  for each row execute function public.guard_receipt_request();

-- ------------------------------------------------------------------ notices

-- New enum values cannot be used in the transaction that adds them (55P04),
-- which only matters for a dry run.
alter type public.notice_kind add value if not exists 'receipt_requested';
alter type public.notice_kind add value if not exists 'receipt_added';

-- ------------------------------------------------------------------ storage

-- Private: every read goes through a signed download, checked below. Bills are
-- phone photos compressed on the phone to well under a megabyte; five is room
-- for a long pharmacy receipt without inviting anything else in.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 5242880, array['image/jpeg', 'image/png'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Whether you can reach the group an object's path names. Security definer for
-- the same reason as is_member: a policy's own subquery is subject to RLS.
-- A path that does not start with a uuid is nobody's.
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
  if folder !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return public.is_member(folder::uuid) or public.is_group_creator(folder::uuid);
end;
$$;

revoke all on function public.can_reach_receipt(text) from public, anon;
grant execute on function public.can_reach_receipt(text) to authenticated;

drop policy if exists receipts_read on storage.objects;
create policy receipts_read on storage.objects
  for select to authenticated
  using (bucket_id = 'receipts' and public.can_reach_receipt(name));

-- Every upload is a new name (the client puts a fresh id in it), so there is
-- no update policy: a bill once attached cannot be swapped under the same key.
drop policy if exists receipts_insert on storage.objects;
create policy receipts_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'receipts' and public.can_reach_receipt(name));

drop policy if exists receipts_delete on storage.objects;
create policy receipts_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'receipts' and public.can_reach_receipt(name));
