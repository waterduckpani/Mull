// The app's own traffic, shaped exactly as groups_sync.dart sends it. Every
// one of these has to keep working after the migration.
import { world, as, q, expect, done, U, G1, G2, SEAT } from './harness.mjs';
const ok = (r) => !(typeof r === 'string' && r.startsWith('ERROR'));
const refused = (r) => !ok(r);
const lit = (v) => v === null ? 'null' : typeof v === 'number' || typeof v === 'boolean' ? String(v) : `'${String(v).replace(/'/g, "''")}'`;
// PostgREST upsert: INSERT (payload cols) ... ON CONFLICT (pk) DO UPDATE SET col = EXCLUDED.col for each payload col.
function upsert(table, rows, conflict = ['id']) {
  const cols = Object.keys(rows[0]);
  const values = rows.map(r => `(${cols.map(c => lit(r[c])).join(', ')})`).join(', ');
  const set = cols.map(c => `${c} = excluded.${c}`).join(', ');
  return `insert into public.${table} (${cols.join(', ')}) values ${values} on conflict (${conflict.join(', ')}) do update set ${set};`;
}
const seat = (id, g, user, name, role = 'member', extra = {}) => ({ id, group_id: g, user_id: user, name, email: null, phone: null, upi_id: null, role, ...extra });
const expense = (id, g, payer, amount, by, extra = {}) => ({ id, group_id: g, description: 'Dinner', amount, payer_member_id: payer, method: 'exact',
  repeats_monthly: false, spent_on: '2026-09-27', created_by: by, recurring_id: null, note: null, receipt_path: null, receipt_requested_by: null, ...extra });
const settlement = (id, g, from, to, amount, by, extra = {}) => ({ id, group_id: g, from_member_id: from, to_member_id: to, amount,
  status: 'pending', utr: null, is_offset: false, claimed_at: '2026-09-27T10:00:00Z', claimed_by: by, confirmed_at: null, ...extra });
const E1 = '30000000-0000-0000-0000-0000000000e1', E2 = '30000000-0000-0000-0000-0000000000e2';
const extra = process.argv.slice(2);

// --- groups, seats, expenses: first push, re-push, edit, by creator and by a member
{ const db = await world(extra);
  await expect('creator pushes a new expense with shares', () => as(db, U.A,
    upsert('expenses', [expense(E1, G1, SEAT.A1, 600, U.A)]) +
    upsert('expense_shares', [{ expense_id: E1, member_id: SEAT.A1, amount: 300 }, { expense_id: E1, member_id: SEAT.V1, amount: 300 }], ['expense_id', 'member_id'])), ok);
  await expect('a member (not the creator) re-sends every seat, including the admin\'s', () => as(db, U.V,
    upsert('members', [seat(SEAT.A1, G1, U.A, 'A', 'admin'), seat(SEAT.V1, G1, U.V, 'V')])), ok);
  await expect('a member re-sends the group row unchanged', () => as(db, U.V,
    upsert('groups', [{ id: G1, name: 'G', created_by: U.V, kind: 'group', icon: null }])), ok);
  await expect('a member edits the expense someone else added', () => as(db, U.V,
    upsert('expenses', [expense(E1, G1, SEAT.A1, 900, U.V)]) +
    upsert('expense_shares', [{ expense_id: E1, member_id: SEAT.A1, amount: 450 }, { expense_id: E1, member_id: SEAT.V1, amount: 450 }], ['expense_id', 'member_id'])), ok);
  await expect('...and the edit landed', () => q(db, `select amount from public.expenses where id = '${E1}'`), [{ amount: 900 }]);
  await expect('the admin adds a placeholder seat with a UPI ID', () => as(db, U.A,
    upsert('members', [seat(SEAT.P1, G1, null, 'Rahul', 'member', { upi_id: 'rahul@okaxis', email: 'rahul@x.in' })])), ok);
  await expect('...and any member edits it', () => as(db, U.V,
    upsert('members', [seat(SEAT.P1, G1, null, 'Rahul K', 'member', { upi_id: 'rahulk@okaxis', email: 'rahul@x.in' })])), ok);
  await expect('the admin renames the group', () => as(db, U.A, `update public.groups set name = 'Flat' where id = '${G1}'`), ok);
  await expect('a member deletes an expense (tombstone)', () => as(db, U.V, `update public.expenses set deleted_at = now() where id in ('${E1}')`), ok);
  await expect('an expense with a 150-character description still saves', () => as(db, U.A,
    upsert('expenses', [expense(E2, G1, SEAT.A1, 100, U.A, { description: 'x'.repeat(150) })])), ok);
  await expect('the admin removes a seat with no history', () => as(db, U.A, `delete from public.members where id in ('${SEAT.P1}')`), ok);
  await expect('the admin deletes the group', () => as(db, U.A, `update public.groups set deleted_at = now() where id = '${G2}'`), ok);
}

