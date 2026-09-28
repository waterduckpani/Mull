// Each attack says what a *secure* server does. Run before the fix: the
// failures are the holes. Run after: everything passes.
import { world, as, q, expect, done, U, G1, G2, SEAT } from './harness.mjs';
const extra = process.argv.slice(2);
const refused = (r) => typeof r === 'string' && r.startsWith('ERROR');
const fresh = () => world(extra);

// 1. Moving someone's seat into a group of your choosing.
{ const db = await fresh();
  const G3 = '10000000-0000-0000-0000-000000000003';
  await as(db, U.A, `insert into public.groups (id, name, created_by) values ('${G3}', 'Trap', '${U.A}');
    insert into public.members (id, group_id, user_id, name, role) values ('20000000-0000-0000-0000-0000000000a3', '${G3}', '${U.A}', 'A', 'admin');`);
  await expect('a member cannot move someone else\'s seat to another group', () =>
    as(db, U.A, `update public.members set group_id = '${G3}' where id = '${SEAT.V1}'`), refused);
  await expect('...and the seat is still where it was', () => q(db, `select group_id from public.members where id = '${SEAT.V1}'`), [{ group_id: G1 }]);
}

// 2. Writing a one-sided "net-off" to wipe your own debt.
{ const db = await fresh();
  await as(db, U.V, `insert into public.expenses (id, group_id, description, amount, payer_member_id, method, spent_on, repeats_monthly, created_by)
      values ('30000000-0000-0000-0000-000000000001', '${G1}', 'Dinner', 500, '${SEAT.V1}', 'exact', current_date, false, '${U.V}');
    insert into public.expense_shares (expense_id, member_id, amount) values ('30000000-0000-0000-0000-000000000001', '${SEAT.A1}', 500);`);
  await as(db, U.A, `insert into public.settlements (id, group_id, from_member_id, to_member_id, amount, status, is_offset, claimed_by, confirmed_at)
      values ('40000000-0000-0000-0000-000000000001', '${G1}', '${SEAT.A1}', '${SEAT.V1}', 500, 'confirmed', true, '${U.A}', now())`).catch(() => {});
  await expect('a lone offset written straight to the table does not clear a debt', () =>
    q(db, `select count(*)::int n from public.settlements where status = 'confirmed' and deleted_at is null`), [{ n: 0 }]);
}

// 3. The payee taking back a payment they confirmed, or disputing an offset.
{ const db = await fresh();
  await as(db, U.V, `insert into public.settlements (id, group_id, from_member_id, to_member_id, amount, status, claimed_by)
      values ('40000000-0000-0000-0000-000000000002', '${G1}', '${SEAT.V1}', '${SEAT.A1}', 900, 'pending', '${U.V}')`);
  await as(db, U.A, `update public.settlements set status = 'confirmed', confirmed_at = now() where id = '40000000-0000-0000-0000-000000000002'`);
  await expect('the payee cannot quietly delete a payment they confirmed', () =>
    as(db, U.A, `update public.settlements set deleted_at = now() where id = '40000000-0000-0000-0000-000000000002'`), refused);
  await expect('the payer can still take their own payment off the record', () =>
    as(db, U.V, `update public.settlements set deleted_at = now() where id = '40000000-0000-0000-0000-000000000002'`), (r) => !refused(r));
}

// 4. Turning a group into a "direct" ledger so nobody can leave it.
{ const db = await fresh();
  await expect('a group\'s kind cannot be changed after it is made', () =>
    as(db, U.V, `update public.groups set kind = 'direct' where id = '${G1}'`), refused);
}

// 5. Finding out who owns an email address, and their name.
{ const db = await fresh();
  const T = '00000000-0000-0000-0000-0000000000cc';
  await db.exec(`insert into auth.users (id, email, email_confirmed_at) values ('${T}', 'stranger@x.in', now());
    update public.profiles set name = 'Secret Stranger' where id = '${T}'`);
  await as(db, U.A, `select public.send_friend_request('stranger@x.in')`);
  const leaked = async () => {
    await db.exec(`begin; set local role authenticated; select set_config('request.jwt.claim.sub', '${U.A}', true);`);
    try { return (await db.query(`select other_id, other_name from public.friend_list() where other_email = 'stranger@x.in' or addressee_email = 'stranger@x.in'`)).rows; }
    finally { await db.exec('rollback'); } };
  await expect('a pending request does not reveal the account or its name', leaked,
    (rows) => Array.isArray(rows) && rows.length === 1 && rows[0].other_id === null && rows[0].other_name === null);
  await expect('the friendships table cannot be read around friend_list()', () =>
    as(db, U.A, `select addressee_id from public.friendships`), refused);
  await expect('friend requests cannot be inserted around send_friend_request()', () =>
    as(db, U.A, `insert into public.friendships (requester_id, addressee_email, status) values ('${U.A}', 'nobody@x.in', 'pending')`), refused);
}

