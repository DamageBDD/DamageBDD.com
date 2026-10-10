#!/usr/bin/env sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if ! command -v emacs >/dev/null 2>&1; then
  printf 'Local preview requires Emacs and the bundled simple-httpd.el.\n' >&2
  exit 1
fi
# The named foreground daemon does not interfere with a normal Emacs server.
# Bind to loopback by default; use Ctrl+C to stop it.
exec env DAMAGEBDD_PUBLISH_NO_AUTO=1 emacs -Q --fg-daemon=damagebdd-preview \
  -l "$SCRIPT_DIR/publish.el" --eval '(publish-and-serve)'
