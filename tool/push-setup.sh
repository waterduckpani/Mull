#!/bin/sh
# Wires up push on the Supabase side. Safe to run again.
#
#   ./tool/push-setup.sh                      deploy, and link the database to it
#   ./tool/push-setup.sh AuthKey_XXXXXXXX.p8  ...and install the APNs key
#   ./tool/push-setup.sh mull-d75d7-*.json    ...and install the Firebase key
#
# Keys can be given together, in any order.
#
# The key comes from developer.apple.com -> Certificates, IDs & Profiles ->
# Keys -> "+", tick Apple Push Notifications service (APNs), Sandbox &
# Production. Download the .p8 once (Apple never shows it again); the key id
# is the part of the file name after AuthKey_.
#
# The Firebase key is for Android: console.firebase.google.com -> Mull ->
# Project settings -> Service accounts -> Generate new private key. It is a
# JSON file; keep it in .secrets/ with the other keys.
#
# The database reaches the function through pg_net with a shared secret, kept
# in Vault on one side and in the function's secrets on the other. It is made
# here, stored in .secrets/push-webhook, and never printed.

set -e
# Read the key paths before changing directory, or a relative path breaks.
for arg in "$@"; do
  path=$(cd "$(dirname "$arg")" && pwd)/$(basename "$arg")
  if grep -q '"type": *"service_account"' "$path"; then
    FCM_FILE=$path
  elif grep -q "BEGIN PRIVATE KEY" "$path"; then
    KEY_FILE=$path
  else
    echo "$arg is neither an APNs .p8 key nor a Firebase service account"; exit 1
  fi
done
cd "$(dirname "$0")/.."
REF=nfuujjyscybqdcfryiwk

mkdir -p .secrets
if [ ! -s .secrets/push-webhook ]; then
  openssl rand -hex 32 > .secrets/push-webhook
  chmod 600 .secrets/push-webhook
fi
SECRET=$(cat .secrets/push-webhook)

cd supabase
supabase secrets set --project-ref "$REF" \
  PUSH_WEBHOOK_SECRET="$SECRET" APNS_TEAM_ID=B3F76H2UHH APNS_TOPIC=in.mull.app > /dev/null

if [ -n "${KEY_FILE:-}" ]; then
  KEY_ID=$(basename "$KEY_FILE" .p8 | sed 's/^AuthKey_//')
  supabase secrets set --project-ref "$REF" APNS_KEY_ID="$KEY_ID" APNS_PRIVATE_KEY="$(cat "$KEY_FILE")" > /dev/null
  echo "APNs key $KEY_ID installed."
fi

if [ -n "${FCM_FILE:-}" ]; then
  supabase secrets set --project-ref "$REF" FCM_SERVICE_ACCOUNT="$(cat "$FCM_FILE")" > /dev/null
  echo "Firebase key installed."
fi

supabase functions deploy push --project-ref "$REF" --no-verify-jwt --use-api

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<SQL
do \$\$
begin
  perform vault.update_secret(id, 'https://$REF.supabase.co/functions/v1/push')
     from vault.secrets where name = 'push_function_url';
  if not found then
    perform vault.create_secret('https://$REF.supabase.co/functions/v1/push', 'push_function_url');
  end if;
  perform vault.update_secret(id, '$SECRET') from vault.secrets where name = 'push_webhook_secret';
  if not found then
    perform vault.create_secret('$SECRET', 'push_webhook_secret');
  end if;
end \$\$;
SQL
supabase db query --linked -f "$TMP" > /dev/null
echo "Database -> push function linked."
