#!/bin/sh
# Use the shared game + call centre launcher, forwarding every argument.
set -e
cd "$(dirname "$0")"
exec ./call_center/run.sh "$@"
