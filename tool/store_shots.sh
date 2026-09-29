#!/bin/sh
# App Store screenshots from tool/store_shots.html, via headless Chrome.
#
#   ./tool/store_shots.sh        # writes store/screenshots-6.5 and store/screenshots
#
# Needs the tour's captures in screenshots/ (see the header of
# integration_test/tour_test.dart) and the fonts (tool/fetch-fonts.sh).
set -e
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PAGE="file://$PWD/tool/store_shots.html"
render() { # out-dir width height
  mkdir -p "$1"
  for s in 1 2 3 4 5 6; do
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
      --allow-file-access-from-files --virtual-time-budget=3000 \
      --window-size="$2,$3" --screenshot="$PWD/$1/0$s.png" "$PAGE?s=$s&w=$2&h=$3" 2>/dev/null
  done
}
render store/screenshots-6.5 1284 2778
render store/screenshots 1320 2868
