#!/bin/sh
# Launch Help I'm Stuck In A Fractal from the terminal.
#
#   ./run.sh            run the project
#   ./run.sh --editor   open it in the Godot editor instead
#
# Set GODOT to point at a different Godot 4 binary if needed. This is the
# launcher for a person; a Claude Code session launches through tools/launch.sh.
set -e
cd "$(dirname "$0")"

GODOT="${GODOT:-godot4}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  if [ -x "$HOME/Downloads/Godot_mono.app/Contents/MacOS/Godot" ]; then
    GODOT="$HOME/Downloads/Godot_mono.app/Contents/MacOS/Godot"
  elif [ -x /Applications/Godot_mono.app/Contents/MacOS/Godot ]; then
    GODOT=/Applications/Godot_mono.app/Contents/MacOS/Godot
  elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
    GODOT=/Applications/Godot.app/Contents/MacOS/Godot
  else
    echo "Godot 4 not found. Install it or set GODOT=/path/to/godot" >&2
    exit 1
  fi
fi

if [ "$1" = "--editor" ]; then
  shift
  exec "$GODOT" --editor --path . "$@"
fi

. tools/lib/import.sh
refresh_class_cache

exec "$GODOT" --path . "$@"
