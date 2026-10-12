#!/usr/bin/env bash
# Launches the game the way a Claude Code session should, as Spellgraft's tools/launch.sh does:
# off screen and never taking focus. Godot activates itself before any game code runs, so only the
# launcher can give focus back: this remembers the app in front, starts Godot, and hands focus back
# every time Godot takes it, until Godot exits. The game itself parks its window off screen under a
# Claude session (src/session/session_launch.gd); FRACTAL_PLAY=1 opts out of both.
#
#   tools/launch.sh [godot args...] [-- game args...]
#   tools/launch.sh -- --play                      straight into the explorer (what the MCP server runs)
#   tools/launch.sh -- --play --foreground-window  a normal window, and it keeps focus
#
# Refreshes the script class cache first (tools/lib/import.sh), as run.sh does. GODOT overrides the
# binary. Exits with Godot's status.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1
# shellcheck source=lib/focus.sh
source "$REPO/tools/lib/focus.sh"
# shellcheck source=lib/import.sh
source "$REPO/tools/lib/import.sh"
# shellcheck source=lib/process.sh
source "$REPO/tools/lib/process.sh"

GODOT="${GODOT:-$HOME/Downloads/Godot_mono.app/Contents/MacOS/Godot}"
[ -x "$GODOT" ] || { echo "launch: no Godot at $GODOT (set \$GODOT)" >&2; exit 1; }
refresh_class_cache

# A window asked for in the foreground keeps focus, as Spellgraft's foreground captures do.
FOCUS_HOME=""
foreground=0
for a in "$@"; do [ "$a" = --foreground-window ] && foreground=1; done
[ "${FRACTAL_PLAY:-}" = 1 ] || [ "$foreground" = 1 ] || remember_focus

"$GODOT" --path "$REPO" "$@" </dev/null & pid=$!
watcher=""
[ -n "$FOCUS_HOME" ] && { return_focus "$FOCUS_HOME" "$pid" & watcher=$!; }
wait_for_godot "$pid" "$watcher"
exit $?
