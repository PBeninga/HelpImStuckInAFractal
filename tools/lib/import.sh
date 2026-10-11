# shellcheck shell=sh
# Sourced by run.sh and tools/launch.sh, from the repo root, with $GODOT set.
#
# Refresh the script class cache when a script is newer than it, or declares a
# class_name the cache has not heard of (the editor does this on open; this
# project is run from the terminal, so do it here).
CACHE=.godot/global_script_class_cache.cfg
needs_import() {
  [ -f "$CACHE" ] || return 0
  if [ -n "$(find src tests -name '*.gd' -newer "$CACHE" -print 2>/dev/null | head -n 1)" ]; then
    return 0
  fi
  find src tests -name '*.gd' -exec grep -hoE '^class_name[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' {} + 2>/dev/null \
    | awk '{ print $2 }' \
    | while IFS= read -r cls; do
        grep -q "\"class\": &\"$cls\"" "$CACHE" || echo "$cls"
      done \
    | grep -q .
}
refresh_class_cache() {
  if needs_import; then
    echo "Refreshing Godot's script class cache (import step)..." >&2
    "$GODOT" --headless --import --path . >/dev/null 2>&1 || true
  fi
}
