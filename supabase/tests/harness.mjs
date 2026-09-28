import { fresh } from './load.mjs';
export const U = {
  A: '00000000-0000-0000-0000-00000000000a', // attacker
  V: '00000000-0000-0000-0000-00000000000b', // victim
  F: '00000000-0000-0000-0000-00000000000f', // a friend of both
};
export const G1 = '10000000-0000-0000-0000-000000000001', G2 = '10000000-0000-0000-0000-000000000002';
export const SEAT = { A1: '20000000-0000-0000-0000-0000000000a1', V1: '20000000-0000-0000-0000-0000000000b1',
  A2: '20000000-0000-0000-0000-0000000000a2', V2: '20000000-0000-0000-0000-0000000000b2', P1: '20000000-0000-0000-0000-0000000000c1' };
export async function world(extra = []) {
  const db = await fresh({ extra });
  await db.exec(`
    insert into auth.users (id, email, email_confirmed_at) values
      ('${U.A}', 'a@x.in', now()), ('${U.V}', 'v@x.in', now()), ('${U.F}', 'f@x.in', now());
    update public.profiles set name = case id when '${U.A}' then 'Attacker' when '${U.V}' then 'Victim Real Name' else 'Friend' end;
    insert into public.friendships (requester_id, addressee_id, status) values
      ('${U.A}', '${U.V}', 'accepted'), ('${U.F}', '${U.V}', 'accepted'), ('${U.A}', '${U.F}', 'accepted');
  `);
  // Two groups both A and V are in, made the way the app makes them.
  for (const [g, a, v] of [[G1, SEAT.A1, SEAT.V1], [G2, SEAT.A2, SEAT.V2]]) {
    await as(db, U.A, `
      insert into public.groups (id, name, created_by) values ('${g}', 'G', '${U.A}');
      insert into public.members (id, group_id, user_id, name, role) values ('${a}', '${g}', '${U.A}', 'A', 'admin');
      insert into public.members (id, group_id, user_id, name, role) values ('${v}', '${g}', '${U.V}', 'V', 'member');`);
  }
  return db;
}
export async function as(db, user, sql) {
  await db.exec(`begin; set local role authenticated; select set_config('request.jwt.claim.sub', '${user}', true);`);
  try { const r = await db.exec(sql); await db.exec('commit'); return r; }
  catch (e) { await db.exec('rollback'); throw e; }
}
export async function q(db, sql) { return (await db.query(sql)).rows; }
let failures = 0;
export async function expect(name, fn, want) {
  let got;
  try { got = await fn(); } catch (e) { got = 'ERROR: ' + e.message.split('\n')[0]; }
  const ok = typeof want === 'function' ? want(got) : JSON.stringify(got) === JSON.stringify(want);
  if (!ok) failures++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : ' -> ' + JSON.stringify(got)}`);
}
export function done() { console.log(failures ? `\n${failures} FAILED` : '\nall passed'); process.exitCode = failures ? 1 : 0; }
