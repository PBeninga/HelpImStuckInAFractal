#!/bin/sh
# Run the game with the call centre attached. Nothing in the game changes: the
# game's own ./run.sh starts call_center/boot.tscn, which adds the call centre
# and then loads the game's main scene.
#
#   call_center/run.sh                 the game as usual, plus the call centre
#   call_center/run.sh --demo          straight to the cockpit, sample escape route
#   call_center/run.sh -- --ship-server=wss://example.ngrok.app/game --ship-token=...
set -e
cd "$(dirname "$0")/.."
SCENE=res://call_center/boot.tscn
if [ "$1" = "--demo" ]; then
  SCENE=res://call_center/demo.tscn
  shift
fi
exec ./run.sh "$SCENE" "$@"
