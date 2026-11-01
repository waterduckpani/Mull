// Sends one notice to its recipient's phones: iPhones through APNs, Android
// phones through Firebase Cloud Messaging.
//
// Called by the database, not by the app: the `push_notice` trigger on
// public.notices posts `{ notice_id }` here through pg_net after the insert
// commits, with a shared secret in `x-mull-push-secret`. JWT verification is
// off for this function (supabase/config.toml) because the caller is
// Postgres, and the secret is what stands in for it.
//
// What the push says is built here from rows only the server can vouch for.
// The notice's own text is written by the sender's app, so it is only ever
// the body: the bold line on the lock screen is the group's name, or the
// sender's account name for a one-to-one ledger. A modified client can put
// what it likes in a notice, but it cannot make it look like it came from
// anyone else.
//
// Secrets (supabase secrets set ...):
//   APNS_KEY_ID          the key's id, from developer.apple.com → Keys
//   APNS_TEAM_ID         B3F76H2UHH
//   APNS_PRIVATE_KEY     the .p8 file's contents, BEGIN/END lines included
//   APNS_TOPIC           in.mull.app
//   FCM_SERVICE_ACCOUNT  the Firebase service account's JSON key, whole
//   PUSH_WEBHOOK_SECRET  the same value as the `push_webhook_secret` Vault entry
//
// tool/push-setup.sh sets all of these. Either platform can be missing; its
// phones are skipped until its key is there.

import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
} as const;

// APNs wants a fresh token at most every 20 minutes and refuses one older
// than an hour. A warm function instance reuses it for 40.
let cached: { jwt: string; at: number } | null = null;

async function apnsToken(): Promise<string> {
  if (cached && Date.now() - cached.at < 40 * 60 * 1000) return cached.jwt;
  const key = await importPKCS8(Deno.env.get("APNS_PRIVATE_KEY")!.trim(), "ES256");
  const jwt = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID")! })
    .setIssuer(Deno.env.get("APNS_TEAM_ID")!)
    .setIssuedAt()
    .sign(key);
  cached = { jwt, at: Date.now() };
  return jwt;
}

// Firebase takes an OAuth token, which the service account signs for itself.
// It lasts an hour; a warm instance reuses it for 50 minutes.
let fcmCached: { token: string; project: string; at: number } | null = null;

async function fcmAuth(): Promise<{ token: string; project: string }> {
  if (fcmCached && Date.now() - fcmCached.at < 50 * 60 * 1000) return fcmCached;
  const account = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
  const key = await importPKCS8(account.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`fcm oauth ${res.status} ${await res.text()}`);
  fcmCached = { token: (await res.json()).access_token, project: account.project_id, at: Date.now() };
  return fcmCached;
}

function clip(text: string, max: number): string {
  return text.length <= max ? text : text.slice(0, max - 1) + "…";
}

// Compared in constant time. `!==` stops at the first differing character,
// and how long it took says how much of a guess was right.
function sameSecret(given: string | null, expected: string | undefined): boolean {
  if (!given || !expected) return false;
  const a = new TextEncoder().encode(given);
  const b = new TextEncoder().encode(expected);
  let diff = a.length ^ b.length;
  for (let i = 0; i < b.length; i++) diff |= (a[i % (a.length || 1)] ?? 0) ^ b[i];
  return diff === 0;
}