// --- a new group from scratch, pushed in the app's order
{ const db = await world(extra);
  const G = '10000000-0000-0000-0000-0000000000aa', S1 = '20000000-0000-0000-0000-0000000000aa', S2 = '20000000-0000-0000-0000-0000000000ab';
  await expect('a brand new group, its seats (one a friend), and a schedule', () => as(db, U.A,
    upsert('groups', [{ id: G, name: 'Trip', created_by: U.A, kind: 'group', icon: null, deleted_at: null }]) +
    upsert('members', [seat(S1, G, U.A, 'A', 'admin'), seat(S2, G, U.V, 'V')]) +
    upsert('recurring_expenses', [{ id: '50000000-0000-0000-0000-000000000001', group_id: G, description: 'Rent', amount: 1000, payer_member_id: S1, method: 'equal',
      frequency: 'monthly', next_due: '2026-10-01', ends_on: null, paused: false, auto_add: false, last_added_on: null, anchor_day: 31, created_by: U.A, deleted_at: null }]) +
    upsert('recurring_shares', [{ recurring_id: '50000000-0000-0000-0000-000000000001', member_id: S1, amount: 500 }, { recurring_id: '50000000-0000-0000-0000-000000000001', member_id: S2, amount: 500 }], ['recurring_id', 'member_id'])), ok);
  await expect('a direct ledger is created as direct', () => as(db, U.A,
    upsert('groups', [{ id: '10000000-0000-0000-0000-0000000000dd', name: 'V', created_by: U.A, kind: 'direct', icon: null, deleted_at: null }])), ok);
}

// --- paying and confirming
{ const db = await world(extra);
  const S = '40000000-0000-0000-0000-0000000000s1'.replace('s', 'a');
  await expect('the payer claims a payment', () => as(db, U.V, upsert('settlements', [settlement(S, G1, SEAT.V1, SEAT.A1, 300, U.V)])), ok);
  await expect('the payee confirms it (re-sending the whole row)', () => as(db, U.A,
    upsert('settlements', [settlement(S, G1, SEAT.V1, SEAT.A1, 300, U.A, { status: 'confirmed', confirmed_at: '2026-09-27T11:00:00Z' })])), ok);
  await expect('...and it is confirmed', () => q(db, `select status from public.settlements where id = '${S}'`), [{ status: 'confirmed' }]);
  await expect('the payee can still say it never arrived', () => as(db, U.A,
    upsert('settlements', [settlement(S, G1, SEAT.V1, SEAT.A1, 300, U.A, { status: 'disputed', confirmed_at: null })])), ok);
  await expect('...and it is disputed', () => q(db, `select status from public.settlements where id = '${S}'`), [{ status: 'disputed' }]);
  await expect('a disputed payment can be removed by the payee', () => as(db, U.A, `update public.settlements set deleted_at = now() where id in ('${S}')`), ok);
  const S2 = '40000000-0000-0000-0000-0000000000a2';
  await as(db, U.V, upsert('settlements', [settlement(S2, G1, SEAT.V1, SEAT.A1, 100, U.V)]));
  await expect('the payer withdraws a pending claim', () => as(db, U.V, `update public.settlements set deleted_at = now() where id in ('${S2}')`), ok);
  await expect('...and undoes that', () => as(db, U.V, upsert('settlements', [settlement(S2, G1, SEAT.V1, SEAT.A1, 100, U.V, { deleted_at: null })])), ok);
  await expect('a stale re-send by the payer of a confirmed row does not break the push', async () => {
    await as(db, U.A, `update public.settlements set status = 'confirmed', confirmed_at = now() where id = '${S2}'`);
    await as(db, U.V, upsert('settlements', [settlement(S2, G1, SEAT.V1, SEAT.A1, 100, U.V)]));
    return (await q(db, `select status from public.settlements where id = '${S2}'`))[0].status; }, 'confirmed');
  await expect('recording money you received from a placeholder is confirmed at once', async () => {
    await as(db, U.A, upsert('members', [seat(SEAT.P1, G1, null, 'Rahul')]) +
      upsert('settlements', [settlement('40000000-0000-0000-0000-0000000000a3', G1, SEAT.P1, SEAT.A1, 50, U.A, { status: 'confirmed', confirmed_at: '2026-09-27T11:00:00Z' })]));
    return (await q(db, `select status from public.settlements where id = '40000000-0000-0000-0000-0000000000a3'`))[0]?.status; }, 'confirmed');
  await expect('...and can take it back again, as nobody else could', () => as(db, U.A,
    `update public.settlements set deleted_at = now() where id in ('40000000-0000-0000-0000-0000000000a3')`), ok);
}