// 6. Rewriting the UPI ID of someone who left, so their money comes to you.
{ const db = await fresh();
  await db.exec(`update public.profiles set upi_id = 'victim@okbank' where id = '${U.V}'`);
  await as(db, U.V, `insert into public.expenses (id, group_id, description, amount, payer_member_id, method, spent_on, repeats_monthly, created_by)
      values ('30000000-0000-0000-0000-000000000009', '${G1}', 'Cab', 300, '${SEAT.V1}', 'exact', current_date, false, '${U.V}');
    insert into public.expense_shares (expense_id, member_id, amount) values ('30000000-0000-0000-0000-000000000009', '${SEAT.A1}', 300);
    select public.leave_group('${G1}');`);
  await as(db, U.A, `update public.members set upi_id = 'attacker@okbank' where id = '${SEAT.V1}'`).catch(() => {});
  await expect('a leaver\'s UPI ID stays the one from their account', () =>
    q(db, `select upi_id from public.members where id = '${SEAT.V1}'`), [{ upi_id: 'victim@okbank' }]);
}

// 7. Filling the database with one enormous row.
{ const db = await fresh();
  await expect('an expense description cannot be a megabyte', () =>
    as(db, U.A, `insert into public.expenses (id, group_id, description, amount, payer_member_id, method, spent_on, repeats_monthly, created_by)
      values ('30000000-0000-0000-0000-000000000002', '${G1}', repeat('x', 1000000), 5, '${SEAT.A1}', 'exact', current_date, false, '${U.A}')`), refused);
  await expect('a group name cannot be a megabyte', () =>
    as(db, U.A, `update public.groups set name = repeat('x', 1000000) where id = '${G1}'`), refused);
  await expect('a profile name cannot be a megabyte', () =>
    as(db, U.A, `update public.profiles set name = repeat('x', 1000000) where id = '${U.A}'`), refused);
}

// 8. Pre-registering a password on someone else's email before they sign up.
{ const db = await fresh();
  const W = '00000000-0000-0000-0000-0000000000dd';
  await db.exec(`insert into auth.users (id, email, encrypted_password) values ('${W}', 'future@x.in', 'attackers-hash')`);
  await db.exec(`update auth.users set email_confirmed_at = now() where id = '${W}'`);
  await expect('confirming an email wipes any password set before it was confirmed', () =>
    q(db, `select encrypted_password = 'attackers-hash' as kept from auth.users where id = '${W}'`), [{ kept: false }]);
}
// 9. A bill path that climbs out of the phone's receipts folder.
{ const db = await fresh();
  const E = '30000000-0000-0000-0000-00000000000e';
  await as(db, U.A, `insert into public.expenses (id, group_id, description, amount, payer_member_id, method, spent_on, repeats_monthly, created_by)
      values ('${E}', '${G1}', 'Bill', 5, '${SEAT.A1}', 'exact', current_date, false, '${U.A}')`);
  await expect('a receipt path cannot contain ../', () =>
    as(db, U.A, `update public.expenses set receipt_path = '${G1}/../../mull.json' where id = '${E}'`), refused);
  await expect('a well-formed receipt path is fine', () =>
    as(db, U.A, `update public.expenses set receipt_path = '${G1}/${E}/40000000-0000-0000-0000-000000000abc.jpg' where id = '${E}'`), (r) => !refused(r));
}
// 10. A member who is not an admin adding people to the group.
{ const db = await fresh();
  await as(db, U.V, `insert into public.members (id, group_id, user_id, name, role) values ('20000000-0000-0000-0000-0000000000d1', '${G1}', null, 'Stranger', 'member')`).catch(() => {});
  await expect('only an admin can add a seat', () =>
    q(db, `select count(*)::int n from public.members where id = '20000000-0000-0000-0000-0000000000d1'`), [{ n: 0 }]);
  await expect('...while an admin still can', async () => {
    await as(db, U.A, `insert into public.members (id, group_id, user_id, name, role) values ('20000000-0000-0000-0000-0000000000d2', '${G1}', null, 'Rahul', 'member')`);
    return q(db, `select count(*)::int n from public.members where id = '20000000-0000-0000-0000-0000000000d2'`); }, [{ n: 1 }]);
}
done();
