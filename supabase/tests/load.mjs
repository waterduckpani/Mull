import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import fs from 'fs';
const MIG = new URL('../migrations', import.meta.url).pathname;
export async function fresh({ extra = [] } = {}) {
  const db = await PGlite.create({ extensions: { pgcrypto } });
  await db.exec(fs.readFileSync(new URL('./prelude.sql', import.meta.url), 'utf8'));
  const files = fs.readdirSync(MIG).filter(f => f.endsWith('.sql') && !(process.env.SKIP && f.includes(process.env.SKIP))).sort();
  for (const f of [...files.map(f => `${MIG}/${f}`), ...extra]) {
    try { await db.exec(fs.readFileSync(f, 'utf8').replace(/create extension if not exists (pg_net|pg_cron)[^;]*;/gi, '')); }
    catch (e) { throw new Error(`${f}: ${e.message}`); }
  }
  return db;
}
if (process.argv[1].endsWith('load.mjs')) {
  const db = await fresh({ extra: process.argv.slice(2) });
  const r = await db.query(`select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where nspname='public'`);
  console.log('loaded, public functions:', r.rows[0].count);
}