// --- net-off, the new way
{ const db = await world(extra);
  const O1 = '40000000-0000-0000-0000-0000000000f1', O2 = '40000000-0000-0000-0000-0000000000f2';
  const offs = JSON.stringify([
    { id: O1, group_id: G1, from_member_id: SEAT.V1, to_member_id: SEAT.A1, amount: 500, claimed_at: '2026-09-27T10:00:00Z' },
    { id: O2, group_id: G2, from_member_id: SEAT.A2, to_member_id: SEAT.V2, amount: 500, claimed_at: '2026-09-27T10:00:00Z' }]);
  await expect('a balanced net-off goes through record_offsets', () => as(db, U.A, `select public.record_offsets('${offs}'::jsonb)`), ok);
  await expect('...both halves are confirmed offsets', () => q(db, `select count(*)::int n from public.settlements where is_offset and status = 'confirmed'`), [{ n: 2 }]);
  await expect('sending the same pair again is harmless', () => as(db, U.A, `select public.record_offsets('${offs}'::jsonb)`), ok);
  await expect('...and writes nothing new', () => q(db, `select count(*)::int n from public.settlements`), [{ n: 2 }]);
  await expect('the group push then re-sends both rows without trouble', () => as(db, U.A,
    upsert('settlements', [settlement(O1, G1, SEAT.V1, SEAT.A1, 500, U.A, { status: 'confirmed', is_offset: true, confirmed_at: '2026-09-27T10:00:00Z' })]) +
    upsert('settlements', [settlement(O2, G2, SEAT.A2, SEAT.V2, 500, U.A, { status: 'confirmed', is_offset: true, confirmed_at: '2026-09-27T10:00:00Z' })])), ok);
  await expect('...and they are still confirmed offsets', () => q(db, `select count(*)::int n from public.settlements where is_offset and status = 'confirmed' and deleted_at is null`), [{ n: 2 }]);
  await expect('the other person cannot dispute half of it', async () => {
    await as(db, U.V, `update public.settlements set status = 'disputed', confirmed_at = null where id = '${O2}'`).catch(() => {});
    return (await q(db, `select status from public.settlements where id = '${O2}'`))[0].status; }, 'confirmed');
  await expect('an unbalanced set is refused', () => as(db, U.A, `select public.record_offsets('${JSON.stringify([
    { id: '40000000-0000-0000-0000-0000000000f3', group_id: G2, from_member_id: SEAT.A2, to_member_id: SEAT.V2, amount: 800 }])}'::jsonb)`), refused);
  await expect('someone outside the pair cannot write it', () => as(db, U.F, `select public.record_offsets('${JSON.stringify([
    { id: '40000000-0000-0000-0000-0000000000f4', group_id: G1, from_member_id: SEAT.V1, to_member_id: SEAT.A1, amount: 1 },
    { id: '40000000-0000-0000-0000-0000000000f5', group_id: G2, from_member_id: SEAT.A2, to_member_id: SEAT.V2, amount: 1 }])}'::jsonb)`), refused);
  await expect('an offset against a placeholder still goes straight in', async () => {
    await as(db, U.A, upsert('members', [seat(SEAT.P1, G1, null, 'Rahul')]) +
      upsert('settlements', [settlement('40000000-0000-0000-0000-0000000000f6', G1, SEAT.A1, SEAT.P1, 40, U.A, { status: 'confirmed', is_offset: true, confirmed_at: '2026-09-27T10:00:00Z' })]));
    return (await q(db, `select status, is_offset from public.settlements where id = '40000000-0000-0000-0000-0000000000f6'`))[0]; }, { status: 'confirmed', is_offset: true });
  await expect('the payer side of an offset can take it back', () => as(db, U.A, `update public.settlements set deleted_at = now() where id in ('${O2}')`), ok);
}

