#!/bin/sh
# The call centre's tests: its Godot suites (call_center/tests/*_test.gd), the
# boundary check (only the adapter may name game classes), and the relay's
# Node tests when its dependencies are installed. Exit status is non-zero if
# anything fails. The game's own suite is tests/run_all.sh.
cd "$(dirname "$0")/../.." || exit 2
GODOT="${GODOT:-godot4}"
status=0

echo "=== boundary: game classes appear only in call_center/adapter/explorer_adapter.gd"
leaks=$(grep -rnwE 'Main|CameraState|FractalParams|FractalView|FlyCamera|DistanceEstimator|ResolutionGovernor|AttributeTable|MandelboxShape' \
  call_center --include='*.gd' | grep -v '^call_center/adapter/explorer_adapter.gd:' | grep -v '^call_center/tests/' | grep -v '##')
if [ -n "$leaks" ]; then
  printf '%s\n' "$leaks"
  echo "*** game classes used outside the adapter"
  status=1
else
  echo "ok"
fi

"$GODOT" --headless --import --path . >/dev/null 2>&1
for t in call_center/tests/*_test.gd; do
  echo "=== $t"
  out=$("$GODOT" --headless --path . -s "$t" 2>&1)
  code=$?
  printf '%s\n' "$out" | grep -vE '^Godot Engine|^$'
  if [ "$code" -ne 0 ] || printf '%s' "$out" | grep -qE 'SCRIPT ERROR|Failed to load script| FAILED'; then
    status=1
    echo "*** $t FAILED (exit $code)"
  fi
done

if [ -d call_center/server/node_modules ]; then
  echo "=== call_center/server (npm test)"
  out=$(cd call_center/server && npm test 2>&1)
  code=$?
  printf '%s\n' "$out" | grep -E '^# (tests|pass|fail)|^ *not ok'
  [ "$code" -eq 0 ] || { status=1; echo "*** relay tests FAILED"; }
else
  echo "=== call_center/server: run 'npm install' there to include the relay's tests"
fi
exit $status
