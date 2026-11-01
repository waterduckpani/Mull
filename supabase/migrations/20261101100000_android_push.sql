-- Push on Android.
--
-- Android phones register a Firebase Cloud Messaging token through the same
-- register_push_token(), with 'fcm' where iPhones say which APNs host they
-- use. The `push` edge function sends 'fcm' rows through Firebase and the
-- rest through APNs. The signature is unchanged, so builds already on
-- people's iPhones keep working.

alter table public.push_tokens drop constraint if exists push_tokens_environment_check;
alter table public.push_tokens
  add constraint push_tokens_environment_check check (environment in ('sandbox', 'production', 'fcm'));

create or replace function public.register_push_token(device_token text, apns_env text default 'production')
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  if apns_env not in ('sandbox', 'production', 'fcm') then
    raise exception 'unknown APNs environment' using errcode = '22023';
  end if;
  -- APNs tokens are hex. FCM tokens are longer and URL-safe base64 with a
  -- colon after the instance id.
  if device_token is null
     or (apns_env <> 'fcm' and (length(device_token) not between 32 and 200 or device_token !~ '^[0-9a-f]+$'))
     or (apns_env = 'fcm' and (length(device_token) not between 32 and 1024 or device_token !~ '^[A-Za-z0-9_:-]+$')) then
    raise exception 'not a device token' using errcode = '22023';
  end if;

  insert into public.push_tokens as p (token, user_id, environment, updated_at)
  values (device_token, auth.uid(), apns_env, now())
  on conflict (token) do update
     set user_id = excluded.user_id, environment = excluded.environment, updated_at = now();

  -- Ten devices is generous; past it the oldest go.
  delete from public.push_tokens p
   where p.user_id = auth.uid()
     and p.token in (
       select t.token from public.push_tokens t
        where t.user_id = auth.uid()
        order by t.updated_at desc
       offset 10
     );
end;
$$;

revoke all on function public.register_push_token(text, text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;