// One notice to all of its recipient's phones.
async function sendNotice(notice_id: string): Promise<{ sent: number; removed: number; skipped?: string }> {
  const { data: notice } = await db
    .from("notices")
    .select("id, recipient_id, actor_id, kind, group_id, title, body")
    .eq("id", notice_id)
    .maybeSingle();
  if (!notice) return { sent: 0, removed: 0, skipped: "no such notice" };

  const [{ data: tokens }, { data: group }, { data: actor }, { count: unread }] = await Promise.all([
    db.from("push_tokens").select("token, environment").eq("user_id", notice.recipient_id),
    notice.group_id
      ? db.from("groups").select("name, kind").eq("id", notice.group_id).maybeSingle()
      : Promise.resolve({ data: null }),
    notice.actor_id
      ? db.from("profiles").select("name").eq("id", notice.actor_id).maybeSingle()
      : Promise.resolve({ data: null }),
    db.from("notices").select("id", { count: "exact", head: true })
      .eq("recipient_id", notice.recipient_id).is("read_at", null),
  ]);
  if (!tokens?.length) return { sent: 0, removed: 0 };

  const actorName = (actor?.name ?? "").trim();
  const heading = group && group.kind !== "direct" && group.name?.trim()
    ? group.name.trim()
    : actorName || "Mull";
  const text = [notice.title, notice.body].filter((s: string) => s && s.trim()).join(" · ");

  const title = clip(heading, 60);
  const body = clip(text, 180);
  // What a tap hands back to the app, the same keys on both platforms.
  const data: Record<string, string> = { notice_id: notice.id, kind: notice.kind };
  if (notice.group_id) data.group_id = notice.group_id;

  const apple = tokens.filter((t) => t.environment !== "fcm");
  const android = tokens.filter((t) => t.environment === "fcm");
  const dead: string[] = [];
  let sent = 0;

  if (apple.length && Deno.env.get("APNS_PRIVATE_KEY")) {
    const payload = JSON.stringify({
      aps: {
        alert: { title, body },
        badge: unread ?? undefined,
        sound: "default",
        // Stacks one group's notifications together in Notification Centre.
        "thread-id": notice.group_id ?? notice.actor_id ?? "mull",
      },
      ...data,
    });
    const jwt = await apnsToken();
    const topic = Deno.env.get("APNS_TOPIC") ?? "in.mull.app";

    await Promise.all(apple.map(async ({ token, environment }) => {
      const host = HOSTS[environment as keyof typeof HOSTS] ?? HOSTS.production;
      const res = await fetch(`${host}/3/device/${token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
          // A day. A notice older than that is in the inbox, and a buzz for it
          // would only be confusing.
          "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400),
        },
        body: payload,
      });
      if (res.ok) {
        sent++;
        return;
      }
      const reason = (await res.json().catch(() => ({}))).reason ?? res.status;
      // Gone for good: uninstalled, or a token for the other environment. The
      // app registers again on its next launch if it is still there.
      if (res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered" ||
          reason === "DeviceTokenNotForTopic") {
        dead.push(token);
      } else {
        console.error(`apns ${res.status} ${reason}`);
      }
    }));
  }

  if (android.length && Deno.env.get("FCM_SERVICE_ACCOUNT")) {
    const auth = await fcmAuth();
    await Promise.all(android.map(async ({ token }) => {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${auth.project}/messages:send`, {
        method: "POST",
        headers: { authorization: `Bearer ${auth.token}`, "content-type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data,
            android: {
              priority: "high",
              // A day, as for APNs.
              ttl: "86400s",
              notification: {
                // The channel MainActivity makes, so Settings can turn it off.
                channel_id: "notices",
                notification_count: unread ?? undefined,
              },
            },
          },
        }),
      });
      if (res.ok) {
        sent++;
        return;
      }
      const error = (await res.json().catch(() => ({}))).error ?? {};
      const code = (error.details ?? []).find((d: { errorCode?: string }) => d.errorCode)?.errorCode;
      // Uninstalled, or the app's data was cleared. A fresh token comes with
      // the next launch.
      if (res.status === 404 || code === "UNREGISTERED") {
        dead.push(token);
      } else {
        console.error(`fcm ${res.status} ${code ?? error.status ?? ""} ${error.message ?? ""}`);
      }
    }));
  }

  if (dead.length) await db.from("push_tokens").delete().in("token", dead);
  return { sent, removed: dead.length };
}

Deno.serve(async (req) => {
  if (!sameSecret(req.headers.get("x-mull-push-secret"), Deno.env.get("PUSH_WEBHOOK_SECRET"))) {
    return new Response("forbidden", { status: 403 });
  }
  if (!Deno.env.get("APNS_PRIVATE_KEY") && !Deno.env.get("FCM_SERVICE_ACCOUNT")) {
    // Deployed before either key exists. Nothing to do, and not an error.
    return Response.json({ skipped: "no APNs or FCM key configured" });
  }

  // `notice_ids` is every notice one insert wrote — one call for a whole
  // group's worth, where each notice used to be a call of its own.
  // `notice_id` is the single form the trigger sent before.
  const request = (await req.json().catch(() => null)) ?? {};
  const ids: unknown[] = Array.isArray(request.notice_ids) ? request.notice_ids : [request.notice_id];
  if (!ids.length || !ids.every((id) => typeof id === "string")) {
    return new Response("bad request", { status: 400 });
  }

  let sent = 0;
  let removed = 0;
  for (const id of ids.slice(0, 100) as string[]) {
    try {
      const result = await sendNotice(id);
      sent += result.sent;
      removed += result.removed;
    } catch (e) {
      // One notice that could not be sent does not stop the rest.
      console.error(`push ${id}: ${e}`);
    }
  }
  return Response.json({ sent, removed });
});
