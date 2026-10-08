#!/bin/sh
# Render the windowed check in a real window and report what happened.
#
# Produces, in screenshots/ :
#   default_view.png            the default Ice Fractal view
#   mode_<id>.png               one per colour mode
#   lighting_raked.png          the default view under a swung, broad light
# and one PASS/FAIL line per check in tests/out/screenshots.txt.
#
# The window must never take desktop focus, so the app is launched through
# `open -g` (background) with `-n` (new instance) and `-W` (wait for exit).
cd "$(dirname "$0")/.." || exit 2
GODOT="${GODOT:-godot4}"
APP="${GODOT_APP:-/Applications/Godot_mono.app}"

mkdir -p tests/out screenshots
rm -f tests/out/screenshots.txt        # one named file; never a recursive delete

"$GODOT" --headless --import --path . >/dev/null 2>&1

open -g -n -W -a "$APP" --args --path "$PWD" -s tests/screenshots.gd

if [ ! -f tests/out/screenshots.txt ]; then
  echo "*** tests/out/screenshots.txt was not written: the run crashed or never started."
  echo "*** Check that $APP exists, or set GODOT_APP=/path/to/Godot_mono.app"
  exit 1
fi

cat tests/out/screenshots.txt
echo "--- PNGs in screenshots/ :"
ls screenshots
if grep -q '^FAIL' tests/out/screenshots.txt; then
  exit 1
fi
exit 0
