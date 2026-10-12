# shellcheck shell=sh
# Wait in the shell so terminal interrupts can stop and reap the background game.
wait_for_godot() {
  game_pid="$1"
  focus_pid="${2:-}"
  trap 'stop_godot 130' INT
  trap 'stop_godot 143' TERM
  trap 'stop_godot 129' HUP
  game_status=0
  wait "$game_pid" || game_status=$?
  stop_focus_watcher
  trap - INT TERM HUP
  return "$game_status"
}

stop_focus_watcher() {
  if [ -n "$focus_pid" ]; then
    kill "$focus_pid" 2>/dev/null || true
    wait "$focus_pid" 2>/dev/null || true
  fi
}

stop_godot() {
  trap '' INT TERM HUP
  # POSIX shells start asynchronous commands with SIGINT ignored; use TERM.
  kill -TERM "$game_pid" 2>/dev/null || true
  wait "$game_pid" 2>/dev/null || true
  stop_focus_watcher
  exit "$1"
}
