# shellcheck shell=bash
# Sourced by tools/launch.sh. Ported from Spellgraft's tools/lib/focus.sh (one copy there, so every launch path a Claude
# session uses hands focus back).
#
# Godot activates itself as its window opens, so on macOS a windowed capture would take focus from
# whatever you were typing in, and its window would cover your screen. The game's --background-window
# flag parks the window off screen bar a few pixels in the bottom-right corner (a window with nothing
# on screen draws no frames), and focus is handed straight back to the app that had it.
# Anywhere osascript is missing or not allowed to drive System Events this quietly does nothing.

# How often the frontmost app is checked while Godot runs. Godot re-activates itself several times
# while it loads (seen at 3s, 5s and 7s into a capture), so the watch lasts its whole lifetime.
FOCUS_POLL_SECONDS=0.25

frontmost_pid() {
  osascript -e 'tell application "System Events" to get unix id of first application process whose frontmost is true' 2>/dev/null
}

# Sets FOCUS_HOME to the app in front right now, for return_focus to hand focus back to.
remember_focus() {
  FOCUS_HOME=""
  [ "$(uname)" = Darwin ] && command -v osascript >/dev/null 2>&1 || return 0
  FOCUS_HOME="$(frontmost_pid)"
}

# Every time Godot ($2) comes to the front, puts app $1 back in front, until Godot exits.
return_focus() {
  local home="$1" godot="$2"
  while kill -0 "$godot" 2>/dev/null; do
    sleep "$FOCUS_POLL_SECONDS"
    [ "$(frontmost_pid)" = "$godot" ] || continue
    osascript -e "tell application \"System Events\" to set frontmost of first application process whose unix id is $home to true" >/dev/null 2>&1
  done
}

