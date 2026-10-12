#!/bin/sh
# Run the game with the call centre. The root ./run.sh delegates here.
#
#   ./run.sh                     the game (title menu), plus the call centre
#   ./run.sh --demo              straight to the cockpit, with live geometry navigation
#   ./run.sh --editor            open the game in the Godot editor
#   ./run.sh [godot args] [-- more game args]
#
# Set GODOT to point at a different Godot 4 binary if needed.
# For a Claude session: tools/launch.sh -- --play --call-center-demo
set -e
cd "$(dirname "$0")/.."

demo=0
if [ "${1:-}" = "--demo" ]; then
  demo=1
  shift
fi

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

. tools/lib/process.sh

if [ "${1:-}" = "--editor" ]; then
  shift
  "$GODOT" --editor --path . "$@" </dev/null &
  wait_for_godot "$!"
  exit $?
fi

. tools/lib/import.sh
refresh_class_cache

# Add our game flags after the caller's separator, or supply one if absent.
has_separator=0
for arg in "$@"; do
  if [ "$arg" = "--" ]; then
    has_separator=1
    break
  fi
done
if [ "$has_separator" = 0 ]; then
  set -- "$@" --
fi
if [ "$demo" = 1 ]; then
  set -- "$@" --call-center-demo --play
else
  set -- "$@" --call-center
fi

"$GODOT" --path . "$@" </dev/null &
wait_for_godot "$!"
