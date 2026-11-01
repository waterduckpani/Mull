#!/bin/sh
# Makes the Play upload key, once.
#
#   ./tool/android-keystore.sh
#
# Writes .secrets/mull-upload.jks (git-ignored) and android/key.properties
# (git-ignored), which android/app/build.gradle.kts signs release builds with.
#
# This is the *upload* key, not the key users' phones check: with Play App
# Signing (the default for new apps), Google holds that one. Losing this file is
# recoverable (Play Console -> App integrity -> Request upload key reset), but
# it takes days, so keep a copy of .secrets/ somewhere that is not this Mac.

set -e
cd "$(dirname "$0")/.."

STORE=.secrets/mull-upload.jks
if [ -f "$STORE" ]; then
  echo "$STORE already exists. Refusing to replace an upload key."
  exit 1
fi

[ -n "$JAVA_HOME" ] || JAVA_HOME=$(flutter config --list 2>/dev/null | sed -n 's/^ *jdk-dir: //p')
KEYTOOL=${JAVA_HOME:+$JAVA_HOME/bin/}keytool

mkdir -p .secrets
PASS=$(openssl rand -base64 24 | tr -d '/+=')
"$KEYTOOL" -genkeypair -v -keystore "$STORE" -storetype PKCS12 \
  -alias upload -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=Mull, O=Mull, C=IN" >/dev/null 2>&1

cat > android/key.properties <<PROPS
storeFile=../.secrets/mull-upload.jks
storePassword=$PASS
keyPassword=$PASS
keyAlias=upload
PROPS
chmod 600 "$STORE" android/key.properties
echo "Made $STORE and android/key.properties. Back up .secrets/ now."
