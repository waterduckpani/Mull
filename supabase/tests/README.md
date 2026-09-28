# Migration tests

Every migration in `../migrations`, replayed into PGlite (Postgres compiled to
WebAssembly) with small stand-ins for Supabase's own schemas (`prelude.sql`),
then attacked and exercised the way the app does it. No Docker, no live data.

    npm install
    npm test                         # attacks.mjs, then flows.mjs
    SKIP=fortress node attacks.mjs   # leave a migration out, to see the holes it closes

- `attacks.mjs` — what a modified client with a real session could try. Each
  line states what a secure server does.
- `flows.mjs` — the app's own traffic, shaped like `groups_sync.dart` sends it
  (PostgREST upserts are `insert … on conflict do update set <sent columns>`).
  A new guard is not done until this still passes.
