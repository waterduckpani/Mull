create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role supabase_auth_admin nologin;
create schema auth; create schema storage; create schema realtime; create schema vault; create schema net; create schema cron; create schema extensions;
grant usage on schema auth, storage, realtime, public to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text, phone text, raw_user_meta_data jsonb default '{}'::jsonb,
  email_confirmed_at timestamptz, encrypted_password text, is_anonymous boolean default false,
  created_at timestamptz default now()
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant execute on function auth.uid() to anon, authenticated, service_role;
create table storage.buckets (id text primary key, name text, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text,
  owner uuid, owner_id text, created_at timestamptz default now(), metadata jsonb);
alter table storage.objects enable row level security;
grant select, insert, update, delete on storage.objects to authenticated;
create table realtime.messages (id bigserial primary key, topic text, extension text, payload jsonb);
alter table realtime.messages enable row level security;
create function realtime.topic() returns text language sql stable as $$ select current_setting('realtime.topic', true) $$;
create table realtime.sent (payload jsonb, event text, topic text, private boolean);
create function realtime.send(payload jsonb, event text, topic text, private boolean) returns void
  language sql as $$ insert into realtime.sent values (payload, event, topic, private) $$;
grant insert on realtime.sent to public;
create table vault.decrypted_secrets (name text, decrypted_secret text);
create function net.http_post(url text, body jsonb, headers jsonb, timeout_milliseconds int) returns bigint
  language sql as $$ select 1::bigint $$;
create table cron.job (jobid bigserial, jobname text, schedule text, command text);
create function cron.schedule(jobname text, schedule text, command text) returns bigint language sql as $$
  insert into cron.job (jobname, schedule, command) values ($1,$2,$3) returning jobid $$;
create function cron.unschedule(jobname text) returns boolean language sql as $$
  delete from cron.job where jobname = $1 returning true $$;
create publication supabase_realtime;
create function cron.unschedule(job_id bigint) returns boolean language sql as $$
  delete from cron.job where jobid = $1 returning true $$;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