// --- leaving, with and without history; deleting an account
{ const db = await world(extra);
  await db.exec(`update public.profiles set upi_id = 'victim@okbank' where id = '${U.V}'`);
  await as(db, U.A, upsert('expenses', [expense(E1, G1, SEAT.A1, 200, U.A)]) + upsert('expense_shares', [{ expense_id: E1, member_id: SEAT.V1, amount: 200 }], ['expense_id', 'member_id']));
  await expect('leaving a group with history detaches the seat', () => as(db, U.V, `select public.leave_group('${G1}')`), ok);
  await expect('...keeping the leaver\'s UPI ID', () => q(db, `select user_id, upi_id, left_by from public.members where id = '${SEAT.V1}'`), [{ user_id: null, upi_id: 'victim@okbank', left_by: U.V }]);
  await expect('the others re-send that seat as they pulled it', () => as(db, U.A, upsert('members', [seat(SEAT.V1, G1, null, 'V', 'member', { upi_id: 'victim@okbank' })])), ok);
  await expect('...and left_by survives the re-send', () => q(db, `select left_by from public.members where id = '${SEAT.V1}'`), [{ left_by: U.V }]);
  await expect('leaving a group with no history deletes the seat', () => as(db, U.V, `select public.leave_group('${G2}')`), ok);
  await expect('deleting the account clears their UPI ID from the seat they left', async () => {
    await as(db, U.V, `select public.delete_my_account()`);
    return q(db, `select upi_id, left_by from public.members where id = '${SEAT.V1}'`); }, [{ upi_id: null, left_by: null }]);
}

