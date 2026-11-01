#!/bin/sh
# Builds a Google Play upload (an .aab).
#
#   ./tool/play.sh
#
# Then Play Console -> Mull -> Test and release -> pick a track -> Create new
# release -> upload build/app/outputs/bundle/release/app-release.aab.
#
# Same rules as tool/testflight.sh: the build number is the commit count, so
# commit first. Needs android/key.properties (./tool/android-keystore.sh).

set -e
cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain)" ] && [ -z "$ALLOW_DIRTY" ]; then
  echo "Uncommitted changes. Commit first, so this build is a commit you can find again."
  exit 1
fi

if [ ! -f android/key.properties ]; then
  echo "No upload key. Run ./tool/android-keystore.sh first; Play refuses debug-signed builds."
  exit 1
fi

# The typefaces are not in git (see tool/fetch-fonts.sh).
[ -f assets/fonts/Ranade-Regular.otf ] || ./tool/fetch-fonts.sh

BUILD=$(git rev-list --count HEAD)
VERSION=$(sed -n 's/^version: \([0-9.]*\).*/\1/p' pubspec.yaml)

echo "Building Mull $VERSION ($BUILD) for Play"
flutter build appbundle --release \
  --build-name="$VERSION" --build-number="$BUILD" \
  --dart-define=SUPABASE_URL=https://nfuujjyscybqdcfryiwk.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5mdXVqanlzY3licWRjZnJ5aXdrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk1NjkzNDcsImV4cCI6MjEwNTE0NTM0N30.TVpPThLe_P5LVgbwa_QnRBlfyIXcJli95cFM7NBvh2M \
  --dart-define="MULL_BUILD=$VERSION ($BUILD) android"

# Never ship the sample data: MULL_SAMPLE is not defined above, on purpose.
echo
echo "Upload: build/app/outputs/bundle/release/app-release.aab"
