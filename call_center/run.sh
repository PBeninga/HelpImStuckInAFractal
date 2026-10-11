#!/bin/sh
# Run the game with the call centre: the game's own ./run.sh, with McpBridge
# told to start call_center/ beside it (`-- --call-center`).
#
#   call_center/run.sh            the game as usual (title menu), plus the call centre
#   call_center/run.sh --demo     straight to the cockpit, on the sample escape route
#   call_center/run.sh [godot args] [-- more game args]
#
# For a Claude session, the same flags go through tools/launch.sh:
#   tools/launch.sh -- --play --call-center-demo
set -e
cd "$(dirname "$0")/.."
FLAGS="--call-center"
if [ "$1" = "--demo" ]; then
  FLAGS="--call-center-demo --play"
  shift
fi
# Anything after a `--` the caller gave stays a game arg; ours follow.
exec ./run.sh "$@" -- $FLAGS