// --- friends
{ const db = await world(extra);
  const N = '00000000-0000-0000-0000-0000000000ee';
  await db.exec(`insert into auth.users (id, email, email_confirmed_at) values ('${N}', 'new@x.in', now()); update public.profiles set name = 'New Person' where id = '${N}'`);
  await expect('send a friend request to an account', () => as(db, U.A, `select public.send_friend_request('new@x.in')`), ok);
  const fid = (await q(db, `select id from public.friendships where addressee_id = '${N}'`))[0].id;
  await expect('the addressee sees who asked', async () => {
    await db.exec(`begin; set local role authenticated; select set_config('request.jwt.claim.sub', '${N}', true);`);
    try { return (await db.query(`select other_name from public.friend_list()`)).rows; } finally { await db.exec('rollback'); } }, [{ other_name: 'Attacker' }]);
  await expect('the addressee accepts', () => as(db, N, `select public.accept_friend_request('${fid}')`), ok);
  await expect('...and now the requester sees their name', async () => {
    await db.exec(`begin; set local role authenticated; select set_config('request.jwt.claim.sub', '${U.A}', true);`);
    try { return (await db.query(`select other_name from public.friend_list() where other_email = 'new@x.in'`)).rows; } finally { await db.exec('rollback'); } }, [{ other_name: 'New Person' }]);
  await expect('unfriending by id still works', () => as(db, U.A, `delete from public.friendships where id = '${fid}'`), ok);
  await expect('...and the row is gone', () => q(db, `select count(*)::int n from public.friendships where id = '${fid}'`), [{ n: 0 }]);
  await expect('an invite to an address with no account', () => as(db, U.A, `select public.send_friend_request('later@x.in')`), ok);
  await expect('signing up later claims the invite and the seat', async () => {
    await as(db, U.A, upsert('members', [seat(SEAT.P1, G1, null, 'Later', 'member', { email: 'later@x.in' })]));
    const L = '00000000-0000-0000-0000-0000000000ff';
    await db.exec(`insert into auth.users (id, email, email_confirmed_at) values ('${L}', 'later@x.in', now())`);
    await as(db, L, `select public.claim_invitations()`);
    const inv = (await q(db, `select id from public.friendships where addressee_id = '${L}'`))[0].id;
    await as(db, L, `select public.accept_friend_request('${inv}'); select public.claim_invitations();`);
    return (await q(db, `select user_id from public.members where id = '${SEAT.P1}'`))[0].user_id; }, '00000000-0000-0000-0000-0000000000ff');
  await expect('declining an invite sent to your address', async () => {
    await as(db, U.V, `select public.send_friend_request('someone@x.in')`);
    const S = '00000000-0000-0000-0000-0000000000a9';
    await db.exec(`insert into auth.users (id, email, email_confirmed_at) values ('${S}', 'someone@x.in', now())`);
    const inv = (await q(db, `select id from public.friendships where addressee_email = 'someone@x.in'`))[0].id;
    await as(db, S, `delete from public.friendships where id = '${inv}'`);
    return q(db, `select count(*)::int n from public.friendships where id = '${inv}'`); }, [{ n: 0 }]);
}

// --- sign-in, receipts, reminders
{ const db = await world(extra);
  await expect('a normal sign-up confirms and gets a profile', async () => {
    await db.exec(`insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000123', 'otp@x.in');
      update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-000000000123'`);
    return q(db, `select email from public.profiles where id = '00000000-0000-0000-0000-000000000123'`); }, [{ email: 'otp@x.in' }]);
  await expect('the review account keeps its password when confirmed', async () => {
    await db.exec(`insert into auth.users (id, email, encrypted_password) values ('00000000-0000-0000-0000-000000000124', 'review@mull.oblunestudio.com', 'review-hash');
      update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-000000000124'`);
    return q(db, `select encrypted_password from auth.users where id = '00000000-0000-0000-0000-000000000124'`); }, [{ encrypted_password: 'review-hash' }]);
  await expect('a member uploads a bill to their group', () => as(db, U.A,
    `insert into storage.objects (bucket_id, name, owner_id) values ('receipts', '${G1}/${E1}/40000000-0000-0000-0000-000000000001.jpg', '${U.A}')`), ok);
  await expect('...but not into a group they are not in', () => as(db, U.F,
    `insert into storage.objects (bucket_id, name, owner_id) values ('receipts', '${G1}/${E1}/40000000-0000-0000-0000-000000000002.jpg', '${U.F}')`), refused);
  await expect('the sixty-first bill in a day is refused', async () => {
    for (let i = 0; i < 59; i++) await as(db, U.A, `insert into storage.objects (bucket_id, name, owner_id) values ('receipts', '${G1}/${E1}/40000000-0000-0000-0000-${String(i).padStart(12, '0')}.jpg', '${U.A}')`);
    return as(db, U.A, `insert into storage.objects (bucket_id, name, owner_id) values ('receipts', '${G1}/${E1}/40000000-0000-0000-0000-00000000ffff.jpg', '${U.A}')`); }, refused);
  await expect('a reminder still sends', () => as(db, U.A, `select public.send_reminder('${U.V}', '${G1}', 'Pay up', '', 100)`), ok);
  await expect('a notice to the group still sends', () => as(db, U.A, `select public.notify('${G1}', array['${U.V}']::uuid[], 'expense_added', 'A added Dinner', '₹500', 500)`), ok);
}
done();
